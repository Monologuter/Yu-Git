import Foundation

/// `git log` 自定义格式输出的解析器。
///
/// 分隔符选用 ASCII 控制字符而非常见的 `|`、`\t`：commit message 里出现制表符、
/// 竖线甚至换行都很正常，但不会出现 0x1F / 0x1E——这两个字符正是为「分隔字段/记录」
/// 而定义的（Unit Separator / Record Separator）。
public enum LogParser {

    /// 字段分隔符（Unit Separator）。
    static let fieldSeparator: UInt8 = 0x1F
    /// 记录分隔符（Record Separator）。
    static let recordSeparator: UInt8 = 0x1E

    /// 传给 `git log --format=` 的格式串。
    ///
    /// 字段顺序必须与 ``parse(_:)`` 中的下标一一对应，改动时要同步。
    /// `%D` 配合 `--decorate=full` 输出完整 ref 路径（`refs/heads/main`），
    /// 短名形式（`main`）无法区分本地分支与同名 tag。
    public static let format =
        [
            "%H",  // 0 完整 hash
            "%h",  // 1 缩写 hash
            "%P",  // 2 父提交，空格分隔
            "%an",  // 3 author 名
            "%ae",  // 4 author 邮箱
            "%aI",  // 5 author 时间，严格 ISO 8601
            "%cn",  // 6 committer 名
            "%ce",  // 7 committer 邮箱
            "%cI",  // 8 committer 时间
            "%D",  // 9 ref 装饰
            "%s",  // 10 subject
            "%b",  // 11 body
        ].joined(separator: "%x1f") + "%x1e"

    public static func parse(_ data: Data) throws -> [Commit] {
        try data
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap { try parseRecord($0) }
    }

    private static func parseRecord(_ record: Data) throws -> Commit? {
        let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }

        // git 在每条记录后补一个换行，它会落在下一条记录的开头。
        guard let hash = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines),
            !hash.isEmpty
        else {
            return nil
        }

        guard fields.count >= 12 else {
            throw GitError.parseFailure(
                reason: "commit 记录应有 12 个字段，实得 \(fields.count)",
                context: String(fields.first ?? "")
            )
        }

        return Commit(
            hash: hash,
            abbreviatedHash: fields[1],
            // 根提交的父列表为空字符串，split 后要滤掉空片段
            parents: fields[2].split(separator: " ").map(String.init),
            author: try signature(name: fields[3], email: fields[4], date: fields[5]),
            committer: try signature(name: fields[6], email: fields[7], date: fields[8]),
            subject: fields[10],
            body: fields[11].trimmingCharacters(in: .whitespacesAndNewlines),
            refs: parseRefs(fields[9])
        )
    }

    private static func signature(name: String, email: String, date: String) throws -> Signature {
        guard let parsed = parseTimestamp(date) else {
            throw GitError.parseFailure(reason: "无法解析时间戳", context: date)
        }
        return Signature(name: name, email: email, date: parsed)
    }

    /// 解析 `%D` 的装饰串，形如
    /// `HEAD -> refs/heads/main, refs/remotes/origin/main, refs/tags/v0.1.0`。
    private static func parseRefs(_ decoration: String) -> [CommitRef] {
        let trimmed = decoration.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var refs: [CommitRef] = []
        for piece in trimmed.split(separator: ",") {
            var name = piece.trimmingCharacters(in: .whitespaces)

            // `HEAD -> refs/heads/main` 表示 HEAD 跟着这个分支走，
            // 拆成 HEAD 与分支两条引用，界面才能分别标注。
            if let arrow = name.range(of: " -> ") {
                refs.append(.head)
                name = String(name[arrow.upperBound...])
            }

            refs.append(classify(name))
        }
        return refs
    }

    private static func classify(_ decoratedName: String) -> CommitRef {
        // 即便用了 --decorate=full，tag 仍会带一层 "tag: " 前缀：
        // `tag: refs/tags/v0.1.0`。先把它剥掉。
        let fullName = decoratedName.dropPrefix("tag: ") ?? decoratedName

        return if fullName == "HEAD" {
            .head
        } else if let short = fullName.dropPrefix("refs/heads/") {
            .localBranch(short)
        } else if let short = fullName.dropPrefix("refs/remotes/") {
            .remoteBranch(short)
        } else if let short = fullName.dropPrefix("refs/tags/") {
            .tag(short)
        } else {
            .other(fullName)
        }
    }

    /// 解析 `%aI` / `%cI` 输出的严格 ISO 8601 时间戳，形如 `2026-08-13T10:16:06-07:00`。
    ///
    /// 刻意不用 `ISO8601DateFormatter`，有两个原因：
    /// 1. **性能**——5 万 commit 要解析 10 万个时间戳（author + committer 各一个），
    ///    Formatter 的开销会吃掉 PRD 首屏 500ms 预算的一大半。这里是纯整数运算。
    /// 2. **并发**——Formatter 不是 `Sendable`，做不了 static 常量，每次新建又更慢。
    ///
    /// 格式由 git 的 `%aI` 保证固定，所以按字节位置直接取值是安全的。
    static func parseTimestamp(_ text: String) -> Date? {
        // 0123456789...
        // 2026-08-13T10:16:06-07:00
        let bytes = Array(text.utf8)
        guard bytes.count >= 25 else { return nil }

        func number(from start: Int, length: Int) -> Int? {
            var value = 0
            for index in start..<(start + length) {
                let digit = Int(bytes[index]) &- 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }

        guard let year = number(from: 0, length: 4),
            let month = number(from: 5, length: 2),
            let day = number(from: 8, length: 2),
            let hour = number(from: 11, length: 2),
            let minute = number(from: 14, length: 2),
            let second = number(from: 17, length: 2),
            let offsetHour = number(from: 20, length: 2),
            let offsetMinute = number(from: 23, length: 2),
            (1...12).contains(month), (1...31).contains(day)
        else {
            return nil
        }

        let offsetSign = bytes[19] == UInt8(ascii: "-") ? -1 : 1
        let offsetSeconds = offsetSign * (offsetHour * 3600 + offsetMinute * 60)
        let daysSinceEpoch = daysFromCivil(year: year, month: month, day: day)
        let secondsSinceEpoch =
            daysSinceEpoch * 86400 + hour * 3600 + minute * 60 + second - offsetSeconds

        return Date(timeIntervalSince1970: TimeInterval(secondsSinceEpoch))
    }

    /// 公历日期转 Unix 纪元天数（Howard Hinnant 的 `days_from_civil` 算法）。
    ///
    /// 把 3 月当作一年的起点，闰日就落在「年末」，闰年判断因此退化成纯除法，
    /// 无需分支也无需查表。
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = year - (month <= 2 ? 1 : 0)
        let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra - 719468
    }
}

extension String {
    fileprivate func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
