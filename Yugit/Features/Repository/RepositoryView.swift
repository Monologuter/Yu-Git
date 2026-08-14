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
    @State private var stashModel: StashViewModel?
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
        .navigationSubtitle(subtitleText)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.closeRepository()
                } label: {
                    Label("关闭仓库", systemImage: "chevron.left")
                }
                .help("回到欢迎页")
            }

            // 工具栏只留四项：远程三件套 + 一个「更多」菜单。
            //
            // 上一版按功能分了三组、组间加 Divider，结果在三栏都展开的窗口下
            // 空间不够，NSToolbar 把大半按钮折进了 ›› 溢出菜单，
            // 还把「获取」「拉取」甩到了窗口左上角红绿灯旁边——比不分组更糟。
            //
            // 教训是：在 NavigationSplitView 里，工具栏可用宽度是被三栏分掉的
            // 剩余空间，比看上去的窗口宽度小得多。与其让系统在空间不足时
            // 替我们做取舍（它的取舍很难看），不如自己先收敛到放得下的数量。
            //
            // 留在外面的是每天要点很多次的远程操作；收进菜单的那几个都有快捷键，
            // 而且菜单会把快捷键显示出来，反倒帮用户记住它们。
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

                Menu {
                    Button {
                        showsCommandPalette = true
                    } label: {
                        Label("命令面板", systemImage: "command")
                    }
                    .keyboardShortcut("k", modifiers: .command)

                    Button {
                        isSearching = true
                    } label: {
                        Label("搜索仓库", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])

                    Divider()

                    Button {
                        showsTimeline.toggle()
                    } label: {
                        Label("时间线", systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        Task { await repository.refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(repository.isRefreshing)
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .help("命令面板、搜索、时间线、刷新")
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
                    showStashes: { stashModel = StashViewModel(repository: repository) },
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
        .sheet(item: $stashModel) { model in
            StashView(model: model) { stashModel = nil }
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

    /// 副标题：一个品牌色的分支图标 + 分支名与领先/落后。
    ///
    /// 用 `Text` 拼接而不是换成自绘的 `ToolbarItem`：那样才能带上颜色，
    /// 又不动工具栏的结构。这里的可用宽度是被三栏分剩下的，比窗口看着窄得多，
    /// 上一版正是因为往工具栏里塞了太多东西，被 `NSToolbar` 折进了 `››` 溢出菜单。
    ///
    /// 图标用品牌色：整个工具栏只有这一处是产品自己的颜色，其余都跟随系统。
    private var subtitleText: Text {
        let text = subtitle
        guard !text.isEmpty else { return Text("") }
        return Text(Image(systemName: "arrow.triangle.branch"))
            .foregroundStyle(Theme.Colors.brand)
            + Text(" ") + Text(text)
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
