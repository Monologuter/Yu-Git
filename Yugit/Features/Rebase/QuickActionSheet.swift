import GitKit
import SwiftUI

/// Quick Action 的确认面板。
///
/// 改写历史是不可逆的（虽然有备份 tag 兜底），所以哪怕是「一步到位」的动作
/// 也要先把「将要发生什么」摆出来。reword 还得在这里收一段新信息。
struct QuickActionSheet: View {

    let action: QuickAction
    let commit: Commit
    @Bindable var repository: RepositoryViewModel
    let onDismiss: () -> Void

    @State private var message = ""
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(action.title, systemImage: action.systemImage)
                    .font(Theme.Font.title)
                Text(action.explanation)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            GroupBox {
                HStack(spacing: 8) {
                    Text(commit.abbreviatedHash)
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text(commit.subject)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if action.needsMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新的提交信息")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    TextEditor(text: $message)
                        .font(Theme.Font.mono)
                        .frame(height: 100)
                        .scrollContentBackground(.hidden)
                        .background(Theme.Colors.contentBackground, in: .rect(cornerRadius: 4))
                        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator) }
                }
            }

            Label("开始前会自动打一个备份 tag，随时可以退回来", systemImage: "shield")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.secondaryText)

            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.circle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.danger)
                    .textSelection(.enabled)
            }

            HStack {
                if isRunning { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("执行") {
                    Task { await run() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isRunning || (action.needsMessage && message.trimmed.isEmpty))
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear {
            // reword 带上原信息作起点：改一句比从头写一遍常见得多
            if action.needsMessage {
                message =
                    commit.body.isEmpty
                    ? commit.subject : "\(commit.subject)\n\n\(commit.body)"
            }
        }
    }

    private func run() async {
        isRunning = true
        defer { isRunning = false }
        errorMessage = nil

        guard
            let plan = action.makePlan(
                target: commit,
                in: repository.commits,
                message: action.needsMessage ? message : nil
            )
        else {
            errorMessage = "这条提交不在可整理的范围内。可以先向下滚动加载更多历史再试。"
            return
        }

        let outcome = await repository.runRebase(
            plan, summary: action.summary(subject: commit.subject))

        switch outcome {
        case .completed:
            onDismiss()
        case let .conflicted(paths, _):
            errorMessage =
                "重放到某条提交时发生冲突：\(paths.joined(separator: "、"))。已停在这一步，可以在变更列表里解决后继续。"
            onDismiss()
        case let .failed(message):
            errorMessage = message
        }
    }
}

extension String {
    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
