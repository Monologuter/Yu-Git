import Foundation

/// 文件内容中的一处匹配。
public struct ContentMatch: Sendable, Equatable, Identifiable {
    public var id: String { "\(path):\(lineNumber)" }

    public let path: String
    public let lineNumber: Int
    /// 匹配所在的整行内容。
    public let line: String

    public init(path: String, lineNumber: Int, line: String) {
        self.path = path
        self.lineNumber = lineNumber
        self.line = line
    }
}

extension GitClient {

    /// 在被 git 跟踪的文件内容里搜索。
    ///
    /// 用 `git grep` 而不是自己遍历目录：它只搜被跟踪的文件，天然跳过 .gitignore
    /// 里的构建产物与依赖目录，在大仓库上快一个数量级。
    ///
    /// - Parameters:
    ///   - query: 按字面匹配，不当正则解释——用户在搜索框里打的 `.` 和 `*` 就是字符本身。
    ///   - limit: 结果上限。即时搜索每敲一个字就重跑一次，不设上限会在大仓库上卡住界面。
    public func searchFileContents(
        _ query: String,
        in repository: URL,
        limit: Int = 200,
        caseSensitive: Bool = false
    ) async throws -> [ContentMatch] {
        guard !query.isEmpty else { return [] }

        var arguments = [
            "grep",
            "--line-number",
            "-z",
            "--fixed-strings",
            "--no-color",
        ]
        if !caseSensitive {
            arguments.append("--ignore-case")
        }
        arguments += ["--", query]

        // grep 没有匹配时以 1 退出，那不是错误
        let result = try await runReturningResult(arguments, in: repository, allowsOptionalLocks: false)
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw GitError.commandFailed(
                arguments: arguments,
                exitCode: result.exitCode,
                standardError: result.standardErrorText
            )
        }

        return parseGrepOutput(result.standardOutput, limit: limit)
    }

    /// `git grep -n -z` 的输出格式是 `路径\0行号\0内容\n`。
    private func parseGrepOutput(_ data: Data, limit: Int) -> [ContentMatch] {
        var matches: [ContentMatch] = []

        // 按字节切行：内容里可能有 \r，用 String.split 会把 \r\n 当成一个 Character
        for record in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard matches.count < limit else { break }

            let fields = record.split(separator: 0x00, maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3,
                let lineNumber = Int(String(decoding: fields[1], as: UTF8.self))
            else {
                continue
            }

            matches.append(
                ContentMatch(
                    path: String(decoding: fields[0], as: UTF8.self),
                    lineNumber: lineNumber,
                    line: String(decoding: fields[2], as: UTF8.self)
                )
            )
        }
        return matches
    }

    /// 按文件名搜索被跟踪的文件。
    public func searchFilePaths(
        _ query: String,
        in repository: URL,
        limit: Int = 200
    ) async throws -> [String] {
        guard !query.isEmpty else { return [] }

        // 一次列全再在内存里过滤：ls-files 很快，而 git 的通配符匹配
        // 不支持「子串出现在路径任意位置」这种最符合直觉的搜法
        let result = try await run(["ls-files", "-z"], in: repository, allowsOptionalLocks: false)
        let lowercasedQuery = query.lowercased()

        var paths: [String] = []
        for record in result.standardOutput.split(separator: 0x00, omittingEmptySubsequences: true) {
            guard paths.count < limit else { break }
            let path = String(decoding: record, as: UTF8.self)
            if path.lowercased().contains(lowercasedQuery) {
                paths.append(path)
            }
        }
        return paths
    }

    /// 搜索提交。
    ///
    /// - Parameter query: 同时匹配提交说明与作者。若它看起来像 commit hash 前缀，
    ///   还会尝试直接定位那条提交。
    public func searchCommits(
        _ query: String,
        in repository: URL,
        limit: Int = 200
    ) async throws -> [Commit] {
        guard !query.isEmpty else { return [] }

        var found: [Commit] = []
        var seen = Set<String>()

        // 看着像 hash 就先按 hash 试一把，用户复制一段 hash 过来就是想直接跳过去
        if query.count >= 4, query.allSatisfy(\.isHexDigit) {
            let direct = try await runReturningResult(
                ["log", "--format=\(LogParser.format)", "--decorate=full", "--max-count=1", query],
                in: repository,
                allowsOptionalLocks: false
            )
            if direct.isSuccess, let commit = try? LogParser.parse(direct.standardOutput).first {
                found.append(commit)
                seen.insert(commit.hash)
            }
        }

        // 说明与作者必须分两次查：git log 把 --grep 与 --author 之间当作「与」，
        // 而用户期望的是「或」——搜一个词，不管它出现在说明里还是作者名里都该命中。
        for criterion in ["--grep=\(query)", "--author=\(query)"] {
            // --all 覆盖所有分支：用户搜提交时并不关心它在哪个分支上
            let arguments = [
                "log",
                "--format=\(LogParser.format)",
                "--decorate=full",
                "--all",
                "--max-count=\(limit)",
                "--regexp-ignore-case",
                "--fixed-strings",
                criterion,
            ]

            let result = try await runReturningResult(
                arguments, in: repository, allowsOptionalLocks: false)
            guard result.isSuccess else { continue }

            for commit in (try? LogParser.parse(result.standardOutput)) ?? []
            where !seen.contains(commit.hash) {
                found.append(commit)
                seen.insert(commit.hash)
            }
        }

        return Array(found.prefix(limit))
    }
}
