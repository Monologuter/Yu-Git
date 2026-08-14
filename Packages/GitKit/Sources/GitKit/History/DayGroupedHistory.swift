import Foundation

/// 把按时间倒序的提交列表切成「日期分组 + 提交」两种行。
///
/// 放在这里而不是留在视图层，是因为它全部是下标算术：某条提交排在表格第几行、
/// 第几行对应哪条提交。算错了不会崩，只会**静默选中另一条提交**——
/// 那种 bug 靠肉眼看界面发现不了，只有测试能锁住。
///
/// - Important: 输入必须按时间倒序（`git log` 的默认顺序）。乱序的输入不会报错，
///   但同一天会被切成好几段。
public struct DayGroupedHistory: Sendable {

    /// 列表里的一行。
    public enum Row: Sendable, Equatable {
        /// 日期分组行。带的是 ``blocks`` 的下标而不是日期本身——
        /// 同一天的提交数会随增量加载不断变大，存下标才不用回头改已经生成的行。
        case dayGroup(blockIndex: Int)
        case commit(index: Int)
    }

    /// 同一天的一段提交。
    public struct Block: Sendable, Equatable {
        /// 这一天里最新那条提交的时间，用来生成显示用的日期。
        public let date: Date
        /// 这一天的第一条提交在输入数组里的下标。
        public let firstCommitIndex: Int
        public internal(set) var count: Int
    }

    public private(set) var rows: [Row] = []
    public private(set) var blocks: [Block] = []

    /// 已经分过组的提交数。
    private var groupedCount = 0
    /// 用来识别「整批换了」而不是「又追加了一页」。
    private var firstCommitHash: String?

    public init() {}

    /// 用最新的提交列表更新分组。
    ///
    /// **增量。** 历史是一页一页追加进来的，每次只处理新到的那一段。
    /// 全量重算的话，每加载一页都要把已有的提交重新过一遍 `Calendar`，
    /// 而分页加载会发生几十上百次——总开销 O(N²/页大小)，
    /// 5 万条下累计好几秒，且全部花在滚动到底的那一刻。
    ///
    /// - Returns: 行有没有变。调用方拿它决定要不要重绘。
    @discardableResult
    public mutating func update(with commits: [Commit], calendar: Calendar = .current) -> Bool {
        // 换分支、改筛选条件时是整批换掉，之前算的全部作废。
        // 只看数量会漏：新旧两批恰好一样长时，增量接上去的日期是错的。
        let restarted = commits.count < groupedCount || commits.first?.hash != firstCommitHash
        if restarted {
            rows.removeAll(keepingCapacity: true)
            blocks.removeAll(keepingCapacity: true)
            groupedCount = 0
            firstCommitHash = commits.first?.hash
        }

        guard groupedCount < commits.count else { return restarted }
        rows.reserveCapacity(commits.count + commits.count / 8)

        for index in groupedCount..<commits.count {
            let date = commits[index].author.date

            if let last = blocks.last, calendar.isDate(last.date, inSameDayAs: date) {
                blocks[blocks.count - 1].count += 1
            } else {
                rows.append(.dayGroup(blockIndex: blocks.count))
                blocks.append(Block(date: date, firstCommitIndex: index, count: 1))
            }
            rows.append(.commit(index: index))
        }

        groupedCount = commits.count
        return true
    }

    /// 第 `row` 行对应哪条提交。分组行返回 nil。
    public func commitIndex(atRow row: Int) -> Int? {
        guard rows.indices.contains(row), case .commit(let index) = rows[row] else { return nil }
        return index
    }

    /// 第 `index` 条提交排在第几行。
    ///
    /// 不是「下标加分组行总数」——得知道它**前面**插了几条分组行。
    /// 二分找它所属的那一段，比每次线性扫一遍便宜；这个函数在每次
    /// 同步选中态时都会调一次。
    public func row(forCommitIndex index: Int) -> Int? {
        guard index >= 0, !blocks.isEmpty else { return nil }

        var low = 0
        var high = blocks.count - 1
        var found = 0
        while low <= high {
            let middle = (low + high) / 2
            if blocks[middle].firstCommitIndex <= index {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }

        let block = blocks[found]
        guard index >= block.firstCommitIndex, index < block.firstCommitIndex + block.count else {
            return nil
        }
        // 前面有 found + 1 条分组行（自己这一段的那条也在前面）
        return index + found + 1
    }
}
