import GitKit
import SwiftUI

/// 三栏工作区：侧栏（分支/tag）｜ 变更与历史 ｜ 详情。
struct RepositoryView: View {

    @Bindable var repository: RepositoryViewModel
    let model: AppModel

    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isSearching = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(repository: repository)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } content: {
            ChangesView(repository: repository)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 460)
        } detail: {
            DetailView(repository: repository)
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

            ToolbarItem(placement: .principal) {
                Button {
                    isSearching = true
                } label: {
                    Label("搜索", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .help("在整个仓库中搜索（⇧⌘F）")
            }

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

                Button {
                    Task { await repository.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(repository.isRefreshing)
                .help("重新读取仓库状态（⌘R）")
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
