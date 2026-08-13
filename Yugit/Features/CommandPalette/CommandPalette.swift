import GitKit
import SwiftUI

/// 命令面板里的一条命令。
struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    /// 补充说明，通常讲清这一步会发生什么。
    let subtitle: String?
    /// 等价的 git 命令。教学层的核心：每个操作都让用户看得见底下发生了什么。
    let equivalentCommand: String?
    let systemImage: String
    let isEnabled: Bool
    let run: () -> Void

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        equivalentCommand: String? = nil,
        systemImage: String = "command",
        isEnabled: Bool = true,
        run: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.equivalentCommand = equivalentCommand
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.run = run
    }
}

/// 命令面板。⌘K 唤起，输入即筛选。
///
/// 借鉴 Sublime Merge：它的 Command Palette 会显示每个操作等价的 git 命令，
/// 这既是透明（可审计），也是教学（界面即中文 Git 教材）。
struct CommandPaletteView: View {

    let commands: [PaletteCommand]
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectionIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField("输入命令", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: query) { _, _ in selectionIndex = 0 }
                    .onSubmit(runSelected)
            }
            .padding(12)

            Divider()

            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(height: 200)
            } else {
                ScrollViewReader { proxy in
                    List(Array(filtered.enumerated()), id: \.element.id) { index, command in
                        CommandRow(command: command, isSelected: index == selectionIndex)
                            .id(command.id)
                            .contentShape(.rect)
                            .onTapGesture {
                                selectionIndex = index
                                runSelected()
                            }
                    }
                    .listStyle(.plain)
                    .onChange(of: selectionIndex) { _, index in
                        guard filtered.indices.contains(index) else { return }
                        proxy.scrollTo(filtered[index].id)
                    }
                }
            }
        }
        .frame(width: 560, height: 380)
        // 键盘上下选择：命令面板必须能全键盘操作，鼠标只是补充
        .onKeyPress(.upArrow) {
            selectionIndex = max(0, selectionIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectionIndex = min(filtered.count - 1, selectionIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private var filtered: [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return commands }

        // 子序列匹配：输入 "tj" 也能命中「提交」——不必打全，顺序对上即可
        return commands.filter { command in
            matches(query: trimmed, in: command.title)
                || command.subtitle.map { matches(query: trimmed, in: $0) } ?? false
                || command.equivalentCommand.map { matches(query: trimmed, in: $0) } ?? false
        }
    }

    private func matches(query: String, in text: String) -> Bool {
        let haystack = Array(text.lowercased())
        var index = haystack.startIndex

        for character in query.lowercased() {
            guard let found = haystack[index...].firstIndex(of: character) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }

    private func runSelected() {
        guard filtered.indices.contains(selectionIndex) else { return }
        let command = filtered[selectionIndex]
        guard command.isEnabled else { return }
        onDismiss()
        command.run()
    }
}

struct CommandRow: View {

    let command: PaletteCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.systemImage)
                .foregroundStyle(command.isEnabled ? Color.accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .foregroundStyle(command.isEnabled ? .primary : .secondary)

                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let equivalent = command.equivalentCommand {
                Text(equivalent)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear
        )
    }
}
