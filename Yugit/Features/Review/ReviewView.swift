import AIKit
import GitKit
import Observation
import SwiftUI

/// 提交前的本地 diff 评审。
@MainActor
@Observable
final class ReviewViewModel: Identifiable {

    nonisolated let id = UUID()

    private let repository: RepositoryViewModel

    private(set) var review: DiffReview?
    private(set) var isRunning = false
    var errorMessage: String?
    /// 展开状态。默认跟着等级走：格式化那类折叠，其余展开。
    var expanded: Set<UUID> = []

    init(repository: RepositoryViewModel) {
        self.repository = repository
    }

    func run(using store: AISettingsStore) async {
        guard let (provider, model) = store.makeProvider() else {
            errorMessage = AIError.notConfigured.localizedMessage
            return
        }

        isRunning = true
        defer { isRunning = false }
        errorMessage = nil

        do {
            // 评审的是**将要提交的内容**，所以看暂存区而不是工作区。
            // 看工作区会把还没决定要不要提交的实验性改动一起评了。
            let diff = try await repository.stagedDiff()
            guard !diff.isEmpty else {
                errorMessage = "暂存区是空的，先暂存一些改动再评审"
                return
            }

            let result = try await DiffReviewer(provider: provider, model: model)
                .review(diff: diff, branchName: repository.currentBranch?.name)

            review = result
            expanded = Set(result.findings.filter { $0.severity.isExpandedByDefault }.map(\.id))
        } catch let error as AIError {
            errorMessage = "\(error.localizedMessage)\n\(error.suggestion)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    func toggle(_ finding: ReviewFinding) {
        if expanded.contains(finding.id) {
            expanded.remove(finding.id)
        } else {
            expanded.insert(finding.id)
        }
    }
}

struct ReviewView: View {

    @Bindable var model: ReviewViewModel
    let onDismiss: () -> Void

    @Environment(AISettingsStore.self) private var aiSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 760, height: 620)
        .task {
            if model.review == nil { await model.run(using: aiSettings) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("提交前自查")
                .font(Theme.Font.title)
            Text("只看这次暂存的改动。AI 看不到需求文档，给的是「你可能没注意到的地方」，不是结论。")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if model.isRunning {
            ProgressView("正在通读改动…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let review = model.review {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !review.summary.isEmpty {
                        summaryCard(review.summary)
                    }

                    if let redaction = review.redaction, let summary = redaction.summary {
                        // 评审看的内容不完整时，结论也是不完整的——必须说出来
                        Label("\(summary)。这些部分没有被评审。", systemImage: "eye.slash")
                            .font(Theme.Font.secondary)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }

                    if review.findings.isEmpty {
                        EmptyStateView(
                            "没有发现值得指出的问题",
                            systemImage: "checkmark.circle",
                            description: "这不代表没有问题，只代表从 diff 本身看不出来",
                            compact: true
                        )
                    } else {
                        // 分级导航：鉴权/数据层置顶，格式化垫底且默认折叠
                        ForEach(ReviewFinding.Severity.allCases, id: \.self) { severity in
                            let findings = review.findings(of: severity)
                            if !findings.isEmpty {
                                severitySection(severity, findings: findings)
                            }
                        }
                    }
                }
                .padding(12)
            }
        } else if let error = model.errorMessage {
            EmptyStateView(
                "评审没能完成",
                systemImage: "exclamationmark.triangle",
                description: error,
                tone: .warning
            ) {
                Button("重试") { Task { await model.run(using: aiSettings) } }
            }
        } else {
            EmptyStateView(
                "还没有开始", systemImage: "sparkles",
                description: "点下面的「开始评审」"
            )
        }
    }

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("这次改动做了什么", systemImage: "text.alignleft")
                .font(Theme.Font.secondary.weight(.medium))
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(summary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Theme.Colors.raisedBackground, in: .rect(cornerRadius: 8))
    }

    private func severitySection(
        _ severity: ReviewFinding.Severity,
        findings: [ReviewFinding]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint(for: severity))
                    .frame(width: 8, height: 8)
                Text("\(severity.displayName)（\(findings.count)）")
                    .font(Theme.Font.secondary.weight(.medium))
            }

            ForEach(findings) { finding in
                FindingRow(
                    finding: finding,
                    tint: tint(for: severity),
                    isExpanded: model.expanded.contains(finding.id),
                    onToggle: { model.toggle(finding) }
                )
            }
        }
    }

    private func tint(for severity: ReviewFinding.Severity) -> Color {
        switch severity {
        case .critical: .red
        case .warning: .orange
        case .info: .blue
        case .nitpick: .secondary
        }
    }

    private var footer: some View {
        HStack {
            if let review = model.review, review.hasBlockingConcerns {
                Label("有需要重点确认的地方，建议看过再提交", systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.warning)
            }

            Spacer()

            if model.review != nil {
                Button("重新评审") { Task { await model.run(using: aiSettings) } }
                    .disabled(model.isRunning)
            } else {
                Button("开始评审") { Task { await model.run(using: aiSettings) } }
                    .disabled(model.isRunning)
            }

            // 评审永远不阻断提交：它是自查工具，不是门禁
            Button("知道了") { onDismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}

// MARK: - 单条意见

private struct FindingRow: View {

    let finding: ReviewFinding
    let tint: Color
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(finding.title)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 4) {
                            Text(finding.path)
                                .lineLimit(1)
                                .truncationMode(.head)
                            if let line = finding.line {
                                Text("第 \(line) 行")
                            }
                        }
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded && !finding.detail.isEmpty {
                Text(finding.detail)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
            }
        }
        .padding(8)
        .background(tint.opacity(0.06), in: .rect(cornerRadius: 6))
    }
}
