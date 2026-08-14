import Foundation

/// stash 栈里的一条。
///
/// 同时带着**索引和 hash**，因为 git 对这两者的接受程度不一样：
/// `stash apply` / `stash show` 认 hash，`stash drop` 只认 `stash@{N}`
/// （给它 hash 会报 "is not a stash reference"）。
/// 而 `N` 是会漂移的——见 ``StashEntry/index``。
public struct StashEntry: Sendable, Equatable, Identifiable {

    /// `stash@{N}` 里的 N。
    ///
    /// **这个值只在读出来的那一刻有效。** 删掉中间任何一条，它后面所有条目的索引
    /// 都会往前挪一位。用户在终端里 `git stash` 一下也会让全部索引 +1。
    /// 所以凡是要按索引下手的操作（只有 drop），执行前必须拿 ``hash`` 反查一次，
    /// 确认这个位置上还是同一条。
    public let index: Int

    /// 这条 stash 对应的 commit hash。稳定，可以存。
    public let hash: String

    /// 储藏的时间。
    public let date: Date

    /// 储藏时 HEAD 在哪个分支上。
    public let branch: String

    /// 用户自己写的说明。git 自动生成描述时为 nil。
    public let message: String?

    /// 自动生成描述时，储藏点那条提交的标题。
    ///
    /// 注意它说的是「储藏时 HEAD 停在哪」，**不是「这条 stash 里改了什么」**——
    /// 这是 `git stash list` 最容易骗人的地方：一列 `WIP on main: 8f2c1a 修复登录`
    /// 看着像在描述储藏的内容，其实每一条都只是在说当时的落脚点。
    public let baseSubject: String?

    public var id: String { hash }

    /// 有没有用户自己写的说明。
    ///
    /// 没有的话界面上要提示补一句：`stash@{3}` 放三天，没人记得那是什么。
    public var hasUserMessage: Bool { message != nil }

    /// 列表里显示的一行字。
    public var displayName: String {
        message ?? baseSubject.map { "储藏于「\($0)」" } ?? "未命名的储藏"
    }

    public init(
        index: Int,
        hash: String,
        date: Date,
        branch: String,
        message: String?,
        baseSubject: String?
    ) {
        self.index = index
        self.hash = hash
        self.date = date
        self.branch = branch
        self.message = message
        self.baseSubject = baseSubject
    }
}

/// 解析 `git stash list` 的输出。
public enum StashParser {

    /// 用户自己写了说明时的前缀。
    private static let userPrefix = "On "
    /// git 自动生成描述时的前缀。
    private static let autoPrefix = "WIP on "

    /// 解析 `git stash list --format="%gd%x1f%s%x1f%ct%x1f%H" -z` 的输出。
    ///
    /// subject 有两种形态，前缀不同：
    /// ```
    /// WIP on master: 78f2b67 base   ← 没给说明时 git 自动生成
    /// On master: 改了一半的功能       ← 用户 -m 填了说明
    /// ```
    /// 判前缀必须用 `hasPrefix` 而不是「包不包含」：`WIP on master: ...` 里面
    /// 也有一个 `on master`，用包含判断的话，自动生成的那种会被当成用户写的，
    /// 分支名被切成「 master」，说明变成后半截的 hash 加标题。
    public static func parse(_ data: Data) -> [StashEntry] {
        var result: [StashEntry] = []

        for record in data.split(separator: 0x00) where !record.isEmpty {
            let fields = record.split(separator: 0x1F, omittingEmptySubsequences: false)
            guard fields.count >= 4 else { continue }

            let selector = String(decoding: fields[0], as: UTF8.self)
            let subject = String(decoding: fields[1], as: UTF8.self)
            let timestamp = String(decoding: fields[2], as: UTF8.self)
            let hash = String(decoding: fields[3], as: UTF8.self)

            guard let index = Self.index(from: selector), !hash.isEmpty else { continue }

            let parsed = Self.describe(subject)
            result.append(
                StashEntry(
                    index: index,
                    hash: hash,
                    date: Date(timeIntervalSince1970: Double(timestamp) ?? 0),
                    branch: parsed.branch,
                    message: parsed.message,
                    baseSubject: parsed.baseSubject
                )
            )
        }

        return result
    }

    /// 从 `stash@{3}` 里取出 3。
    static func index(from selector: String) -> Int? {
        guard selector.hasPrefix("stash@{"), selector.hasSuffix("}") else { return nil }
        let digits = selector.dropFirst("stash@{".count).dropLast()
        return Int(digits)
    }

    /// 拆开 subject。
    static func describe(_ subject: String) -> (branch: String, message: String?, baseSubject: String?) {
        // 先判自动生成的那种。两个前缀里 "WIP on " 更长也更具体，
        // 而 "On " 那种永远不会以 "WIP" 开头，所以这个顺序不会误判。
        if subject.hasPrefix(autoPrefix) {
            let rest = String(subject.dropFirst(autoPrefix.count))
            guard let colon = rest.range(of: ": ") else {
                return (rest, nil, nil)
            }
            let branch = String(rest[rest.startIndex..<colon.lowerBound])
            // 后半截是「hash 提交标题」，把 hash 去掉只留标题
            let tail = String(rest[colon.upperBound...])
            let base =
                tail.split(separator: " ", maxSplits: 1).count == 2
                ? String(tail.split(separator: " ", maxSplits: 1)[1])
                : tail
            return (branch, nil, base.isEmpty ? nil : base)
        }

        if subject.hasPrefix(userPrefix) {
            let rest = String(subject.dropFirst(userPrefix.count))
            guard let colon = rest.range(of: ": ") else {
                return (rest, nil, nil)
            }
            let branch = String(rest[rest.startIndex..<colon.lowerBound])
            let message = String(rest[colon.upperBound...])
            return (branch, message.isEmpty ? nil : message, nil)
        }

        // 认不出的形态：整段当说明，总比丢掉强
        return ("", subject.isEmpty ? nil : subject, nil)
    }
}
