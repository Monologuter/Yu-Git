import GitKit
import SwiftUI

/// 左栏：本地分支、远程分支、tag。
struct SidebarView: View {

    @Bindable var repository: RepositoryViewModel

    @State private var newBranchName = ""
    @State private var isCreatingBranch = false
    @State private var renaming: Branch?
    @State private var renamedName = ""
    @State private var pendingDelete: Branch?

    var body: some View {
        List {
            Section {
                if repository.localBranches.isEmpty {
                    EmptyHint("尚无分支")
                } else {
                    ForEach(repository.localBranches) { branch in
                        BranchRow(branch: branch)
                            .contextMenu { localBranchMenu(for: branch) }
                    }
                }
            } header: {
                HStack {
                    Text("本地分支")
                    Spacer()
                    Button {
                        newBranchName = ""
                        isCreatingBranch = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("新建分支")
                }
            }

            if !repository.remoteBranches.isEmpty {
                Section("远程分支") {
                    ForEach(repository.remoteBranches) { branch in
                        BranchRow(branch: branch)
                            .contextMenu { remoteBranchMenu(for: branch) }
                    }
                }
            }

            if !repository.tags.isEmpty {
                Section("标签") {
                    ForEach(repository.tags) { tag in
                        TagRow(tag: tag)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .alert("新建分支", isPresented: $isCreatingBranch) {
            TextField("分支名", text: $newBranchName)
            Button("创建并切换") {
                let name = newBranchName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await repository.createBranch(named: name) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("从当前 HEAD 新建分支。")
        }
        .alert(
            "重命名分支",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )
        ) {
            TextField("新名字", text: $renamedName)
            Button("重命名") {
                guard let branch = renaming else { return }
                let name = renamedName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name != branch.name else { return }
                Task { await repository.renameBranch(from: branch.name, to: name) }
                renaming = nil
            }
            Button("取消", role: .cancel) { renaming = nil }
        } message: {
            // 远程分支不会跟着改名，这一点必须说清楚
            Text("只改本地分支名。若它已推送到远程，远程那边的名字不会跟着变。")
        }
        .confirmationDialog(
            "确定删除分支？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { branch in
            Button("删除 \(branch.name)", role: .destructive) {
                Task { await repository.deleteBranch(named: branch.name) }
                pendingDelete = nil
            }
            Button("强制删除（含未合并的提交）", role: .destructive) {
                Task { await repository.deleteBranch(named: branch.name, force: true) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("普通删除会在分支还有未合并提交时被 git 拒绝；强制删除后那些提交只能靠 reflog 找回。")
        }
    }

    // MARK: - 菜单

    @ViewBuilder
    private func localBranchMenu(for branch: Branch) -> some View {
        if !branch.isCurrent {
            Button("切换到 \(branch.name)") {
                Task { await repository.switchBranch(to: branch.name) }
            }
            Button("合并 \(branch.name) 到当前分支") {
                Task { await repository.merge(branch.name) }
            }
            Divider()
        }

        Button("重命名…") {
            renamedName = branch.name
            renaming = branch
        }

        if !branch.isCurrent {
            Button("删除…", role: .destructive) { pendingDelete = branch }
        }
    }

    @ViewBuilder
    private func remoteBranchMenu(for branch: Branch) -> some View {
        // origin/main → main
        let localName = branch.name.split(separator: "/").dropFirst().joined(separator: "/")

        Button("基于它新建本地分支") {
            guard !localName.isEmpty else { return }
            Task { await repository.createBranch(named: localName, from: branch.name) }
        }
        Button("合并到当前分支") {
            Task { await repository.merge(branch.name) }
        }
    }
}

struct BranchRow: View {

    let branch: Branch

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: branch.isRemote ? "cloud" : "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(branch.isCurrent ? Color.accentColor : .secondary)
                .frame(width: 14)

            Text(branch.name)
                .fontWeight(branch.isCurrent ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            trackingBadge
        }
        .help(tooltip)
    }

    @ViewBuilder
    private var trackingBadge: some View {
        let tracking = branch.tracking
        if tracking.isGone {
            // upstream 被删了还留着配置，push 会失败，值得显眼提示
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if tracking.ahead > 0 || tracking.behind > 0 {
            HStack(spacing: 3) {
                if tracking.ahead > 0 {
                    Label("\(tracking.ahead)", systemImage: "arrow.up")
                }
                if tracking.behind > 0 {
                    Label("\(tracking.behind)", systemImage: "arrow.down")
                }
            }
            .labelStyle(.compact)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var tooltip: String {
        var lines = [branch.name]
        if let upstream = branch.upstream {
            lines.append("upstream：\(upstream)")
        }
        if branch.tracking.isGone {
            lines.append("upstream 已在远程被删除")
        } else if branch.tracking.hasDiverged {
            lines.append("已分叉：领先 \(branch.tracking.ahead)，落后 \(branch.tracking.behind)")
        }
        if !branch.lastCommitSubject.isEmpty {
            lines.append("最新提交：\(branch.lastCommitSubject)")
        }
        return lines.joined(separator: "\n")
    }
}

struct TagRow: View {

    let tag: Tag

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(tag.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if !tag.isAnnotated {
                // 工程规范要求发布用附注 tag，轻量 tag 标出来便于发现
                Text("轻量")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .help(tag.message ?? tag.name)
    }
}

/// 列表分组为空时的占位。
struct EmptyHint: View {

    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
    }
}

/// 图标与文字紧凑排列，用于角标这类窄空间。
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == CompactLabelStyle {
    static var compact: CompactLabelStyle { CompactLabelStyle() }
}
