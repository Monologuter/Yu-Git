import Foundation
import GitKit

extension RepositoryViewModel {

    /// 重新读取时间线。
    func reloadTimeline() async {
        do {
            timelineEntries = try await repository.timelineEntries()
            timelineSnapshots = try await repository.timelineSnapshots()
        } catch {
            failure = FailurePresentation(from: error)
        }
    }

    /// 最近一次可撤销的操作，供全局 ⌘Z 使用。
    var mostRecentUndoableEntry: TimelineEntry? {
        timelineEntries.last { $0.canUndo }
    }

    func undo(_ entry: TimelineEntry) async {
        await mutate { try await self.repository.undo(entry) }
        await reloadTimeline()
    }

    /// 全局撤销：退回最近一次留有快照的操作之前。
    func undoMostRecent() async {
        guard let entry = mostRecentUndoableEntry else { return }
        await undo(entry)
    }

    func restore(_ snapshot: Snapshot) async {
        await mutate { try await self.repository.restoreSnapshot(snapshot) }
        await reloadTimeline()
    }

    /// 外部改动打点。
    ///
    /// 终端里的 git、编辑器保存、agent 写的代码都不经过我们的写入口，
    /// 却同样需要退路。限流是必须的：编辑器每次保存都拍一张会让仓库迅速膨胀。
    func captureExternalChangeIfNeeded() async {
        let now = Date()
        if let last = lastExternalCapture, now.timeIntervalSince(last) < Self.externalCaptureInterval {
            return
        }

        // 工作区干净就没什么可存的
        guard let status, !status.isClean else { return }

        lastExternalCapture = now
        _ = await repository.captureExternalChange(
            summary: "外部改动 · \(now.formatted(date: .omitted, time: .standard))")
    }

    /// 算出恢复到某张快照会改动哪些文件。
    ///
    /// 只读，不走写队列——它是要在对话框弹出那一刻就显示的，
    /// 排在写队列后面等于每次都先卡一下。
    func previewRestore(_ snapshot: Snapshot) async -> SnapshotPreview? {
        try? await repository.previewRestore(snapshot)
    }

    /// 只恢复点名的那几个文件。
    func restore(_ snapshot: Snapshot, paths: [String]) async {
        await mutate {
            try await self.repository.restore(snapshot, paths: paths)
        }
        await reloadTimeline()
    }

    /// 给快照起个人话名字。起过名字的不会被自动清理。
    func setSnapshotLabel(_ label: String, for snapshot: Snapshot) async {
        try? await repository.setSnapshotLabel(label, for: snapshot)
        await reloadTimeline()
    }

    func snapshotLabel(for snapshot: Snapshot) async -> String? {
        await repository.snapshotLabel(for: snapshot)
    }

    /// 哪些快照被标注过。一次问完，时间线列表拿它标记。
    func labelledSnapshots() async -> Set<String> {
        await repository.labelledSnapshots()
    }
}
