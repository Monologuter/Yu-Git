import Foundation
import Testing

@testable import GitKit

@Suite("RepoActor")
struct RepoActorTests {

    private func makeActor(on repository: TemporaryRepository) async throws -> (RepoActor, InMemoryOperationLog) {
        let log = InMemoryOperationLog()
        let actor = try await RepoActor(root: repository.url, client: repository.client, operationLog: log)
        return (actor, log)
    }

    // MARK: - 记录

    @Test("成功的写操作被记入日志")
    func recordsSuccessfulOperation() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("hello", to: "a.txt")
        let (actor, log) = try await makeActor(on: repository)

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
        let (actor, log) = try await makeActor(on: repository)

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
        let (actor, log) = try await makeActor(on: repository)

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
        let (actor, log) = try await makeActor(on: repository)

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
        let (actor, log) = try await makeActor(on: repository)

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

@Suite("部分暂存")
struct PartialStagingTests {

    private func makeActor(on repository: TemporaryRepository) async throws -> RepoActor {
        try await RepoActor(root: repository.url, client: repository.client, operationLog: InMemoryOperationLog())
    }

    private func indexContent(of path: String, in repository: TemporaryRepository) async throws -> String {
        try await repository.client.run(["show", ":\(path)"], in: repository.url).standardOutputText
    }

    @Test("按 hunk 暂存，未选中的 hunk 留在工作区")
    func stagesSelectedHunk() async throws {
        let repository = try await TemporaryRepository()
        try repository.write((1...30).map(String.init).joined(separator: "\n") + "\n", to: "f.txt")
        try await repository.commitAll("base")

        var lines = (1...30).map(String.init)
        lines[1] = "改了第二行"
        lines[27] = "改了第二十八行"
        try repository.write(lines.joined(separator: "\n") + "\n", to: "f.txt")

        let actor = try await makeActor(on: repository)
        let staged = try await actor.stagePartial(path: "f.txt", selecting: .hunks([0]))

        #expect(staged)
        let content = try await indexContent(of: "f.txt", in: repository)
        #expect(content.contains("改了第二行"))
        #expect(!content.contains("改了第二十八行"))
    }

    @Test("部分暂存被记入操作日志，但 patch 内容不入日志")
    func recordsPartialStagingWithoutContent() async throws {
        // 工程规范 §7：操作日志不含文件内容。patch 就是用户的代码，必须走单独通道。
        let repository = try await TemporaryRepository()
        try repository.write("原来的内容\n", to: "机密.txt")
        try await repository.commitAll("base")
        try repository.write("这行是不该出现在日志里的机密内容\n", to: "机密.txt")

        let log = InMemoryOperationLog()
        let actor = try await RepoActor(root: repository.url, client: repository.client, operationLog: log)
        try await actor.stagePartial(path: "机密.txt", selecting: .whole)

        let records = await log.recent(limit: 10)
        let record = try #require(records.first)

        #expect(record.operation.kind == .stagePartial)
        #expect(record.operation.summary.contains("机密.txt"))

        let encoded = try JSONEncoder().encode(record)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("不该出现在日志里的机密内容"), "文件内容绝不能进操作日志")
    }

    @Test("取消部分暂存")
    func unstagesPartially() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\nb\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("A\nB\n", to: "f.txt")
        try await repository.git("add", "f.txt")

        let actor = try await makeActor(on: repository)
        let unstaged = try await actor.unstagePartial(path: "f.txt", selecting: .whole)

        #expect(unstaged)
        let content = try await indexContent(of: "f.txt", in: repository)
        #expect(content == "a\nb\n", "index 应退回 HEAD 的内容")
    }

    @Test("没有选中任何改动时返回 false 且不产生日志")
    func skipsEmptySelection() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("A\n", to: "f.txt")

        let log = InMemoryOperationLog()
        let actor = try await RepoActor(root: repository.url, client: repository.client, operationLog: log)
        let staged = try await actor.stagePartial(path: "f.txt", selecting: .hunks([]))

        #expect(!staged)
        let records = await log.recent(limit: 10)
        #expect(records.isEmpty, "什么都没做就不该留下记录")
    }

    @Test("丢弃改动被标记为最高危险级别")
    func flagsDiscardAsDestructive() {
        let discard = GitOperation.discard(paths: ["f.txt"])

        #expect(discard.hazard == .discardsUncommittedWork)
        #expect(discard.explanation.contains("无法找回"), "危险性必须在文案里说清楚")
    }

    @Test("stash 与取回")
    func stashesAndPops() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("原始\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("改过的\n", to: "f.txt")

        let actor = try await makeActor(on: repository)
        try await actor.perform(.stashPush(message: "临时收起来"))

        let afterStash = try await actor.status()
        #expect(afterStash.isClean, "stash 之后工作区应当干净")

        try await actor.perform(.stashPop())
        let afterPop = try await actor.status()
        #expect(!afterPop.isClean, "取回后改动应当回来")
    }
}
