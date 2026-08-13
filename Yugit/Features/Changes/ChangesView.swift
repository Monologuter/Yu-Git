import GitKit
import SwiftUI

/// 中栏：工作区变更与提交历史。
struct ChangesView: View {

    @Bindable var repository: RepositoryViewModel
    @State private var section = Section.changes

    enum Section: String, CaseIterable, Identifiable {
        case changes = "变更"
        case history = "历史"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $section) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()

            switch section {
            case .changes: changeList
            case .history: historyList
            }
        }
    }

    // MARK: - 变更

    @ViewBuilder
    private var changeList: some View {
        if !repository.hasChanges && repository.conflictedEntries.isEmpty {
            ContentUnavailableView(
                "工作区干净",
                systemImage: "checkmark.circle",
                description: Text("没有待处理的改动")
            )
        } else {
            List(selection: $repository.selectedFile) {
                if !repository.conflictedEntries.isEmpty {
                    SwiftUI.Section("冲突") {
                        ForEach(repository.conflictedEntries, id: \.path) { entry in
                            FileRow(entry: entry).tag(entry.path)
                        }
                    }
                }

                if !repository.stagedEntries.isEmpty {
                    SwiftUI.Section("已暂存") {
                        ForEach(repository.stagedEntries, id: \.path) { entry in
                            FileRow(entry: entry, showsIndexStatus: true).tag(entry.path)
                        }
                    }
                }

                if !repository.unstagedEntries.isEmpty {
                    SwiftUI.Section("未暂存") {
                        ForEach(repository.unstagedEntries, id: \.path) { entry in
                            FileRow(entry: entry).tag(entry.path)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 历史

    @ViewBuilder
    private var historyList: some View {
        if repository.commits.isEmpty {
            ContentUnavailableView(
                "尚无提交",
                systemImage: "clock",
                description: Text("这个仓库还没有任何 commit")
            )
        } else {
            List(repository.commits, selection: $repository.selectedCommit) { commit in
                CommitRow(commit: commit).tag(commit.id)
            }
        }
    }
}

/// 变更列表中的一行。
struct FileRow: View {

    let entry: StatusEntry
    var showsIndexStatus = false

    var body: some View {
        HStack(spacing: 8) {
            Text(statusLetter)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(statusColor)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let directory {
                    Text(directory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 0)
        }
        .help(helpText)
    }

    private var fileName: String {
        (entry.path as NSString).lastPathComponent
    }

    private var directory: String? {
        let parent = (entry.path as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }

    private var status: FileStatus {
        showsIndexStatus ? entry.indexStatus : entry.workTreeStatus
    }

    private var statusLetter: String {
        switch entry.kind {
        case .untracked: "?"
        case .unmerged: "!"
        case .ignored: "·"
        case .renamed: "R"
        case .copied: "C"
        case .ordinary: String(status.rawValue)
        }
    }

    private var statusColor: Color {
        switch entry.kind {
        case .untracked: .secondary
        case .unmerged: .orange
        case .ignored: Color(nsColor: .tertiaryLabelColor)
        case .renamed, .copied: .purple
        case .ordinary:
            switch status {
            case .added: .green
            case .deleted: .red
            case .modified, .fileTypeChanged: .blue
            default: .secondary
            }
        }
    }

    private var helpText: String {
        var lines = [entry.path]
        if let original = entry.originalPath {
            lines.append("原路径：\(original)")
        }
        if let similarity = entry.similarity {
            lines.append("相似度：\(similarity)%")
        }
        if entry.kind == .unmerged {
            lines.append("存在冲突，需要先解决")
        }
        if let submodule = entry.submodule {
            var states: [String] = []
            if submodule.commitChanged { states.append("指向的 commit 有变化") }
            if submodule.hasModifiedContent { states.append("内部有改动") }
            if submodule.hasUntrackedContent { states.append("内部有未跟踪文件") }
            if !states.isEmpty {
                lines.append("submodule：" + states.joined(separator: "、"))
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// 历史列表中的一行。
///
/// 这里先用 SwiftUI 实现，v0.3 会换成 AppKit 的 NSTableView + 自绘分支图——
/// 5 万 commit 的滚动性能 SwiftUI List 撑不住。
struct CommitRow: View {

    let commit: Commit

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if commit.isMerge {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .help("合并提交")
                    }

                    Text(commit.subject)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 6) {
                    Text(commit.abbreviatedHash)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(commit.author.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(commit.author.date, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !commit.refs.isEmpty {
                    RefBadges(refs: commit.refs)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// commit 上的分支/tag 徽章。
struct RefBadges: View {

    let refs: [CommitRef]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in
                if let label = label(for: ref) {
                    Text(label.text)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(label.color.opacity(0.15), in: .capsule)
                        .foregroundStyle(label.color)
                }
            }
        }
    }

    private func label(for ref: CommitRef) -> (text: String, color: Color)? {
        switch ref {
        // HEAD 总是和它指向的分支一起出现，单独画一个徽章只是噪音
        case .head: nil
        case let .localBranch(name): (name, .accentColor)
        case let .remoteBranch(name): (name, .gray)
        case let .tag(name): (name, .orange)
        case .other: nil
        }
    }
}
