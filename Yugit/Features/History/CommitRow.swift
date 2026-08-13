import GitKit
import SwiftUI

/// 历史列表中的一行。
///
/// 目前用 SwiftUI 实现，v0.3 会换成 AppKit 的 NSTableView + 自绘分支图——
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
