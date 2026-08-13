import GitKit
import SwiftUI

/// 三栏工作区：侧栏（分支/tag）｜ 变更与历史 ｜ 详情。
struct RepositoryView: View {

    @Bindable var repository: RepositoryViewModel
    let model: AppModel

    @State private var columnVisibility = NavigationSplitViewVisibility.all

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

            ToolbarItem(placement: .primaryAction) {
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
        }
        .overlay(alignment: .top) {
            if let message = repository.errorMessage {
                ErrorBanner(message: message)
            }
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

/// 顶部错误提示条。git 的错误往往很长，这里保持可读且不遮挡内容。
struct ErrorBanner: View {

    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(4)
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(.separator)
        }
        .padding(12)
        .frame(maxWidth: 620)
    }
}
