import GitKit
import SwiftUI

/// 提交信息，其中的 `#123` 变成可点的 issue 链接。
///
/// 解决的是一个具体的小麻烦：读历史时看到 `#412`，想知道那是什么，
/// 得手工去网页上找。**只做识别，不做 issue 管理**——完整的 issue 列表、
/// 筛选、评论是网页和 IDE 的地盘，在 Git 客户端里重做一遍既做不好也没人用。
struct CommitMessageText: View {

    let text: String
    /// 用来拼 issue 地址的 remote。认不出平台时传 nil，那就只显示文本。
    let remoteURL: String?

    var body: some View {
        Text(attributed)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        var result = AttributedString(text)
        guard let remoteURL else { return result }

        let references = IssueReferenceScanner.scan(text)
        guard !references.isEmpty else { return result }

        // 从后往前改。从前往后的话，前面的替换会让后面那些 range 全部失效——
        // AttributedString 的索引和 String 的索引不是一回事，改一处就得重算。
        for reference in references.reversed() {
            guard let url = IssueURLBuilder.url(forIssue: reference.number, remoteURL: remoteURL)
            else { continue }

            let offset = text.distance(from: text.startIndex, to: reference.range.lowerBound)
            let length = text.distance(
                from: reference.range.lowerBound, to: reference.range.upperBound)
            guard
                let start = result.index(
                    result.startIndex, offsetByCharacters: offset),
                let end = result.index(start, offsetByCharacters: length)
            else { continue }

            result[start..<end].link = url
            result[start..<end].foregroundColor = Theme.Colors.brand
        }

        return result
    }
}
