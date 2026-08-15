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
}
