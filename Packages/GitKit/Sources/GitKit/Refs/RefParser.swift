import Foundation

/// `git for-each-ref` 输出的解析器。
///
/// 用 `for-each-ref` 而不是 `git branch` / `git tag`：后两者是给人看的，
/// 输出格式随配置和版本变化；`for-each-ref` 是明确的脚本接口，字段可精确指定。
public enum RefParser {

    static let fieldSeparator: UInt8 = 0x1F
    static let recordSeparator: UInt8 = 0x1E

    /// 分支查询的格式串，字段顺序与 ``parseBranches(_:)`` 的下标对应。
    public static let branchFormat =
        [
            "%(refname)",  // 0 完整引用名
            "%(objectname)",  // 1 指向的 commit
            "%(HEAD)",  // 2 当前分支为 "*"，否则为空格
            "%(upstream:short)",  // 3 upstream 短名
            "%(upstream:track)",  // 4 [ahead 1, behind 2] / [gone] / 空
            "%(committerdate:iso8601-strict)",  // 5 最后一次提交时间
            "%(contents:subject)",  // 6 最后一次提交的标题
        ].joined(separator: "%1f") + "%1e"

    /// tag 查询的格式串，字段顺序与 ``parseTags(_:)`` 的下标对应。
    public static let tagFormat =
        [
            "%(refname)",  // 0 完整引用名
            "%(objecttype)",  // 1 "tag" = 附注，"commit" = 轻量
            "%(objectname)",  // 2 附注 tag 时是 tag 对象，轻量 tag 时就是 commit
            "%(*objectname)",  // 3 解引用后的 commit；轻量 tag 为空
            "%(creatordate:iso8601-strict)",  // 4 两种 tag 都有值
            "%(taggername)",  // 5 轻量 tag 为空
            "%(taggeremail)",  // 6 带尖括号，轻量 tag 为空
            "%(contents:subject)",  // 7 附注 tag 是其说明；轻量 tag 是 commit 的标题
        ].joined(separator: "%1f") + "%1e"

    // MARK: - 分支

    public static func parseBranches(_ data: Data) throws -> [Branch] {
        try records(in: data).compactMap { fields in
            guard fields.count >= 7 else {
                throw GitError.parseFailure(
                    reason: "分支记录应有 7 个字段，实得 \(fields.count)",
                    context: fields.first ?? ""
                )
            }

            let fullName = fields[0]
            // refs/remotes/origin/HEAD 是指向默认分支的符号引用，不是真正的分支，
            // 留着会在分支列表里多出一个幽灵条目。
            guard !fullName.hasSuffix("/HEAD") else { return nil }

            let isRemote = fullName.hasPrefix("refs/remotes/")
            let upstream = fields[3].isEmpty ? nil : fields[3]

            return Branch(
                fullName: fullName,
                name: shortName(of: fullName),
                commit: fields[1],
                isCurrent: fields[2] == "*",
                isRemote: isRemote,
                upstream: upstream,
                tracking: parseTracking(fields[4]),
                lastCommitDate: LogParser.parseTimestamp(fields[5]),
                lastCommitSubject: fields[6]
            )
        }
    }

    /// 解析 `%(upstream:track)`：`[ahead 1, behind 2]`、`[gone]`，或空。
    static func parseTracking(_ text: String) -> TrackingStatus {
        guard !text.isEmpty else { return .notTracking }
        if text.contains("gone") {
            return TrackingStatus(ahead: 0, behind: 0, isGone: true)
        }

        var ahead = 0
        var behind = 0
        let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
        for piece in stripped.split(separator: ",") {
            let tokens = piece.split(separator: " ").map(String.init)
            guard tokens.count == 2, let value = Int(tokens[1]) else { continue }
            if tokens[0] == "ahead" {
                ahead = value
            } else if tokens[0] == "behind" {
                behind = value
            }
        }
        return TrackingStatus(ahead: ahead, behind: behind, isGone: false)
    }

    // MARK: - tag

    public static func parseTags(_ data: Data) throws -> [Tag] {
        try records(in: data).map { fields in
            guard fields.count >= 8 else {
                throw GitError.parseFailure(
                    reason: "tag 记录应有 8 个字段，实得 \(fields.count)",
                    context: fields.first ?? ""
                )
            }

            let isAnnotated = fields[1] == "tag"
            // 附注 tag 的 objectname 指向 tag 对象，要用解引用后的 *objectname
            let commit = isAnnotated ? fields[3] : fields[2]

            let tagger: Signature? =
                isAnnotated && !fields[5].isEmpty
                ? Signature(
                    name: fields[5],
                    email: fields[6].trimmingCharacters(in: CharacterSet(charactersIn: "<>")),
                    date: LogParser.parseTimestamp(fields[4]) ?? Date(timeIntervalSince1970: 0)
                )
                : nil

            return Tag(
                name: shortName(of: fields[0]),
                commit: commit,
                tagObject: isAnnotated ? fields[2] : nil,
                tagger: tagger,
                // 轻量 tag 没有自己的消息，这里的 subject 其实是它指向的 commit 的标题，
                // 直接拿来当 tag 说明会误导用户。
                message: isAnnotated ? fields[7] : nil,
                date: LogParser.parseTimestamp(fields[4])
            )
        }
    }

    // MARK: - 通用

    private static func records(in data: Data) -> [[String]] {
        data
            .split(separator: recordSeparator, omittingEmptySubsequences: true)
            .compactMap { record in
                let fields =
                    record
                    .split(separator: fieldSeparator, omittingEmptySubsequences: false)
                    .map { String(decoding: $0, as: UTF8.self) }
                // 记录之间的换行会粘在下一条记录开头
                guard var first = fields.first else { return nil }
                first = first.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !first.isEmpty else { return nil }
                return [first] + fields.dropFirst()
            }
    }

    /// `refs/heads/main` → `main`，`refs/remotes/origin/main` → `origin/main`。
    private static func shortName(of fullName: String) -> String {
        for prefix in ["refs/heads/", "refs/remotes/", "refs/tags/"] where fullName.hasPrefix(prefix) {
            return String(fullName.dropFirst(prefix.count))
        }
        return fullName
    }
}
