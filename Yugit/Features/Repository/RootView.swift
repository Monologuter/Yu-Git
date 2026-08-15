import SwiftUI

/// 窗口根视图：没打开仓库时显示欢迎页，否则显示三栏工作区。
struct RootView: View {

    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let repository = model.repository {
                RepositoryView(repository: repository, model: model)
            } else {
                WelcomeView(model: model)
            }
        }
        .sheet(isPresented: $model.showsSwitcher) {
            RepositorySwitcher(model: model) { model.showsSwitcher = false }
        }
        .sheet(
            item: Binding(
                get: { model.pendingInit },
                set: { if $0 == nil { model.pendingInit = nil } }
            )
        ) { pending in
            InitRepositorySheet(pending: pending, model: model) { model.pendingInit = nil }
        }
        .alert(
            "无法打开仓库",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// 未打开仓库时的入口页。
struct WelcomeView: View {

    let model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: Theme.Spacing.regular) {
                brandMark

                Text("驭Git")
                    .font(Theme.Font.display)
                    // display 这一档字大，默认字距会显得松散
                    .tracking(-0.32)

                Text("AI 帮你写代码，驭Git 帮你驾驭它")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            HStack(spacing: Theme.Spacing.loose) {
                Button {
                    model.presentOpenPanel()
                } label: {
                    Label("打开仓库…", systemImage: "folder")
                        .frame(minWidth: 120)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button {
                    model.presentInitPanel()
                } label: {
                    Label("新建仓库…", systemImage: "folder.badge.plus")
                        .frame(minWidth: 120)
                }
            }
            .controlSize(.large)

            if !model.recentRepositories.isEmpty {
                recentList
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    /// 品牌标志：靛底白「驭」。
    ///
    /// 仓库里没有任何图形 logo，这里也不造一个——整块由一个圆角矩形和一个汉字
    /// 构成，两行代码，任何分辨率下都清晰，也不必为深浅模式各出一版图。
    ///
    /// 换掉原来那个 SF Symbol 分支图标是因为它谁都在用：那个符号出现在
    /// 每一个 Git 工具里，放在欢迎页正中央等于告诉用户「这是一个 Git 客户端」，
    /// 而不是「这是驭Git」。
    private var brandMark: some View {
        Text("驭")
            .font(Theme.Font.mark)
            .foregroundStyle(Theme.Colors.onBrand)
            .frame(width: 96, height: 96)
            .background(Theme.Colors.brand, in: .rect(cornerRadius: 22))
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近打开")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.secondaryText)

            ForEach(model.recentRepositories, id: \.path) { url in
                Button {
                    model.open(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(Theme.Colors.secondaryText)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                            Text(abbreviate(url.deletingLastPathComponent().path))
                                .font(Theme.Font.secondary)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("从列表移除") { model.removeRecent(url) }
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    /// 把 home 目录换成 `~`，长路径在小窗口里才不至于撑破布局。
    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
