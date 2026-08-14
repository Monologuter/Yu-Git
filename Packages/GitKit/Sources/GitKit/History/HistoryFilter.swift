import Foundation

/// 提交历史的过滤条件。
///
/// **交给 git 去筛，不在客户端过滤已加载的那几百条。** 这个区别很要紧：
/// 客户端过滤只能在首屏那 200 条里找，用户搜不到就会以为"仓库里没有"，
/// 而实际上它在第 300 条。让 git 扫完整个历史，答案才是可信的。
public struct HistoryFilter: Sendable, Equatable {

    /// 在提交信息里找这段文字。**字面匹配，不是正则**。
    public var message: String?
    /// 作者名或邮箱包含这段文字。
    public var author: String?
    /// 只要这个时刻之后的提交。
    public var since: Date?
    /// 只要这个时刻之前的提交。
    public var until: Date?
    /// 只看改动过这些路径的提交。
    public var paths: [String]

    public init(
        message: String? = nil,
        author: String? = nil,
        since: Date? = nil,
        until: Date? = nil,
        paths: [String] = []
    ) {
        self.message = message
        self.author = author
        self.since = since
        self.until = until
        self.paths = paths
    }

    public var isEmpty: Bool {
        normalized(message) == nil && normalized(author) == nil
            && since == nil && until == nil && paths.isEmpty
    }

    private func normalized(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// 转成 git log 的参数。
    var arguments: [String] {
        var result: [String] = []

        if let message = normalized(message) {
            // --fixed-strings：不加的话查询会按 basic regex 解释，
            // 而提交信息里满是 `.` `[` `*`——搜 "v1.0" 会匹配到 "v1X0"，
            // 搜 "[WIP]" 更是直接变成字符集。
            // -i：不加则区分大小写，搜 "FEAT" 一条都出不来（实测）。
            result += ["--fixed-strings", "-i", "--grep=\(message)"]
        }

        if let author = normalized(author) {
            // --author 是**子串**匹配，但**始终按正则解释**——
            // --fixed-strings 只管 --grep，管不到它（实测：-F 之后
            // "M.nologuter" 仍然能匹配 "Monologuter"）。
            // 所以只能自己把元字符转义掉，否则名字里带 `.` 的（邮箱很常见）
            // 会匹配到不相干的人。
            result += ["-i", "--author=\(escapedForBasicRegex(author))"]
        }

        if let since {
            result.append("--since=\(Self.timestamp(since))")
        }
        if let until {
            result.append("--until=\(Self.timestamp(until))")
        }

        return result
    }

    /// 转义 basic regex 的元字符。
    private func escapedForBasicRegex(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\.[]^$*".contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    /// 时间戳格式。
    ///
    /// **必须给到分钟并带时区**，不能只给 `2026-08-14` 这样的裸日期：
    /// 实测裸日期会漏掉当天的提交（git 对它的解释和本地时区不一致），
    /// 用户按"今天"筛却一条都看不到，而实际上今天提交了十几次。
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
