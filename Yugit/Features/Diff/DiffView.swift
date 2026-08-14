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

    /// 长行是否折行显示。
    ///
    /// 存在 AppStorage 而不是 @State：这是个人偏好，不是某个文件的属性，
    /// 每换一个文件都要重设一次会很烦。
    @AppStorage("com.chenya.yugit.diff.wrapLines") private var wrapsLines = false

    /// 这个文件的语言，按路径判定一次。
    private var language: Language { Language.detect(fromPath: diff.path) }

    /// 一个 hunk 里每行「真正变了的那几段」。
    ///
    /// 在 hunk 层算一次而不是每行各算：行内差异是**成对**的，
    /// 一次比较同时得出删除行和新增行两边的范围，逐行算等于把每对都算两遍。
    private func inlineChanges(in hunk: DiffHunk) -> [Int: [Range<Int>]] {
        var result: [Int: [Range<Int>]] = [:]
        for pair in hunk.inlinePairs {
            let comparison = InlineDiff.compare(
                old: hunk.lines[pair.oldIndex].text,
                new: hunk.lines[pair.newIndex].text
            )
            result[pair.oldIndex] = comparison.old
            result[pair.newIndex] = comparison.new
        }
        return result
    }

    /// 行号列宽度，按这个 diff 里最大的行号算。
    ///
    /// 固定宽度在小文件上很浪费：两列各 44pt 就是 88pt，而三位数行号
    /// 只需要一半。diff 面板本来就窄，省下来的都是正文的宽度。
    private var lineNumberWidth: CGFloat {
        let widest = diff.hunks
            .flatMap(\.lines)
            .reduce(0) { current, line in
                max(current, max(line.oldLineNumber ?? 0, line.newLineNumber ?? 0))
            }
        // 等宽数字大约 7pt 一位，最少留两位，两侧各留一点内边距
        let digits = max(String(widest).count, 2)
        return CGFloat(digits) * 7 + 10
    }

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
        // 折行时关掉横向滚动。两个都开着的话，SwiftUI 会认为内容宽度不受限，
        // 折行就永远不会发生——正文一路往右延伸，开关看着像是失灵了。
        ScrollView(wrapsLines ? [.vertical] : [.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(Array(diff.hunks.enumerated()), id: \.offset) { hunkIndex, hunk in
                    let inlineRanges = inlineChanges(in: hunk)
                    Section {
                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { lineIndex, line in
                            DiffLineRow(
                                line: line,
                                isSelected: selection[hunkIndex]?.contains(lineIndex) ?? false,
                                wrapsLines: wrapsLines,
                                lineNumberWidth: lineNumberWidth,
                                language: language,
                                changedRanges: inlineRanges[lineIndex] ?? [],
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
        .background(Theme.Colors.contentBackground)
        .overlay(alignment: .bottomTrailing) { wrapToggle }
    }

    /// 折行开关。
    ///
    /// 放右下角而不是顶部工具条：diff 面板的顶部已经有文件名和暂存按钮，
    /// 再加一条只为一个开关的工具条，会把本就不多的正文高度又挤掉一截。
    /// 右下角是滚动内容天然的空区，也不挡任何一行的行首。
    private var wrapToggle: some View {
        Button {
            wrapsLines.toggle()
        } label: {
            Image(systemName: wrapsLines ? "text.alignleft" : "arrow.left.and.right")
                .font(.system(size: 11))
                .padding(Theme.Spacing.tight + 1)
                .background(.thinMaterial, in: .rect(cornerRadius: Theme.Radius.small))
        }
        .buttonStyle(.borderless)
        .padding(Theme.Spacing.regular)
        .help(wrapsLines ? "改为不折行（长行横向滚动）" : "折行显示长行")
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
    var wrapsLines = false
    var lineNumberWidth: CGFloat = 44
    /// 这个文件是什么语言。由 DiffView 按路径判定一次后传下来——
    /// 每行各判一次的话，一个几千行的 diff 要重复几千次同样的扩展名匹配。
    var language: Language = .plain
    /// 这一行里真正变了的那几段（字符范围）。空数组表示整行都算变化。
    var changedRanges: [Range<Int>] = []
    /// 参数为 true 表示按住 shift 点击（连选）。
    var onTap: ((Bool) -> Void)?

    @State private var isHovering = false

    var body: some View {
        // 折行时行号要顶在第一行文字的基线上，否则一行折成五行后，
        // 行号会飘到这五行的正中间，跟哪一行都对不上。
        HStack(alignment: wrapsLines ? .firstTextBaseline : .center, spacing: 0) {
            lineNumber(line.oldLineNumber)
            lineNumber(line.newLineNumber)

            Text(String(line.kind.prefix))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(markerColor)
                .frame(width: 14)

            Text(styled)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: !wrapsLines, vertical: true)

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

    /// 最终画出来的那一行：语法高亮 + 行内变化底色。
    ///
    /// 两者叠在一起而不是二选一：语法色管"这是什么"，行内底色管"这里改了"，
    /// 是两个正交的维度。只留一个的话，要么看不出改在哪，要么代码读起来费劲。
    private var styled: AttributedString {
        var result = highlighted
        guard !isSelected, !changedRanges.isEmpty else { return result }

        // 行内底色比整行底色更深一档：整行已经是浅红/浅绿，
        // 变化的那几段要在这个背景上再压一层才看得出来。
        let emphasis: Color =
            line.kind == .addition ? Theme.Colors.diffAddedWord : Theme.Colors.diffDeletedWord
        let characters = Array(displayText)

        for range in changedRanges {
            guard range.upperBound <= characters.count else { continue }
            // AttributedString 的索引和 Character 索引不是一回事，
            // 得按字符偏移一步步挪过去，不能拿 Int 直接下标
            guard
                let start = result.index(
                    result.startIndex, offsetByCharacters: range.lowerBound),
                let end = result.index(
                    result.startIndex, offsetByCharacters: range.upperBound)
            else { continue }
            result[start..<end].backgroundColor = emphasis
        }
        return result
    }

    /// 上过语法色的行。
    ///
    /// 选中时不上色：选中背景是强调色，语法色画在上面对比度全乱，
    /// 而此刻用户关心的是"我选了哪些行"，不是这行的语法结构。
    private var highlighted: AttributedString {
        let text = displayText
        guard !isSelected, language != .plain else { return AttributedString(text) }

        let tokens = SyntaxHighlighter.tokenize(text, language: language)
        guard !tokens.isEmpty else { return AttributedString(text) }

        // 按 token 顺序拼：token 之间的空隙原样补上纯文本。
        // 扫描器保证 token 不重叠且递增（有测试锁着），所以这里能一遍走完。
        var result = AttributedString()
        let characters = Array(text)
        var cursor = 0

        for token in tokens {
            if token.range.lowerBound > cursor {
                result += AttributedString(String(characters[cursor..<token.range.lowerBound]))
            }
            var piece = AttributedString(String(characters[token.range]))
            piece.foregroundColor = color(for: token.kind)
            result += piece
            cursor = token.range.upperBound
        }
        if cursor < characters.count {
            result += AttributedString(String(characters[cursor...]))
        }
        return result
    }

    /// 语法配色。
    ///
    /// 全部走系统色而不是自选一套色板：系统色在深浅模式下各有一份，
    /// 也跟随「增强对比度」辅助功能。刻意避开纯红纯绿——
    /// 那两个在 diff 里已经稳定表示增删，再用来标语法会混淆两套含义。
    private func color(for kind: SyntaxToken.Kind) -> Color {
        switch kind {
        case .keyword: Theme.Colors.syntaxKeyword
        case .string: Theme.Colors.syntaxString
        case .comment: Theme.Colors.syntaxComment
        case .number: Theme.Colors.syntaxNumber
        case .type: Theme.Colors.syntaxType
        case .plain: Theme.Colors.primaryText
        }
    }

    @ViewBuilder
    private func lineNumber(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
            // 行号绝不参与压缩：被挤掉一位数字的行号是错的行号，
            // 比不显示还糟——正文可以横向滚动，行号没有退路。
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .frame(width: lineNumberWidth, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var markerColor: Color {
        switch line.kind {
        case .addition: Theme.Colors.diffAddedText
        case .deletion: Theme.Colors.diffDeletedText
        case .context: Theme.Colors.secondaryText
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Theme.Colors.accent.opacity(0.22)
        }
        if isHovering && isSelectable {
            return Color.primary.opacity(0.06)
        }
        switch line.kind {
        case .addition: return Theme.Colors.diffAddedLine
        case .deletion: return Theme.Colors.diffDeletedLine
        case .context: return .clear
        }
    }
}

extension AttributedString {

    /// 按**字符**数偏移取索引。
    ///
    /// `AttributedString` 的索引不能拿 Int 直接下标，而 `InlineDiff` 给出的
    /// 是字符偏移。用 `characters` 视图一步步挪：直接用 utf8 偏移的话，
    /// 中文和 emoji 会切到字符中间，轻则乱码重则崩。
    func index(_ from: Index, offsetByCharacters offset: Int) -> Index? {
        guard offset >= 0 else { return nil }
        var index = from
        for _ in 0..<offset {
            guard index < endIndex else { return nil }
            index = characters.index(after: index)
        }
        return index <= endIndex ? index : nil
    }
}
