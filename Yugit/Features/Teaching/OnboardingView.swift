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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("跳过") { finish() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }

                Text(step.title)
                    .font(.title3.weight(.semibold))

                Text(step.detail)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                if let concept = step.concept {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("顺带一提", systemImage: "lightbulb")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(concept)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .underPageBackgroundColor), in: .rect(cornerRadius: 6))
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private var footer: some View {
        HStack {
            // 进度点：让人知道还剩几步，不至于以为没完没了
            HStack(spacing: 5) {
                ForEach(steps.indices, id: \.self) { position in
                    Circle()
                        .fill(position == index ? Color.accentColor : Color.secondary.opacity(0.3))
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
