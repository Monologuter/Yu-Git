import GitKit
import SwiftUI

/// 待确认的丢弃请求。sheet(item:) 需要 Identifiable。
struct DiscardRequest: Identifiable {
    let paths: [String]
    var id: String { paths.joined(separator: "\u{1F}") }
}

/// 一个待确认的 Quick Action。sheet(item:) 需要 Identifiable，
/// 而动作和提交要成对传过去，所以打个包。
struct PendingQuickAction: Identifiable {
    let action: QuickAction
    let commit: Commit
    var id: String { "\(commit.hash)-\(action.hashValue)" }
}

/// 中栏：工作区变更与提交历史。
struct ChangesView: View {

    @Bindable var repository: RepositoryViewModel
    let onResolveConflicts: () -> Void
    let onReview: () -> Void
    @State private var section = Section.changes
    @State private var pendingDiscard: [String]?
    @State private var pendingQuickAction: PendingQuickAction?

    enum Section: String, CaseIterable, Identifiable {
        case changes = "变更"
        case history = "历史"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 「变更」上带一个待处理计数。
            //
            // 不带的话，人得先切过去才知道有没有改动——而这恰恰是打开客户端后
            // 最先想知道的一件事。有冲突时改成警示图标，因为冲突不是"几个文件"
            // 的量级问题，是"现在什么都别干先解决它"的性质问题。
            Picker("", selection: $section) {
                ForEach(Section.allCases) { section in
                    if section == .changes {
                        Text(changesLabel).tag(section)
                    } else {
                        Text(section.rawValue).tag(section)
                    }
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Theme.Spacing.regular)

            Divider()

            switch section {
            case .changes:
                changeList
                Divider()
                CommitPanel(repository: repository, onReview: onReview)
            case .history:
                historyList
            }
        }
        .sheet(item: $pendingQuickAction) { pending in
            QuickActionSheet(
                action: pending.action,
                commit: pending.commit,
                repository: repository,
                onDismiss: { pendingQuickAction = nil }
            )
        }
        // 危险操作走统一的预警对话框：会发生什么、能不能撤销、怎么撤销，
        // 三个问题一次答完，并附上等价的 git 命令（教学模式）
        .sheet(
            item: Binding(
                get: { pendingDiscard.map { DiscardRequest(paths: $0) } },
                set: { if $0 == nil { pendingDiscard = nil } }
            )
        ) { request in
            if let warning = GitOperation.discard(paths: request.paths)
                .warning(hasSnapshot: true)
            {
                HazardDialog(warning: warning) {
                    Task { await repository.discard(request.paths) }
                    pendingDiscard = nil
                } onCancel: {
                    pendingDiscard = nil
                }
            }
        }
    }

    /// 「变更」分段上显示的文字。
    ///
    /// 计数用去重后的路径数，不是暂存 + 未暂存两个数组之和：
    /// 同一个文件既有已暂存的 hunk 又有未暂存的 hunk 时会同时出现在两边，
    /// 直接相加会把它数成两个文件，用户看到的数字对不上眼前的列表。
    private var changesLabel: String {
        if !repository.conflictedEntries.isEmpty {
            return "变更 ⚠"
        }
        let paths = Set(
            (repository.stagedEntries + repository.unstagedEntries).map(\.path))
        return paths.isEmpty ? "变更" : "变更 \(paths.count)"
    }

    // MARK: - 变更

    @ViewBuilder
    private var changeList: some View {
        if !repository.hasChanges && repository.conflictedEntries.isEmpty {
            ContentUnavailableView(
                "工作区干净",
                systemImage: "checkmark.circle",
                description: Text("没有待处理的改动")
            )
            .frame(maxHeight: .infinity)
        } else {
            List(selection: $repository.selectedFile) {
                if !repository.conflictedEntries.isEmpty {
                    SwiftUI.Section {
                        ForEach(repository.conflictedEntries, id: \.path) { entry in
                            FileRow(entry: entry)
                                .tag(RepositoryViewModel.FileSelection(path: entry.path, isStaged: false))
                        }
                    } header: {
                        HStack {
                            Text("冲突（\(repository.conflictedEntries.count)）")
                            Spacer()
                            // 冲突文件就在眼前时给个直达入口，比让人去翻命令面板顺手
                            Button("解决…") { onResolveConflicts() }
                                .buttonStyle(.borderless)
                                .font(.caption)
                        }
                    }
                }

                if !repository.stagedEntries.isEmpty {
                    SwiftUI.Section {
                        ForEach(repository.stagedEntries, id: \.path) { entry in
                            FileRow(entry: entry, showsIndexStatus: true)
                                .tag(RepositoryViewModel.FileSelection(path: entry.path, isStaged: true))
                                .contextMenu {
                                    Button("取消暂存") {
                                        Task { await repository.unstage([entry.path]) }
                                    }
                                }
                        }
                    } header: {
                        sectionHeader("已暂存", count: repository.stagedEntries.count) {
                            Button("全部取消") {
                                Task { await repository.unstage(repository.stagedEntries.map(\.path)) }
                            }
                        }
                    }
                }

                if !repository.unstagedEntries.isEmpty {
                    SwiftUI.Section {
                        ForEach(repository.unstagedEntries, id: \.path) { entry in
                            FileRow(entry: entry)
                                .tag(RepositoryViewModel.FileSelection(path: entry.path, isStaged: false))
                                .contextMenu {
                                    Button("暂存") {
                                        Task { await repository.stage([entry.path]) }
                                    }
                                    if entry.kind != .untracked {
                                        Button("丢弃改动…", role: .destructive) {
                                            pendingDiscard = [entry.path]
                                        }
                                    }
                                }
                        }
                    } header: {
                        sectionHeader("未暂存", count: repository.unstagedEntries.count) {
                            Button("全部暂存") {
                                Task { await repository.stage(repository.unstagedEntries.map(\.path)) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(
        _ title: String,
        count: Int,
        @ViewBuilder action: () -> some View
    ) -> some View {
        HStack {
            Text("\(title)（\(count)）")
            Spacer()
            action()
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    // MARK: - 历史

    @ViewBuilder
    private var historyList: some View {
        if repository.commits.isEmpty {
            ContentUnavailableView(
                "尚无提交",
                systemImage: "clock",
                description: Text("这个仓库还没有任何 commit")
            )
        } else {
            CommitHistoryView(
                commits: repository.commits,
                graph: repository.graph,
                selection: $repository.selectedCommit,
                onReachEnd: {
                    Task { await repository.loadMoreCommits() }
                },
                onQuickAction: { action, commit in
                    pendingQuickAction = PendingQuickAction(action: action, commit: commit)
                }
            )
        }
    }
}

/// 提交面板。
struct CommitPanel: View {

    @Bindable var repository: RepositoryViewModel
    let onReview: () -> Void
    @Environment(AISettingsStore.self) private var aiSettings
    @FocusState private var isMessageFocused: Bool

    /// AI 起草按钮。
    ///
    /// 生成的内容直接进提交框且可编辑——这是刻意的：不弹窗、不做「接受/拒绝」的二选一，
    /// 因为大多数时候用户想做的是「在它的基础上改一句」，而不是整段收下或整段丢掉。
    private var aiDraftButton: some View {
        Button {
            Task { await repository.generateCommitMessage(using: aiSettings) }
        } label: {
            if repository.aiState.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Label("AI 起草", systemImage: "sparkles")
            }
        }
        .disabled(repository.aiState.isRunning || repository.stagedEntries.isEmpty)
        .help(
            repository.stagedEntries.isEmpty
                ? "先暂存一些改动，AI 才知道要描述什么" : "根据暂存的改动起草提交信息，生成后可直接编辑")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $repository.commitMessage)
                .font(.body)
                .frame(height: 72)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if repository.commitMessage.isEmpty {
                        Text("提交说明")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(.separator)
                }
                .focused($isMessageFocused)

            HStack {
                Toggle("修改上一条提交", isOn: $repository.isAmending)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: repository.isAmending) { _, isOn in
                        // 勾上就把上一条的说明带出来，省得用户重打一遍
                        if isOn && repository.commitMessage.isEmpty {
                            Task { await repository.prepareAmend() }
                        }
                    }

                Spacer()

                // 没配 AI 的用户看不到这些按钮，界面上不留任何 AI 痕迹
                if aiSettings.isAvailable {
                    Button {
                        onReview()
                    } label: {
                        Label("自查", systemImage: "checkmark.shield")
                    }
                    .disabled(repository.stagedEntries.isEmpty)
                    .help("提交前让 AI 通读暂存的改动，按风险分级列出值得确认的地方")

                    aiDraftButton
                }

                Button("提交") {
                    Task { await repository.commit() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!repository.canCommit)
            }

            if let summary = repository.aiState.redactionSummary {
                // 脱敏做了什么必须说出来，否则用户以为 AI 看到了全部改动
                Label(summary, systemImage: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = repository.aiState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if repository.isAmending {
                // amend 会生成新的 commit hash，已推送的提交再推就需要 force
                Label("修改后 commit hash 会变，若已推送则需要 force push", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
    }
}
