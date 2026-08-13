import Foundation

extension GitClient {

    /// 对一个文件做 blame，并判定每一行是人写的还是 AI 参与的。
    ///
    /// 分两步是必须的：`git blame --porcelain` 只给 `summary`（提交标题），
    /// 而 AI 的署名写在提交信息的**正文末尾**（`Co-Authored-By:` 那一行），
    /// blame 输出里根本看不到。所以拿到涉及的 commit 之后还得单独取一次完整信息。
    public func blame(
        path: String,
        in repository: URL,
        revision: String? = nil
    ) async throws -> BlameResult {
        var arguments = ["blame", "--porcelain"]
        if let revision { arguments.append(revision) }
        arguments += ["--", path]

        let result = try await run(arguments, in: repository, allowsOptionalLocks: false)
        let parsed = BlameParser.parse(result.standardOutput, path: path)

        let messages = try await commitMessages(
            for: Array(parsed.commits.keys), in: repository)

        let authorship = parsed.commits.keys.reduce(into: [String: Authorship]()) { result, hash in
            result[hash] = AuthorshipDetector.detect(message: messages[hash] ?? "")
        }

        return BlameResult(
            path: path,
            lines: parsed.lines,
            commits: parsed.commits,
            authorship: authorship
        )
    }

    /// 批量取一组 commit 的完整信息。
    ///
    /// sha 走 stdin 而不是命令行参数：一个改动频繁的文件 blame 出几百个 commit
    /// 很正常，全塞进 argv 会撞上系统的参数长度上限（`E2BIG`）。
    func commitMessages(for hashes: [String], in repository: URL) async throws -> [String: String] {
        guard !hashes.isEmpty else { return [:] }

        // 0x1F 分隔 hash 与正文，0x1E 分隔记录——正文里什么字符都可能有，
        // 换行更是家常便饭，只能用这类控制字符做边界。
        let result = try await run(
            ["show", "--no-patch", "--format=%H%x1f%B%x1e", "--stdin"],
            in: repository,
            standardInput: Data(hashes.joined(separator: "\n").utf8)
        )

        var messages: [String: String] = [:]
        for record in result.standardOutputText.split(separator: "\u{1E}", omittingEmptySubsequences: true) {
            let parts = record.split(separator: "\u{1F}", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let hash = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !hash.isEmpty else { continue }
            messages[hash] = String(parts[1])
        }

        return messages
    }
}
