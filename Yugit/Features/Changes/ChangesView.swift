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
    /// 右键某个文件时选了「查看历史」。
    let onShowFileHistory: (String) -> Void
    @State private var section = Section.changes
    @State private var pendingDiscard: [String]?
    @State private var fileFilter = ""
    /// 折叠起来的目录。存"折叠的"而不是"展开的"，所以默认全展开——
    /// 打开变更列表就是为了看有哪些文件，默认折叠等于每次都要先点开一遍。
    @State private var collapsedDirectories: Set<String> = []
    @AppStorage("com.chenya.yugit.changes.treeView") private var usesTreeView = true
    @State private var pendingQuickAction: PendingQuickAction?
    @State private var pendingCommitAction: PendingCommitAction?
    /// 用户配了外部工具没有。没配就不显示那些菜单项——
    /// 摆一个点了没反应的入口比没有更糟。
    @State private var hasExternalDiffTool = false
    @State private var hasExternalMergeTool = false

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
        .task {
            hasExternalDiffTool = await repository.hasDiffTool()
            hasExternalMergeTool = await repository.hasMergeTool()
        }
        .sheet(item: $pendingQuickAction) { pending in
            QuickActionSheet(
                action: pending.action,
                commit: pending.commit,
                repository: repository,
                onDismiss: { pendingQuickAction = nil }
            )
        }
        .sheet(item: $pendingCommitAction) { pending in
            CommitActionSheet(
                pending: pending,
                repository: repository,
                onDismiss: { pendingCommitAction = nil },
                // 停在冲突上时切回「变更」——冲突文件就列在那一栏的最上面，
                // 旁边就是「解决…」。留在历史列表里的话，用户看到的是
                // 一个什么都没发生的界面。
                onConflict: { section = .changes }
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

    // MARK: - 变更：过滤
    //
    // 一个改到一半的仓库有两三百个变更文件是常事，平铺成一列根本没法用。
    // 过滤之外还有一层用意：筛出来之后**批量操作只作用于筛选结果**，
    // 于是「过滤 *.swift → 暂存这 12 个」就成了按模式分批提交的顺手组合，
    // 不必一个一个右键点过去。

    private func matchesFilter(_ entry: StatusEntry) -> Bool {
        let query = fileFilter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return entry.path.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private var filteredStaged: [StatusEntry] {
        repository.stagedEntries.filter(matchesFilter)
    }

    private var filteredUnstaged: [StatusEntry] {
        repository.unstagedEntries.filter(matchesFilter)
    }

    private var filteredConflicted: [StatusEntry] {
        repository.conflictedEntries.filter(matchesFilter)
    }

    private var isFiltering: Bool {
        !fileFilter.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 变更：树

    /// 渲染一个分组里的文件，按当前模式决定是树还是平铺。
    ///
    /// 树和平铺共用同一个 `FileRow`，只是平铺时显示完整路径、树里显示文件名——
    /// 两套行视图会立刻在状态图标、右键菜单、选中态上走样。
    @ViewBuilder
    private func entryRows(
        _ entries: [StatusEntry],
        isStaged: Bool,
        @ViewBuilder row: @escaping (StatusEntry) -> some View
    ) -> some View {
        if usesTreeView {
            let tree = PathTree.build(from: entries, path: \.path)
            ForEach(tree.flattenedTree(collapsed: collapsedDirectories)) { item in
                if let entry = item.node.value {
                    row(entry)
                        .padding(.leading, CGFloat(item.depth) * 12)
                } else {
                    DirectoryRow(
                        node: item.node,
                        depth: item.depth,
                        isCollapsed: collapsedDirectories.contains(item.node.id),
                        isStaged: isStaged,
                        onToggle: {
                            if collapsedDirectories.contains(item.node.id) {
                                collapsedDirectories.remove(item.node.id)
                            } else {
                                collapsedDirectories.insert(item.node.id)
                            }
                        },
                        onStageAll: {
                            let paths = item.node.allValues.map(\.path)
                            Task {
                                if isStaged {
                                    await repository.unstage(paths)
                                } else {
                                    await repository.stage(paths)
                                }
                            }
                        }
                    )
                    // 目录行不是可选中的对象，别让它抢走文件的选中态
                    .selectionDisabled()
                }
            }
        } else {
            ForEach(entries, id: \.path) { entry in
                row(entry)
            }
        }
    }

    // MARK: - 变更：列表

    @ViewBuilder
    private var changeList: some View {
        if !repository.hasChanges && repository.conflictedEntries.isEmpty {
            EmptyStateView(
                "工作区干净",
                systemImage: "checkmark.circle",
                description: "没有待处理的改动"
            )
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // 文件不多时不显示过滤框，省得白占一行高度
                if repository.stagedEntries.count + repository.unstagedEntries.count > 8 {
                    HStack(spacing: Theme.Spacing.tight) {
                        FilterField(text: $fileFilter, placeholder: "过滤文件路径")

                        Button {
                            usesTreeView.toggle()
                        } label: {
                            Image(systemName: usesTreeView ? "list.bullet.indent" : "list.bullet")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help(usesTreeView ? "改为平铺显示完整路径" : "改为按目录分组")
                    }
                    .padding(.horizontal, Theme.Spacing.regular)
                    .padding(.bottom, Theme.Spacing.tight + 2)
                }

                if isFiltering && filteredStaged.isEmpty && filteredUnstaged.isEmpty
                    && filteredConflicted.isEmpty
                {
                    EmptyStateView(
                        "没有匹配的文件",
                        systemImage: "line.3.horizontal.decrease",
                        description: "试试别的关键词",
                        compact: true
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    entryList
                }
            }
        }
    }

    /// 这个文件是不是当前选中的那个。
    ///
    /// 要单独算是因为 `List` 只把选中态用在**背景**上，行内容显式设过的颜色
    /// 它一概不管。状态字母正好有一个是强调色，落在强调色背景上会消失。
    private func isSelected(_ path: String, isStaged: Bool) -> Bool {
        repository.selectedFile
            == RepositoryViewModel.FileSelection(path: path, isStaged: isStaged)
    }

    private var entryList: some View {
        List(selection: $repository.selectedFile) {
            if !filteredConflicted.isEmpty {
                SwiftUI.Section {
                    ForEach(filteredConflicted, id: \.path) { entry in
                        FileRow(entry: entry, isSelected: isSelected(entry.path, isStaged: false))
                            .tag(RepositoryViewModel.FileSelection(path: entry.path, isStaged: false))
                            .contextMenu {
                                // 尊重用户已经配好的工具。冲突这种场合，
                                // 手上那把用了多年的三方合并器往往比我们的好使
                                if hasExternalMergeTool {
                                    Button("用外部工具解决") {
                                        repository.openInMergeTool(entry.path)
                                    }
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("冲突（\(filteredConflicted.count)）")
                        Spacer()
                        // 冲突文件就在眼前时给个直达入口，比让人去翻命令面板顺手
                        Button("解决…") { onResolveConflicts() }
                            .buttonStyle(.borderless)
                            .font(Theme.Font.secondary)
                    }
                }
            }

            if !filteredStaged.isEmpty {
                SwiftUI.Section {
                    entryRows(filteredStaged, isStaged: true) { entry in
                        FileRow(
                            entry: entry,
                            showsIndexStatus: true,
                            showsFullPath: !usesTreeView,
                            isSelected: isSelected(entry.path, isStaged: true)
                        )
                        .tag(RepositoryViewModel.FileSelection(path: entry.path, isStaged: true))
                        .contextMenu {
                            Button("取消暂存") {
                                Task { await repository.unstage([entry.path]) }
                            }
                            fileMenuExtras(for: entry)
                        }
                    }
                } header: {
                    sectionHeader("已暂存", count: filteredStaged.count) {
                        // 过滤时只作用于筛选结果，按钮文案也照实说是几个，
                        // 不能让人以为点下去会动到看不见的那些文件
                        Button(isFiltering ? "取消这 \(filteredStaged.count) 个" : "全部取消") {
                            Task { await repository.unstage(filteredStaged.map(\.path)) }
                        }
                    }
                }
            }

            if !filteredUnstaged.isEmpty {
                SwiftUI.Section {
                    entryRows(filteredUnstaged, isStaged: false) { entry in
                        FileRow(
                            entry: entry,
                            showsFullPath: !usesTreeView,
                            isSelected: isSelected(entry.path, isStaged: false)
                        )
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
                            fileMenuExtras(for: entry)
                        }
                    }
                } header: {
                    sectionHeader("未暂存", count: filteredUnstaged.count) {
                        Button(isFiltering ? "暂存这 \(filteredUnstaged.count) 个" : "全部暂存") {
                            Task { await repository.stage(filteredUnstaged.map(\.path)) }
                        }
                    }
                }
            }
        }
    }

    /// 暂存与未暂存两处右键菜单共有的那几项。
    ///
    /// 抽出来是因为两边必须一致：只在一边加了「查看历史」，用户会以为
    /// 这个功能取决于文件暂存没暂存，而那毫无道理。
    @ViewBuilder
    private func fileMenuExtras(for entry: StatusEntry) -> some View {
        Divider()

        Button("查看这个文件的历史…") {
            onShowFileHistory(entry.path)
        }

        // 没配外部工具就不显示这一项——摆一个点了没反应的入口比没有更糟
        if hasExternalDiffTool {
            Button("用外部工具比较") {
                repository.openInDiffTool(entry.path)
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
                .font(Theme.Font.secondary)
        }
    }

    // MARK: - 历史

    @ViewBuilder
    private var historyList: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.tight) {
                FilterField(text: historyMessageBinding, placeholder: "搜提交信息")

                Menu {
                    // 作者筛选放菜单里而不是再摆一个输入框：
                    // 中栏只有三百来 pt 宽，两个并排的输入框谁都填不下东西
                    TextField("作者名或邮箱", text: historyAuthorBinding)
                    if !(repository.historyFilter.author ?? "").isEmpty {
                        Button("清除作者条件") { repository.historyFilter.author = nil }
                    }
                    Divider()
                    Button("最近一天") { setSince(days: 1) }
                    Button("最近一周") { setSince(days: 7) }
                    Button("最近一月") { setSince(days: 30) }
                    if repository.historyFilter.since != nil {
                        Button("清除时间条件") { repository.historyFilter.since = nil }
                    }
                } label: {
                    Image(systemName: hasExtraFilters ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("按作者或时间筛选")
            }
            .padding(.horizontal, Theme.Spacing.regular)
            .padding(.vertical, Theme.Spacing.tight + 2)

            if !repository.historyFilter.isEmpty {
                filterSummary
            }

            Divider()

            historyContent
        }
    }

    /// 当前生效的筛选条件，以及命中了多少条。
    ///
    /// 必须显式说明「在整个历史里搜」：客户端过滤只能筛已加载的那几百条，
    /// 用户搜不到就会以为仓库里没有。这里筛的是全量，得让人知道结果是可信的。
    private var filterSummary: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.tint)

            Text("在整个历史中找到 \(repository.commits.count) 条")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.secondaryText)

            Spacer(minLength: 0)

            Button("清除") { repository.historyFilter = HistoryFilter() }
                .buttonStyle(.borderless)
                .font(Theme.Font.secondary)
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .padding(.bottom, Theme.Spacing.tight + 2)
    }

    private var hasExtraFilters: Bool {
        !(repository.historyFilter.author ?? "").isEmpty || repository.historyFilter.since != nil
    }

    private var historyMessageBinding: Binding<String> {
        Binding(
            get: { repository.historyFilter.message ?? "" },
            set: { repository.historyFilter.message = $0.isEmpty ? nil : $0 }
        )
    }

    private var historyAuthorBinding: Binding<String> {
        Binding(
            get: { repository.historyFilter.author ?? "" },
            set: { repository.historyFilter.author = $0.isEmpty ? nil : $0 }
        )
    }

    private func setSince(days: Int) {
        repository.historyFilter.since = Calendar.current.date(
            byAdding: .day, value: -days, to: Date())
    }

    @ViewBuilder
    private var historyContent: some View {
        if repository.commits.isEmpty {
            if !repository.historyFilter.isEmpty {
                EmptyStateView(
                    "没有匹配的提交",
                    systemImage: "magnifyingglass",
                    description: "整个历史里都没有符合这些条件的提交",
                    compact: true
                )
            } else {
                EmptyStateView(
                    "尚无提交",
                    systemImage: "clock",
                    description: "这个仓库还没有任何 commit"
                )
            }
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
                },
                onCommitAction: { action, commit in
                    // 挑取不弹确认：它只往历史上加一条新提交，后悔了删掉就行。
                    // 为它多设一道确认，只会让人对真正需要确认的那几个也麻木。
                    guard action.needsConfirmation else {
                        Task {
                            let outcome = await repository.cherryPick(commit)
                            if case .conflicted = outcome { section = .changes }
                        }
                        return
                    }
                    pendingCommitAction = PendingCommitAction(action: action, commit: commit)
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
                .font(Theme.Font.body)
                .frame(height: 72)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.contentBackground, in: .rect(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if repository.commitMessage.isEmpty {
                        Text("提交说明")
                            .foregroundStyle(Theme.Colors.tertiaryText)
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
                    .font(Theme.Font.secondary)
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
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            if let error = repository.aiState.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .textSelection(.enabled)
            }

            if repository.isAmending {
                // amend 会生成新的 commit hash，已推送的提交再推就需要 force
                Label("修改后 commit hash 会变，若已推送则需要 force push", systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .padding(10)
    }
}
