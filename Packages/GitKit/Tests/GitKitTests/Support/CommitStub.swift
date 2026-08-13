import Foundation

@testable import GitKit

extension Commit {

    /// 造一个只填了必要字段的 Commit，用于不涉及仓库的纯逻辑测试。
    static func stub(
        hash: String,
        subject: String,
        parents: [String] = [],
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Commit {
        let signature = Signature(name: "测试", email: "t@t", date: date)
        return Commit(
            hash: hash,
            abbreviatedHash: String(hash.prefix(7)),
            parents: parents,
            author: signature,
            committer: signature,
            subject: subject,
            body: "",
            refs: []
        )
    }
}
