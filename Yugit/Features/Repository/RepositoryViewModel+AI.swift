import AIKit
import Foundation
import GitKit

extension RepositoryViewModel {

    /// AI 生成提交信息的状态。
    struct AIGenerationState {
        var isRunning = false
        /// 脱敏做了什么，生成结束后仍然显示——用户有权知道 AI 看到了什么、没看到什么。
        var redactionSummary: String?
        var errorMessage: String?
    }

    // MARK: - 生成提交信息

    /// 用 AI 起草提交信息，逐字写进提交框。
    ///
    /// 写进去的是**草稿**：可以接着改、可以整段删掉重写。这是 PRD 的 AI 铁律——
    /// AI 给建议，用户下结论。
    func generateCommitMessage(using store: AISettingsStore) async {
        guard let (provider, model) = store.makeProvider() else {
            aiState.errorMessage = AIError.notConfigured.localizedMessage
            return
        }

        aiState = AIGenerationState(isRunning: true)
        defer { aiState.isRunning = false }

        do {
            let input = try await makeCommitMessageInput()
            let generator = CommitMessageGenerator(provider: provider, model: model)
            let stream = try generator.generate(input)

            aiState.redactionSummary = stream.redaction.summary

            // 从空白开始写：接着已有内容续写只会拼出一段谁也不想要的东西
            commitMessage = ""
            for try await delta in stream.text {
                commitMessage += delta
            }
            commitMessage = CommitMessageGenerator.sanitize(commitMessage)
        } catch let error as AIError {
            aiState.errorMessage = "\(error.localizedMessage)\n\(error.suggestion)"
        } catch {
            aiState.errorMessage = "\(error)"
        }
    }

    /// 收集生成所需的上下文。
    private func makeCommitMessageInput() async throws -> CommitMessageGenerator.Input {
        let diff = try await repository.client.runReturningResult(
            ["diff", "--cached"],
            in: repository.root
        ).standardOutputText

        // 让 AI 沿用这个仓库既有的书写风格，比让它套一个通用模板贴切得多
        let recent = (try? await repository.client.recentSubjects(in: repository.root, limit: 5)) ?? []

        return CommitMessageGenerator.Input(
            stagedDiff: diff,
            stagedPaths: stagedEntries.map(\.path),
            branchName: currentBranch?.name,
            recentSubjects: recent
        )
    }

    // MARK: - 中文解释

    /// 组装一次 commit 的解释请求。
    func explainSubject(for commit: Commit) async throws -> Explainer.Subject {
        // --no-color 防止 ANSI 转义序列混进上下文白占 token；
        // 根提交没有父提交，git show 会自然处理这种情况
        let diff = try await repository.client.runReturningResult(
            ["show", "--patch", "--no-color", "--format=", commit.hash],
            in: repository.root
        ).standardOutputText

        return .commit(
            subject: commit.subject,
            author: commit.author.name,
            date: commit.author.date.formatted(date: .abbreviated, time: .shortened),
            diff: diff
        )
    }

    /// 组装当前选中文件的改动解释请求。
    func explainSubject(for selection: FileSelection) async throws -> Explainer.Subject {
        var arguments = ["diff", "--no-color"]
        if selection.isStaged { arguments.append("--cached") }
        arguments += ["--", selection.path]

        let diff = try await repository.client.runReturningResult(
            arguments, in: repository.root
        ).standardOutputText

        return .diff(diff)
    }
}

extension RepositoryViewModel {

    /// 有未提交改动的文件路径（已暂存的和未暂存的都算）。
    var changedPaths: [String] {
        var seen = Set<String>()
        return (stagedEntries + unstagedEntries)
            .map(\.path)
            .filter { seen.insert($0).inserted }
    }

    /// 还没被 git 跟踪的文件。
    ///
    /// `git diff HEAD` 看不见它们（实测输出为空），凡是靠 diff 取内容的地方
    /// 都得先把它们挑出来单独处理，否则新加的文件会整个消失。
    var untrackedPaths: Set<String> {
        Set(status?.entries.filter { $0.kind == .untracked }.map(\.path) ?? [])
    }

    /// 某个文件相对 HEAD 的全部改动。
    func diffAgainstHead(for path: String) async throws -> FileDiff {
        try await repository.client.diffAgainstHead(of: path, in: repository.root)
    }

    /// 未跟踪文件的内容，拿它跟 /dev/null 比出来。
    func diffForUntrackedFile(at path: String) async throws -> FileDiff {
        try await repository.client.diffForUntrackedFile(at: path, in: repository.root)
    }

    /// 按分组逐批提交。
    func commitInBatches(_ batches: [CommitBatch]) async -> BatchCommitResult {
        await repository.commitInBatches(batches)
    }
}

extension RepositoryViewModel {

    // MARK: - 冲突

    func conflictedPaths() async throws -> [String] {
        try await repository.client.conflictedPaths(in: repository.root)
    }

    func conflictedFile(at path: String) async throws -> ConflictedFile {
        try await repository.client.conflictedFile(at: path, in: repository.root)
    }

    func resolveConflict(at path: String, content: String) async throws {
        try await repository.client.resolveConflict(
            at: path, content: content, in: repository.root)
    }
}

extension RepositoryViewModel {

    /// 暂存区的完整 diff。评审看的是**将要提交的内容**，不是工作区里的一切。
    func stagedDiff() async throws -> String {
        try await repository.client.runReturningResult(
            ["diff", "--cached", "--no-color"], in: repository.root
        ).standardOutputText
    }
}

extension RepositoryViewModel {

    // MARK: - Worktree

    var rootURL: URL { repository.root }

    func worktreeStatuses(comparedTo baseline: String) async throws -> [WorktreeStatus] {
        try await repository.client.worktreeStatuses(in: repository.root, comparedTo: baseline)
    }

    func addWorktree(at path: URL, branch: String, createBranch: Bool) async throws {
        try await repository.client.addWorktree(
            at: path, branch: branch, createBranch: createBranch, in: repository.root)
    }

    func removeWorktree(at path: String, force: Bool) async throws {
        try await repository.client.removeWorktree(at: path, force: force, in: repository.root)
    }

    func pruneWorktrees() async throws {
        try await repository.client.pruneWorktrees(in: repository.root)
    }
}

extension RepositoryViewModel {

    /// 逐行追溯出处，并判定人写还是 AI 参与。
    func blame(path: String) async throws -> BlameResult {
        try await repository.client.blame(path: path, in: repository.root)
    }
}

extension RepositoryViewModel {

    /// origin 远程的 URL。认平台用。
    func originURL() async -> String? {
        let result = try? await repository.client.runReturningResult(
            ["remote", "get-url", "origin"], in: repository.root)
        guard let result, result.isSuccess else { return nil }

        let url = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }
}
