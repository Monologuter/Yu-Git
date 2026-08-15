import AIKit
import GitKit
import SwiftUI

/// 对话式 Git 操作。
///
/// 说一句话，看一份计划，确认后执行。**预览不可跳过**——AI 理解错的时候，
/// 这是唯一能拦住它的地方；而看得懂计划本身也是在学 Git。
struct ChatView: View {

    @Bindable var model: ChatViewModel
    let onDismiss: () -> Void

    @Environment(AISettingsStore.self) private var aiSettings
    @State private var showsDestructiveConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 560)
        .confirmationDialog(
            "这份计划里有会丢东西的步骤",
            isPresented: $showsDestructiveConfirm
        ) {
            Button("我确认，执行", role: .destructive) {
                Task { await model.execute() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("其中包含丢弃未提交改动的操作。这些改动没进过 git 的对象库，reflog 也找不回来。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("说一句话")
                .font(Theme.Font.title)
            Text("例如「把 README 的改动单独提交」「新建一个 feature/登录 分支并切过去」。")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inputBox

                switch model.outcome {
                case .idle:
                    EmptyView()

                case let .clarification(question):
                    // 模型没听懂时反问，比硬凑一个计划安全得多
                    calloutCard(
                        "还需要确认一下", text: question,
                        icon: "questionmark.circle", tint: .blue)

                case let .unsupported(reason):
                    calloutCard(
                        "这件事做不了", text: reason,
                        icon: "hand.raised", tint: .orange)

                case let .failed(message):
                    calloutCard(
                        "出错了", text: message,
                        icon: "xmark.circle", tint: .red)

                case let .executed(completed, total):
                    calloutCard(
                        "执行完了",
                        text: "共 \(total) 步，成功 \(completed) 步。每一步都记在时间线上，⌘Z 可以逐步撤销。",
                        icon: "checkmark.circle", tint: .green)

                case let .ready(understanding):
                    if !understanding.isEmpty {
                        calloutCard(
                            "我的理解", text: understanding,
                            icon: "text.bubble", tint: .secondary)
                    }
                    planPreview
                }
            }
            .padding(12)
        }
    }

    private var inputBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $model.request)
                .font(Theme.Font.body)
                .frame(height: 64)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.contentBackground, in: .rect(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if model.request.isEmpty {
                        Text("想让它做什么？")
                            .foregroundStyle(Theme.Colors.tertiaryText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.separator) }

            HStack {
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                Button("想一想") {
                    Task { await model.plan(using: aiSettings) }
                }
                .disabled(model.request.trimmingCharacters(in: .whitespaces).isEmpty || model.isWorking)
            }
        }
    }

    private var planPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("它打算这么做（共 \(model.steps.count) 步）")
                .font(Theme.Font.secondary.weight(.medium))

            ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                StepCard(index: index + 1, step: step)
            }

            // 每一步都走同一个写入口，所以事后能逐步退回来
            Label("执行后每一步都会记在时间线上，可以逐步撤销。", systemImage: "clock.arrow.circlepath")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
    }

    private func calloutCard(_ title: String, text: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(Theme.Font.secondary.weight(.medium))
                .foregroundStyle(tint)
            Text(text)
                .font(Theme.Font.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 6))
    }

    private var footer: some View {
        HStack {
            if model.hasDestructiveStep {
                Label("含会丢东西的步骤", systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.danger)
            }

            Spacer()

            Button("清空") { model.reset() }
                .disabled(model.isWorking)

            Button("关闭") { onDismiss() }
                .keyboardShortcut(.cancelAction)

            Button("按计划执行") {
                if model.hasDestructiveStep {
                    showsDestructiveConfirm = true
                } else {
                    Task { await model.execute() }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canExecute)
        }
        .padding(12)
    }
}

// MARK: - 一步

private struct StepCard: View {

    let index: Int
    let step: ChatViewModel.ResolvedStep

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index)")
                .font(Theme.Font.caption.monospacedDigit())
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(width: 18, height: 18)
                .background(Theme.Colors.fillQuaternary, in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(step.operation.summary)
                        .font(Theme.Font.callout)
                    if step.isDestructive {
                        Text("会丢东西")
                            .font(Theme.Font.caption)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.Colors.danger.opacity(0.15), in: .capsule)
                            .foregroundStyle(Theme.Colors.danger)
                    }
                }

                if !step.reason.isEmpty {
                    Text(step.reason)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                // 透明命令层贯穿到这里：看得懂计划本身就是在学 Git
                Text(step.operation.equivalentCommand)
                    .font(Theme.Font.mono)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(5)
                    .background(Theme.Colors.sunkenBackground, in: .rect(cornerRadius: 4))
            }
        }
        .padding(8)
        .background(Theme.Colors.raisedBackground, in: .rect(cornerRadius: 6))
    }
}
