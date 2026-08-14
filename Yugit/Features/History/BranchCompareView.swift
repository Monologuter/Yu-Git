import GitKit
import Observation
import SwiftUI

/// 分支对比面板的状态。
@MainActor
@Observable
final class BranchCompareViewModel: Identifiable {

    nonisolated let id = UUID()

    let repository: RepositoryViewModel

    var base: String
    var target: String

    private(set) var comparison: BranchComparison?
    private(set) var isLoading = false
    var errorMessage: String?

    /// 可选的分支，本地在前、远程在后。
    var candidates: [String] {
        repository.localBranches.map(\.name) + repository.remoteBranches.map(\.name)
    }

    init(repository: RepositoryViewModel, target: String) {
        self.repository = repository
        self.target = target
        // 基准默认取当前分支——「这条分支相对我现在在的地方多了什么」
        // 是最常问的那个问题
        self.base = repository.currentBranch?.name ?? "main"
    }

    func reload() async {
        guard base != target else {
            comparison = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            comparison = try await repository.compareBranches(base: base, target: target)
        } catch {
            errorMessage = "对比失败：\(error)"
        }
    }

    func swap() async {
        let old = base
        base = target
        target = old
        await reload()
    }
}

/// 两个分支差了哪些提交、哪些文件。
struct BranchCompareView: View {

    @Bindable var model: BranchCompareViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 760, height: 500)
        .task { await model.reload() }
        .task(id: "\(model.base)|\(model.target)") { await model.reload() }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.regular) {
            Picker("基准", selection: $model.base) {
                ForEach(model.candidates, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 220)

            Button {
                Task { await model.swap() }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
            }
            .help("对调两边")

            Picker("对比", selection: $model.target) {
                ForEach(model.candidates, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 220)

            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(Theme.Spacing.loose)
    }

    @ViewBuilder
    private var content: some View {
        if model.base == model.target {
            EmptyStateView("选两个不同的分支", systemImage: "arrow.left.arrow.right", compact: true)
        } else if let comparison = model.comparison {
            if comparison.mergeBase == nil {
                // 这不是错误，是一个要说清楚的事实：两条历史毫无关系，
                // 「差了多少」这个问题在这里没有意义
                EmptyStateView(
                    "这两条分支没有共同起点",
                    systemImage: "questionmark.circle",
                    description: "它们是两段互不相关的历史，没有共同祖先可以作为对比的基准。",
                    tone: .warning
                )
            } else {
                HSplitView {
                    commitColumns(comparison).frame(minWidth: 420)
                    fileColumn(comparison).frame(minWidth: 240)
                }
            }
        } else {
            EmptyStateView("正在对比", systemImage: "clock", compact: true)
        }
    }

    private func commitColumns(_ comparison: BranchComparison) -> some View {
        VSplitView {
            commitList(
                title: "\(comparison.target) 有而 \(comparison.base) 没有",
                systemImage: "arrow.up",
                commits: comparison.ahead
            )
            commitList(
                title: "\(comparison.base) 有而 \(comparison.target) 没有",
                systemImage: "arrow.down",
                commits: comparison.behind
            )
        }
    }

    private func commitList(title: String, systemImage: String, commits: [Commit]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.tight) {
                Image(systemName: systemImage)
                Text(title)
                Text("\(commits.count)")
                    .foregroundStyle(Theme.Colors.decorativeText)
            }
            .font(Theme.Font.secondary)
            .foregroundStyle(Theme.Colors.secondaryText)
            .padding(.horizontal, Theme.Spacing.loose)
            .padding(.vertical, Theme.Spacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.sunkenBackground)

            if commits.isEmpty {
                Text("没有")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .padding(Theme.Spacing.loose)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(commits) { commit in
                    HStack(spacing: Theme.Spacing.regular) {
                        Text(commit.abbreviatedHash)
                            .font(Theme.Font.mono)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                        Text(commit.subject)
                            .font(Theme.Font.body)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(commit.author.name)
                            .font(Theme.Font.secondary)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func fileColumn(_ comparison: BranchComparison) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(comparison.target) 改了 \(comparison.files.count) 个文件")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                // 说清基准是共同祖先而不是对面的尖端。不说的话，用户会奇怪
                // 为什么另一条分支新加的文件没有出现在这个列表里。
                Text("从共同起点算起，不含 \(comparison.base) 后来的改动")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
            .padding(.horizontal, Theme.Spacing.loose)
            .padding(.vertical, Theme.Spacing.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.sunkenBackground)

            List(comparison.files) { file in
                HStack(spacing: Theme.Spacing.regular) {
                    Text(file.kind.letter)
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .frame(width: 14)
                        .help(file.kind.displayName)
                    Text(file.path)
                        .font(Theme.Font.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
            }
            .listStyle(.plain)
        }
    }

    private var footer: some View {
        HStack {
            if let comparison = model.comparison, comparison.hasDiverged {
                Label("两条分支已经分叉，合并时可能有冲突", systemImage: "arrow.triangle.branch")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.warning)
            }
            Spacer()
            Button("完成") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Theme.Spacing.loose)
    }
}
