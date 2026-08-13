import Foundation
import Testing

@testable import GitKit

@Suite("时间线快照")
struct SnapshotStoreTests {

    private func store(on repository: TemporaryRepository) async throws -> SnapshotStore {
        try await SnapshotStore.open(root: repository.url, client: repository.client)
    }

    @Test("快照存下工作区内容，包括未跟踪文件")
    func capturesWorkTree() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("已提交\n", to: "tracked.txt")
        try await repository.commitAll("base")
        try repository.write("改过了\n", to: "tracked.txt")
        try repository.write("没跟踪\n", to: "untracked.txt")

        let store = try await store(on: repository)
        let snapshot = try #require(await store.capture(summary: "测试快照", identifier: "t1"))

        let files = try await repository.client.run(
            ["ls-tree", "-r", "--name-only", snapshot.commit], in: repository.url
        ).standardOutputText

        #expect(files.contains("tracked.txt"))
        #expect(files.contains("untracked.txt"), "未跟踪文件也要存，否则撤销后它们就没了")
    }

    @Test("临时 index 不落在工作区里")
    func keepsTemporaryIndexOutOfWorkTree() async throws {
        // 放工作区会变成未跟踪文件，既出现在变更列表里，还会被快照自己收进去
        let repository = try await TemporaryRepository()
        try repository.write("内容\n", to: "a.txt")
        try await repository.commitAll("base")
        try repository.write("改动\n", to: "a.txt")

        let store = try await store(on: repository)
        let snapshot = try #require(await store.capture(summary: "快照", identifier: "t1"))

        let status = try await repository.status()
        let strayFiles = status.entries.filter { $0.path.contains(".idx") }
        #expect(strayFiles.isEmpty, "工作区里不该出现临时 index")

        let files = try await repository.client.run(
            ["ls-tree", "-r", "--name-only", snapshot.commit], in: repository.url
        ).standardOutputText
        #expect(!files.contains(".idx"), "快照内容里也不该有临时 index")
    }

    @Test("拍快照不污染真正的 index")
    func doesNotTouchRealIndex() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("原始\n", to: "a.txt")
        try await repository.commitAll("base")
        try repository.write("工作区改动\n", to: "a.txt")

        let before = try await repository.status()
        let store = try await store(on: repository)
        _ = try await store.capture(summary: "快照", identifier: "t1")
        let after = try await repository.status()

        #expect(before.entries.map(\.path) == after.entries.map(\.path))
        let entry = try #require(after.entries.first { $0.path == "a.txt" })
        #expect(entry.hasUnstagedChanges, "改动应当仍未暂存")
        #expect(!entry.hasStagedChanges, "拍快照不该把改动暂存进去")
    }

    @Test("快照不出现在分支、stash 与历史里")
    func staysOutOfUserVisibleViews() async throws {
        // 这是选 refs/yugit/ 而不用 stash 栈的全部理由：
        // 用户的工作区不该被工具塞满
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")
        try repository.write("改动\n", to: "a.txt")

        let store = try await store(on: repository)
        _ = try await store.capture(summary: "快照", identifier: "t1")

        let branches = try await repository.client.branches(in: repository.url)
        #expect(!branches.contains { $0.name.contains("yugit") })

        let stash = try await repository.client.run(["stash", "list"], in: repository.url)
        #expect(stash.standardOutputText.isEmpty, "不碰用户的 stash 栈")

        let history = try await repository.client.log(in: repository.url, includingAllRefs: true)
        #expect(history.count == 1, "快照 commit 不该混进用户看到的历史")
        #expect(!history.contains { $0.subject == "快照" })
    }

    @Test("恢复快照后工作区回到当时的状态")
    func restoresWorkTree() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("第一版\n", to: "a.txt")
        try await repository.commitAll("base")

        try repository.write("第二版\n", to: "a.txt")
        let store = try await store(on: repository)
        let snapshot = try #require(await store.capture(summary: "第二版快照", identifier: "t1"))

        // 继续改，然后撤回快照
        try repository.write("第三版——不该保留\n", to: "a.txt")
        try await store.restore(snapshot)

        let content = try String(
            contentsOf: repository.url.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(content == "第二版\n")
    }

    @Test("恢复会删掉快照之后新增的文件")
    func removesFilesAddedAfterSnapshot() async throws {
        // 只写回文件而不删多余的，恢复得不干净：
        // 用户以为回到了那一刻，实际却留着后来的产物
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")

        let store = try await store(on: repository)
        let snapshot = try #require(await store.capture(summary: "快照", identifier: "t1"))

        try repository.write("后来加的\n", to: "later.txt")
        try await store.restore(snapshot)

        let exists = FileManager.default.fileExists(
            atPath: repository.url.appendingPathComponent("later.txt").path)
        #expect(!exists, "快照之后新增的文件应当被清掉")
    }

    @Test("空仓库上也能拍快照")
    func capturesInUnbornRepository() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("还没提交过\n", to: "a.txt")

        let store = try await store(on: repository)
        let snapshot = try #require(await store.capture(summary: "首次快照", identifier: "t1"))

        #expect(snapshot.headCommit == nil, "unborn 仓库没有 HEAD")
        let files = try await repository.client.run(
            ["ls-tree", "-r", "--name-only", snapshot.commit], in: repository.url
        ).standardOutputText
        #expect(files.contains("a.txt"))
    }

    @Test("列出快照，按时间倒序")
    func listsSnapshots() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")

        let store = try await store(on: repository)
        for index in 1...3 {
            try repository.write("第 \(index) 次\n", to: "a.txt")
            _ = try await store.capture(summary: "第 \(index) 次改动", identifier: "t\(index)")
        }

        let snapshots = try await store.list()

        #expect(snapshots.count == 3)
        #expect(snapshots.allSatisfy { $0.reference.hasPrefix(GitNamespace.timelineRefPrefix) })
        let summaries = Set(snapshots.map(\.summary))
        #expect(summaries.contains("第 3 次改动"))
    }

    @Test("清理只保留最近若干张")
    func prunesOldSnapshots() async throws {
        // 快照 ref 让对象免于 gc，不清理仓库体积会一直涨
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")

        let store = try await store(on: repository)
        for index in 1...5 {
            try repository.write("第 \(index) 次\n", to: "a.txt")
            _ = try await store.capture(summary: "第 \(index) 次", identifier: "t\(index)")
        }

        try await store.prune(keeping: 2)
        let remaining = try await store.list()

        #expect(remaining.count == 2)
    }

    @Test("被忽略的文件不进快照")
    func skipsIgnoredFiles() async throws {
        // 构建产物没有快照的价值，还会让每张快照都很大
        let repository = try await TemporaryRepository()
        try repository.write("build/\n", to: ".gitignore")
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")
        try repository.write("产物\n", to: "build/output.bin")

        let store = try await store(on: repository)
        let snapshot = try #require(await store.capture(summary: "快照", identifier: "t1"))

        let files = try await repository.client.run(
            ["ls-tree", "-r", "--name-only", snapshot.commit], in: repository.url
        ).standardOutputText
        #expect(!files.contains("build/"))
    }
}
