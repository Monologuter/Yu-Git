import GitKit
import SwiftUI

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
            Picker("", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()

            switch section {
            case .changes:
                changeList
                Divider()
                CommitPanel(repository: repository)
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
        .confirmationDialog(
            "确定丢弃这些改动？",
            isPresented: Binding(
                get: { pendingDiscard != nil },
                set: { if !$0 { pendingDiscard = nil } }
            ),
            presenting: pendingDiscard
        ) { paths in
            Button("丢弃 \(paths.count) 个文件的改动", role: .destructive) {
                Task { await repository.discard(paths) }
                pendingDiscard = nil
            }
            Button("取消", role: .cancel) { pendingDiscard = nil }
        } message: { _ in
            // 这类改动从未进过 git 的对象库，reflog 也找不回来
            Text("这些改动没有提交过，丢弃后 git 无法找回。")
        }
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
                    SwiftUI.Section("冲突") {
                        ForEach(repository.conflictedEntries, id: \.path) { entry in
                            FileRow(entry: entry)
                                .tag(RepositoryViewModel.FileSelection(path: entry.path, isStaged: false))
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

                // 没配 AI 的用户看不到这个按钮，界面上不留任何 AI 痕迹
                if aiSettings.isAvailable {
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
