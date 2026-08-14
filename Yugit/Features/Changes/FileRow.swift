import GitKit
import SwiftUI

/// 变更列表中的一行。
struct FileRow: View {

    let entry: StatusEntry
    var showsIndexStatus = false
    /// 平铺模式下要显示所在目录；树里目录已经由缩进表达了，再显示一遍是噪音。
    var showsFullPath = true
    /// 这一行是不是选中行。
    ///
    /// 必须知道：选中行的背景是强调色，而「修改」的状态字母恰好也是强调色——
    /// 不换色的话 `M` 画在选中行上等于消失。分支图上踩过一模一样的坑。
    var isSelected = false

    var body: some View {
        HStack(spacing: Theme.Spacing.regular) {
            // 等宽 + 固定 14pt 宽，好让后面的路径左边界对齐成一列。
            // 不固定的话 A/M/D 各自宽度不同，整列会呈锯齿状。
            Text(statusLetter)
                .font(Theme.Font.mono)
                .foregroundStyle(isSelected ? Theme.Colors.onAccent : statusColor)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(Theme.Font.body)
                    .lineLimit(1)
                    // 文件名从中间截断：开头是模块，结尾是文件名，两头都有信息
                    .truncationMode(.middle)

                if showsFullPath, let directory {
                    Text(directory)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(
                            isSelected
                                ? Theme.Colors.onAccent.opacity(0.78) : Theme.Colors.secondaryText
                        )
                        .lineLimit(1)
                        // 目录从头部截断：最后一段离文件最近，最能说明这是哪个目录
                        .truncationMode(.head)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.tight)
        .frame(minHeight: showsFullPath && directory != nil ? 38 : 30)
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

    /// 状态**永远同时由字母和颜色表达**。
    ///
    /// 只靠颜色的话色盲用户什么都读不到，而这一列传的是「这个文件被怎么了」——
    /// 读不到就等于这一列不存在。字母才是主信息，颜色只是让它扫得更快。
    private var statusColor: Color {
        switch entry.kind {
        case .untracked: Theme.Colors.secondaryText
        case .unmerged: Theme.Colors.warning
        case .ignored: Theme.Colors.decorativeText
        // 改名和复制归到合并色：它们和新增/删除不是一回事，
        // 内容其实没变，变的是这个文件在树里的位置
        case .renamed, .copied: Theme.Colors.mergeAccent
        case .ordinary:
            switch status {
            case .added: Theme.Colors.success
            case .deleted: Theme.Colors.danger
            case .modified, .fileTypeChanged: Theme.Colors.accent
            default: Theme.Colors.secondaryText
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
