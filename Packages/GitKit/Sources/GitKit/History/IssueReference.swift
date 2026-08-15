import Foundation

/// 提交信息里提到的一个 issue。
public struct IssueReference: Sendable, Equatable, Hashable {

    /// issue 编号。
    public let number: Int
    /// 它在原文里的位置，用来把那一段变成可点的链接。
    public let range: Range<String.Index>

    public init(number: Int, range: Range<String.Index>) {
        self.number = number
        self.range = range
    }
}

/// 从提交信息里找出 `#123` 这样的 issue 引用。
///
/// **只做识别，不做 issue 管理。** 完整的 issue 列表、筛选、评论是网页和 IDE
/// 的地盘，在 Git 客户端里重做一遍既做不好也没人用。这里要解决的是一个具体的
/// 小麻烦：读历史时看到 `#412`，想知道那是什么，得手工去网页上找。
public enum IssueReferenceScanner {

    /// 扫描一段文本。
    ///
    /// 规则刻意收紧，宁可漏也不误报——把不是引用的东西变成链接，
    /// 比不变成链接烦人得多：
    /// - `#` 前面必须是行首或空白或标点。`C#7` 里的 `#7` 不算
    /// - `#` 后面必须紧跟数字，且数字后面不能再跟字母或数字
    /// - 编号不能以 0 开头（`#007` 更可能是别的东西）
    /// - 编号上限一千万，再大的不是 issue 号
    public static func scan(_ text: String) -> [IssueReference] {
        var result: [IssueReference] = []
        var index = text.startIndex

        while let hash = text[index...].firstIndex(of: "#") {
            defer { index = text.index(after: hash) }

            // 前一个字符：行首、空白、或标点都算合法的起点
            if hash > text.startIndex {
                let previous = text[text.index(before: hash)]
                let isBoundary =
                    previous.isWhitespace || previous.isNewline
                    || previous.isPunctuation || previous == "(" || previous == "["
                guard isBoundary else { continue }
            }

            var end = text.index(after: hash)
            var digits = ""
            while end < text.endIndex, text[end].isNumber {
                digits.append(text[end])
                end = text.index(after: end)
            }

            guard !digits.isEmpty, !digits.hasPrefix("0"), digits.count <= 8,
                let number = Int(digits), number > 0
            else { continue }

            // 数字后面还跟着字母的话，整段更像标识符而不是引用
            if end < text.endIndex, text[end].isLetter { continue }

            result.append(IssueReference(number: number, range: hash..<end))
            index = end
        }

        return result
    }
}

/// 托管平台的 issue 链接怎么拼。
///
/// 三家的路径不一样，拼错的话点开是 404——那比不给链接更糟，
/// 用户会以为 issue 被删了。
public enum IssueURLBuilder {

    /// 从 remote 地址推出 issue 页的地址。
    ///
    /// 认不出平台时返回 nil，界面就只显示文本不做链接。
    public static func url(forIssue number: Int, remoteURL: String) -> URL? {
        guard let base = webBase(from: remoteURL) else { return nil }

        let path: String
        if base.contains("gitlab") {
            // GitLab 用 `-/issues`，少了那个 `-` 会 404
            path = "/-/issues/\(number)"
        } else {
            // GitHub 与 Gitee 都是 /issues/N
            path = "/issues/\(number)"
        }
        return URL(string: base + path)
    }

    /// 把 remote 地址规整成一个网页地址。
    ///
    /// 要处理三种形态：
    /// ```
    /// https://github.com/owner/repo.git
    /// git@github.com:owner/repo.git
    /// ssh://git@github.com/owner/repo.git
    /// ```
    static func webBase(from remoteURL: String) -> String? {
        var text = remoteURL.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("git@") {
            // git@host:owner/repo → https://host/owner/repo
            let withoutUser = String(text.dropFirst("git@".count))
            guard let colon = withoutUser.firstIndex(of: ":") else { return nil }
            let host = String(withoutUser[withoutUser.startIndex..<colon])
            let path = String(withoutUser[withoutUser.index(after: colon)...])
            text = "https://\(host)/\(path)"
        } else if text.hasPrefix("ssh://") {
            text = "https://" + text.dropFirst("ssh://".count)
            text = text.replacingOccurrences(of: "https://git@", with: "https://")
        } else if !text.hasPrefix("http") {
            // 本地路径这类，没有网页地址
            return nil
        }

        // 顺序要紧：`repo.git/` 这种两样都有，先剥 `.git` 的话它被结尾的斜杠挡着，
        // 剥不掉。所以先去斜杠、再去 `.git`、再去一次可能露出来的斜杠。
        func trimTrailingSlashes() {
            while text.hasSuffix("/") {
                text = String(text.dropLast())
            }
        }
        trimTrailingSlashes()
        if text.hasSuffix(".git") {
            text = String(text.dropLast(".git".count))
        }
        trimTrailingSlashes()

        // 至少要有 host + owner + repo 三段，否则拼出来的链接一定是错的
        guard let url = URL(string: text), url.host != nil,
            url.path.split(separator: "/").count >= 2
        else { return nil }
        return text
    }
}
