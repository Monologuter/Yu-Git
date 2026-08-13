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

    @State private var expandedLargeDiff = false

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
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(Array(diff.hunks.enumerated()), id: \.offset) { index, hunk in
                        Section {
                            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                DiffLineRow(line: line)
                            }
                        } header: {
                            HunkHeaderRow(
                                hunk: hunk,
                                isStaged: isStaged,
                                onStage: { onStageHunk(index) },
                                onUnstage: { onUnstageHunk(index) }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

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
        switch line.kind {
        case .addition: Color.green.opacity(0.12)
        case .deletion: Color.red.opacity(0.12)
        case .context: .clear
        }
    }
}
