import GitKit
import SwiftUI

/// 右栏：选中对象的详情。选中文件时显示 diff，选中提交时显示提交信息。
struct DetailView: View {

    @Bindable var repository: RepositoryViewModel
    @State private var blameModel: BlameViewModel?

    var body: some View {
        Group {
            if let selection = repository.selectedFile {
                fileDetail(for: selection)
            } else if let commit = selectedCommit {
                CommitDetailView(commit: commit, repository: repository)
            } else {
                ContentUnavailableView(
                    "未选择内容",
                    systemImage: "sidebar.right",
                    description: Text("在左侧选择一个文件或提交")
                )
            }
        }
        // 选中项变了就重新取 diff
        .task(id: repository.selectedFile) {
            await repository.reloadSelectedDiff()
        }
        .sheet(item: $blameModel) { model in
            BlameView(model: model) { blameModel = nil }
        }
    }

    @ViewBuilder
    private func fileDetail(for selection: RepositoryViewModel.FileSelection) -> some View {
        VStack(spacing: 0) {
            DiffToolbar(repository: repository, selection: selection) {
                blameModel = BlameViewModel(repository: repository, path: selection.path)
            }
            Divider()

            ExplanationPanel(title: "用中文讲讲这份改动") {
                try await repository.explainSubject(for: selection)
            }
            .id(selection)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if let diff = repository.selectedDiff {
                DiffView(
                    diff: diff,
                    isStaged: selection.isStaged,
                    onStageHunk: { index in
                        Task { await repository.stageHunk(at: index, in: selection.path) }
                    },
                    onUnstageHunk: { index in
                        Task { await repository.unstageHunk(at: index, in: selection.path) }
                    },
                    onApplyLines: { lines in
                        Task {
                            await repository.applyLines(
                                lines, of: selection.path, isStaged: selection.isStaged)
                        }
                    }
                )
            } else if repository.isLoadingDiff {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "无法读取 diff",
                    systemImage: "exclamationmark.triangle",
                    description: Text("这个文件的差异暂时取不到")
                )
            }
        }
    }

    private var selectedCommit: Commit? {
        guard let id = repository.selectedCommit else { return nil }
        return repository.commits.first { $0.id == id }
    }
}

/// diff 上方的工具条：文件名、增删统计、整文件暂存入口。
struct DiffToolbar: View {

    let repository: RepositoryViewModel
    let selection: RepositoryViewModel.FileSelection
    let onShowBlame: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)

            Text(selection.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if let diff = repository.selectedDiff, !diff.isBinary {
                HStack(spacing: 4) {
                    Text("+\(diff.addedLineCount)").foregroundStyle(.green)
                    Text("−\(diff.deletedLineCount)").foregroundStyle(.red)
                }
                .font(.system(.caption, design: .monospaced))
            }

            Spacer(minLength: 8)

            Button("查看归因") { onShowBlame() }
                .help("逐行看这段代码是谁写的：人，还是哪个 AI 工具")

            if selection.isStaged {
                Button("取消暂存整个文件") {
                    Task { await repository.unstage([selection.path]) }
                }
            } else {
                Button("暂存整个文件") {
                    Task { await repository.stage([selection.path]) }
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct CommitDetailView: View {

    let commit: Commit
    let repository: RepositoryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                    // 不用 .title3（20pt）。这是侧栏面板不是页面标题，
                    // 字号过大会让它抢走主列表的视线，而主列表才是干活的地方。
                    Text(commit.subject)
                        .font(Theme.Font.title)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if !commit.body.isEmpty {
                        Text(commit.body)
                            .font(Theme.Font.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !commit.refs.isEmpty {
                    RefBadges(refs: commit.refs)
                }

                // 放在提交信息下面而不是页面底部：想读懂一次提交的人，
                // 正是刚看完标题却没看明白的人
                ExplanationPanel(title: "用中文讲讲这次 commit") {
                    try await repository.explainSubject(for: commit)
                }
                // commit 变了就重置面板，否则会把上一条的解释留在屏幕上
                .id(commit.hash)

                Divider()

                Grid(
                    alignment: .leading,
                    horizontalSpacing: Theme.Spacing.loose,
                    verticalSpacing: Theme.Spacing.regular
                ) {
                    // 只显示短 hash，完整的那 40 个字符交给复制按钮。
                    //
                    // 完整 hash 的用途是**粘贴到别处**，不是阅读——没人会一位一位
                    // 去核对 40 个十六进制字符。而强行显示全长在这么窄的面板里
                    // 必然折行，折成两截之后连双击选中都做不到，反而更难复制。
                    row("提交", value: commit.abbreviatedHash, monospaced: true) {
                        CopyButton(text: commit.hash, help: "复制完整 commit hash")
                    }

                    row(
                        "作者",
                        value: commit.author.name,
                        secondary: "\(commit.author.email) · "
                            + commit.author.date.formatted(date: .abbreviated, time: .shortened)
                    )

                    // author 与 committer 不同意味着经过 rebase / cherry-pick / amend，
                    // 相同则没必要重复显示
                    if commit.committer.email != commit.author.email
                        || commit.committer.date != commit.author.date
                    {
                        row(
                            "提交者",
                            value: commit.committer.name,
                            secondary: "\(commit.committer.email) · "
                                + commit.committer.date.formatted(
                                    date: .abbreviated, time: .shortened)
                        )
                    }

                    if commit.parents.isEmpty {
                        row("父提交", value: "无（根提交）")
                    } else {
                        row(
                            commit.isMerge ? "父提交（合并）" : "父提交",
                            value: commit.parents.map { String($0.prefix(9)) }
                                .joined(separator: "  "),
                            monospaced: true
                        )
                    }
                }

                Divider()

                changedFiles
            }
            .padding(Theme.Spacing.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 换一条提交就重新取文件列表
        .task(id: commit.hash) {
            await repository.reloadSelectedCommitFiles()
        }
    }

    /// 这次提交改了哪些文件。
    ///
    /// 这是点开一条提交后最想知道的事，却是原先整个面板里唯一没有的东西——
    /// 那时右边三分之二的屏幕只用来显示 hash、作者、父提交这四行元信息。
    @ViewBuilder
    private var changedFiles: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
            HStack(spacing: Theme.Spacing.tight) {
                Text("改动的文件")
                    .font(Theme.Font.title)
                if !repository.selectedCommitFiles.isEmpty {
                    Text("\(repository.selectedCommitFiles.count)")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.Spacing.tight + 1)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: .capsule)
                }
                if repository.isLoadingCommitFiles {
                    ProgressView().controlSize(.small)
                }
            }

            if repository.selectedCommitFiles.isEmpty {
                if !repository.isLoadingCommitFiles {
                    Text(commit.isMerge ? "这次合并相对第一个父提交没有改动" : "列不出改动的文件")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(repository.selectedCommitFiles) { change in
                        CommitFileRow(change: change)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row<Trailing: View>(
        _ title: String,
        value: String,
        secondary: String? = nil,
        monospaced: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        GridRow {
            Text(title)
                .font(Theme.Font.secondary)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)

            VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
                HStack(spacing: Theme.Spacing.tight) {
                    Text(value)
                        .font(monospaced ? Theme.Font.mono : Theme.Font.body)
                        .textSelection(.enabled)
                    trailing()
                }

                if let secondary {
                    Text(secondary)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// 提交详情里的一行文件。
private struct CommitFileRow: View {

    let change: CommitFileChange

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.regular) {
            // 状态字母用固定宽度且等宽字体，好让路径的左边界对齐成一列。
            // 不固定的话 A/M/D 宽度不同，整列会呈锯齿状。
            Text(change.kind.letter)
                .font(Theme.Font.mono)
                .foregroundStyle(color)
                .frame(width: 14, alignment: .center)
                .help(change.kind.displayName)

            VStack(alignment: .leading, spacing: 1) {
                // 路径从中间截断：两头都是有信息的（开头是模块，结尾是文件名），
                // 尾部截断会把最该看的文件名切掉。
                Text(change.path)
                    .font(Theme.Font.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if let source = change.sourcePath {
                    Text("原名 \(source)")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.tight)
        .help(change.path)
    }

    /// 状态字母的颜色。
    ///
    /// 增删沿用 diff 里的绿红，这两个颜色在这个 app 里已经稳定表示增删，
    /// 换一套反而要让人重新学。
    private var color: Color {
        switch change.kind {
        case .added: .green
        case .deleted: .red
        case .renamed, .copied: .blue
        default: .secondary
        }
    }
}

/// 复制到剪贴板，并给一个短暂的「已复制」反馈。
///
/// 没有反馈的复制按钮是最让人犯嘀咕的交互之一：点完什么都没发生，
/// 用户不知道到底复制上没有，往往会再点两下。
private struct CopyButton: View {

    let text: String
    let help: String

    @State private var justCopied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            justCopied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                justCopied = false
            }
        } label: {
            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(justCopied ? .green : .secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        // 图标切换时不做位移动画，只做淡入淡出——按钮在原地变，视线不用跟着跑
        .animation(.easeInOut(duration: 0.15), value: justCopied)
    }
}
