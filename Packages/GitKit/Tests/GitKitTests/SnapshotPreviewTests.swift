import Foundation
import Testing

@testable import GitKit

@Suite("恢复前预览")
struct SnapshotPreviewTests {

    private func makeStore(for repo: TemporaryRepository) async throws -> SnapshotStore {
        try await SnapshotStore.open(root: repo.url, client: repo.client)
    }

    /// 造一个有内容的仓库，拍一张快照。
    private func snapshotted() async throws -> (
        repo: TemporaryRepository, store: SnapshotStore, snapshot: Snapshot
    ) {
        let repo = try await TemporaryRepository()
        try repo.write("原始\n", to: "tracked.txt")
        try await repo.commitAll("base")
        try repo.write("未跟踪的原始内容\n", to: "untracked.txt")

        let store = try await makeStore(for: repo)
        let snapshot = try await store.capture(summary: "测试快照", identifier: "test")
        return (repo, store, try #require(snapshot))
    }

    @Test("什么都没动时预览是空的")
    func reportsNothingWhenUnchanged() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        defer { _ = repo }

        let preview = try await store.preview(snapshot)

        #expect(preview.isEmpty)
        #expect(preview.totalCount == 0)
        #expect(!preview.losesWork)
    }

    /// **这是预览存在的理由**：快照之后新建的文件会被删掉，
    /// 而在此之前用户看不到这件事就点了确定。
    @Test("快照之后新建的文件会被列成「将被删除」")
    func listsFilesThatWillDisappear() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        try repo.write("快照之后写的\n", to: "新文件.txt")

        let preview = try await store.preview(snapshot)

        #expect(preview.removed == ["新文件.txt"])
        #expect(preview.restored.isEmpty)
        #expect(preview.losesWork)
    }

    @Test("快照之后删掉的文件会被列成「将被恢复」")
    func listsFilesThatWillComeBack() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        try repo.delete("untracked.txt")

        let preview = try await store.preview(snapshot)

        #expect(preview.restored == ["untracked.txt"])
        #expect(preview.removed.isEmpty)
        // 只是把东西写回来，不丢现有的活
        #expect(!preview.losesWork)
    }

    @Test("内容改过的文件会被列成「将被覆盖」")
    func listsFilesThatWillBeOverwritten() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        try repo.write("改过了\n", to: "tracked.txt")

        let preview = try await store.preview(snapshot)

        #expect(preview.overwritten == ["tracked.txt"])
        #expect(preview.losesWork)
    }

    @Test("三种改动同时存在时各归各类")
    func separatesTheThreeKinds() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        try repo.write("改过了\n", to: "tracked.txt")
        try repo.delete("untracked.txt")
        try repo.write("新的\n", to: "新文件.txt")

        let preview = try await store.preview(snapshot)

        #expect(preview.overwritten == ["tracked.txt"])
        #expect(preview.restored == ["untracked.txt"])
        #expect(preview.removed == ["新文件.txt"])
        #expect(preview.totalCount == 3)
    }

    /// 文件内容一样时不该报「会被覆盖」。删了再写回一模一样的内容
    /// 就是这种情况——报了的话用户会以为有活要丢。
    @Test("内容相同的文件不算被覆盖")
    func ignoresIdenticalContent() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        try repo.delete("tracked.txt")
        try repo.write("原始\n", to: "tracked.txt")

        let preview = try await store.preview(snapshot)
        #expect(preview.overwritten.isEmpty)
        #expect(preview.isEmpty)
    }

    /// 被 `.gitignore` 忽略的文件不参与预览，也不会被恢复删掉——
    /// 删掉别人的构建缓存是很讨人厌的行为。
    @Test("被忽略的文件不出现在预览里")
    func ignoresIgnoredFiles() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        try repo.write("build/\n", to: ".gitignore")
        try repo.write("产物\n", to: "build/output.o")

        let preview = try await store.preview(snapshot)

        #expect(!preview.removed.contains("build/output.o"))
        // .gitignore 本身是新加的，它会被删
        #expect(preview.removed.contains(".gitignore"))
    }

    /// 预览之后真去恢复，结果必须和预览说的一致。
    /// 说一套做一套的预览比没有预览更糟。
    @Test("预览说的和实际恢复的结果一致")
    func previewMatchesTheActualRestore() async throws {
        let (repo, store, snapshot) = try await snapshotted()
        try repo.write("改过了\n", to: "tracked.txt")
        try repo.write("新的\n", to: "新文件.txt")

        let preview = try await store.preview(snapshot)
        try await store.restore(snapshot)

        for path in preview.removed {
            #expect(
                !FileManager.default.fileExists(
                    atPath: repo.url.appendingPathComponent(path).path),
                "预览说 \(path) 会被删，但它还在")
        }
        for path in preview.overwritten {
            let contents = try String(
                contentsOf: repo.url.appendingPathComponent(path), encoding: .utf8)
            #expect(contents == "原始\n", "预览说 \(path) 会被覆盖，但内容没回到快照那一刻")
        }
    }

    @Test("大量文件时不逐个起进程，预览仍然很快")
    func handlesManyFilesQuickly() async throws {
        let repo = try await TemporaryRepository()
        for index in 0..<300 {
            try repo.write("内容 \(index)\n", to: "file\(index).txt")
        }
        try await repo.commitAll("三百个文件")
        let store = try await makeStore(for: repo)
        let snapshot = try #require(try await store.capture(summary: "大工作区", identifier: "bulk"))
        try repo.write("改了\n", to: "file7.txt")

        let started = Date()
        let preview = try await store.preview(snapshot)
        let elapsed = Date().timeIntervalSince(started)

        #expect(preview.overwritten == ["file7.txt"])
        // 逐个 hash-object 的话三百个文件要几十秒。这里给足余量，
        // 只要没退化成一文件一进程就一定过得去。
        #expect(elapsed < 10)
    }
}
