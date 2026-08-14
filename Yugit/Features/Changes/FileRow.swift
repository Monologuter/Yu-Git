import GitKit
import SwiftUI

/// 变更列表中的一行。
struct FileRow: View {

    let entry: StatusEntry
    var showsIndexStatus = false
    /// 平铺模式下要显示所在目录；树里目录已经由缩进表达了，再显示一遍是噪音。
    var showsFullPath = true

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

                if showsFullPath, let directory {
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

/// 树形变更列表里的目录行。
struct DirectoryRow: View {

    let node: PathTreeNode<StatusEntry>
    let depth: Int
    let isCollapsed: Bool
    let isStaged: Bool
    let onToggle: () -> Void
    let onStageAll: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.tight + 2) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                .frame(width: 10)

            Image(systemName: isCollapsed ? "folder.fill" : "folder")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(node.name)
                .font(Theme.Font.body)
                .lineLimit(1)
                // 目录名从头部截断：合并后的 a/b/c/d 里，最后一段离文件最近，
                // 也最能说明这是哪个目录
                .truncationMode(.head)

            Text("\(node.leafCount)")
                .font(Theme.Font.secondary)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)

            // 悬停才出现，不然每个目录后面挂一个按钮会很吵
            if isHovering {
                Button(isStaged ? "取消" : "暂存") { onStageAll() }
                    .buttonStyle(.borderless)
                    .font(Theme.Font.secondary)
                    .help(
                        isStaged
                            ? "取消暂存这个目录下的 \(node.leafCount) 个文件"
                            : "暂存这个目录下的 \(node.leafCount) 个文件")
            }
        }
        .padding(.leading, CGFloat(depth) * 12)
        .padding(.vertical, 1)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onToggle)
        .help(node.id)
    }
}
