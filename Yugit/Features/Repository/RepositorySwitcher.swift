import GitKit
import SwiftUI

/// 多仓库切换器。⌘⇧O 唤起。
///
/// **刻意不做 GitKraken 的 Workspaces。** 那套抽象是给团队协作设计的——
/// 把一组仓库定义成一个工作区、共享给同事、统一操作。我们的用户多是个人
/// 同时开三五个项目，需要的只是「快速跳到另一个」，为此先建一个工作区
/// 是纯粹的仪式。
struct RepositorySwitcher: View {

    let model: AppModel
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var glances: [RepositoryGlance] = []
    @State private var selectionIndex = 0

    private var filtered: [RepositoryGlance] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return glances }
        return glances.filter {
            $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.url.path.range(of: trimmed, options: .caseInsensitive) != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.regular) {
                Image(systemName: "folder")
                    .foregroundStyle(Theme.Colors.brand)
                TextField("切换到哪个仓库", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: query) { _, _ in selectionIndex = 0 }
                    .onSubmit(openSelected)
            }
            .padding(Theme.Spacing.loose)

            Divider()

            if filtered.isEmpty {
                EmptyStateView(
                    glances.isEmpty ? "还没有打开过仓库" : "没有匹配的仓库",
                    systemImage: glances.isEmpty ? "folder" : "magnifyingglass",
                    description: glances.isEmpty ? "打开一个仓库之后它会出现在这里" : nil,
                    compact: true
                )
                .frame(height: 200)
            } else {
                ScrollViewReader { proxy in
                    List(Array(filtered.enumerated()), id: \.element.url) { index, glance in
                        RepositoryRow(
                            glance: glance,
                            isCurrent: model.repository?.rootURL.path == glance.url.path,
                            isSelected: index == selectionIndex
                        )
                        .id(glance.url)
                        .contentShape(.rect)
                        .onTapGesture {
                            selectionIndex = index
                            openSelected()
                        }
                        .contextMenu {
                            Button("从列表移除") {
                                model.removeRecent(glance.url)
                                reload()
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: selectionIndex) { _, index in
                        guard filtered.indices.contains(index) else { return }
                        proxy.scrollTo(filtered[index].url)
                    }
                }
            }

            Divider()

            HStack {
                Button("打开别的仓库…") {
                    onDismiss()
                    model.presentOpenPanel()
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("↑↓ 选择 · ⏎ 打开")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
            .padding(Theme.Spacing.loose)
        }
        .frame(width: 520, height: 380)
        .onAppear(perform: reload)
        // 全键盘可用。切仓库这件事恰恰是最不该摸鼠标的——
        // 它发生在你正打算干别的事的路上。
        .onKeyPress(.upArrow) {
            selectionIndex = max(0, selectionIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectionIndex = min(filtered.count - 1, selectionIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    /// 读一遍每个仓库的当前分支。
    ///
    /// 走 `RepositoryGlance`（直接读 `.git/HEAD`）而不是各开一次仓库：
    /// 十个仓库就是十次 git 进程启动，而这个面板可能只是被扫一眼就关掉。
    private func reload() {
        glances = model.recentRepositories.compactMap(RepositoryGlance.read)
        selectionIndex = 0
    }

    private func openSelected() {
        guard filtered.indices.contains(selectionIndex) else { return }
        let target = filtered[selectionIndex]
        onDismiss()
        // 已经打开着的就不用重开了，重开会丢掉当前的选中与滚动位置
        guard model.repository?.rootURL.path != target.url.path else { return }
        model.open(target.url)
    }
}

private struct RepositoryRow: View {

    let glance: RepositoryGlance
    let isCurrent: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.regular) {
            Image(systemName: isCurrent ? "folder.fill" : "folder")
                .foregroundStyle(isCurrent ? Theme.Colors.brand : Theme.Colors.secondaryText)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(glance.name)
                    .font(Theme.Font.body)
                Text(abbreviated)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: Theme.Spacing.regular)

            if let branch = glance.branch {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .labelStyle(.compact)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
            } else if glance.isDetached {
                Text("detached")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(isSelected ? Theme.Colors.accent.opacity(0.15) : Color.clear)
    }

    /// 把 home 换成 `~`，长路径在这个宽度下才不至于占满整行。
    private var abbreviated: String {
        let path = glance.url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
