import Foundation

/// 把 git 的远程操作报错翻成中文，并给出下一步该做什么。
///
/// PRD 的验收标准写着「凭据失败给中文可操作提示而非挂起」。挂起靠
/// `GIT_TERMINAL_PROMPT=0` 已经避免了，剩下的问题是 git 的英文报错对中文用户
/// 既看不懂也不知道该干嘛——这里补上后半截。
public struct RemoteFailure: Sendable, Equatable {

    public enum Reason: Sendable, Equatable {
        /// HTTPS 认证失败：用户名密码或 token 不对。
        case authenticationFailed
        /// 需要凭据但无法交互获取。
        case credentialsRequired
        /// SSH 公钥被拒绝。
        case sshKeyRejected
        /// 仓库不存在，或当前身份无权访问（GitHub 对私有仓库统一报 not found，避免信息泄露）。
        case repositoryNotFound
        /// 网络不通或主机无法解析。
        case networkUnreachable
        /// 远程有新提交，需要先合并。
        case nonFastForward
        /// 未识别的失败。
        case other
    }

    public let reason: Reason
    /// 面向用户的中文说明。
    public let message: String
    /// 下一步该做什么。
    public let suggestion: String
    /// git 的原始输出，供「查看详情」展开。
    public let rawOutput: String

    /// 从 git 的 stderr 识别失败原因。
    public static func diagnose(standardError: String, arguments: [String]) -> RemoteFailure {
        let text = standardError.lowercased()

        if text.contains("could not read username") || text.contains("terminal prompts disabled") {
            return RemoteFailure(
                reason: .credentialsRequired,
                message: "这个远程仓库需要账号凭据，但系统里没有存。",
                suggestion: "在终端执行一次 git push 完成登录，凭据会存入钥匙串；"
                    + "或改用 SSH 地址避免每次输入密码。",
                rawOutput: standardError
            )
        }

        if text.contains("authentication failed") || text.contains("invalid username or password") {
            return RemoteFailure(
                reason: .authenticationFailed,
                message: "账号或密码不正确，认证被拒绝。",
                suggestion: "GitHub、GitLab 等平台早已不接受账号密码，需要用 access token 代替密码。"
                    + "若钥匙串里存的是过期凭据，先在「钥匙串访问」里删掉对应条目再重试。",
                rawOutput: standardError
            )
        }

        if text.contains("permission denied (publickey)") || text.contains("host key verification failed") {
            return RemoteFailure(
                reason: .sshKeyRejected,
                message: "SSH 密钥没有被远程接受。",
                suggestion: "确认密钥已添加到远程平台，并已用 ssh-add 加进 ssh-agent。"
                    + "可以先用 ssh -T git@github.com 单独验证连接。",
                rawOutput: standardError
            )
        }

        if text.contains("repository not found") || text.contains("does not appear to be a git repository") {
            return RemoteFailure(
                reason: .repositoryNotFound,
                message: "找不到这个远程仓库。",
                suggestion: "检查远程地址是否拼写正确。若是私有仓库，"
                    + "平台通常把「无权访问」也报成「不存在」，需要确认当前身份有权限。",
                rawOutput: standardError
            )
        }

        if text.contains("could not resolve host") || text.contains("connection timed out")
            || text.contains("network is unreachable")
        {
            return RemoteFailure(
                reason: .networkUnreachable,
                message: "连不上远程主机。",
                suggestion: "检查网络连接与代理设置。若在公司网络内，可能需要配置 http.proxy。",
                rawOutput: standardError
            )
        }

        if text.contains("non-fast-forward") || text.contains("failed to push some refs")
            || text.contains("rejected")
        {
            return RemoteFailure(
                reason: .nonFastForward,
                message: "远程有你本地还没有的提交，推送被拒绝。",
                suggestion: "先 pull 把远程改动合并进来再推。"
                    + "**不要直接用 force**——那会覆盖掉别人推上去的提交。",
                rawOutput: standardError
            )
        }

        return RemoteFailure(
            reason: .other,
            message: "远程操作失败。",
            suggestion: "展开详情查看 git 的原始输出。等价命令：git " + arguments.joined(separator: " "),
            rawOutput: standardError
        )
    }
}

extension RemoteFailure: Error, CustomStringConvertible {
    public var description: String {
        "\(message)\n\(suggestion)"
    }
}
