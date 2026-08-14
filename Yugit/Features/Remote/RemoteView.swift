import GitKit
import Observation
import SwiftUI

/// 远程管理面板的状态。
@MainActor
@Observable
final class RemoteViewModel: Identifiable {

    nonisolated let id = UUID()

    let repository: RepositoryViewModel

    private(set) var remotes: [Remote] = []
    private(set) var isLoading = false

    var selection: String?
    var pendingRemove: Remote?

    /// 新建或编辑用的草稿。
    var draftName = ""
    var draftURL = ""
    var editing: Remote?
    var isAdding = false

    var selected: Remote? { remotes.first { $0.name == selection } }

    init(repository: RepositoryViewModel) {
        self.repository = repository
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        remotes = (try? await repository.remoteList()) ?? []
        if let selection, !remotes.contains(where: { $0.name == selection }) {
            self.selection = nil
        }
        if selection == nil { selection = remotes.first?.name }
    }

    func beginAdding() {
        editing = nil
        // origin 是绝大多数仓库第一个远程的名字，预填省一次输入；
        // 已经有 origin 了就留空，免得用户还得先删掉再打
        draftName = remotes.contains { $0.name == "origin" } ? "" : "origin"
        draftURL = ""
        isAdding = true
    }

    func beginEditing(_ remote: Remote) {
        editing = remote
        draftName = remote.name
        draftURL = remote.fetchURL
        isAdding = true
    }

    func commitDraft() async {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        let url = draftURL.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !url.isEmpty else { return }

        if let editing {
            // 名字和地址各是一条命令，改了哪个跑哪个
            if name != editing.name {
                await repository.renameRemote(from: editing.name, to: name)
            }
            if url != editing.fetchURL {
                await repository.setRemoteURL(name: name, url: url)
            }
        } else {
            await repository.addRemote(name: name, url: url)
        }

        isAdding = false
        self.editing = nil
        await reload()
    }

    func remove(_ remote: Remote) async {
        await repository.removeRemote(named: remote.name)
        await reload()
    }
}

/// 远程管理。
struct RemoteView: View {

    @Bindable var model: RemoteViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 620, height: 400)
        .task { await model.reload() }
        .sheet(isPresented: $model.isAdding) { editor }
        .confirmationDialog(
            "确定删除这个远程？",
            isPresented: Binding(
                get: { model.pendingRemove != nil },
                set: { if !$0 { model.pendingRemove = nil } }
            ),
            presenting: model.pendingRemove
        ) { remote in
            Button("删除 \(remote.name)", role: .destructive) {
                Task { await model.remove(remote) }
                model.pendingRemove = nil
            }
            Button("取消", role: .cancel) { model.pendingRemove = nil }
        } message: { remote in
            Text(
                "会连同 `\(remote.name)/` 下的全部远程跟踪分支一起删掉。本地分支不受影响，"
                    + "但那些只在远程存在、你从没建过本地分支的提交，删完就没有引用指向它们了。"
                    + "重新添加再 fetch 一次可以拿回来。")
        }
    }

    private var header: some View {
        HStack {
            Label("远程", systemImage: "cloud")
                .font(Theme.Font.title)
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
            Button {
                model.beginAdding()
            } label: {
                Label("添加", systemImage: "plus")
            }
        }
        .padding(Theme.Spacing.loose)
    }

    @ViewBuilder
    private var content: some View {
        if model.remotes.isEmpty && !model.isLoading {
            EmptyStateView(
                "还没有远程",
                systemImage: "cloud",
                description: "加一个远程之后就能推送和拉取。本地仓库不加远程也完全可用。"
            ) {
                Button("添加远程…") { model.beginAdding() }
            }
        } else {
            List(model.remotes, selection: $model.selection) { remote in
                RemoteRow(remote: remote)
                    .tag(remote.name)
                    .contextMenu {
                        Button("编辑…") { model.beginEditing(remote) }
                        Divider()
                        Button("删除…", role: .destructive) { model.pendingRemove = remote }
                    }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let remote = model.selected {
                Button("编辑…") { model.beginEditing(remote) }
                Button("删除…", role: .destructive) { model.pendingRemove = remote }
            }
            Spacer()
            Button("完成") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Theme.Spacing.loose)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            Text(model.editing == nil ? "添加远程" : "编辑远程")
                .font(Theme.Font.title)

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                TextField("名字，例如 origin", text: $model.draftName)
                TextField("地址，https:// 或 git@…", text: $model.draftURL)
            }
            .textFieldStyle(.roundedBorder)

            Text("加完之后要 fetch 一次才能看到那边有哪些分支——这一步只写配置，不会去连它。")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    model.isAdding = false
                    model.editing = nil
                }
                Button(model.editing == nil ? "添加" : "保存") {
                    Task { await model.commitDraft() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.draftName.trimmingCharacters(in: .whitespaces).isEmpty
                        || model.draftURL.trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
        }
        .padding(Theme.Spacing.section)
        .frame(width: 440)
    }
}

private struct RemoteRow: View {

    let remote: Remote

    var body: some View {
        HStack(spacing: Theme.Spacing.regular) {
            Image(systemName: remote.usesSSH ? "key" : "globe")
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(width: 16)
                .help(remote.usesSSH ? "SSH" : "HTTPS")

            VStack(alignment: .leading, spacing: 1) {
                Text(remote.name)
                    .font(Theme.Font.body)
                Text(remote.fetchURL)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // 推送地址和拉取地址不一样是可以配的，但很少见——
                // 不显眼地标出来，免得用户推到了自己没料到的地方
                if remote.pushURL != remote.fetchURL {
                    Text("推送到 \(remote.pushURL)")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.warning)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
