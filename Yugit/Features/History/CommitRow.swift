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
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.mergeAccent)
                            .help("合并提交")
                    }

                    Text(commit.subject)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                HStack(spacing: 6) {
                    Text(commit.abbreviatedHash)
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    Text(commit.author.name)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)

                    Text(commit.author.date, format: .relative(presentation: .named))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
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
