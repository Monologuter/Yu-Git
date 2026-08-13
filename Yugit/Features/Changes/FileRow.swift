import GitKit
import SwiftUI

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
