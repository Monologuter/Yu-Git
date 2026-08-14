import SwiftUI

/// 外观设置：选主题。
struct AppearanceSettingsView: View {

    @State private var manager = ThemeManager.shared

    var body: some View {
        Form {
            Section("主题") {
                ForEach(manager.available, id: \.identifier) { theme in
                    ThemeRow(
                        theme: theme,
                        isSelected: manager.palette.identifier == theme.identifier
                    ) {
                        manager.select(theme)
                    }
                }
            }

            Section {
                Label(
                    "深色模式跟随系统设置，不在这里切换——每套主题都自带深浅两版。",
                    systemImage: "circle.lefthalf.filled"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
    }
}

/// 一套主题的选项行，带实时预览。
private struct ThemeRow: View {

    let theme: any ThemePalette
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.loose) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(theme.displayName)
                Text(theme.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Theme.Spacing.regular)

            LanePreview(theme: theme)
        }
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
    }
}

/// 分支图色板的缩略预览。
///
/// 预览这个而不是随便画几个色块：分支图是这个产品里颜色最密集、
/// 也最能看出一套配色好坏的地方。八条线并排一放，明度不齐、
/// 相邻色相太近这类问题一眼就能看出来——而那正是选主题时真正要判断的。
private struct LanePreview: View {

    let theme: any ThemePalette

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(theme.lanes.enumerated()), id: \.offset) { _, lane in
                Capsule()
                    .fill(Color(nsColor: lane))
                    .frame(width: theme.laneLineWidth, height: 22)
            }
        }
        .padding(.horizontal, Theme.Spacing.tight)
        .padding(.vertical, Theme.Spacing.tight)
        .background(theme.contentBackground, in: .rect(cornerRadius: Theme.Radius.small))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.small)
                .strokeBorder(theme.separator, lineWidth: 1)
        }
    }
}
