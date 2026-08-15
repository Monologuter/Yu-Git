import Foundation

/// 把选中的改动还原成可 `git apply` 的 patch。
///
/// 与 ``DiffParser`` 同构：解析出来的结构必须能原样还原回去。这条关系用往返测试
/// 锁死，因为它直接决定 hunk / 行级暂存会不会损坏用户的文件（工程规范 §6 铁律 3）。
public enum PatchBuilder {

    /// 选择哪些行进入 patch。
    public enum Selection: Sendable, Equatable {
        /// 整个文件的全部改动。
        case whole
        /// 指定下标的 hunk（对应 ``FileDiff/hunks`` 的下标）。
        case hunks(Set<Int>)
        /// 精确到行：键是 hunk 下标，值是该 hunk 内选中的行下标。
        case lines([Int: Set<Int>])

        /// 明确什么都没选。`.whole` 永远不算空——文件本身有没有改动是另一回事。
        public var isEmpty: Bool {
            switch self {
            case .whole: false
            case let .hunks(indices): indices.isEmpty
            case let .lines(map): map.values.allSatisfy(\.isEmpty)
            }
        }
    }

    /// patch 的应用方向。
    public enum Direction: Sendable {
        /// 把工作区的改动加进 index（暂存）。
        case stage
        /// 把 index 里的改动撤回工作区（取消暂存），生成的 patch 需配合 `--reverse`。
        case unstage
    }

    /// 生成 patch 文本。返回 nil 表示没有任何改动被选中。
    ///
    /// - Parameter alreadyApplied: 已经落进文件里的改动行（键是 hunk 下标）。
    ///   分批提交时，同一个 hunk 里前几批选走的行**此刻已经在文件里了**，
    ///   而这份 patch 是照着最初的 HEAD 算的——不告诉它，patch 里的上下文
    ///   还是旧内容，`git apply` 直接拒绝（实测报 `patch does not apply`）。
    /// - Note: 二进制文件无法做部分暂存，调用方应改用整文件 `git add`。
    public static func patch(
        for diff: FileDiff,
        selecting selection: Selection = .whole,
        direction: Direction = .stage,
        alreadyApplied: [Int: Set<Int>] = [:]
    ) -> String? {
        guard !diff.isBinary else { return nil }

        var patchHunks: [String] = []
        // 已选改动带来的行号偏移，累加到后续 hunk 的新起点上。
        // 只暂存了部分 hunk 时，后面 hunk 在新文件里的位置会随之前移或后移。
        var lineOffset = 0

        for (hunkIndex, hunk) in diff.hunks.enumerated() {
            let selectedLines = selectedLineIndices(in: hunk, at: hunkIndex, selection: selection)
            guard !selectedLines.isEmpty else { continue }

            guard
                let rendered = renderHunk(
                    hunk,
                    selectedLines: selectedLines,
                    appliedLines: alreadyApplied[hunkIndex] ?? [],
                    lineOffset: lineOffset,
                    direction: direction
                )
            else { continue }

            patchHunks.append(rendered.text)
            lineOffset += rendered.netLineChange
        }

        guard !patchHunks.isEmpty else { return nil }

        let header = diff.header.isEmpty ? fallbackHeader(for: diff) : diff.header
        return header + "\n" + patchHunks.joined(separator: "\n") + "\n"
    }

    // MARK: - 选择

    /// 这份选择实际会动到哪些行，按 hunk 下标归类。
    ///
    /// 分批提交靠它记账：把 `.whole` / `.hunks` 这类粗粒度的选择摊平成具体行号，
    /// 后面几批才能算出「基准文件已经被改成什么样」。
    public static func selectedLines(
        of diff: FileDiff,
        selecting selection: Selection
    ) -> [Int: Set<Int>] {
        var map: [Int: Set<Int>] = [:]
        for (hunkIndex, hunk) in diff.hunks.enumerated() {
            let lines = selectedLineIndices(in: hunk, at: hunkIndex, selection: selection)
            if !lines.isEmpty { map[hunkIndex] = lines }
        }
        return map
    }

    private static func selectedLineIndices(
        in hunk: DiffHunk,
        at hunkIndex: Int,
        selection: Selection
    ) -> Set<Int> {
        // 上下文行永远要进 patch，它们是 git 定位的锚点
        let changedIndices = hunk.lines.indices.filter { hunk.lines[$0].kind != .context }

        switch selection {
        case .whole:
            return Set(changedIndices)
        case let .hunks(indices):
            return indices.contains(hunkIndex) ? Set(changedIndices) : []
        case let .lines(map):
            return map[hunkIndex].map { Set($0).intersection(changedIndices) } ?? []
        }
    }

    // MARK: - 渲染

    /// 一行相对这次 patch 的处境。
    private enum LineState {
        /// 这次要应用它。
        case selected
        /// 前几批已经应用过，基准文件里已是改动后的样子。
        case applied
        /// 谁都没动过。
        case untouched
    }

    private static func renderHunk(
        _ hunk: DiffHunk,
        selectedLines: Set<Int>,
        appliedLines: Set<Int>,
        lineOffset: Int,
        direction: Direction
    ) -> (text: String, netLineChange: Int)? {
        var body: [String] = []
        var oldCount = 0
        var newCount = 0

        // 三种状态，一条判断链：选中的照原样写；已经应用过的按「文件里现在是什么样」
        // 写；剩下的按「文件里原来是什么样」写。中间那一档正是分批提交时前几批
        // 留下的痕迹——它们已经不在待应用的改动里，却实实在在改变了基准文件。
        for (lineIndex, line) in hunk.lines.enumerated() {
            let state: LineState =
                selectedLines.contains(lineIndex)
                ? .selected : (appliedLines.contains(lineIndex) ? .applied : .untouched)

            switch (line.kind, state) {
            case (.context, _):
                body.append(render(line, as: .context))
                oldCount += 1
                newCount += 1

            case (.addition, .selected):
                body.append(render(line, as: .addition))
                newCount += 1

            case (.addition, .applied):
                // 前几批已经把它加进去了，现在是文件里实打实的一行，
                // 必须作为上下文出现，否则后面的行对不上位置。
                body.append(render(line, as: .context))
                oldCount += 1
                newCount += 1

            case (.addition, .untouched):
                // 它在旧文件里不存在，这次也不打算加进去，完全不进 patch。
                break

            case (.deletion, .selected):
                body.append(render(line, as: .deletion))
                oldCount += 1

            case (.deletion, .applied):
                // 前几批已经删掉了，文件里根本没有这一行，写进去反而对不上。
                break

            case (.deletion, .untouched):
                // 这一行在旧文件里存在且要保留，于是降级成上下文行——
                // 漏掉这一步，git apply 会把它一并删掉。
                body.append(render(line, as: .context))
                oldCount += 1
                newCount += 1
            }
        }

        // 全是上下文说明这个 hunk 没有实际改动被选中
        guard body.contains(where: { $0.hasPrefix("+") || $0.hasPrefix("-") }) else { return nil }

        let newStart: Int
        switch direction {
        case .stage:
            newStart = hunk.oldStart + lineOffset
        case .unstage:
            // 反向应用时基准是 index 里的内容，新起点直接沿用原值
            newStart = hunk.newStart
        }

        let rebuilt = DiffHunk(
            oldStart: hunk.oldStart,
            oldCount: oldCount,
            newStart: max(newStart, oldCount == 0 ? 0 : 1),
            newCount: newCount,
            heading: hunk.heading,
            lines: []
        )

        return (rebuilt.header + "\n" + body.joined(separator: "\n"), newCount - oldCount)
    }

    private static func render(_ line: DiffLine, as kind: DiffLine.Kind) -> String {
        var rendered = String(kind.prefix) + line.text
        if line.isMissingNewline {
            // 这个标记必须跟着走：漏掉它，git apply 会给文件补上一个本不存在的换行
            rendered += "\n\\ No newline at end of file"
        }
        return rendered
    }

    /// 只在没有原始 header 时使用（例如测试里手工构造的 diff）。
    ///
    /// 路径含空格或引号时 git 会用 C 风格引用，这里的简化拼接覆盖不了那些情况，
    /// 所以正常路径下一律优先用 git 给的原文。
    private static func fallbackHeader(for diff: FileDiff) -> String {
        let old: String
        let new: String
        switch diff.change {
        case .added:
            old = "/dev/null"
            new = "b/\(diff.path)"
        case .deleted:
            old = "a/\(diff.path)"
            new = "/dev/null"
        default:
            old = "a/\(diff.path)"
            new = "b/\(diff.path)"
        }
        return """
            diff --git a/\(diff.path) b/\(diff.path)
            --- \(old)
            +++ \(new)
            """
    }
}
