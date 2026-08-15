import Foundation

/// 用户配好的外部 diff / merge 工具。
public struct ExternalTool: Sendable, Equatable, Identifiable {

    public let name: String
    /// git 给的一句说明，如「Use FileMerge (requires a graphical session)」。
    public let detail: String
    /// 这台机器上装了没有。
    public let isAvailable: Bool
    /// 是用户在配置里自己定义的，而不是 git 内置认识的。
    public let isUserDefined: Bool

    public var id: String { name }

    public init(name: String, detail: String, isAvailable: Bool, isUserDefined: Bool) {
        self.name = name
        self.detail = detail
        self.isAvailable = isAvailable
        self.isUserDefined = isUserDefined
    }
}

/// 解析 `git difftool --tool-help` / `git mergetool --tool-help`。
///
/// 输出分三段，段与段之间靠标题行区分：
/// ```
/// 'git difftool --tool=<tool>' may be set to one of the following:
///         opendiff         Use FileMerge (requires a graphical session)
///
///     user-defined:
///         mytool.cmd code --diff "$LOCAL" "$REMOTE"
///
/// The following tools are valid, but not currently available:
///         bc               Use Beyond Compare (requires a graphical session)
/// ```
public enum ExternalToolParser {

    private static let availableHeader = "may be set to one of the following:"
    private static let userDefinedHeader = "user-defined:"
    private static let unavailableHeader = "valid, but not currently available:"

    public static func parse(_ text: String) -> [ExternalTool] {
        enum Section { case none, available, userDefined, unavailable }
        var section = Section.none
        var result: [ExternalTool] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if line.contains(availableHeader) {
                section = .available
                continue
            }
            if trimmed == userDefinedHeader {
                section = .userDefined
                continue
            }
            if line.contains(unavailableHeader) {
                section = .unavailable
                continue
            }
            guard section != .none, !trimmed.isEmpty else { continue }
            // 条目一律有缩进；顶格的是别的说明文字
            guard line.hasPrefix("\t") || line.hasPrefix(" ") else { continue }

            let parts = trimmed.split(
                separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let first = parts.first else { continue }

            // 用户自定义那段的条目形如 `mytool.cmd <命令>`，工具名要去掉 `.cmd`
            var name = String(first)
            if section == .userDefined, name.hasSuffix(".cmd") {
                name = String(name.dropLast(".cmd".count))
            }
            guard !name.isEmpty else { continue }

            result.append(
                ExternalTool(
                    name: name,
                    detail: parts.count > 1
                        ? String(parts[1]).trimmingCharacters(in: .whitespaces) : "",
                    isAvailable: section != .unavailable,
                    isUserDefined: section == .userDefined
                )
            )
        }

        return result
    }
}

extension GitClient {

    /// 这台机器上能用哪些 diff 工具。
    public func diffTools(in repository: URL) async -> [ExternalTool] {
        await tools(subcommand: "difftool", in: repository)
    }

    /// 这台机器上能用哪些 merge 工具。
    public func mergeTools(in repository: URL) async -> [ExternalTool] {
        await tools(subcommand: "mergetool", in: repository)
    }

    private func tools(subcommand: String, in repository: URL) async -> [ExternalTool] {
        // `--tool-help` 走 stdout 还是 stderr 随版本不同，两边都收
        guard
            let result = try? await runReturningResult(
                [subcommand, "--tool-help"], in: repository, allowsOptionalLocks: false)
        else { return [] }
        return ExternalToolParser.parse(result.standardOutputText + "\n" + result.standardErrorText)
    }

    /// 用户配的 `diff.tool`。没配返回 nil。
    public func configuredDiffTool(in repository: URL) async -> String? {
        await configuredValue("diff.tool", in: repository)
    }

    /// 用户配的 `merge.tool`。
    public func configuredMergeTool(in repository: URL) async -> String? {
        await configuredValue("merge.tool", in: repository)
    }

    private func configuredValue(_ key: String, in repository: URL) async -> String? {
        // `git config --get` 没设过时以 1 退出，那不是错误
        guard
            let result = try? await runReturningResult(
                ["config", "--get", key], in: repository, allowsOptionalLocks: false),
            result.isSuccess
        else { return nil }
        let value = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// 用外部工具打开某个文件的 diff。
    ///
    /// **不走 `RepoActor.perform`。** 那条队列是串行的，而 difftool 会一直阻塞到
    /// 用户关掉工具窗口——放进队列等于在此期间冻结所有其他操作。
    /// 而且这不是我们发起的写：mergetool 改的是工作区文件，性质上和用户
    /// 在 Vim 里改了个文件一样，由文件监听器发现即可，和终端里跑 git 是同一条路。
    ///
    /// - Parameter tool: nil 表示用户配的默认工具。
    public func launchDiffTool(
        path: String,
        tool: String? = nil,
        in repository: URL
    ) async throws {
        var arguments = ["difftool"]
        // `-y` 不能省。不带它 git 会对每个文件在 stdin 上问
        // `Launch 'xxx' [Y/n]?` 并一直等下去——从 GUI 调起就是永久挂死，
        // 而且那个提问根本没人看得到。
        arguments.append("-y")
        if let tool { arguments += ["--tool", tool] }
        arguments += ["--", path]

        _ = try await runReturningResult(
            arguments,
            in: repository,
            allowsOptionalLocks: false,
            // 用户可能盯着工具看很久，不设超时
            timeout: nil
        )
    }

    /// 用外部工具解决某个文件的冲突。
    public func launchMergeTool(
        path: String,
        tool: String? = nil,
        in repository: URL
    ) async throws {
        var arguments = ["mergetool", "--no-prompt"]
        if let tool { arguments += ["--tool", tool] }
        arguments += ["--", path]

        _ = try await runReturningResult(
            arguments, in: repository, allowsOptionalLocks: false, timeout: nil)
    }
}
