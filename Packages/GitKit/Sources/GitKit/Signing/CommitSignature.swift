import Foundation

/// 一条提交的签名状态。
///
/// 取自 `git log --format=%G?` 的单字母代码。
public enum SignatureStatus: String, Sendable, Equatable, CaseIterable {

    /// 签名有效。
    case good = "G"
    /// 签名**无效**——内容和签名对不上，提交可能被改过。
    case bad = "B"
    /// 签名有效，但签名者的 key 你没有标记为可信。
    case unknownTrust = "U"
    /// 签名有效，但签名已过期。
    case expiredSignature = "X"
    /// 签名有效，但签名者的 key 已过期。
    case expiredKey = "Y"
    /// 签名有效，但 key 已被吊销。
    case revokedKey = "R"
    /// 本地没有对应的 key，无法校验——**不代表签名有问题**。
    case cannotCheck = "E"
    /// 没有签名。
    case none = "N"

    /// 这条提交是不是可信的。
    ///
    /// 只有 `good` 一种算数。`unknownTrust` 单独列出来是因为它极其常见——
    /// 对方确实签了名、签名也对得上，只是你没把他的 key 标记为信任，
    /// 把它跟「签名是坏的」混为一谈会让这个功能变成噪音。
    public var isVerified: Bool { self == .good }

    /// 需要提醒用户的状态。
    ///
    /// 「没有签名」不在其中：绝大多数仓库的绝大多数提交都没签名，
    /// 给每一条都挂个警告等于没有警告。
    public var needsAttention: Bool {
        switch self {
        case .bad, .expiredSignature, .expiredKey, .revokedKey: true
        case .good, .unknownTrust, .cannotCheck, .none: false
        }
    }

    public var displayName: String {
        switch self {
        case .good: "签名有效"
        case .bad: "签名无效"
        case .unknownTrust: "签名有效，但 key 未标记为可信"
        case .expiredSignature: "签名已过期"
        case .expiredKey: "签名者的 key 已过期"
        case .revokedKey: "签名者的 key 已吊销"
        case .cannotCheck: "本地缺少 key，无法校验"
        case .none: "未签名"
        }
    }

    /// 一句话说清这意味着什么。
    public var explanation: String {
        switch self {
        case .good:
            "这条提交带着有效签名，且签名者的 key 在你的信任列表里。"
        case .bad:
            "**签名和内容对不上。** 这条提交在签名之后被改动过，或者签名本身被伪造。"
        case .unknownTrust:
            "签名本身是对的，只是你没把签名者的 key 标记为可信。"
                + "这不代表有问题——大多数别人签的提交都是这个状态。"
        case .expiredSignature:
            "签名有效，但已经超过了它自己声明的有效期。"
        case .expiredKey:
            "签名有效，但签名用的 key 已经过期。key 过期通常是到期没续，不等于泄露。"
        case .revokedKey:
            "**签名用的 key 已被吊销。** 吊销通常意味着 key 泄露了，这条签名不该再被信任。"
        case .cannotCheck:
            "本地没有这个签名者的公钥，所以校验不了。**这不代表签名有问题**，"
                + "把对方的公钥导入之后就能校验了。"
        case .none:
            "这条提交没有签名。绝大多数提交都没有签名，这是常态。"
        }
    }
}

/// 提交签名的完整信息。
public struct CommitSignature: Sendable, Equatable {

    public let status: SignatureStatus
    /// 签名者，形如 `名字 <邮箱>`。没有签名时为空。
    public let signer: String
    /// 签名用的 key 指纹。
    public let key: String

    public init(status: SignatureStatus, signer: String, key: String) {
        self.status = status
        self.signer = signer
        self.key = key
    }

    public static let unsigned = CommitSignature(status: .none, signer: "", key: "")
}

extension GitClient {

    /// 读一条提交的签名状态。
    ///
    /// **单条查询，不进历史列表的格式串。** `%G?` 会让 git 对每一条提交
    /// 实际跑一次验签（可能要唤起 gpg），加进默认 log 格式的话，
    /// 一次 5 万条的历史加载要付 5 万次验签的代价——PRD 要求的首屏 500ms
    /// 会直接崩掉。选中某条提交时再问它一次，代价可以忽略。
    public func signature(of hash: String, in repository: URL) async throws -> CommitSignature {
        let result = try await runReturningResult(
            ["log", "--format=%G?%x1f%GS%x1f%GK", "--max-count=1", hash],
            in: repository,
            allowsOptionalLocks: false
        )
        guard result.isSuccess else { return .unsigned }

        let fields = result.standardOutputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\u{1F}", omittingEmptySubsequences: false)
            .map(String.init)
        guard let code = fields.first, let status = SignatureStatus(rawValue: code) else {
            return .unsigned
        }

        return CommitSignature(
            status: status,
            signer: fields.count > 1 ? fields[1] : "",
            key: fields.count > 2 ? fields[2] : ""
        )
    }
}
