import GitKit
import Observation
import SwiftUI

/// 储藏面板的状态。
@MainActor
@Observable
final class StashViewModel: Identifiable {

    nonisolated let id = UUID()

    let repository: RepositoryViewModel

    private(set) var entries: [StashEntry] = []
    private(set) var files: [CommitFileChange] = []
    private(set) var isLoading = false

    /// 选中哪一条。存 hash 而不是索引——索引会漂移。
    var selection: String? {
        didSet {
            guard selection != oldValue else { return }
            files = []
            Task { await loadFiles() }
        }
    }

    var pendingDrop: StashEntry?
    var errorMessage: String?

    var selected: StashEntry? {
        entries.first { $0.hash == selection }
    }

    init(repository: RepositoryViewModel) {
        self.repository = repository
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await repository.stashEntries()
            // 选中的那条被别处删掉了就清空，别让详情停在一条已经不存在的储藏上
            if let selection, !entries.contains(where: { $0.hash == selection }) {
                self.selection = nil
            }
            if selection == nil { selection = entries.first?.hash }
        } catch {
            errorMessage = "读取储藏失败：\(error)"
        }
    }

    private func loadFiles() async {
        guard let hash = selection else { return }
        files = (try? await repository.stashFiles(at: hash)) ?? []
    }

    func apply(_ entry: StashEntry) async {
        await repository.applyStash(entry)
        await reload()
    }

    func pop(_ entry: StashEntry) async {
        let done = await repository.popStash(entry)
        if done == false {
            errorMessage = "「\(entry.displayName)」已经不在栈里了，可能刚被别处取走。"
        }
        await reload()
    }

    func drop(_ entry: StashEntry) async {
        let done = await repository.dropStash(entry)
        if done == false {
            errorMessage = "「\(entry.displayName)」已经不在栈里了，什么都没删。"
        }
        await reload()
    }
}

/// 储藏管理。
///
/// 之前只有 push/pop 两个按钮，看不见里面装了什么——而 `stash@{3}` 放上三天，
/// 没人记得那是什么。这个面板要回答的就是「这一条到底是什么」：
/// 说明、储藏时在哪个分支、改了哪些文件。
struct StashView: View {

    @Bindable var model: StashViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 460)
        .task { await model.reload() }
        .alert(
            "储藏已经不在了",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "确定丢弃这条储藏？",
            isPresented: Binding(
                get: { model.pendingDrop != nil },
                set: { if !$0 { model.pendingDrop = nil } }
            ),
            presenting: model.pendingDrop
        ) { entry in
            Button("丢弃「\(entry.displayName)」", role: .destructive) {
                Task { await model.drop(entry) }
                model.pendingDrop = nil
            }
            Button("取消", role: .cancel) { model.pendingDrop = nil }
        } message: { _ in
            Text("储藏里装的是**从未提交过**的改动，丢掉之后没有正常途径找回来——reflog 管不到 stash。")
        }
    }

    private var header: some View {
        HStack {
            Label("储藏", systemImage: "tray.full")
                .font(Theme.Font.title)
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(Theme.Spacing.loose)
    }

    @ViewBuilder
    private var content: some View {
        if model.entries.isEmpty && !model.isLoading {
            EmptyStateView(
                "还没有储藏",
                systemImage: "tray",
                description: "手上的活干到一半要切走时，先把改动收进储藏，工作区就干净了。"
            )
        } else {
            HSplitView {
                list.frame(minWidth: 300, idealWidth: 340)
                detail.frame(minWidth: 280)
            }
        }
    }

    private var list: some View {
        List(model.entries, selection: $model.selection) { entry in
            StashRow(entry: entry)
                .tag(entry.hash)
                .contextMenu {
                    Button("应用（保留这一条）") { Task { await model.apply(entry) } }
                    Button("取回（应用后删除）") { Task { await model.pop(entry) } }
                    Divider()
                    Button("丢弃…", role: .destructive) { model.pendingDrop = entry }
                }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let entry = model.selected {
            VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                if !entry.hasUserMessage {
                    // 自动生成的描述说的是「储藏时 HEAD 在哪」，不是「里面改了什么」。
                    // 这个区别值得当面讲一次：一列 WIP on main 看着像在描述内容。
                    Label(
                        "这条没有自己的说明，上面那行讲的是储藏时 HEAD 停在哪，"
                            + "不是里面改了什么。下次收起改动时顺手写一句，三天后会感谢自己。",
                        systemImage: "info.circle"
                    )
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Text("改了 \(model.files.count) 个文件")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)

                List(model.files) { file in
                    HStack(spacing: Theme.Spacing.regular) {
                        Text(file.kind.letter)
                            .font(Theme.Font.mono)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .frame(width: 14)
                            .help(file.kind.displayName)
                        Text(file.path)
                            .font(Theme.Font.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                }
                .listStyle(.plain)
            }
            .padding(Theme.Spacing.loose)
        } else {
            EmptyStateView("选一条储藏", systemImage: "sidebar.right", compact: true)
        }
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.regular) {
            if let entry = model.selected {
                // apply 在前、pop 在后，且默认按钮是 apply：
                // 拿不准时该用 apply，用错了栈里那份还在。
                Button("应用") { Task { await model.apply(entry) } }
                    .keyboardShortcut(.defaultAction)
                    .help("把改动应用回工作区，栈里这一份保留")
                Button("取回") { Task { await model.pop(entry) } }
                    .help("把改动应用回工作区，并从栈里删掉这一条")
                Button("丢弃…", role: .destructive) { model.pendingDrop = entry }
            }
            Spacer()
            Button("完成") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Theme.Spacing.loose)
    }
}

private struct StashRow: View {

    let entry: StashEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.displayName)
                .font(Theme.Font.body)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: Theme.Spacing.regular) {
                Label(entry.branch, systemImage: "arrow.triangle.branch")
                    .labelStyle(.compact)
                Text(Self.formatter.localizedString(for: entry.date, relativeTo: Date()))
                if !entry.hasUserMessage {
                    Text("未命名")
                        .foregroundStyle(Theme.Colors.decorativeText)
                }
            }
            .font(Theme.Font.secondary)
            .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .padding(.vertical, 2)
        .help(entry.hash)
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
