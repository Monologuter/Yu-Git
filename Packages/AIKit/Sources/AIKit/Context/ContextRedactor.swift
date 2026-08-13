import Foundation

/// 把 diff 交给模型之前先过一遍。
///
/// PRD 的 AI 设计铁律：**发出去的东西用户必须可预期**。这里做三件事：
///
/// 1. 整份排除敏感文件（`.env`、私钥、凭据）——这类文件即使只看 diff 也会泄密
/// 2. 对剩下内容里形似密钥的字符串打码
/// 3. 控制体积，超了就按文件截断而不是拦腰砍断
///
/// 每一步都会记录**做了什么**，界面上要如实告诉用户「哪些文件没发出去」。
/// 悄悄脱敏和悄悄发送一样糟：用户会以为 AI 看到了全部改动。
public struct ContextRedactor: Sendable {

    /// 默认体积上限（字符数）。
    ///
    /// 按中英文混合代码大致 3 字符 ≈ 1 token 估，6 万字符约 2 万 token，
    /// 对提交信息生成足够，也远低于各家模型的上下文下限。
    /// 之所以不按 token 精算：本地没有分词器，而各家分词还不一样，
    /// 估一个偏保守的字符数比假装精确更实在。
    public static let defaultBudget = 60_000

    /// 整份不发的文件。命中即整个文件的 diff 都不进上下文。
    ///
    /// 匹配的是路径的最后一段或全路径后缀，宁可漏判也不搞模糊匹配——
    /// 把 `*secret*` 这种加进来会误伤 `SecretsManagerTests.swift` 之类的正常文件。
    static let sensitiveNames: Set<String> = [
        ".env", ".netrc", ".npmrc", ".pypirc", ".htpasswd",
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
        "credentials", "terraform.tfstate", "terraform.tfstate.backup",
    ]

    static let sensitiveExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "jks", "keystore", "mobileprovision", "ppk", "asc",
    ]

    /// 前缀式的敏感文件，例如 `.env.local`、`.env.production`。
    static let sensitivePrefixes = [".env."]

    public init() {}

    // MARK: - 结果

    public struct Result: Sendable, Equatable {
        /// 可以安全发出去的内容。
        public let text: String
        /// 因敏感而整份排除的文件。
        public let excludedPaths: [String]
        /// 因体积超限而未纳入的文件。
        public let truncatedPaths: [String]
        /// 打码掉的疑似密钥个数。
        public let maskedSecretCount: Int

        public var isEmpty: Bool { text.isEmpty }

        /// 给界面用的一句话说明。没有任何删改时返回 nil。
        public var summary: String? {
            var parts: [String] = []
            if !excludedPaths.isEmpty {
                parts.append("已排除 \(excludedPaths.count) 个敏感文件")
            }
            if !truncatedPaths.isEmpty {
                parts.append("\(truncatedPaths.count) 个文件因内容过长未纳入")
            }
            if maskedSecretCount > 0 {
                parts.append("\(maskedSecretCount) 处疑似密钥已打码")
            }
            return parts.isEmpty ? nil : parts.joined(separator: "，")
        }
    }

    // MARK: - 主流程

    /// 处理一份 `git diff` 输出。
    public func redact(diff: String, budget: Int = ContextRedactor.defaultBudget) -> Result {
        let files = Self.splitByFile(diff)

        var kept: [String] = []
        var excluded: [String] = []
        var truncated: [String] = []
        var masked = 0
        var used = 0

        for file in files {
            if Self.isSensitive(path: file.path) {
                excluded.append(file.path)
                continue
            }

            let (body, count) = Self.maskSecrets(in: file.body)
            masked += count

            // 按文件为单位取舍：截断在一个 hunk 中间会让模型看到半截改动，
            // 那比明说「这个文件没给你」更容易导致胡说。
            guard used + body.count <= budget else {
                truncated.append(file.path)
                continue
            }

            kept.append(body)
            used += body.count
        }

        return Result(
            text: kept.joined(separator: "\n"),
            excludedPaths: excluded,
            truncatedPaths: truncated,
            maskedSecretCount: masked
        )
    }

    // MARK: - 切分

    struct FileDiff: Equatable {
        let path: String
        let body: String
    }

    /// 按 `diff --git` 把整份 diff 切成一个个文件。
    ///
    /// 路径优先取自 `+++ b/` 行而不是 `diff --git` 行。后者在路径含空格时是**真有歧义**的：
    /// 一个叫 `foo b/bar.txt` 的文件，头一行长这样
    ///
    ///     diff --git a/foo b/bar.txt b/foo b/bar.txt
    ///
    /// 光看这一行无法确定 ` b/` 哪一处才是分界。而 `+++ b/foo b/bar.txt` 只有开头一个前缀，
    /// 拆下来就是完整路径，没有二义性。
    static func splitByFile(_ diff: String) -> [FileDiff] {
        guard !diff.isEmpty else { return [] }

        var files: [FileDiff] = []
        var currentPath: String?
        var currentLines: [Substring] = []
        /// 进入 hunk 之后就不再找路径了：正文里一行内容如果本身是 `++ b/x`，
        /// 加号前缀一叠就成了 `+++ b/x`，会被误认成文件头。
        var inHunk = false

        func flush() {
            guard let path = currentPath, !currentLines.isEmpty else { return }
            files.append(FileDiff(path: path, body: currentLines.joined(separator: "\n")))
        }

        // 按 \n 切即可：git diff 的行分隔一定是 \n，文件内容里的 CR 会留在行尾，
        // 不影响我们只关心行首标记的判断。
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") {
                flush()
                currentPath = parsePath(fromHeader: line)
                currentLines = [line]
                inHunk = false
                continue
            }

            guard currentPath != nil else { continue }
            currentLines.append(line)

            if line.hasPrefix("@@") {
                inHunk = true
            } else if !inHunk {
                // `+++` 后到 `---`：新增文件的 `---` 是 /dev/null，删除文件的 `+++` 是
                // /dev/null，两边各取所需。`+++` 在后面，正常情况下自然覆盖 `---`。
                if let path = parseSidePath(line, prefix: "--- a/") {
                    currentPath = path
                } else if let path = parseSidePath(line, prefix: "+++ b/") {
                    currentPath = path
                }
            }
        }
        flush()

        return files
    }

    /// 从 `--- a/路径` / `+++ b/路径` 取路径。
    private static func parseSidePath(_ line: Substring, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        var path = line.dropFirst(prefix.count)
        // 路径含空格时 git 会在行尾补一个制表符
        while path.hasSuffix("\t") { path = path.dropLast() }
        guard !path.isEmpty else { return nil }
        return unquote(String(path))
    }

    /// 从 `diff --git a/路径 b/路径` 里取路径。
    ///
    /// 只作为兜底：二进制文件的 diff 没有 `---`/`+++` 行。取 `b/` 那一侧，
    /// 因为重命名时它才是改动后的名字。
    static func parsePath(fromHeader line: Substring) -> String? {
        guard let range = line.range(of: " b/", options: .backwards) else {
            // 极少数情况下没有 b/ 侧（例如某些 --no-prefix 输出），退回整行末段
            let parts: [Substring] = line.split(separator: " ")
            return parts.last.map(String.init)
        }
        return unquote(String(line[range.upperBound...]))
    }

    /// 去掉 git 对特殊字符路径加的双引号。
    ///
    /// GitKit 统一带 `core.quotepath=false`，所以中文路径不会被转义；
    /// 但引号、制表符这类字符仍会让 git 给整个路径加引号。
    private static func unquote(_ path: String) -> String {
        guard path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") else { return path }
        return String(path.dropFirst().dropLast())
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - 敏感判定

    static func isSensitive(path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        let lowered = name.lowercased()

        if sensitiveNames.contains(lowered) { return true }
        if sensitivePrefixes.contains(where: lowered.hasPrefix) { return true }

        let ext = (lowered as NSString).pathExtension
        if !ext.isEmpty, sensitiveExtensions.contains(ext) { return true }

        // ~/.aws/credentials、config/credentials.yml 这类带目录语义的
        if lowered.hasPrefix("credentials.") { return true }

        return false
    }

    // MARK: - 打码

    /// 常见密钥的样子。只认有明确前缀的——靠长度或熵去猜会把 commit hash、
    /// base64 资源、UUID 全都误伤。
    private static let secretPatterns: [String] = [
        #"sk-[A-Za-z0-9_\-]{16,}"#,  // OpenAI / Anthropic
        #"gh[pousr]_[A-Za-z0-9]{16,}"#,  // GitHub token
        #"github_pat_[A-Za-z0-9_]{20,}"#,
        #"glpat-[A-Za-z0-9_\-]{16,}"#,  // GitLab
        #"AKIA[0-9A-Z]{16}"#,  // AWS access key id
        #"xox[abprs]-[A-Za-z0-9\-]{10,}"#,  // Slack
        #"AIza[0-9A-Za-z_\-]{35}"#,  // Google API key
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
    ]

    private static let secretRegex: NSRegularExpression? = {
        let combined = secretPatterns.joined(separator: "|")
        return try? NSRegularExpression(pattern: combined)
    }()

    /// 把疑似密钥换成占位符，保留行结构。
    static func maskSecrets(in text: String) -> (String, Int) {
        guard let regex = secretRegex else { return (text, 0) }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return (text, 0) }

        var result = text
        // 从后往前替换，前面的位置就不会被打乱
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(matchRange, with: "«已打码»")
        }
        return (result, matches.count)
    }
}
