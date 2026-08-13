import Foundation

extension GitClient {

    /// 读取一个冲突文件，**并确保带上共同祖先那一段**。
    ///
    /// 默认的 `merge` 冲突风格只写 ours 和 theirs 两段，看不到共同祖先。
    /// 那样既没法告诉用户「对方到底改了什么」，AI 也只能在两个结果之间瞎猜。
    /// 所以先用 `git checkout --conflict=diff3` 重建一次标记，再读。
    ///
    /// 重建**只影响冲突标记的写法**，不会丢掉已经手工改过的内容吗？会。所以只在
    /// 文件里还没有 base 段时才重建——已经在手工解的文件原样读取。
    public func conflictedFile(at path: String, in repository: URL) async throws -> ConflictedFile {
        let url = repository.appendingPathComponent(path)

        var data = try Data(contentsOf: url)
        var parsed = ConflictParser.parse(data, path: path)

        let needsBase = parsed.hasConflicts && parsed.blocks.allSatisfy { $0.base == nil }
        if needsBase {
            // 重建会覆盖工作区文件，所以只在「还没人动过、且确实缺 base」时做
            let rebuilt = try await runReturningResult(
                ["checkout", "--conflict=diff3", "--", path],
                in: repository
            )
            if rebuilt.isSuccess {
                data = try Data(contentsOf: url)
                parsed = ConflictParser.parse(data, path: path)
            }
        }

        return parsed
    }

    /// 三个 stage 的完整内容：共同祖先、我方、对方。
    ///
    /// 冲突标记只给出冲突那几行，而判断「这块该怎么解」常常要看周围的代码。
    /// 这三份是完整文件，AI 和三方合并编辑器都用得上。
    public func conflictStages(
        at path: String,
        in repository: URL
    ) async throws -> (base: String?, ours: String?, theirs: String?) {
        func stage(_ number: Int) async -> String? {
            let result = try? await runReturningResult(
                ["show", ":\(number):\(path)"], in: repository)
            guard let result, result.isSuccess else { return nil }
            return result.standardOutputText
        }

        // 新增/删除类冲突里某个 stage 可能压根不存在，那是正常的
        return (await stage(1), await stage(2), await stage(3))
    }

    /// 把解决后的内容写回工作区并标记为已解决。
    ///
    /// - Important: 内容里还留着冲突标记时**拒绝执行**。`git add` 不会检查这个，
    ///   带标记的文件照样能提交进去——那种提交一旦推出去，别人拉下来就是一份
    ///   语法都不成立的代码。
    public func resolveConflict(
        at path: String,
        content: String,
        in repository: URL
    ) async throws {
        let parsed = ConflictParser.parse(Data(content.utf8), path: path)
        guard !parsed.hasConflicts else {
            throw GitError.commandFailed(
                arguments: ["add", "--", path],
                exitCode: 1,
                standardError: "内容里还留着冲突标记，先把每一处都处理完再标记为已解决"
            )
        }

        let url = repository.appendingPathComponent(path)
        try Data(content.utf8).write(to: url, options: .atomic)
        _ = try await run(["add", "--", path], in: repository)
    }

    /// 当前所有冲突文件的路径。
    public func conflictedPaths(in repository: URL) async throws -> [String] {
        let status = try await status(of: repository)
        return status.entries.filter { $0.kind == .unmerged }.map(\.path)
    }
}
