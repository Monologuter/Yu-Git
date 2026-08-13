import Foundation

extension GitClient {

    /// 取单个文件的 diff。
    ///
    /// - Parameters:
    ///   - staged: 为 `true` 时比较 index 与 HEAD（已暂存的改动），否则比较工作区与 index。
    ///   - contextLines: hunk 上下文行数。界面上「展开更多上下文」就是调大这个值。
    public func diff(
        of path: String,
        in repository: URL,
        staged: Bool = false,
        contextLines: Int = 3
    ) async throws -> FileDiff {
        var arguments = ["diff", "--unified=\(contextLines)"]
        if staged {
            arguments.append("--cached")
        }
        arguments += ["--", path]

        let result = try await run(arguments, in: repository, allowsOptionalLocks: false)
        return try DiffParser.parse(result.standardOutput, path: path)
    }

    /// 取未跟踪文件的 diff。
    ///
    /// `git diff` 看不见未跟踪文件，得用 `--no-index` 拿它跟 /dev/null 比。
    /// 这条命令在有差异时以 1 退出——那是预期结果而非错误。
    public func diffForUntrackedFile(
        at path: String,
        in repository: URL,
        contextLines: Int = 3
    ) async throws -> FileDiff {
        let arguments = [
            "diff", "--no-index", "--unified=\(contextLines)", "--", "/dev/null", path,
        ]
        let result = try await runReturningResult(arguments, in: repository, allowsOptionalLocks: false)

        // 退出码 0 = 无差异（空文件），1 = 有差异，其余才是真错误
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw GitError.commandFailed(
                arguments: arguments,
                exitCode: result.exitCode,
                standardError: result.standardErrorText
            )
        }
        return try DiffParser.parse(result.standardOutput, path: path)
    }

    /// 把 patch 应用到 index。
    ///
    /// - Parameter reverse: 反向应用，用于取消暂存。
    /// - Note: 只动 index，不碰工作区——这正是部分暂存需要的语义。
    public func applyToIndex(
        patch: String,
        in repository: URL,
        reverse: Bool = false
    ) async throws {
        var arguments = ["apply", "--cached"]
        if reverse {
            arguments.append("--reverse")
        }
        // 从 stdin 读，避免为临时文件挑位置以及随之而来的清理问题
        arguments.append("-")

        try await run(arguments, in: repository, standardInput: Data(patch.utf8))
    }

    /// 变更文件的增删行数统计。
    ///
    /// 用 `-z`：numstat 的默认输出会对含空格与非 ASCII 的路径加引用转义。
    public func changedLineCounts(
        in repository: URL,
        staged: Bool = false
    ) async throws -> [String: (added: Int, deleted: Int)] {
        var arguments = ["diff", "--numstat", "-z"]
        if staged {
            arguments.append("--cached")
        }

        let result = try await run(arguments, in: repository, allowsOptionalLocks: false)
        var counts: [String: (added: Int, deleted: Int)] = [:]

        // -z 模式下每条记录是 "<added>\t<deleted>\t<path>\0"
        for record in result.standardOutput.split(separator: 0x00, omittingEmptySubsequences: true) {
            let fields = String(decoding: record, as: UTF8.self).split(
                separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            // 二进制文件的增删数是 "-"
            let added = Int(fields[0]) ?? 0
            let deleted = Int(fields[1]) ?? 0
            counts[String(fields[2])] = (added, deleted)
        }
        return counts
    }
}
