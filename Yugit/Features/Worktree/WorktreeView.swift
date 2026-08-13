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

    private(set) var statuses: [WorktreeStatus] = []
    private(set) var isLoading = false
    var errorMessage: String?

    /// 比较的基线，通常是主分支。
    var baseline: String = "main"

    init(repository: RepositoryViewModel) {
        self.repository = repository
        // 当前分支通常就是想比的基线
        if let current = repository.currentBranch?.name { baseline = current }
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }

        do {
            statuses = try await repository.worktreeStatuses(comparedTo: baseline)
        } catch {
            errorMessage = "读取 worktree 失败：\(error)"
        }
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
                    .font(.headline)
                Text("同一个仓库同时签出多个分支到不同目录，各干各的互不打扰。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            ContentUnavailableView {
                Label("还没有并行工作区", systemImage: "square.split.2x1")
            } description: {
                Text("给每个 agent 分一个工作区，它们就不会互相踩工作区了。")
            } actions: {
                Button("新建一个") { isAdding = true }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.statuses) { status in
                        WorktreeCard(
                            status: status,
                            baseline: model.baseline,
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

    private var footer: some View {
        HStack {
            if let error = model.errorMessage {
                Label(error, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if model.statuses.contains(where: { $0.worktree.isPrunable }) {
                Label("有记录指向的目录已经不在了", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
    let onMerge: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.worktree.isMain ? "house" : "square.split.2x1")
                    .foregroundStyle(status.worktree.isMain ? .secondary : Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(status.worktree.branch ?? "（detached）")
                            .font(.callout.weight(.medium))

                        if status.worktree.isMain {
                            Text("主工作区")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: .capsule)
                        }

                        if let reason = status.worktree.lockReason {
                            Label(reason.isEmpty ? "已锁定" : reason, systemImage: "lock")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(status.worktree.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer(minLength: 4)

                if status.isReadyToMerge {
                    // 「可以合了」是这个面板最想让人一眼看到的信号
                    Label("可以合了", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if status.worktree.isPrunable {
                Label("目录已经不在了，可以清理掉这条记录", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                statsRow
            }

            if let subject = status.lastCommitSubject {
                Text(subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            actionRow
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    status.isReadyToMerge ? Color.green.opacity(0.4) : Color(nsColor: .separatorColor)
                )
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            if status.ahead > 0 {
                Label("领先 \(status.ahead)", systemImage: "arrow.up")
                    .foregroundStyle(.green)
            }
            if status.behind > 0 {
                Label("落后 \(status.behind)", systemImage: "arrow.down")
                    .foregroundStyle(.orange)
            }
            if status.dirtyFileCount > 0 {
                Label("\(status.dirtyFileCount) 个文件未提交", systemImage: "pencil")
                    .foregroundStyle(.secondary)
            }
            if status.ahead == 0 && status.behind == 0 && status.isClean {
                Text("与 \(baseline) 一致")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption2)
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
                .font(.headline)

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
                            .font(.caption)
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
                .font(.caption)
                .foregroundStyle(.secondary)

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
