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
            VStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)

                Text("驭Git")
                    .font(.system(size: 32, weight: .semibold))

                Text("AI 帮你写代码，驭Git 帮你驾驭它")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.presentOpenPanel()
            } label: {
                Label("打开仓库…", systemImage: "folder")
                    .frame(minWidth: 140)
            }
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)

            if !model.recentRepositories.isEmpty {
                recentList
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近打开")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(model.recentRepositories, id: \.path) { url in
                Button {
                    model.open(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                            Text(abbreviate(url.deletingLastPathComponent().path))
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
