import Foundation
import Testing

@testable import GitKit

@Suite("RepoActor")
struct RepoActorTests {

    private func makeActor(on repository: TemporaryRepository) -> (RepoActor, InMemoryOperationLog) {
        let log = InMemoryOperationLog()
        let actor = RepoActor(root: repository.url, client: repository.client, operationLog: log)
        return (actor, log)
    }

    // MARK: - 记录

    @Test("成功的写操作被记入日志")
    func recordsSuccessfulOperation() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("hello", to: "a.txt")
        let (actor, log) = makeActor(on: repository)

        try await actor.perform(.stage(paths: ["a.txt"]))

        let records = await log.recent(limit: 10)
        #expect(records.count == 1)
        #expect(records[0].operation.kind == .stage)
        #expect(records[0].outcome == .succeeded)

        let status = try await actor.status()
        #expect(status.entries.first?.hasStagedChanges == true)
    }

    @Test("失败的操作同样留下记录")
    func recordsFailedOperation() async throws {
        // 「我刚才那步为什么没生效」也是用户要在时间线上看到的东西。
        let repository = try await TemporaryRepository()
        let (actor, log) = makeActor(on: repository)

        await #expect(throws: GitError.self) {
            try await actor.perform(.stage(paths: ["根本不存在.txt"]))
        }

        let records = await log.recent(limit: 10)
        #expect(records.count == 1)
        #expect(!records[0].outcome.isSuccess)

        guard case let .failed(exitCode, message) = records[0].outcome else {
            Issue.record("失败的操作应当留下 failed 记录")
            return
        }
        #expect(exitCode != 0)
        #expect(!message.isEmpty)
    }

    @Test("记录 HEAD 的前后变化——这是 Undo 的锚点")
    func recordsHeadTransition() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("hello", to: "a.txt")
        let (actor, log) = makeActor(on: repository)

        try await actor.perform(.stage(paths: ["a.txt"]))
        try await actor.perform(.commit(message: "首次提交"))

        let records = await log.recent(limit: 10)
        #expect(records.count == 2)

        #expect(records[0].headBefore == nil, "unborn 仓库还没有 HEAD")
        #expect(!records[0].movedHead, "暂存不移动 HEAD")

        #expect(records[1].headAfter?.count == 40)
        #expect(records[1].movedHead, "提交必然移动 HEAD")
    }

    @Test("只读查询不进操作日志")
    func doesNotLogReads() async throws {
        let repository = try await TemporaryRepository()
        let (actor, log) = makeActor(on: repository)

        _ = try await actor.status()

        let records = await log.recent(limit: 10)
        #expect(records.isEmpty)
    }

    // MARK: - 串行化

    @Test("并发写操作被串行化，不会踩 index.lock", .timeLimit(.minutes(1)))
    func serialisesConcurrentWrites() async throws {
        // git 用 index.lock 独占 index：并发跑 git add，后到的那条会直接失败。
        // GUI 上快速连点暂存就是这个场景，actor 把它们排成队。
        let repository = try await TemporaryRepository()
        let fileCount = 30
        for index in 0..<fileCount {
            try repository.write("内容 \(index)", to: "文件\(index).txt")
        }
        let (actor, log) = makeActor(on: repository)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<fileCount {
                group.addTask {
                    try await actor.perform(.stage(paths: ["文件\(index).txt"]))
                }
            }
            try await group.waitForAll()
        }

        let status = try await actor.status()
        let allStaged = status.entries.allSatisfy(\.hasStagedChanges)
        #expect(status.entries.count == fileCount)
        #expect(allStaged)

        let records = await log.recent(limit: fileCount * 2)
        let allSucceeded = records.allSatisfy(\.outcome.isSuccess)
        #expect(records.count == fileCount)
        #expect(allSucceeded)
    }

    // MARK: - 打开仓库

    @Test("从子目录打开仓库时定位到仓库根")
    func opensFromSubdirectory() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("x", to: "深/层/文件.txt")
        try await repository.commitAll("首次提交")

        let actor = try await RepoActor.open(
            at: repository.url.appendingPathComponent("深/层"),
            client: repository.client
        )

        #expect(actor.root.resolvingSymlinksInPath().path == repository.url.resolvingSymlinksInPath().path)
    }
}

@Suite("FileOperationLog")
struct FileOperationLogTests {

    private func record(_ operation: GitOperation) -> OperationRecord {
        OperationRecord(operation: operation, headBefore: nil, headAfter: nil, outcome: .succeeded)
    }

    @Test("日志落在仓库自己的 git 目录里")
    func writesInsideGitDirectory() async throws {
        let repository = try await TemporaryRepository()
        let log = try await FileOperationLog(repository: repository.url, client: repository.client)

        try await log.record(record(.stage(paths: ["a.txt"])))

        let expected = repository.url.appendingPathComponent(".git/yugit/operations.jsonl")
        #expect(FileManager.default.fileExists(atPath: expected.path))
    }

    @Test("重新打开仍读得到之前的记录——时间线要跨 session")
    func survivesReopening() async throws {
        let repository = try await TemporaryRepository()

        let first = try await FileOperationLog(repository: repository.url, client: repository.client)
        try await first.record(record(.stage(paths: ["a.txt"])))
        try await first.record(record(.commit(message: "首次提交")))

        let reopened = try await FileOperationLog(repository: repository.url, client: repository.client)
        let records = try await reopened.recent(limit: 10)

        #expect(records.count == 2)
        #expect(records[0].operation.summary == "暂存 a.txt")
        #expect(records[1].operation.kind == .commit)
    }

    @Test("日志为空时返回空数组而不是报错")
    func toleratesMissingFile() async throws {
        let repository = try await TemporaryRepository()
        let log = try await FileOperationLog(repository: repository.url, client: repository.client)

        let records = try await log.recent(limit: 10)

        #expect(records.isEmpty)
    }

    @Test("limit 只取最近的若干条")
    func honoursLimit() async throws {
        let repository = try await TemporaryRepository()
        let log = try await FileOperationLog(repository: repository.url, client: repository.client)
        for index in 0..<5 {
            try await log.record(record(.stage(paths: ["文件\(index).txt"])))
        }

        let records = try await log.recent(limit: 2)

        #expect(records.count == 2)
        #expect(records[1].operation.summary == "暂存 文件4.txt")
    }
}
