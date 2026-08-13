import Foundation

/// rebase 跑完之后的结果。
public enum RebaseOutcome: Sendable, Equatable {
    /// 全部重放完成。
    case completed
    /// 中途冲突，rebase 停在半路等人处理。
    case conflicted(paths: [String], message: String)
    /// 没跑起来或中途失败，仓库已回到原状。
    case failed(message: String)
}

/// 仓库当前是不是正卡在一次 rebase 中间。
public struct RebaseProgress: Sendable, Equatable {
    /// 已经处理到第几条。
    public let current: Int
    /// 一共几条。
    public let total: Int
    /// 冲突的文件。
    public let conflictedPaths: [String]

    public init(current: Int, total: Int, conflictedPaths: [String]) {
        self.current = current
        self.total = total
        self.conflictedPaths = conflictedPaths
    }
}

extension GitClient {

    /// 备份 tag 的命名空间。
    ///
    /// 用 `refs/tags/yugit-backup/` 而不是普通 tag：普通 tag 会被 `git push --tags`
    /// 推到远程，而这是纯本地的安全网，不该出现在别人的仓库里。
    public static let backupTagPrefix = "yugit-backup"

    // MARK: - 安全网

    /// 在改写历史之前把当前 HEAD 钉一个 tag。
    ///
    /// 计划里把它列为 interactive rebase 的必备安全网，理由是 reflog 虽然也能找回，
    /// 但要用户会写 `git reflog` 加 `git reset --hard HEAD@{n}`——那正是这个客户端
    /// 想让人不必学的东西。一个有名字的 tag，界面上一键就能回去。
    ///
    /// - Parameter label: 出现在 tag 名里的可读标记，通常是操作名。
    /// - Returns: 建好的 tag 名。
    @discardableResult
    public func createBackupTag(
        in repository: URL,
        label: String,
        timestamp: Date = Date()
    ) async throws -> String {
        let stamp = Self.tagTimestampFormatter.string(from: timestamp)
        let sanitized = Self.sanitizeTagComponent(label)
        var name = "\(Self.backupTagPrefix)/\(sanitized)-\(stamp)"

        // 同一秒内连做两次操作会撞名，补个序号
        var suffix = 2
        while try await tagExists(name, in: repository) {
            name = "\(Self.backupTagPrefix)/\(sanitized)-\(stamp)-\(suffix)"
            suffix += 1
            if suffix > 100 { break }
        }

        _ = try await run(["tag", name, "HEAD"], in: repository)
        return name
    }

    /// 列出所有备份 tag，最新在前。
    public func backupTags(in repository: URL) async throws -> [String] {
        let result = try await runReturningResult(
            [
                "for-each-ref", "--format=%(refname:short)", "--sort=-creatordate",
                "refs/tags/\(Self.backupTagPrefix)/*",
            ],
            in: repository
        )
        guard result.isSuccess else { return [] }

        return result.standardOutputText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func tagExists(_ name: String, in repository: URL) async throws -> Bool {
        let result = try await runReturningResult(
            ["rev-parse", "--verify", "--quiet", "refs/tags/\(name)"],
            in: repository
        )
        return result.isSuccess
    }

    // MARK: - 执行

    /// 按计划跑一次 interactive rebase。
    ///
    /// 全程不弹任何编辑器：todo 由 ``RebaseTodo/render(messageFile:)`` 事先生成，
    /// 经 `GIT_SEQUENCE_EDITOR` 直接拷进去。GUI 里弹起 vim 是最糟的失败模式——
    /// 进程挂住、用户看不见、也不知道该按什么。
    public func performInteractiveRebase(
        _ todo: RebaseTodo,
        in repository: URL
    ) async throws -> RebaseOutcome {
        let problems = todo.validate()
        guard problems.isEmpty else {
            return .failed(message: problems.map(\.localizedMessage).joined(separator: "；"))
        }

        // 工作目录放在 .git 里而不是工作区：放工作区会变成一个未跟踪文件，
        // 既弄脏 status，也会被时间线快照拍进去（快照那边踩过同样的坑）。
        let workDirectory = try await GitNamespace.directory(in: repository, client: self)
            .appendingPathComponent("rebase", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        // 先把 reword / squash 的信息落盘，todo 里的 exec 行才有东西可读
        var messagePaths: [String: String] = [:]
        for item in todo.items where item.action.needsMessage {
            guard let message = item.message else { continue }
            let path = workDirectory.appendingPathComponent("msg-\(item.hash)").path
            try message.write(toFile: path, atomically: true, encoding: .utf8)
            messagePaths[item.hash] = path
        }

        let todoPath = workDirectory.appendingPathComponent("todo").path
        let rendered = todo.render(messageFile: { messagePaths[$0.hash] ?? "" })
        try rendered.write(toFile: todoPath, atomically: true, encoding: .utf8)

        let result = try await runReturningResult(
            ["rebase", "--interactive", todo.base],
            in: repository,
            additionalEnvironment: [
                // git 会把 todo 文件路径作为参数传给这个命令，cp 正好是「用我的内容覆盖它」
                "GIT_SEQUENCE_EDITOR": "cp \(shellQuote(todoPath))",
                // 万一还有别的地方要调编辑器（例如 merge 提交信息），直接接受默认值，
                // 绝不能让 GUI 卡在一个看不见的编辑器上
                "GIT_EDITOR": "true",
            ]
        )

        if result.isSuccess { return .completed }

        // 失败分两种：卡在冲突上（rebase 还在进行中，可以继续或放弃），
        // 以及压根没跑起来（仓库还是原样）。给用户的下一步完全不同。
        if let progress = try await rebaseProgress(in: repository) {
            return .conflicted(
                paths: progress.conflictedPaths,
                message: result.standardErrorText.isEmpty
                    ? "重放提交时发生冲突" : result.standardErrorText
            )
        }

        return .failed(
            message: result.standardErrorText.isEmpty
                ? result.standardOutputText : result.standardErrorText)
    }

    /// 仓库是否正卡在一次 rebase 中间，卡在哪一步。
    public func rebaseProgress(in repository: URL) async throws -> RebaseProgress? {
        // rebase 状态目录在每个 worktree 自己的 git dir 下，所以这里用 --git-dir
        // 而不是 --git-common-dir：两个 worktree 各自可以有各自进行中的 rebase。
        let raw = try await run(["rev-parse", "--git-dir"], in: repository)
            .standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let gitDirectory =
            raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw, isDirectory: true)
            : repository.appendingPathComponent(raw, isDirectory: true)

        let fileManager = FileManager.default

        // interactive rebase 用 rebase-merge，老式的 rebase 用 rebase-apply
        let candidates = [
            gitDirectory.appendingPathComponent("rebase-merge", isDirectory: true),
            gitDirectory.appendingPathComponent("rebase-apply", isDirectory: true),
        ]
        guard let directory = candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
        else { return nil }

        func number(in file: String) -> Int {
            let path = directory.appendingPathComponent(file).path
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return 0 }
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }

        let status = try await status(of: repository)
        return RebaseProgress(
            current: number(in: "msgnum"),
            total: number(in: "end"),
            conflictedPaths: status.entries.filter { $0.kind == .unmerged }.map(\.path)
        )
    }

    // MARK: - 收尾

    /// 放弃这次 rebase，仓库回到开始之前。
    public func abortRebase(in repository: URL) async throws {
        _ = try await run(["rebase", "--abort"], in: repository)
    }

    /// 冲突处理完后继续。
    public func continueRebase(in repository: URL) async throws -> RebaseOutcome {
        let result = try await runReturningResult(
            ["rebase", "--continue"],
            in: repository,
            additionalEnvironment: ["GIT_EDITOR": "true"]
        )

        if result.isSuccess { return .completed }

        if let progress = try await rebaseProgress(in: repository) {
            return .conflicted(paths: progress.conflictedPaths, message: result.standardErrorText)
        }
        return .failed(message: result.standardErrorText)
    }

    /// 跳过当前这条继续。
    public func skipRebaseCommit(in repository: URL) async throws -> RebaseOutcome {
        let result = try await runReturningResult(
            ["rebase", "--skip"],
            in: repository,
            additionalEnvironment: ["GIT_EDITOR": "true"]
        )

        if result.isSuccess { return .completed }
        if let progress = try await rebaseProgress(in: repository) {
            return .conflicted(paths: progress.conflictedPaths, message: result.standardErrorText)
        }
        return .failed(message: result.standardErrorText)
    }

    // MARK: - 内部

    private static let tagTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // tag 名里不能有冒号，所以不用 ISO8601 的时间格式
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    /// 把任意文案压成合法的 ref 名片段。
    ///
    /// git 的 ref 命名规则很细（不能有空格、`~^:?*[`、连续的点、结尾的点等），
    /// 与其逐条对照，不如只放行确定安全的字符。
    static func sanitizeTagComponent(_ text: String) -> String {
        let allowed = text.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "backup" : String(collapsed.prefix(40))
    }

    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
