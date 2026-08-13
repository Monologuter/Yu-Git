import GitKit
import SwiftUI

/// diff 查看器。
///
/// 目前用 SwiftUI 的 LazyVStack 实现，它对几千行的 diff 足够。
/// 单文件超过 ``DiffView/foldThreshold`` 行时折叠为按需展开——PRD 要求大 diff 不能卡死，
/// 真正的 AppKit 行级虚拟化留到实测撑不住时再换（实现计划 v0.3）。
struct DiffView: View {

    /// 超过这个行数就先折叠，避免一次性铺开十万行。
    static let foldThreshold = 2000

    let diff: FileDiff
    let isStaged: Bool
    let onStageHunk: (Int) -> Void
    let onUnstageHunk: (Int) -> Void
    /// 暂存/取消暂存选中的行，键是 hunk 下标，值是该 hunk 内的行下标。
    let onApplyLines: ([Int: Set<Int>]) -> Void

    @State private var expandedLargeDiff = false
    @State private var selection: [Int: Set<Int>] = [:]
    /// shift 连选的锚点。
    @State private var anchor: (hunk: Int, line: Int)?

    var body: some View {
        if diff.isBinary {
            ContentUnavailableView(
                "二进制文件",
                systemImage: "doc.badge.ellipsis",
                description: Text("二进制内容无法按行比较，只能整个文件暂存")
            )
        } else if diff.hunks.isEmpty {
            ContentUnavailableView(
                "没有内容变化",
                systemImage: "equal.circle",
                description: Text(modeChangeDescription ?? "文件内容与对比基准一致")
            )
        } else if totalLineCount > Self.foldThreshold && !expandedLargeDiff {
            largeDiffPrompt
        } else {
            VStack(spacing: 0) {
                if selectedLineCount > 0 {
                    SelectionBar(
                        count: selectedLineCount,
                        isStaged: isStaged,
                        onApply: {
                            onApplyLines(selection)
                            clearSelection()
                        },
                        onClear: clearSelection
                    )
                    Divider()
                }
                lineList
            }
            // 换个文件后旧的选择没有意义
            .onChange(of: diff.path) { _, _ in clearSelection() }
        }
    }

    private var lineList: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(Array(diff.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                    Section {
                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { lineIndex, line in
                            DiffLineRow(
                                line: line,
                                isSelected: selection[hunkIndex]?.contains(lineIndex) ?? false,
                                onTap: { extendsSelection in
                                    toggle(hunk: hunkIndex, line: lineIndex, extending: extendsSelection)
                                }
                            )
                        }
                    } header: {
                        HunkHeaderRow(
                            hunk: hunk,
                            isStaged: isStaged,
                            onStage: { onStageHunk(hunkIndex) },
                            onUnstage: { onUnstageHunk(hunkIndex) }
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - 选择

    private var selectedLineCount: Int {
        selection.values.reduce(0) { $0 + $1.count }
    }

    private func clearSelection() {
        selection = [:]
        anchor = nil
    }

    /// - Parameter extending: 按住 shift 时从锚点连选到当前行。
    private func toggle(hunk hunkIndex: Int, line lineIndex: Int, extending: Bool) {
        // 上下文行不参与选择：它在两边都存在，谈不上暂存与否
        guard diff.hunks[hunkIndex].lines[lineIndex].kind != .context else { return }

        if extending, let anchor, anchor.hunk == hunkIndex {
            let range = min(anchor.line, lineIndex)...max(anchor.line, lineIndex)
            let selectable = range.filter { diff.hunks[hunkIndex].lines[$0].kind != .context }
            selection[hunkIndex, default: []].formUnion(selectable)
            return
        }

        var lines = selection[hunkIndex] ?? []
        if lines.contains(lineIndex) {
            lines.remove(lineIndex)
        } else {
            lines.insert(lineIndex)
        }
        selection[hunkIndex] = lines.isEmpty ? nil : lines
        anchor = (hunkIndex, lineIndex)
    }

    // MARK: - 其他

    private var totalLineCount: Int {
        diff.hunks.reduce(0) { $0 + $1.lines.count }
    }

    private var modeChangeDescription: String? {
        guard case .modeChanged = diff.change, let old = diff.oldMode, let new = diff.newMode else {
            return nil
        }
        return "文件模式从 \(old) 变为 \(new)"
    }

    private var largeDiffPrompt: some View {
        ContentUnavailableView {
            Label("这个 diff 很大", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("共 \(totalLineCount) 行变化，展开可能需要一点时间")
        } actions: {
            Button("仍然展开") { expandedLargeDiff = true }
        }
    }
}

/// 有行被选中时出现的操作条。
struct SelectionBar: View {

    let count: Int
    let isStaged: Bool
    let onApply: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("已选 \(count) 行")
                .font(.callout)

            Spacer(minLength: 8)

            Button("清除选择", action: onClear)
                .buttonStyle(.borderless)

            Button(isStaged ? "取消暂存选中的行" : "暂存选中的行", action: onApply)
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.thinMaterial)
    }
}

/// hunk 的头部，兼作暂存该块的入口。
struct HunkHeaderRow: View {

    let hunk: DiffHunk
    let isStaged: Bool
    let onStage: () -> Void
    let onUnstage: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(hunk.header)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            // 悬停才显示，避免密集的按钮干扰阅读
            if isHovering {
                Button(isStaged ? "取消暂存此块" : "暂存此块") {
                    isStaged ? onUnstage() : onStage()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .underPageBackgroundColor))
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }
}

/// diff 中的一行：行号 + 标记 + 内容。
struct DiffLineRow: View {

    let line: DiffLine
    var isSelected = false
    /// 参数为 true 表示按住 shift 点击（连选）。
    var onTap: ((Bool) -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            lineNumber(line.oldLineNumber)
            lineNumber(line.newLineNumber)

            Text(String(line.kind.prefix))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(markerColor)
                .frame(width: 14)

            Text(displayText)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: false)

            if line.isMissingNewline {
                Text("↵ 无换行结尾")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(Color.accentColor).frame(width: 3)
            }
        }
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onTapGesture {
            onTap?(NSEvent.modifierFlags.contains(.shift))
        }
        .help(isSelectable ? "点击选中此行，按住 Shift 可连选" : "")
    }

    private var isSelectable: Bool {
        line.kind != .context && onTap != nil
    }

    /// 行尾的 \r 在等宽字体里不可见，但它是 CRLF 文件的真实内容，显式标出来。
    private var displayText: String {
        line.text.hasSuffix("\r") ? String(line.text.dropLast()) + "␍" : line.text
    }

    @ViewBuilder
    private func lineNumber(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var markerColor: Color {
        switch line.kind {
        case .addition: .green
        case .deletion: .red
        case .context: .secondary
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.22)
        }
        if isHovering && isSelectable {
            return Color.primary.opacity(0.06)
        }
        switch line.kind {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        case .context: return .clear
        }
    }
}
