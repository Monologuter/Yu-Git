import GitKit
import Observation
import SwiftUI

/// 子模块面板的状态。
@MainActor
@Observable
final class SubmoduleViewModel: Identifiable {

    nonisolated let id = UUID()

    let repository: RepositoryViewModel

    private(set) var submodules: [Submodule] = []
    private(set) var isLoading = false
    private(set) var isUpdating = false

    var selection: String?

    /// 有几个需要处理。
    var needingAttention: Int {
        submodules.filter(\.state.needsAttention).count
    }

    init(repository: RepositoryViewModel) {
        self.repository = repository
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        submodules = (try? await repository.submodules()) ?? []
    }

    func updateAll() async {
        isUpdating = true
        defer { isUpdating = false }
        await repository.updateSubmodules(path: nil)
        await reload()
    }

    func update(_ submodule: Submodule) async {
        isUpdating = true
        defer { isUpdating = false }
        await repository.updateSubmodules(path: submodule.path)
        await reload()
    }
}

/// 子模块面板。
struct SubmoduleView: View {

    @Bindable var model: SubmoduleViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 420)
        .task { await model.reload() }
    }

    private var header: some View {
        HStack {
            Label("子模块", systemImage: "shippingbox")
                .font(Theme.Font.title)
            Spacer()
            if model.isLoading || model.isUpdating { ProgressView().controlSize(.small) }
        }
        .padding(Theme.Spacing.loose)
    }

    @ViewBuilder
    private var content: some View {
        if model.submodules.isEmpty && !model.isLoading {
            EmptyStateView(
                "这个仓库没有子模块",
                systemImage: "shippingbox",
                description: "子模块是把另一个仓库固定在某个版本上嵌进来。没有也很正常。"
            )
        } else {
            List(model.submodules, selection: $model.selection) { submodule in
                SubmoduleRow(submodule: submodule)
                    .tag(submodule.path)
                    .contextMenu {
                        Button("更新这一个") { Task { await model.update(submodule) } }
                    }
            }
        }
    }

    private var footer: some View {
        HStack {
            if model.needingAttention > 0 {
                Label(
                    "\(model.needingAttention) 个需要处理",
                    systemImage: "exclamationmark.triangle"
                )
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.warning)
            }
            Spacer()
            if !model.submodules.isEmpty {
                Button("全部更新") { Task { await model.updateAll() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isUpdating)
                    .help("把每个子模块签出到父仓库记录的那个提交，没初始化的先克隆下来")
            }
            Button("完成") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Theme.Spacing.loose)
    }
}

private struct SubmoduleRow: View {

    let submodule: Submodule

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.regular) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(submodule.path)
                    .font(Theme.Font.body)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: Theme.Spacing.regular) {
                    Text(submodule.state.displayName)
                        .foregroundStyle(tint)
                    Text(String(submodule.recordedCommit.prefix(7)))
                        .font(Theme.Font.mono)
                    if !submodule.describedRef.isEmpty {
                        Text(submodule.describedRef)
                    }
                }
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.tertiaryText)

                // 需要处理的才展开讲，正常的不占版面
                if submodule.state.needsAttention {
                    Text(submodule.state.explanation)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch submodule.state {
        case .current: "checkmark.circle"
        case .notInitialized: "questionmark.circle"
        case .outOfSync: "arrow.triangle.2.circlepath"
        case .conflicted: "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch submodule.state {
        case .current: Theme.Colors.success
        case .notInitialized: Theme.Colors.secondaryText
        case .outOfSync, .conflicted: Theme.Colors.warning
        }
    }
}
