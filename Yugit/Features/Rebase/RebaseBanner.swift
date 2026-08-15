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
            VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                HStack(spacing: Theme.Spacing.regular) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Colors.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline(progress))
                            .font(Theme.Font.callout.weight(.medium))
                        Text(detail(progress))
                            .font(Theme.Font.secondary)
                            .foregroundStyle(Theme.Colors.secondaryText)
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
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .textSelection(.enabled)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "xmark.circle")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.danger)
                        .textSelection(.enabled)
                }
            }
            .padding(Theme.Spacing.regular)
            // 用主题的警示浅底，不是 orange 加透明度：后者叠在不同主题的
            // 底色上会得到四种不同的结果，而 warn-wash 是每套主题各自量过的
            .background(Theme.Colors.warningWash)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Colors.separator).frame(height: 1)
            }
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
