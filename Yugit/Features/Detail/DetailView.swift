import GitKit
import SwiftUI

/// 右栏：选中对象的详情。选中文件时显示 diff，选中提交时显示提交信息。
struct DetailView: View {

    @Bindable var repository: RepositoryViewModel

    var body: some View {
        Group {
            if let selection = repository.selectedFile {
                fileDetail(for: selection)
            } else if let commit = selectedCommit {
                CommitDetailView(commit: commit)
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
    }

    @ViewBuilder
    private func fileDetail(for selection: RepositoryViewModel.FileSelection) -> some View {
        VStack(spacing: 0) {
            DiffToolbar(repository: repository, selection: selection)
            Divider()

            if let diff = repository.selectedDiff {
                DiffView(
                    diff: diff,
                    isStaged: selection.isStaged,
                    onStageHunk: { index in
                        Task { await repository.stageHunk(at: index, in: selection.path) }
                    },
                    onUnstageHunk: { index in
                        Task { await repository.unstageHunk(at: index, in: selection.path) }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(commit.subject)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)

                    if !commit.body.isEmpty {
                        Text(commit.body)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if !commit.refs.isEmpty {
                    RefBadges(refs: commit.refs)
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("提交", value: commit.hash, monospaced: true)

                    row(
                        "作者",
                        value: "\(commit.author.name) <\(commit.author.email)>",
                        secondary: commit.author.date.formatted(date: .abbreviated, time: .shortened)
                    )

                    // author 与 committer 不同意味着经过 rebase / cherry-pick / amend，
                    // 相同则没必要重复显示
                    if commit.committer.email != commit.author.email
                        || commit.committer.date != commit.author.date
                    {
                        row(
                            "提交者",
                            value: "\(commit.committer.name) <\(commit.committer.email)>",
                            secondary: commit.committer.date.formatted(
                                date: .abbreviated, time: .shortened)
                        )
                    }

                    if commit.parents.isEmpty {
                        row("父提交", value: "无（根提交）")
                    } else {
                        row(
                            commit.isMerge ? "父提交（合并）" : "父提交",
                            value: commit.parents.map { String($0.prefix(7)) }.joined(separator: "  "),
                            monospaced: true
                        )
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func row(
        _ title: String,
        value: String,
        secondary: String? = nil,
        monospaced: Bool = false
    ) -> some View {
        GridRow {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                    .textSelection(.enabled)

                if let secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
