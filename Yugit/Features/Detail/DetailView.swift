import GitKit
import SwiftUI

/// 右栏：选中对象的详情。
///
/// v0.1 只做只读展示，diff 查看器是 v0.2 的内容。
struct DetailView: View {

    let repository: RepositoryViewModel

    var body: some View {
        if let commit = selectedCommit {
            CommitDetailView(commit: commit)
        } else if let path = repository.selectedFile {
            FileDetailPlaceholder(path: path)
        } else {
            ContentUnavailableView(
                "未选择内容",
                systemImage: "sidebar.right",
                description: Text("在左侧选择一个文件或提交")
            )
        }
    }

    private var selectedCommit: Commit? {
        guard let id = repository.selectedCommit else { return nil }
        return repository.commits.first { $0.id == id }
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

/// 文件详情占位。真正的 diff 查看器在 v0.2。
struct FileDetailPlaceholder: View {

    let path: String

    var body: some View {
        ContentUnavailableView {
            Label(path, systemImage: "doc.text")
        } description: {
            Text("diff 查看器将在 v0.2 提供")
        }
    }
}
