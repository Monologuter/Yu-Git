import GitKit
import SwiftUI

/// rebase 卡在半路时顶部的提示条。
///
/// 这是 Git 里最容易让人懵的状态：命令行下只有一段 hint 文字，关掉终端就没了，
/// 之后每敲一条命令都被告知「你正处在 rebase 中」却不知道该怎么出去。
/// 所以这条横幅只要状态还在就一直挂着，并且把出路直接做成按钮。
struct RebaseBanner: View {

    @Bindable var repository: RepositoryViewModel

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        if let progress = repository.rebaseProgress {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline(progress))
                            .font(.callout.weight(.medium))
                        Text(detail(progress))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isWorking { ProgressView().controlSize(.small) }

                    // 「放弃」放在左边、「继续」放在右边：继续是需要先解决冲突的那条路，
                    // 不该做成一眼就想点的默认选项
                    Button("放弃整理") {
                        Task { await abort() }
                    }
                    .disabled(isWorking)

                    Button("继续") {
                        Task { await resume() }
                    }
                    .disabled(isWorking || !progress.conflictedPaths.isEmpty)
                    .help(
                        progress.conflictedPaths.isEmpty
                            ? "接着重放剩下的提交" : "还有冲突没解决，先在变更列表里处理并暂存")
                }

                if let backupTag = repository.lastBackupTag {
                    Label(
                        "放弃后仍可用备份 tag `\(backupTag)` 回到整理之前的状态",
                        systemImage: "shield"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .overlay(alignment: .bottom) { Divider() }
        }
    }

    private func headline(_ progress: RebaseProgress) -> String {
        progress.conflictedPaths.isEmpty
            ? "正在整理提交历史" : "整理提交时遇到冲突"
    }

    private func detail(_ progress: RebaseProgress) -> String {
        var text = progress.total > 0 ? "进行到第 \(progress.current) / \(progress.total) 条。" : ""
        if !progress.conflictedPaths.isEmpty {
            text += "冲突文件：\(progress.conflictedPaths.joined(separator: "、"))。解决并暂存后点「继续」。"
        }
        return text
    }

    private func abort() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        await repository.abortRebase()
        await repository.reloadRebaseProgress()
    }

    private func resume() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil

        let outcome = await repository.continueRebase()
        if case let .failed(message) = outcome { errorMessage = message }
        await repository.reloadRebaseProgress()
    }
}
