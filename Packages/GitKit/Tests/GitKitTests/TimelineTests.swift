import Foundation
import Testing

@testable import GitKit

@Suite("仓库时间线")
struct TimelineTests {

    private func makeActor(on repository: TemporaryRepository) async throws -> (RepoActor, InMemoryOperationLog) {
        let log = InMemoryOperationLog()
        let actor = try await RepoActor(
            root: repository.url, client: repository.client, operationLog: log)
        return (actor, log)
    }

    private func content(of path: String, in repository: TemporaryRepository) throws -> String {
        try String(contentsOf: repository.url.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: - 自动打点

    @Test("丢弃改动前自动留下快照")
    func snapshotsBeforeDiscard() async throws {
        // 丢弃的内容从未进过 git 对象库，reflog 也救不回来，
        // 快照是唯一的退路
        let repository = try await TemporaryRepository()
        try repository.write("已提交\n", to: "a.txt")
        try await repository.commitAll("base")
        try repository.write("辛苦写了半天的改动\n", to: "a.txt")

        let (actor, log) = try await makeActor(on: repository)
        try await actor.perform(.discard(paths: ["a.txt"]))

        let records = await log.recent(limit: 10)
        let record = try #require(records.first)
        #expect(record.snapshotReference != nil, "危险操作必须留退路")

        // 改动确实被丢了
        #expect(try content(of: "a.txt", in: repository) == "已提交\n")

        // 但能从时间线找回来
        let entries = try await actor.timelineEntries()
        let entry = try #require(entries.first { $0.record.operation.kind == .discard })
        #expect(entry.canUndo)

        try await actor.undo(entry)
        #expect(try content(of: "a.txt", in: repository) == "辛苦写了半天的改动\n")
    }

    @Test("amend 前自动留下快照")
    func snapshotsBeforeAmend() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("原始说明")

        let (actor, log) = try await makeActor(on: repository)
        try await actor.perform(.commit(message: "改过的说明", amend: true))

        let records = await log.recent(limit: 10)
        let record = try #require(records.first { $0.operation.kind == .amend })
        #expect(record.snapshotReference != nil, "改写历史前要留退路")
    }

    @Test("安全操作不拍快照")
    func skipsSnapshotForSafeOperations() async throws {
        // 拍快照要遍历工作区，每次暂存都拍会明显拖慢
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")

        let (actor, log) = try await makeActor(on: repository)
        try await actor.perform(.stage(paths: ["a.txt"]))

        let records = await log.recent(limit: 10)
        let record = try #require(records.first)
        #expect(record.operation.hazard == .none)
        #expect(record.snapshotReference == nil)
    }

    // MARK: - 撤销

    @Test("撤销本身也留下快照，因此可以再撤回去")
    func undoIsItselfUndoable() async throws {
        // 「撤销撤错了」恰恰是最需要退路的时刻
        let repository = try await TemporaryRepository()
        try repository.write("初始\n", to: "a.txt")
        try await repository.commitAll("base")
        try repository.write("改动内容\n", to: "a.txt")

        let (actor, _) = try await makeActor(on: repository)
        try await actor.perform(.discard(paths: ["a.txt"]))

        let entries = try await actor.timelineEntries()
        let discardEntry = try #require(entries.first { $0.record.operation.kind == .discard })
        try await actor.undo(discardEntry)
        #expect(try content(of: "a.txt", in: repository) == "改动内容\n")

        // 撤销之前的状态（也就是「丢弃后」）也该有快照可回
        let snapshots = try await actor.timelineSnapshots()
        #expect(snapshots.contains { $0.summary.contains("撤销") }, "撤销操作自己也要留点")
    }

    @Test("没有快照的条目无法撤销，且给出中文说明")
    func rejectsUndoWithoutSnapshot() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")

        let (actor, _) = try await makeActor(on: repository)
        try await actor.perform(.stage(paths: ["a.txt"]))

        let entries = try await actor.timelineEntries()
        let entry = try #require(entries.first)
        #expect(!entry.canUndo)

        await #expect(throws: TimelineError.self) {
            try await actor.undo(entry)
        }
    }

    // MARK: - 外部改动

    @Test("为外部改动打点，覆盖终端与 agent 的操作")
    func capturesExternalChanges() async throws {
        // 这是 Claude Code 的 checkpoint 覆盖不到的部分：
        // 跨 session、跨工具、终端里直接跑的命令
        let repository = try await TemporaryRepository()
        try repository.write("初始\n", to: "a.txt")
        try await repository.commitAll("base")

        let (actor, _) = try await makeActor(on: repository)

        // 模拟 agent 在终端里改了文件
        try repository.write("agent 写的内容\n", to: "a.txt")
        let snapshot = try #require(await actor.captureExternalChange(summary: "Claude 第 1 轮改动"))

        // 之后又被别的东西改坏
        try repository.write("被改坏了\n", to: "a.txt")
        try await actor.restoreSnapshot(snapshot)

        #expect(try content(of: "a.txt", in: repository) == "agent 写的内容\n")
    }

    @Test("时间线条目按记录顺序关联快照")
    func linksEntriesToSnapshots() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")

        let (actor, _) = try await makeActor(on: repository)
        try repository.write("改动 1\n", to: "a.txt")
        try await actor.perform(.discard(paths: ["a.txt"]))
        try await actor.perform(.stage(paths: ["a.txt"]))

        let entries = try await actor.timelineEntries()

        #expect(entries.count == 2)
        #expect(entries[0].canUndo, "discard 有快照")
        #expect(!entries[1].canUndo, "stage 没有快照")
        #expect(entries[0].summary.contains("丢弃"))
    }

    @Test("快照数量超过上限时清理最旧的")
    func prunesOldSnapshots() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")

        let store = try await SnapshotStore.open(root: repository.url, client: repository.client)
        let timeline = Timeline(log: InMemoryOperationLog(), snapshots: store)

        for index in 1...5 {
            try repository.write("第 \(index) 次\n", to: "a.txt")
            _ = await timeline.captureExternalChange(summary: "第 \(index) 次外部改动")
        }
        try await store.prune(keeping: 3)

        let remaining = try await timeline.allSnapshots()
        #expect(remaining.count == 3)
    }
}
