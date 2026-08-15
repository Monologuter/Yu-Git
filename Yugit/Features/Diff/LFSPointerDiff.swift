import GitKit
import SwiftUI

/// 一次 LFS 指针的变化。两端都可能为空——新增或删除时只有一边。
struct LFSPointerChange {
    let before: LFSPointer?
    let after: LFSPointer?
}

/// LFS 指针的 diff。
///
/// 换掉的是按行 diff。LFS 把大文件存成三行纯文本，照常按行比的话，
/// 屏幕上显示的是「改了三行字」——而实际发生的是一个上百 MB 的文件被整个换掉。
/// 这里要说的是那件真事：多大、换成了什么、内容不在这儿。
struct LFSPointerDiff: View {

    let change: LFSPointerChange

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            HStack(spacing: Theme.Spacing.regular) {
                Image(systemName: "externaldrive.badge.icloud")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Colors.brand)
                    .frame(width: 48, height: 48)
                    .background(Theme.Colors.brandWash, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Git LFS 管理的大文件")
                        .font(Theme.Font.title)
                    Text("仓库里存的是一个三行的指针，真正的内容放在 LFS 服务器上。")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.loose, verticalSpacing: 6) {
                if let before = change.before {
                    row("原来", pointer: before, tint: Theme.Colors.diffDeletedText)
                }
                if let after = change.after {
                    row("现在", pointer: after, tint: Theme.Colors.diffAddedText)
                }
                if let delta {
                    GridRow {
                        Text("大小变化")
                            .font(Theme.Font.secondary)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                        Text(delta)
                            .font(Theme.Font.body)
                    }
                }
            }
            .padding(Theme.Spacing.loose)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.Colors.sunkenBackground, in: .rect(cornerRadius: Theme.Radius.medium))

            Text(
                "内容不在这个仓库里，所以没法按行比较。要看真正的文件，"
                    + "得先让 git-lfs 把它拉下来。"
            )
            .font(Theme.Font.secondary)
            .foregroundStyle(Theme.Colors.tertiaryText)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ label: String, pointer: LFSPointer, tint: Color) -> some View {
        GridRow {
            Text(label)
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.tertiaryText)
            HStack(spacing: Theme.Spacing.regular) {
                Text(pointer.formattedSize)
                    .font(Theme.Font.body)
                    .foregroundStyle(tint)
                Text(pointer.abbreviatedOID)
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .textSelection(.enabled)
            }
        }
    }

    /// 两个版本差了多少字节。只有一边时没有这一行。
    private var delta: String? {
        guard let before = change.before, let after = change.after else { return nil }
        let difference = after.size - before.size
        guard difference != 0 else { return "大小没变，但内容换了" }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let magnitude = formatter.string(fromByteCount: Int64(abs(difference)))
        return difference > 0 ? "大了 \(magnitude)" : "小了 \(magnitude)"
    }
}
