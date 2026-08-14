import Foundation
import Testing

@testable import GitKit

@Suite("历史按天分组")
struct DayGroupedHistoryTests {

    /// 固定时区，否则同一个时间戳在不同机器上会落到不同的日子，
    /// 测试就成了「看谁在哪个时区跑」。
    ///
    /// 用 UTC 而不是某个具体城市：那些时区带夏令时，跨越切换点的那一天
    /// 只有 23 小时，会让「跨午夜」这类断言在一年里的某两天莫名其妙地失败。
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// 造一条提交。`day` 是从 2026-01-01 起的第几天，`hour` 是当天的钟点。
    private func commit(_ hash: String, day: Int, hour: Int = 12) -> Commit {
        // 2026-01-01 00:00:00 UTC
        let base = 1_767_225_600.0
        let date = Date(timeIntervalSince1970: base + Double(day) * 86400 + Double(hour) * 3600)
        let signature = Signature(name: "测试", email: "t@yugit.local", date: date)
        return Commit(
            hash: hash,
            abbreviatedHash: String(hash.prefix(7)),
            parents: [],
            author: signature,
            committer: signature,
            subject: "提交 \(hash)",
            body: "",
            refs: []
        )
    }

    @Test("同一天的提交合成一段，只插一条分组行")
    func groupsSameDayIntoOneBlock() {
        var history = DayGroupedHistory()
        history.update(
            with: [
                commit("c", day: 0, hour: 18),
                commit("b", day: 0, hour: 12),
                commit("a", day: 0, hour: 9),
            ],
            calendar: calendar
        )

        #expect(history.blocks.count == 1)
        #expect(history.blocks[0].count == 3)
        #expect(history.rows.count == 4)
        #expect(history.rows[0] == .dayGroup(blockIndex: 0))
    }

    @Test("跨天就断开，每天各一条分组行")
    func startsNewBlockOnNewDay() {
        var history = DayGroupedHistory()
        history.update(
            with: [
                commit("c", day: 2),
                commit("b", day: 1),
                commit("a", day: 1),
            ],
            calendar: calendar
        )

        #expect(history.blocks.count == 2)
        #expect(history.blocks[0].count == 1)
        #expect(history.blocks[1].count == 2)
        #expect(history.rows.count == 5)
    }

    @Test("同一天跨越午夜前后仍算两天")
    func splitsAcrossMidnight() {
        var history = DayGroupedHistory()
        history.update(
            with: [
                commit("b", day: 1, hour: 0),
                commit("a", day: 0, hour: 23),
            ],
            calendar: calendar
        )

        #expect(history.blocks.count == 2)
    }

    // MARK: - 下标换算

    /// 这几条是这个类型存在的理由：算错不会崩，只会选中另一条提交。
    @Test("行号与提交下标能互相换算")
    func mapsBetweenRowsAndCommitIndices() {
        var history = DayGroupedHistory()
        history.update(
            with: [
                commit("e", day: 2),
                commit("d", day: 1),
                commit("c", day: 1),
                commit("b", day: 0),
                commit("a", day: 0),
            ],
            calendar: calendar
        )

        // 行： 0=组 1=e 2=组 3=d 4=c 5=组 6=b 7=a
        #expect(history.rows.count == 8)
        for index in 0..<5 {
            let row = try! #require(history.row(forCommitIndex: index))
            #expect(history.commitIndex(atRow: row) == index)
        }
        #expect(history.row(forCommitIndex: 0) == 1)
        #expect(history.row(forCommitIndex: 2) == 4)
        #expect(history.row(forCommitIndex: 4) == 7)
    }

    @Test("分组行不对应任何提交")
    func groupRowsHaveNoCommit() {
        var history = DayGroupedHistory()
        history.update(with: [commit("b", day: 1), commit("a", day: 0)], calendar: calendar)

        #expect(history.commitIndex(atRow: 0) == nil)
        #expect(history.commitIndex(atRow: 2) == nil)
        #expect(history.commitIndex(atRow: 1) == 0)
    }

    @Test("越界的行号与下标返回 nil 而不是崩")
    func rejectsOutOfRange() {
        var history = DayGroupedHistory()
        history.update(with: [commit("a", day: 0)], calendar: calendar)

        #expect(history.commitIndex(atRow: -1) == nil)
        #expect(history.commitIndex(atRow: 99) == nil)
        #expect(history.row(forCommitIndex: -1) == nil)
        #expect(history.row(forCommitIndex: 99) == nil)
    }

    @Test("空历史什么都不产出")
    func handlesEmptyHistory() {
        var history = DayGroupedHistory()
        #expect(history.update(with: [], calendar: calendar) == false)
        #expect(history.rows.isEmpty)
        #expect(history.blocks.isEmpty)
    }

    // MARK: - 增量

    @Test("追加一页时，落在同一天的接进上一段")
    func extendsLastBlockOnAppend() {
        var history = DayGroupedHistory()
        let first = [commit("c", day: 1), commit("b", day: 0, hour: 18)]
        history.update(with: first, calendar: calendar)
        #expect(history.blocks.count == 2)

        // 新来的 a 和 b 同一天，不该多开一段
        history.update(with: first + [commit("a", day: 0, hour: 9)], calendar: calendar)

        #expect(history.blocks.count == 2)
        #expect(history.blocks[1].count == 2)
        #expect(history.rows.count == 5)
        #expect(history.row(forCommitIndex: 2) == 4)
    }

    @Test("追加没有新内容时返回 false，避免无谓重绘")
    func reportsNoChangeWhenNothingAppended() {
        var history = DayGroupedHistory()
        let commits = [commit("b", day: 1), commit("a", day: 0)]

        #expect(history.update(with: commits, calendar: calendar) == true)
        #expect(history.update(with: commits, calendar: calendar) == false)
    }

    /// 换分支时提交被整批换掉。只比数量的话这一条会漏——
    /// 新旧两批一样长，增量会把新提交按旧的分段接上去。
    @Test("整批换掉时重头分组，哪怕条数没变")
    func restartsWhenCommitsAreReplaced() {
        var history = DayGroupedHistory()
        history.update(
            with: [commit("b", day: 0), commit("a", day: 0)],
            calendar: calendar
        )
        #expect(history.blocks.count == 1)

        let changed = history.update(
            with: [commit("y", day: 5), commit("x", day: 4)],
            calendar: calendar
        )

        #expect(changed == true)
        #expect(history.blocks.count == 2)
        #expect(history.rows.count == 4)
    }

    @Test("列表变短时也重头分组")
    func restartsWhenHistoryShrinks() {
        var history = DayGroupedHistory()
        history.update(
            with: [commit("c", day: 2), commit("b", day: 1), commit("a", day: 0)],
            calendar: calendar
        )

        #expect(history.update(with: [commit("c", day: 2)], calendar: calendar) == true)
        #expect(history.blocks.count == 1)
        #expect(history.rows.count == 2)
    }

    /// 分段数增长时，二分查找的每一步都要还能对上。
    @Test("上千段时下标换算仍然正确")
    func mapsCorrectlyAcrossManyBlocks() {
        var history = DayGroupedHistory()
        let commits = (0..<1000).map { commit("h\($0)", day: 1000 - $0) }
        history.update(with: commits, calendar: calendar)

        #expect(history.blocks.count == 1000)
        for index in stride(from: 0, to: 1000, by: 37) {
            let row = try! #require(history.row(forCommitIndex: index))
            #expect(history.commitIndex(atRow: row) == index)
        }
    }
}
