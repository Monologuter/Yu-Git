import GitKit
import SwiftUI

/// 危险操作的确认对话框。
///
/// 教学模式的落点。固定回答三个问题：会发生什么、能不能撤销、怎么撤销。
/// 不写「此操作有风险，是否继续？」这种什么也没说的话。
struct HazardDialog: View {

    let warning: HazardWarning
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: warning.isDestructive ? "trash.circle.fill" : "pencil.circle.fill")
                    .font(Theme.Font.sheetTitle)
                    .foregroundStyle(warning.isDestructive ? .red : .purple)
                Text(warning.title)
                    .font(Theme.Font.title)
            }

            section("会发生什么", text: warning.consequence)
            section(
                "能不能退回来",
                text: warning.recovery,
                tint: warning.isDestructive ? Theme.Colors.warning : Theme.Colors.success
            )

            // 越是危险的一步，越该让人看清它到底等价于哪条命令
            VStack(alignment: .leading, spacing: 4) {
                Text("等价的 git 命令")
                    .font(Theme.Font.secondary.weight(.medium))
                    .foregroundStyle(Theme.Colors.secondaryText)
                Text(warning.equivalentCommand)
                    .font(Theme.Font.mono)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.Colors.sunkenBackground, in: .rect(cornerRadius: 4))
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                // 确认按钮上写的是动作本身，让人在点之前再读一遍自己要做什么
                Button(warning.confirmLabel, role: warning.isDestructive ? .destructive : nil) {
                    onConfirm()
                }
                .keyboardShortcut(warning.isDestructive ? .none : .defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func section(_ title: String, text: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Font.secondary.weight(.medium))
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(markdown(text))
                .font(Theme.Font.callout)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 预警文案里用 `**` 强调关键处，渲染成粗体。
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
