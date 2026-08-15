import Foundation

/// 这个仓库的提交签名配置。
public struct SigningSettings: Sendable, Equatable {

    /// 签名用什么格式。
    public enum Format: String, Sendable, Equatable, CaseIterable {
        case openpgp
        case ssh
        case x509

        public var displayName: String {
            switch self {
            case .openpgp: "GPG"
            case .ssh: "SSH key"
            case .x509: "S/MIME (X.509)"
            }
        }

        /// 一句话说清各自要什么。
        public var requirement: String {
            switch self {
            case .openpgp: "需要本机装有 gpg，并有一把私钥"
            case .ssh: "用现成的 SSH key 签名，不需要装 gpg。GitHub 和 GitLab 都认"
            case .x509: "需要 S/MIME 证书，通常是企业环境"
            }
        }
    }

    /// 每条提交自动签名（`commit.gpgsign`）。
    public var signsCommits: Bool
    /// 签名格式（`gpg.format`）。git 的默认值是 openpgp。
    public var format: Format
    /// 签名用哪把 key（`user.signingkey`）。
    public var signingKey: String

    public init(signsCommits: Bool, format: Format, signingKey: String) {
        self.signsCommits = signsCommits
        self.format = format
        self.signingKey = signingKey
    }

    /// 签名开着但跑不起来的原因。开关关着或一切正常时为 nil。
    ///
    /// **开了签名却缺东西，每一次提交都会失败。** 界面必须在打开开关之前就拦住，
    /// 否则用户只会看到「提交失败」，而失败的原因是他刚刚在另一个页面上做的事。
    ///
    /// 有**两种**失败方式，报错完全不同，实测得来：
    /// ```
    /// gpg.format=ssh 且没有 user.signingkey
    ///   → fatal: either user.signingkey or gpg.ssh.defaultKeyCommand needs to be configured
    /// gpg.format=openpgp（默认）且本机没装 gpg
    ///   → error: cannot run gpg: No such file or directory
    /// ```
    /// 第二种尤其容易漏：key 配得好好的，签名照样失败，因为根本没有 gpg 可跑。
    public enum Blocker: Sendable, Equatable {
        /// 没指定用哪把 key。
        case missingKey
        /// 选了 GPG 格式，但本机找不到 gpg 可执行文件。
        case gpgNotInstalled

        public var displayName: String {
            switch self {
            case .missingKey: "还没有指定签名用的 key"
            case .gpgNotInstalled: "本机没有装 gpg"
            }
        }

        public var suggestion: String {
            switch self {
            case .missingKey:
                "填一个 key 之后才能签名。开着签名却没有 key，每一次提交都会直接失败。"
            case .gpgNotInstalled:
                "GPG 格式需要本机装有 gpg 命令。要么装一个（`brew install gnupg`），"
                    + "要么改用 SSH key 签名——那个用现成的 SSH key，不需要 gpg，"
                    + "GitHub 和 GitLab 都认。"
            }
        }
    }

    /// - Parameter hasGPG: 本机有没有 gpg 可执行文件。
    ///   由 ``GitClient/isGPGAvailable()`` 探测，不在这个类型里做——
    ///   它是一个纯数据类型，不该自己去摸文件系统。
    public func blocker(hasGPG: Bool) -> Blocker? {
        guard signsCommits else { return nil }
        if signingKey.isEmpty { return .missingKey }
        if format == .openpgp && !hasGPG { return .gpgNotInstalled }
        return nil
    }
}

extension GitClient {

    /// 读这个仓库的签名配置。
    public func signingSettings(in repository: URL) async -> SigningSettings {
        // `git config --get` 在没设过这一项时**以 1 退出**。那不是错误，
        // 是「没有值」，所以这里一律用 runReturningResult 而不是 run。
        func value(_ key: String) async -> String {
            let result = try? await runReturningResult(
                ["config", "--get", key], in: repository, allowsOptionalLocks: false)
            guard let result, result.isSuccess else { return "" }
            return result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let signs = await value("commit.gpgsign")
        let format = await value("gpg.format")
        let key = await value("user.signingkey")

        return SigningSettings(
            signsCommits: signs == "true",
            format: SigningSettings.Format(rawValue: format) ?? .openpgp,
            signingKey: key
        )
    }

    /// 本机有没有 gpg。
    ///
    /// 用 `gpg --version` 而不是查固定路径：gpg 可能来自 Homebrew、MacPorts
    /// 或用户自己编译的，路径各不相同，能不能跑起来才是要问的问题。
    public func isGPGAvailable() async -> Bool {
        for executable in ["gpg", "gpg2"] {
            let result = try? await ProcessRunner().run(
                executable: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [executable, "--version"],
                workingDirectory: URL(fileURLWithPath: "/"),
                environment: environment,
                timeout: .seconds(5)
            )
            if result?.isSuccess == true { return true }
        }
        return false
    }
}

extension GitOperation {

    /// 写一项 git 配置。
    ///
    /// 值为空时删掉这一项（`--unset`）而不是写一个空字符串：
    /// 空字符串和「没设置」在 git 里是两回事，前者会让 `gpg.format=` 变成
    /// 一个无效值而不是回落到默认的 openpgp。
    public static func setConfiguration(key: String, value: String) -> GitOperation {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let arguments =
            trimmed.isEmpty
            ? ["config", "--unset", key]
            : ["config", key, trimmed]

        return GitOperation(
            kind: .setConfiguration,
            arguments: arguments,
            summary: trimmed.isEmpty ? "清除配置 \(key)" : "设置 \(key) = \(trimmed)",
            explanation: trimmed.isEmpty
                ? "把 \(key) 从这个仓库的配置里删掉，回落到全局配置或 git 的默认值。"
                : "只改这个仓库的配置（`.git/config`），不影响你的其他仓库。",
            hazard: .none
        )
    }

    /// 单独签一条已有的提交。
    ///
    /// 用 `--amend --no-edit` 重新生成它。**这会改写历史**——提交内容一样，
    /// 但多了签名，hash 因此变了。已经推送过的提交不要这么做。
    public static func signLastCommit() -> GitOperation {
        GitOperation(
            kind: .amend,
            arguments: ["commit", "--amend", "--no-edit", "--gpg-sign"],
            summary: "给最后一条提交补上签名",
            explanation: "重新生成最后一条提交并附上签名。内容一个字不改，"
                + "**但它会得到新的 commit hash**——已经推送过的提交这么做，"
                + "再推送就需要 force。",
            hazard: .rewritesHistory
        )
    }
}
