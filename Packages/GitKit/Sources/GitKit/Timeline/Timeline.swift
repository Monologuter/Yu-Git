import Foundation

/// 时间线上的一项：一次操作，以及它执行前的仓库快照。
public struct TimelineEntry: Sendable, Equatable, Identifiable {

    public var id: UUID { record.id }

    public let record: OperationRecord
    /// 操作执行**前**的工作区快照。有它才能撤销。
    public let snapshot: Snapshot?

    public var canUndo: Bool { snapshot != nil }

    public var timestamp: Date { record.timestamp }
    public var summary: String { record.operation.summary }

    public init(record: OperationRecord, snapshot: Snapshot?) {
        self.record = record
        self.snapshot = snapshot
    }
}

/// 仓库时间线：把操作日志与工作区快照绑在一起，支撑「无畏 Undo」。
///
/// 与 Claude Code 的 `/rewind` 相比，这里刻意覆盖三种它管不到的情形
/// （见 `docs/01` 差异化设计 ①）：跨 session、跨工具、以及终端里直接跑的命令。
public actor Timeline {

    /// 保留多少张快照。每张快照会让对应的对象免于 gc，无限留会让仓库一直涨。
    public static let snapshotRetentionCount = 50

    private let log: OperationLogging
    private let snapshots: SnapshotStore

    public init(log: OperationLogging, snapshots: SnapshotStore) {
        self.log = log
        self.snapshots = snapshots
    }

    public static func open(root: URL, client: GitClient) async throws -> Timeline {
        let log = try await FileOperationLog(repository: root, client: client)
        let snapshots = try await SnapshotStore.open(root: root, client: client)
        return Timeline(log: log, snapshots: snapshots)
    }

    // MARK: - 记录

    /// 操作执行前调用：判断要不要拍快照。
    ///
    /// 不是每个操作都拍——拍快照要遍历工作区，高频操作上会拖慢明显。
    /// 只有 git 自身救不回来的操作才必须留退路。
    public func snapshotIfNeeded(before operation: GitOperation) async -> Snapshot? {
        guard operation.hazard != .none else { return nil }

        let identifier = "\(Int(Date().timeIntervalSince1970 * 1000))-\(operation.kind.rawValue)"
        return try? await snapshots.capture(
            summary: "执行「\(operation.summary)」之前",
            identifier: identifier
        )
    }

    /// 为外部改动打点。
    ///
    /// 终端里的 git、编辑器保存、agent 写的代码都不经过我们的写入口，
    /// 却同样需要退路——这正是 Claude Code 的 checkpoint 覆盖不到的部分。
    @discardableResult
    public func captureExternalChange(summary: String) async -> Snapshot? {
        let identifier = "\(Int(Date().timeIntervalSince1970 * 1000))-external"
        return try? await snapshots.capture(summary: summary, identifier: identifier)
    }

    public func record(_ record: OperationRecord) async {
        try? await log.record(record)
        // 顺手清理，避免快照无限累积
        try? await snapshots.prune(keeping: Self.snapshotRetentionCount)
    }

    // MARK: - 查询

    /// 时间线条目，按时间正序。
    public func entries(limit: Int = 100) async throws -> [TimelineEntry] {
        let records = try await log.recent(limit: limit)
        let available = try await snapshots.list()
        let byReference = Dictionary(uniqueKeysWithValues: available.map { ($0.reference, $0) })

        return records.map { record in
            TimelineEntry(
                record: record,
                snapshot: record.snapshotReference.flatMap { byReference[$0] }
            )
        }
    }

    // MARK: - 撤销

    /// 把工作区退回到某一项操作执行之前。
    ///
    /// 撤销本身也会先拍一张快照——否则用户撤销之后就无法再重做，
    /// 而「撤销撤错了」恰恰是最需要退路的时刻。
    public func undo(_ entry: TimelineEntry) async throws {
        guard let snapshot = entry.snapshot else {
            throw TimelineError.snapshotUnavailable(summary: entry.summary)
        }

        _ = await captureExternalChange(summary: "撤销「\(entry.summary)」之前")
        try await snapshots.restore(snapshot)
    }

    /// 直接恢复到某张快照。
    public func restore(_ snapshot: Snapshot) async throws {
        _ = await captureExternalChange(summary: "恢复到「\(snapshot.summary)」之前")
        try await snapshots.restore(snapshot)
    }

    public func allSnapshots() async throws -> [Snapshot] {
        try await snapshots.list()
    }

    /// 恢复到某张快照会改动哪些文件。只读，不动仓库。
    public func previewRestore(_ snapshot: Snapshot) async throws -> SnapshotPreview {
        try await snapshots.preview(snapshot)
    }

    /// 只恢复点名的那几个文件。
    ///
    /// 和全量恢复一样先给当前状态拍一张——这一步本身也得可撤销。
    public func restore(_ snapshot: Snapshot, paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        _ = await captureExternalChange(
            summary: "恢复「\(snapshot.summary)」的 \(paths.count) 个文件之前")
        try await snapshots.restore(snapshot, paths: paths)
    }

    /// 给快照起个人话名字。标注过的快照不会被自动清理掉。
    public func setLabel(_ label: String, for snapshot: Snapshot) async throws {
        try await snapshots.setLabel(label, for: snapshot)
    }

    public func label(for snapshot: Snapshot) async -> String? {
        await snapshots.label(for: snapshot)
    }

    public func labelledCommits() async -> Set<String> {
        await snapshots.labelledCommits()
    }
}

public enum TimelineError: Error, Sendable, Equatable {
    /// 这一项没有快照可退——多半是当时判定为安全操作而没打点。
    case snapshotUnavailable(summary: String)
}

extension TimelineError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .snapshotUnavailable(summary):
            "「\(summary)」没有可用的快照，无法撤销"
        }
    }
}
