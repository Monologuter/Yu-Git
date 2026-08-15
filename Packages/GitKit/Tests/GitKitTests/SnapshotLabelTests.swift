import Foundation
import Testing

@testable import GitKit

@Suite("快照标注与选择性恢复")
struct SnapshotLabelTests {

    /// 造一个有内容的仓库并拍一张快照。
    ///
    /// - Important: 返回的 `repo` 必须被调用方绑住。`TemporaryRepository` 一释放
    ///   就删目录，用 `_` 接住等于当场删掉仓库。
    private func snapshotted(
        identifier: String = "test"
    ) async throws -> (
        repo: TemporaryRepository, store: SnapshotStore, snapshot: Snapshot
    ) {
        let repo = try await TemporaryRepository()
        try repo.write("原始 a\n", to: "a.txt")
        try repo.write("原始 b\n", to: "b.txt")
        try await repo.commitAll("base")

        let store = try await SnapshotStore.open(root: repo.url, client: repo.client)
        let snapshot = try await store.capture(summary: "自动生成的摘要", identifier: identifier)
        return (repo, store, try #require(snapshot))
    }

    // MARK: - 标注

    /// 默认摘要是「执行「硬重置到 abc1234」之前」，而用户三天后想找的是
    /// 「Claude 大改那次之前」。机器生成的描述准确但不好找。
    @Test("标注写得进也读得出")
    func roundTripsALabel() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }

        #expect(await store.label(for: snapshot) == nil)

        try await store.setLabel("Claude 第 3 轮改动前", for: snapshot)
        #expect(await store.label(for: snapshot) == "Claude 第 3 轮改动前")
    }

    @Test("改标注是覆盖，不是报错")
    func overwritesAnExistingLabel() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }

        try await store.setLabel("第一次", for: snapshot)
        try await store.setLabel("改过了", for: snapshot)

        #expect(await store.label(for: snapshot) == "改过了")
    }

    @Test("传空字符串是去掉标注")
    func clearsWithAnEmptyLabel() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }
        try await store.setLabel("要删掉的", for: snapshot)

        try await store.setLabel("", for: snapshot)

        #expect(await store.label(for: snapshot) == nil)
    }

    @Test("本来就没标注时，去掉标注不会报错")
    func clearingAnAbsentLabelIsHarmless() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }

        try await store.setLabel("", for: snapshot)
        #expect(await store.label(for: snapshot) == nil)
    }

    /// 走私有 ref 而不是默认的 `refs/notes/commits`：后者是用户自己的地盘，
    /// 而且默认会显示在 `git log` 里。
    @Test("标注不落进用户自己的 notes")
    func doesNotTouchTheUsersNotes() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }
        try await store.setLabel("我们的标注", for: snapshot)

        let userNotes = try await repo.client.runReturningResult(["notes", "list"], in: repo.url)
        #expect(
            userNotes.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test("一次问完哪些被标注过，不逐张问")
    func listsLabelledCommitsInOneGo() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }
        try repo.write("再改一点\n", to: "a.txt")
        let second = try #require(
            try await store.capture(summary: "第二张", identifier: "second"))

        try await store.setLabel("重要", for: second)

        let labelled = await store.labelledCommits()
        #expect(labelled.contains(second.commit))
        #expect(!labelled.contains(snapshot.commit))
    }

    // MARK: - 过期策略

    /// **标注是用户明确说过「这张重要」的信号。** 纯按数量的策略会把它删掉，
    /// 而那恰恰是最不该删的那张。
    @Test("清理时标注过的一律留着")
    func neverPrunesLabelledSnapshots() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("v0\n", to: "f.txt")
        try await repo.commitAll("base")
        let store = try await SnapshotStore.open(root: repo.url, client: repo.client)

        var snapshots: [Snapshot] = []
        for index in 0..<5 {
            try repo.write("v\(index)\n", to: "f.txt")
            snapshots.append(
                try #require(try await store.capture(summary: "第 \(index) 张", identifier: "s\(index)")))
        }
        // 把最老的那张标注起来，它本该第一个被淘汰
        let oldest = snapshots[0]
        try await store.setLabel("这张要留着", for: oldest)

        try await store.prune(keeping: 2)

        let remaining = try await store.list()
        #expect(remaining.contains { $0.commit == oldest.commit })
        // 没标注的只留最近 2 张，加上被保住的那张共 3 张
        #expect(remaining.count == 3)
    }

    @Test("没有标注时按数量正常淘汰")
    func prunesNormallyWithoutLabels() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("v0\n", to: "f.txt")
        try await repo.commitAll("base")
        let store = try await SnapshotStore.open(root: repo.url, client: repo.client)

        for index in 0..<5 {
            try repo.write("v\(index)\n", to: "f.txt")
            _ = try await store.capture(summary: "第 \(index) 张", identifier: "s\(index)")
        }

        try await store.prune(keeping: 2)
        #expect(try await store.list().count == 2)
    }

    // MARK: - 选择性恢复

    /// 全量恢复往往下手太重：「agent 把这一个文件改坏了，但另外三个改得挺好」，
    /// 整个退回去会把好的那三个也一起退掉。
    @Test("只恢复点名的文件，其余一概不动")
    func restoresOnlyTheSelectedFiles() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }
        try repo.write("改坏了\n", to: "a.txt")
        try repo.write("改得挺好\n", to: "b.txt")

        try await store.restore(snapshot, paths: ["a.txt"])

        let a = try String(contentsOf: repo.url.appendingPathComponent("a.txt"), encoding: .utf8)
        let b = try String(contentsOf: repo.url.appendingPathComponent("b.txt"), encoding: .utf8)
        #expect(a == "原始 a\n")
        // 没点到的保持原样，改得挺好的那个没被退掉
        #expect(b == "改得挺好\n")
    }

    /// 快照里没有的路径表示「把它删掉」——那是预览里「会被删掉」那一栏
    /// 对应的操作。
    @Test("点名一个快照之后新建的文件，就是把它删掉")
    func removesFilesAbsentFromTheSnapshot() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }
        try repo.write("快照之后写的\n", to: "新文件.txt")

        try await store.restore(snapshot, paths: ["新文件.txt"])

        #expect(
            !FileManager.default.fileExists(
                atPath: repo.url.appendingPathComponent("新文件.txt").path))
    }

    /// **不动 index。** 全量恢复会把 index 退回 HEAD；选择性恢复是外科手术，
    /// 动了 index 会让用户已经暂存好的其他文件莫名其妙地掉出暂存区。
    @Test("选择性恢复不碰暂存区")
    func leavesTheIndexAlone() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }
        try repo.write("暂存好的内容\n", to: "b.txt")
        try await repo.git("add", "b.txt")
        try repo.write("改坏了\n", to: "a.txt")

        try await store.restore(snapshot, paths: ["a.txt"])

        // b.txt 仍然在暂存区里
        let entry = try await repo.entry(at: "b.txt")
        #expect(entry?.indexStatus == .modified)
    }

    @Test("空清单什么都不做")
    func doesNothingForAnEmptySelection() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }
        try repo.write("改坏了\n", to: "a.txt")

        try await store.restore(snapshot, paths: [])

        let a = try String(contentsOf: repo.url.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(a == "改坏了\n")
    }

    /// 预览分好的三栏，每一栏都该能单独拿去做选择性恢复。
    @Test("预览分出来的路径拿去做选择性恢复是对得上的")
    func previewGroupsFeedSelectiveRestore() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }
        try repo.write("改坏了\n", to: "a.txt")
        try repo.write("新的\n", to: "新文件.txt")

        let preview = try await store.preview(snapshot)
        // 只按「会被删掉」那一栏恢复
        try await store.restore(snapshot, paths: preview.removed)

        #expect(
            !FileManager.default.fileExists(
                atPath: repo.url.appendingPathComponent("新文件.txt").path))
        // 「会被覆盖」那一栏没点，所以 a.txt 还是坏的
        let a = try String(contentsOf: repo.url.appendingPathComponent("a.txt"), encoding: .utf8)
        #expect(a == "改坏了\n")
    }
}
