import GitKit
import SwiftUI

/// 三栏工作区：侧栏（分支/tag）｜ 变更与历史 ｜ 详情。
struct RepositoryView: View {

    @Bindable var repository: RepositoryViewModel
    let model: AppModel

    @Environment(AISettingsStore.self) private var aiSettings

    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isSearching = false
    @State private var showsTimeline = false
    @State private var showsCommandPalette = false
    @State private var showsRebase = false
    @State private var composeModel: ComposeViewModel?
    @State private var conflictModel: ConflictViewModel?
    @State private var reviewModel: ReviewViewModel?
    @State private var worktreeModel: WorktreeViewModel?
    @State private var forgeModel: ForgeViewModel?
    @State private var chatModel: ChatViewModel?
    @State private var showsOnboarding = false
    @AppStorage("com.chenya.yugit.hasSeenTour") private var hasSeenTour = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(repository: repository)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } content: {
            ChangesView(
                repository: repository,
                onResolveConflicts: { conflictModel = ConflictViewModel(repository: repository) },
                onReview: { reviewModel = ReviewViewModel(repository: repository) }
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 460)
        } detail: {
            DetailView(repository: repository)
        }
        // 卡在 rebase 里是最需要指路的状态，横幅横跨三栏，切到哪一栏都看得见。
        // 用 safeAreaInset 而不是 VStack 包裹，免得打乱下面整条 modifier 链。
        .safeAreaInset(edge: .top, spacing: 0) {
            RebaseBanner(repository: repository)
        }
        .navigationTitle(repository.displayName)
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.closeRepository()
                } label: {
                    Label("关闭仓库", systemImage: "chevron.left")
                }
                .help("回到欢迎页")
            }

            // 工具栏按功能分三组，组间用分隔线。
            //
            // 原先五个按钮平铺成一排，视觉上完全等权，但它们其实是三类东西：
            // 远程传输（会联网、可能失败、可能改历史）、本地视图（无副作用）、
            // 全局入口。分组之后，"哪些按钮点下去会动到远程"一眼就能看出来。
            //
            // 窗口变窄时 NSToolbar 会自动把放不下的项折进 ›› 溢出菜单，
            // 所以不必为小窗口预先删按钮。

            ToolbarItemGroup(placement: .primaryAction) {
                if repository.isTransferring {
                    TransferIndicator(progress: repository.transferProgress)
                }

                Button {
                    Task { await repository.fetch() }
                } label: {
                    Label("获取", systemImage: "arrow.down.circle")
                }
                .disabled(repository.isTransferring)
                .help("从远程拉取引用与对象，不改动工作区")

                Button {
                    Task { await repository.pull() }
                } label: {
                    Label("拉取", systemImage: "arrow.down.to.line")
                }
                .disabled(repository.isTransferring)
                .help("拉取并合并到当前分支")

                Button {
                    Task { await repository.push(setUpstream: repository.needsUpstreamOnPush) }
                } label: {
                    Label("推送", systemImage: "arrow.up.to.line")
                }
                .disabled(repository.isTransferring)
                .help(repository.needsUpstreamOnPush ? "首次推送，会同时设置 upstream" : "推送到 upstream")
            }

            ToolbarItem(placement: .primaryAction) { Divider() }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await repository.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(repository.isRefreshing)
                .help("重新读取仓库状态（⌘R）")

                Button {
                    showsTimeline.toggle()
                } label: {
                    Label("时间线", systemImage: "clock.arrow.circlepath")
                }
                .help("查看操作记录与可恢复的时间点")
            }

            ToolbarItem(placement: .primaryAction) { Divider() }

            // 搜索和命令面板挪到右侧末尾。
            // 原先放在 .principal（工具栏正中），那个位置在 macOS 上通常留给
            // 与当前文档强相关的分段控件，放两个全局入口会显得没着没落——
            // 截图里那个孤零零飘在中间的放大镜就是这么来的。
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isSearching = true
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .help("在整个仓库中搜索（⇧⌘F）")

                Button {
                    showsCommandPalette = true
                } label: {
                    Label("命令", systemImage: "command")
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("命令面板（⌘K）——每个操作都会显示等价的 git 命令")
            }
        }
        .task {
            await repository.refresh()
            // 监听外部改动：终端里的 git、编辑器保存、agent 写的代码都要能立刻看到
            repository.startWatching()
            repository.prepareCommitGraphCache()
        }
        .onDisappear {
            repository.stopWatching()
        }
        .inspector(isPresented: $showsTimeline) {
            TimelineView(repository: repository)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .sheet(isPresented: $showsCommandPalette) {
            CommandPaletteView(
                commands: CommandRegistry.commands(
                    for: repository,
                    aiSettings: aiSettings,
                    showSearch: { isSearching = true },
                    showTimeline: { showsTimeline = true },
                    showRebase: { showsRebase = true },
                    showCompose: { composeModel = ComposeViewModel(repository: repository) },
                    showConflicts: { conflictModel = ConflictViewModel(repository: repository) },
                    showReview: { reviewModel = ReviewViewModel(repository: repository) },
                    showWorktrees: { worktreeModel = WorktreeViewModel(repository: repository) },
                    showForge: { forgeModel = ForgeViewModel(repository: repository) },
                    showOnboarding: { showsOnboarding = true },
                    showChat: { chatModel = ChatViewModel(repository: repository) },
                    closeRepository: { model.closeRepository() }
                ),
                onDismiss: { showsCommandPalette = false }
            )
        }
        .task(id: repository.status?.branch.commit) {
            // 状态一变就复查：终端里跑的 rebase 同样要在界面上现身
            await repository.reloadRebaseProgress()
        }
        .sheet(item: $chatModel) { model in
            ChatView(model: model) { chatModel = nil }
        }
        .sheet(isPresented: $showsOnboarding) {
            OnboardingView { showsOnboarding = false }
        }
        .task {
            // 第一次打开仓库时自动引导一次，之后不再打扰
            if !hasSeenTour { showsOnboarding = true }
        }
        .sheet(item: $forgeModel) { model in
            ForgeView(model: model) { forgeModel = nil }
        }
        .sheet(item: $worktreeModel) { model in
            WorktreeView(model: model) { worktreeModel = nil }
        }
        .sheet(item: $reviewModel) { model in
            ReviewView(model: model) { reviewModel = nil }
        }
        .sheet(item: $conflictModel) { model in
            ConflictView(model: model) { conflictModel = nil }
        }
        .sheet(item: $composeModel) { model in
            ComposeView(model: model) { composeModel = nil }
        }
        .sheet(isPresented: $showsRebase) {
            RebaseView(repository: repository) { showsRebase = false }
        }
        .sheet(isPresented: $isSearching) {
            SearchView(
                model: repository.search,
                onSelectFile: { path in
                    repository.reveal(path: path)
                    isSearching = false
                },
                onSelectCommit: { commit in
                    repository.reveal(commit: commit)
                    isSearching = false
                }
            )
        }
        .sheet(item: $repository.failure) { failure in
            FailureSheet(failure: failure) { repository.failure = nil }
        }
    }

    private var subtitle: String {
        guard let branch = repository.currentBranch else {
            if repository.status?.branch.isDetached == true {
                return "detached HEAD"
            }
            return repository.status?.branch.isUnborn == true ? "尚无提交" : ""
        }

        var parts = [branch.name]
        let tracking = branch.tracking
        if tracking.isGone {
            parts.append("upstream 已删除")
        } else if tracking.ahead > 0 || tracking.behind > 0 {
            var counts: [String] = []
            if tracking.ahead > 0 { counts.append("领先 \(tracking.ahead)") }
            if tracking.behind > 0 { counts.append("落后 \(tracking.behind)") }
            parts.append(counts.joined(separator: " · "))
        }
        return parts.joined(separator: "  ")
    }
}

/// 失败详情面板。
///
/// git 的报错必须给到「下一步做什么」，否则中文用户只能对着英文原文发呆。
struct FailureSheet: View {

    let failure: FailurePresentation
    let onDismiss: () -> Void

    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(failure.title)
                    .font(.headline)
            }

            Text(failure.message)
                .textSelection(.enabled)

            if let suggestion = failure.suggestion {
                Text(suggestion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .underPageBackgroundColor), in: .rect(cornerRadius: 6))
            }

            if let details = failure.details, !details.isEmpty {
                DisclosureGroup("git 的原始输出", isExpanded: $showsDetails) {
                    ScrollView {
                        Text(details)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
                .font(.callout)
            }

            HStack {
                Spacer()
                Button("好", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// 工具栏上的传输进度。
struct TransferIndicator: View {

    let progress: TransferProgress?

    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            if let progress {
                Text(progress.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
