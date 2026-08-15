import GitKit
import SwiftUI

/// 新手引导。
///
/// 目标不是教会 Git 的全部概念，而是让第一次用的人知道**这个界面上哪里能做什么**。
/// 概念解释挂在用到它的那一步旁边，用到时才讲——不做术语表。
struct OnboardingView: View {

    let onDismiss: () -> Void

    @AppStorage("com.chenya.yugit.hasSeenTour") private var hasSeenTour = false
    @State private var index = 0

    private var steps: [OnboardingStep] { OnboardingStep.repositoryTour }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 520, height: 380)
    }

    @ViewBuilder
    private var content: some View {
        if steps.indices.contains(index) {
            let step = steps[index]

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("第 \(index + 1) / \(steps.count) 步")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Spacer()
                    Button("跳过") { finish() }
                        .buttonStyle(.borderless)
                        .font(Theme.Font.secondary)
                }

                Text(step.title)
                    .font(Theme.Font.sheetTitle)

                Text(step.detail)
                    .font(Theme.Font.callout)
                    .fixedSize(horizontal: false, vertical: true)

                if let concept = step.concept {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("顺带一提", systemImage: "lightbulb")
                            .font(Theme.Font.secondary.weight(.medium))
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text(concept)
                            .font(Theme.Font.callout)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Theme.Colors.sunkenBackground, in: .rect(cornerRadius: Theme.Radius.medium))
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack {
            // 进度点：让人知道还剩几步，不至于以为没完没了。
            // 当前那一点用品牌色而不是强调色——这里没有任何选中态要区分，
            // 而首次运行恰恰是产品该露脸的地方。
            HStack(spacing: 5) {
                ForEach(steps.indices, id: \.self) { position in
                    Circle()
                        .fill(
                            position == index
                                ? Theme.Colors.brand : Theme.Colors.decorativeText.opacity(0.5)
                        )
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            Button("上一步") { index -= 1 }
                .disabled(index == 0)

            if index == steps.count - 1 {
                Button("开始使用") { finish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("下一步") { index += 1 }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private func finish() {
        hasSeenTour = true
        onDismiss()
    }
}
