import AppKit
import GitKit
import Observation
import SwiftUI

/// 并行 Agent 面板的状态。
///
/// 支柱 3。多个 agent 同时改一个仓库时，最大的麻烦是它们会互相踩工作区。
/// 每个 agent 一个 worktree 就没这问题——这个面板是那套流水线的控制台：
/// 建 → 看状态 → 合回来 → 清理。
@MainActor
@Observable
final class WorktreeViewModel: Identifiable {

    nonisolated let id = UUID()

    private let repository: RepositoryViewModel

    private(set) var overview: WorktreeOverview?
    private(set) var isLoading = false
    var errorMessage: String?

    /// 比较的基线，通常是主分支。
    var baseline: String = "main"

    var statuses: [WorktreeStatus] { overview?.statuses ?? [] }
    /// 被多个工作区同时改着的文件。空数组表示各干各的，互不相干。
    var overlaps: [WorktreeOverlap] { overview?.overlaps ?? [] }

    init(repository: RepositoryViewModel) {
        self.repository = repository
        // 当前分支通常就是想比的基线
        if let current = repository.currentBranch?.name { baseline = current }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            overview = try await repository.worktreeOverview(comparedTo: baseline)
        } catch {
            errorMessage = "读取 worktree 失败：\(error)"
        }
    }

    /// 某个工作区碰过的文件数。
    func touchedCount(of status: WorktreeStatus) -> Int {
        overview?.touchedPaths[status.worktree.path]?.count ?? 0
    }

    /// 某个工作区和别人撞在一起的文件。
    func conflicts(of status: WorktreeStatus) -> [WorktreeOverlap] {
        overlaps.filter { $0.worktreePaths.contains(status.worktree.path) }
    }

    /// 一个工作区路径对应的显示名。
    func displayName(ofWorktreeAt path: String) -> String {
        statuses.first { $0.worktree.path == path }
            .map { $0.worktree.branch ?? $0.worktree.displayName }
            ?? (path as NSString).lastPathComponent
    }

    /// 新建一个 worktree。
    ///
    /// 目录默认建在仓库的**兄弟位置**而不是里面：建在里面会变成仓库中一个
    /// 未跟踪的大目录，既弄脏 status，也可能被自己收进快照。
    func suggestedPath(forBranch branch: String) -> URL {
        let safe = branch.replacingOccurrences(of: "/", with: "-")
        return repository.rootURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(repository.rootURL.lastPathComponent)-\(safe)", isDirectory: true)
    }

    func add(branch: String, at path: URL, createBranch: Bool) async {
        errorMessage = nil
        do {
            try await repository.addWorktree(at: path, branch: branch, createBranch: createBranch)
            await reload()
        } catch {
            errorMessage = "新建失败：\(error)"
        }
    }

    func remove(_ status: WorktreeStatus, force: Bool) async {
        errorMessage = nil
        do {
            try await repository.removeWorktree(at: status.worktree.path, force: force)
            await reload()
        } catch {
            errorMessage = "移除失败：\(error)"
        }
    }

    /// 把某个 worktree 的分支合回当前分支。
    func merge(_ status: WorktreeStatus) async {
        guard let branch = status.worktree.branch else { return }
        errorMessage = nil

        await repository.merge(branch)
        await reload()
    }

    func prune() async {
        errorMessage = nil
        do {
            try await repository.pruneWorktrees()
            await reload()
        } catch {
            errorMessage = "清理失败：\(error)"
        }
    }

    /// 在 Finder 里打开。
    func reveal(_ status: WorktreeStatus) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: status.worktree.path)
    }
}

struct WorktreeView: View {

    @Bindable var model: WorktreeViewModel
    let onDismiss: () -> Void

    @State private var isAdding = false
    @State private var pendingRemoval: WorktreeStatus?
    @State private var isSummaryExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 760, height: 560)
        .task { await model.reload() }
        .sheet(isPresented: $isAdding) {
            AddWorktreeSheet(model: model) { isAdding = false }
        }
        .confirmationDialog(
            "移除这个 worktree？",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { status in
            if !status.isClean {
                // 有未提交改动时删除会丢东西，必须说清楚
                Button("强制移除，丢弃 \(status.dirtyFileCount) 个文件的改动", role: .destructive) {
                    Task { await model.remove(status, force: true) }
                    pendingRemoval = nil
                }
            } else {
                Button("移除", role: .destructive) {
                    Task { await model.remove(status, force: false) }
                    pendingRemoval = nil
                }
            }
            Button("取消", role: .cancel) { pendingRemoval = nil }
        } message: { status in
            Text(
                status.isClean
                    ? "目录会被删掉，分支本身保留。"
                    : "这个 worktree 里还有没提交的改动，它们没进过 git 的对象库，删掉就找不回来了。")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("并行工作区")
                    .font(Theme.Font.title)
                Text("同一个仓库同时签出多个分支到不同目录，各干各的互不打扰。")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            Spacer()

            Button {
                isAdding = true
            } label: {
                Label("新建", systemImage: "plus")
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.statuses.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.statuses.count <= 1 {
            EmptyStateView(
                "还没有并行工作区",
                systemImage: "square.split.2x1",
                description: "给每个 agent 分一个工作区，它们就不会互相踩工作区了。"
            ) {
                Button("新建一个") { isAdding = true }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    conflictBanner
                    changeSummary

                    ForEach(model.statuses) { status in
                        WorktreeCard(
                            status: status,
                            baseline: model.baseline,
                            touchedCount: model.touchedCount(of: status),
                            conflicts: model.conflicts(of: status),
                            nameOfWorktree: model.displayName(ofWorktreeAt:),
                            onMerge: { Task { await model.merge(status) } },
                            onRemove: { pendingRemoval = status },
                            onReveal: { model.reveal(status) }
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    /// 撞车预警。
    ///
    /// 两个 agent 各改各的、各自都很顺，合的时候才发现动的是同一个文件——
    /// 这是并行跑 agent 最典型的翻车方式，而且发现得越晚越贵。放在最上面。
    @ViewBuilder
    private var conflictBanner: some View {
        if !model.overlaps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "\(model.overlaps.count) 个文件被多个工作区同时改着",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(Theme.Font.secondary.weight(.medium))
                .foregroundStyle(Theme.Colors.warning)

                Text("现在各改各的都很顺，合并时才会撞上。趁改动还少的时候商量一下便宜得多。")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)

                ForEach(model.overlaps.prefix(8)) { overlap in
                    HStack(spacing: 6) {
                        Text(overlap.path)
                            .font(Theme.Font.caption)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Text(
                            overlap.worktreePaths
                                .map(model.displayName(ofWorktreeAt:))
                                .joined(separator: " · ")
                        )
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.warning)
                        Spacer(minLength: 0)
                    }
                }
                if model.overlaps.count > 8 {
                    Text("还有 \(model.overlaps.count - 8) 个")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.warningWash, in: .rect(cornerRadius: 8))
        }
    }

    /// 跨工作区的改动汇总，一屏看全。默认收起——真正要紧的是上面那条预警。
    @ViewBuilder
    private var changeSummary: some View {
        let total = Set(model.overview?.touchedPaths.values.flatMap { $0 } ?? []).count
        if total > 0 {
            DisclosureGroup(isExpanded: $isSummaryExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(summaryRows, id: \.path) { row in
                        HStack(spacing: 6) {
                            Text(row.path)
                                .font(Theme.Font.caption)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer(minLength: 8)
                            Text(row.worktrees.joined(separator: " · "))
                                .font(Theme.Font.caption)
                                .foregroundStyle(
                                    row.worktrees.count > 1
                                        ? Theme.Colors.warning : Theme.Colors.secondaryText)
                        }
                    }
                    if total > summaryRows.count {
                        Text("还有 \(total - summaryRows.count) 个文件")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }
                .padding(.top, 6)
            } label: {
                Text("跨工作区改动汇总（\(total) 个文件）")
                    .font(Theme.Font.secondary.weight(.medium))
            }
            .padding(10)
            .background(Theme.Colors.raisedBackground, in: .rect(cornerRadius: 8))
        }
    }

    /// 汇总里显示的行。撞车的排前面，其余按路径排。
    private var summaryRows: [(path: String, worktrees: [String])] {
        guard let overview = model.overview else { return [] }

        var owners: [String: [String]] = [:]
        for status in overview.statuses {
            let path = status.worktree.path
            for file in overview.touchedPaths[path] ?? [] {
                owners[file, default: []].append(model.displayName(ofWorktreeAt: path))
            }
        }

        // 上限是防守：一次大重构可能碰几千个文件，全渲染出来会把面板拖垮
        return
            owners
            .map { (path: $0.key, worktrees: $0.value) }
            .sorted { ($1.worktrees.count, $0.path) < ($0.worktrees.count, $1.path) }
            .prefix(120)
            .map { $0 }
    }

    private var footer: some View {
        HStack {
            if let error = model.errorMessage {
                Label(error, systemImage: "xmark.circle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.danger)
                    .textSelection(.enabled)
            } else if model.statuses.contains(where: { $0.worktree.isPrunable }) {
                Label("有记录指向的目录已经不在了", systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.warning)
            }

            Spacer()

            Button("清理失效记录") { Task { await model.prune() } }
                .disabled(!model.statuses.contains { $0.worktree.isPrunable })

            Button("刷新") { Task { await model.reload() } }
            Button("关闭") { onDismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}

// MARK: - 单个工作区

private struct WorktreeCard: View {

    let status: WorktreeStatus
    let baseline: String
    let touchedCount: Int
    let conflicts: [WorktreeOverlap]
    let nameOfWorktree: (String) -> String
    let onMerge: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.worktree.isMain ? "house" : "square.split.2x1")
                    .foregroundStyle(status.worktree.isMain ? Theme.Colors.secondaryText : Theme.Colors.accent)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(status.worktree.branch ?? "（detached）")
                            .font(Theme.Font.callout.weight(.medium))

                        if status.worktree.isMain {
                            Text("主工作区")
                                .font(Theme.Font.caption)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Theme.Colors.fillQuaternary, in: .capsule)
                        }

                        if let reason = status.worktree.lockReason {
                            Label(reason.isEmpty ? "已锁定" : reason, systemImage: "lock")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }

                    Text(status.worktree.path)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 4)

                if status.isReadyToMerge {
                    // 「可以合了」是这个面板最想让人一眼看到的信号
                    Label("可以合了", systemImage: "checkmark.circle")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.success)
                }
            }

            if status.worktree.isPrunable {
                Label("目录已经不在了，可以清理掉这条记录", systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
            } else {
                statsRow
            }

            if let subject = status.lastCommitSubject {
                Text(subject)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
            }

            sessionRow
            conflictRow
            actionRow
        }
        .padding(10)
        .background(Theme.Colors.raisedBackground, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    status.isReadyToMerge ? Theme.Colors.success.opacity(0.4) : Theme.Colors.separator
                )
        }
    }

    /// 这个工作区里是哪次对话在干活。
    ///
    /// 数据来自私有 notes（`refs/yugit/ai-sessions`），由 agent 通过 MCP 工具
    /// `yugit_attribute` 自己写下来。**没记录就说没记录**——提交信息里本来
    /// 就没有会话信息，从「作者是 Claude」倒推出一次对话只会让人当真。
    @ViewBuilder
    private var sessionRow: some View {
        if let session = status.session {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .foregroundStyle(Theme.Colors.brand)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.summary)
                        .lineLimit(2)
                    Text(
                        "\(session.tool) · \(Self.formatter.localizedString(for: session.timestamp, relativeTo: Date()))"
                    )
                    .foregroundStyle(Theme.Colors.tertiaryText)
                }
                Spacer(minLength: 0)
            }
            .font(Theme.Font.caption)
        } else if !status.worktree.isMain && !status.worktree.isPrunable {
            Text("没有 agent 会话记录")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
    }

    @ViewBuilder
    private var conflictRow: some View {
        if !conflicts.isEmpty {
            let others = Set(
                conflicts
                    .flatMap(\.worktreePaths)
                    .filter { $0 != status.worktree.path }
                    .map(nameOfWorktree)
            ).sorted()

            Label(
                "\(conflicts.count) 个文件和 \(others.joined(separator: "、")) 撞在一起",
                systemImage: "exclamationmark.triangle"
            )
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.warning)
        }
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var statsRow: some View {
        HStack(spacing: 12) {
            if status.ahead > 0 {
                Label("领先 \(status.ahead)", systemImage: "arrow.up")
                    .foregroundStyle(Theme.Colors.success)
            }
            if status.behind > 0 {
                Label("落后 \(status.behind)", systemImage: "arrow.down")
                    .foregroundStyle(Theme.Colors.warning)
            }
            if status.dirtyFileCount > 0 {
                Label("\(status.dirtyFileCount) 个文件未提交", systemImage: "pencil")
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            if touchedCount > 0 {
                Label("共碰过 \(touchedCount) 个文件", systemImage: "doc.on.doc")
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .help("相对 \(baseline)，已提交的加上还没提交的")
            }
            if status.ahead == 0 && status.behind == 0 && status.isClean {
                Text("与 \(baseline) 一致")
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            Spacer()
        }
        .font(Theme.Font.caption)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            Button("在 Finder 中显示", action: onReveal)

            if !status.worktree.isMain {
                Button("合并到当前分支", action: onMerge)
                    .disabled(status.ahead == 0 || status.worktree.isPrunable)
                    .help(
                        status.ahead == 0
                            ? "这个工作区没有新的提交" : "把 \(status.worktree.branch ?? "") 合并进当前分支")

                Button("移除…", role: .destructive, action: onRemove)
            }

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - 新建

private struct AddWorktreeSheet: View {

    @Bindable var model: WorktreeViewModel
    let onDismiss: () -> Void

    @State private var branch = ""
    @State private var createBranch = true
    @State private var path: URL?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建并行工作区")
                .font(Theme.Font.title)

            Form {
                TextField("分支名", text: $branch)
                    .onChange(of: branch) { _, value in
                        // 用户没自己挑目录时，跟着分支名走
                        if !value.isEmpty { path = model.suggestedPath(forBranch: value) }
                    }

                Toggle("新建这个分支", isOn: $createBranch)
                    .help("关掉表示签出一个已经存在的分支")

                LabeledContent("目录") {
                    HStack {
                        Text(path?.path(percentEncoded: false) ?? "填了分支名会自动生成")
                            .font(Theme.Font.secondary)
                            .foregroundStyle(path == nil ? .tertiary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Button("选择…") { chooseDirectory() }
                            .controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)

            // 建在仓库里面会变成一个未跟踪的大目录，还可能被快照收进去
            Label("目录会建在仓库外面，和仓库同级", systemImage: "info.circle")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.secondaryText)

            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("新建") {
                    Task {
                        guard let path else { return }
                        isWorking = true
                        await model.add(branch: branch, at: path, createBranch: createBranch)
                        isWorking = false
                        if model.errorMessage == nil { onDismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branch.isEmpty || path == nil || isWorking)
            }
        }
        .padding(16)
        .frame(width: 480)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择新工作区的位置（会在其中创建一个新目录）"

        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let name = branch.isEmpty ? "worktree" : branch.replacingOccurrences(of: "/", with: "-")
        path = chosen.appendingPathComponent(name, isDirectory: true)
    }
}
