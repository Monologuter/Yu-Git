import Foundation

/// 把一个 hunk 切成若干段互不相干的改动。
///
/// 为什么需要它：hunk 是 **git 排版出来的单位，不是语义单位**。默认 `-U3` 之下，
/// 两处间隔不到七行的改动会被并进同一个 hunk——哪怕一处在改错误处理、另一处在改
/// 变量名。以 hunk 为最小粒度分组，这两件事就永远只能进同一个提交。
///
/// 切分规则照抄 git 自己：`git add -p` 的 `s` 命令**在任意一段上下文行处断开**，
/// 断点两侧各自保留完整的上下文。实测（间隔 1 行与间隔 4 行两种情形）本实现
/// 生成的 `@@` 头与 git 的输出逐字一致，`HunkSplitterTests` 把这一点锁死了。
public enum HunkSplitter {

    /// hunk 里的一段独立改动。
    public struct Slice: Sendable, Equatable, Identifiable {

        /// 所属 hunk 在 ``FileDiff/hunks`` 里的下标。
        public let hunkIndex: Int
        /// 这一段在 ``DiffHunk/lines`` 里占的下标区间，含两侧上下文。
        ///
        /// 相邻两段会共用中间那几行上下文——git 的 `s` 就是这么给的，
        /// 两半都要拿到完整上下文才各自定位得了。
        public let range: Range<Int>
        /// 这一段里**改动行**的下标，直接喂给 ``PatchBuilder/Selection/lines(_:)``。
        public let changedLineIndices: Set<Int>

        public let addedLines: Int
        public let deletedLines: Int
        /// 原 hunk 的 `@@` 提示文字，通常是所属函数名。
        public let heading: String

        /// 可读的 diff 片段，含重新算过的 `@@` 头。
        ///
        /// - Important: 这是**给人和模型看的**。真要暂存或提交，走 ``PatchBuilder``——
        ///   它算的行号是为了让 `git apply` 认，与这里如实反映位置的算法并不相同。
        public let text: String

        /// 在一份 diff 里唯一：同一个 hunk 里的两段起点必然不同。
        public var id: String { "\(hunkIndex).\(range.lowerBound)" }
    }

    /// 切一个 hunk。改动行连成一片时原样返回一段。
    public static func split(_ hunk: DiffHunk, at hunkIndex: Int) -> [Slice] {
        let runs = changeRuns(in: hunk.lines)
        guard !runs.isEmpty else { return [] }

        return runs.enumerated().map { index, run in
            // 每段吃下与前后两段之间的**全部**上下文。间隔超过 6 行的改动
            // git 本来就会切成两个 hunk，所以这里的间隔至多 6 行，全给不会失控。
            let lower = index == 0 ? 0 : runs[index - 1].upperBound
            let upper = index == runs.count - 1 ? hunk.lines.count : runs[index + 1].lowerBound
            let range = lower..<upper

            return Slice(
                hunkIndex: hunkIndex,
                range: range,
                changedLineIndices: Set(run),
                addedLines: hunk.lines[run].count { $0.kind == .addition },
                deletedLines: hunk.lines[run].count { $0.kind == .deletion },
                heading: hunk.heading,
                text: render(hunk, range: range)
            )
        }
    }

    /// 切整份文件 diff。
    public static func slices(of diff: FileDiff) -> [Slice] {
        diff.hunks.enumerated().flatMap { split($1, at: $0) }
    }

    // MARK: - 内部

    /// 找出所有极大的「连续改动行」区间。上下文行即断点。
    private static func changeRuns(in lines: [DiffLine]) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?

        for (index, line) in lines.enumerated() {
            if line.kind == .context {
                if let begin = start {
                    runs.append(begin..<index)
                    start = nil
                }
            } else if start == nil {
                start = index
            }
        }
        if let begin = start {
            runs.append(begin..<lines.count)
        }
        return runs
    }

    /// 渲染一段，`@@` 头按这一段在文件里的真实位置重新算。
    ///
    /// 起点不读 ``DiffLine/oldLineNumber``，而是从 hunk 头往下数——纯新增的段里
    /// 一行旧行号都没有，读不出来；从头数则任何形状都算得出。
    private static func render(_ hunk: DiffHunk, range: Range<Int>) -> String {
        let before = hunk.lines[0..<range.lowerBound]
        let window = hunk.lines[range]

        let oldStart = hunk.oldStart + before.count { $0.kind != .addition }
        let newStart = hunk.newStart + before.count { $0.kind != .deletion }

        let header = DiffHunk(
            oldStart: oldStart,
            oldCount: window.count { $0.kind != .addition },
            newStart: newStart,
            newCount: window.count { $0.kind != .deletion },
            heading: hunk.heading,
            lines: []
        ).header

        let body = window.map { "\($0.kind.prefix)\($0.text)" }
        return ([header] + body).joined(separator: "\n")
    }
}
