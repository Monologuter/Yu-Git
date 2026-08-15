import Foundation
import GitKit

// 挑提交、撤提交、退指针、打标签。
//
// 四样共用一条路径：先校验前提，再走 `RepoActor` 执行，最后刷新。
// cherry-pick 与 revert 多一步——它们可能停在冲突上，那不是失败。

extension RepositoryViewModel {

    /// 上一次挑取/撤销停在了哪些冲突文件上。为空表示当前没有卡住的重放。
    ///
    /// 界面拿它把用户领到三方合并编辑器前面。不复用 `failure`：
    /// 那是给「出错了」用的，而停在冲突上是一个等人接手的正常状态，
    /// 摆一个红色错误框只会让人以为自己搞砸了。
    var replayConflictPaths: [String] { conflictedEntries.map(\.path) }

    /// 把一条提交的改动重放到当前分支。
    func cherryPick(_ commit: Commit) async -> ReplayOutcome? {
        await replay(.cherryPick(hash: commit.hash, subject: commit.subject))
    }

    /// 生成一条反向提交抵消某一条。
    func revert(_ commit: Commit) async -> ReplayOutcome? {
        await replay(.revert(hash: commit.hash, subject: commit.subject))
    }

    private func replay(_ operation: GitOperation) async -> ReplayOutcome? {
        await mutate {
            try await self.repository.performAllowingConflict(operation)
        }
    }

    /// 把当前分支退回到某条提交。
    ///
    /// - Parameter action: 只接受三种 reset。传别的会直接返回。
    func reset(_ commit: Commit, mode action: CommitAction) async {
        guard let operation = action.operation(for: commit), action.requiresAncestorOfHead else {
            return
        }

        // 目标必须在当前分支的历史里。不在的话「重置」这个词会骗人——
        // 实际发生的是把分支搬到另一段历史上去。
        guard await isAncestorOfHead(commit.hash) else {
            failure = FailurePresentation(
                title: "这条提交不在当前分支上",
                message: "「\(commit.subject)」不是当前分支的祖先，重置过去不是「退回到走过的某个点」，"
                    + "而是把分支整个搬到另一段历史上。真要这么做的话，"
                    + "请先切到包含这条提交的分支。"
            )
            return
        }

        await mutate {
            try await self.repository.perform(operation)
        }
    }

    /// 这条提交是不是当前 HEAD 的祖先。
    ///
    /// `--is-ancestor` 用退出码表达结果（0 是、1 不是），所以要用
    /// `runReturningResult`——走 `run` 的话「不是祖先」会被当成命令失败抛出来。
    private func isAncestorOfHead(_ hash: String) async -> Bool {
        let result = try? await repository.client.runReturningResult(
            ["merge-base", "--is-ancestor", hash, "HEAD"],
            in: repository.root
        )
        return result?.isSuccess == true
    }

    // MARK: - tag

    /// 在某条提交上打标签。
    ///
    /// - Parameter message: 非空就打附注标签，空则是轻量标签。区别不只是带不带说明：
    ///   附注标签是独立的 git 对象，也只有它会被 `git describe` 计入。
    func createTag(named name: String, at commit: Commit?, message: String) async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        await mutate {
            try await self.repository.perform(
                .createTag(
                    name: trimmedName,
                    at: commit?.hash,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }
    }

    func deleteTag(named name: String) async {
        await mutate {
            try await self.repository.perform(.deleteTag(name: name))
        }
    }

    func pushTag(named name: String) async {
        await mutate {
            try await self.repository.perform(.pushTag(name: name))
        }
    }

    // MARK: - stash

    func stashEntries() async throws -> [StashEntry] {
        try await repository.client.stashList(in: repository.root)
    }

    func stashFiles(at hash: String) async throws -> [CommitFileChange] {
        try await repository.client.stashFiles(at: hash, in: repository.root)
    }

    /// 应用一条储藏，栈里那份保留。
    func applyStash(_ entry: StashEntry) async {
        await mutate {
            try await self.repository.perform(
                .stashApply(hash: entry.hash, name: entry.displayName))
        }
    }

    /// 取回一条储藏（应用后删除）。
    ///
    /// - Returns: 取回了返回 true；那条已经不在栈里返回 false；出错返回 nil。
    func popStash(_ entry: StashEntry) async -> Bool? {
        await mutate {
            try await self.repository.popStash(hash: entry.hash, name: entry.displayName)
        }
    }

    /// 丢掉一条储藏。
    ///
    /// - Returns: 丢掉了返回 true；那条已经不在栈里返回 false；出错返回 nil。
    func dropStash(_ entry: StashEntry) async -> Bool? {
        await mutate {
            try await self.repository.dropStash(hash: entry.hash, name: entry.displayName)
        }
    }

    // MARK: - remote

    func remoteList() async throws -> [Remote] {
        try await repository.client.remotes(in: repository.root)
    }

    func addRemote(name: String, url: String) async {
        await mutate { try await self.repository.perform(.addRemote(name: name, url: url)) }
    }

    func setRemoteURL(name: String, url: String) async {
        await mutate { try await self.repository.perform(.setRemoteURL(name: name, url: url)) }
    }

    func renameRemote(from oldName: String, to newName: String) async {
        await mutate {
            try await self.repository.perform(.renameRemote(from: oldName, to: newName))
        }
    }

    func removeRemote(named name: String) async {
        await mutate { try await self.repository.perform(.removeRemote(name: name)) }
    }

    // MARK: - 只读查询

    func fileHistory(of path: String, follow: Bool) async throws -> [Commit] {
        try await repository.client.fileHistory(
            of: path, in: repository.root, follow: follow, maxCount: 500)
    }

    func compareBranches(base: String, target: String) async throws -> BranchComparison {
        try await repository.client.compareBranches(
            base: base, target: target, in: repository.root)
    }

    // MARK: - 签名

    func signingSettings() async -> SigningSettings {
        await repository.client.signingSettings(in: repository.root)
    }

    func isGPGAvailable() async -> Bool {
        await repository.client.isGPGAvailable()
    }

    func setConfiguration(key: String, value: String) async {
        await mutate {
            try await self.repository.perform(.setConfiguration(key: key, value: value))
        }
    }

    /// 读一条提交的签名。
    ///
    /// 只在选中某条提交时调用。放进历史列表的格式串会让 git 对每一条都验一次签，
    /// 5 万条的首屏直接崩掉。
    func signature(of hash: String) async -> CommitSignature {
        (try? await repository.client.signature(of: hash, in: repository.root)) ?? .unsigned
    }

    // MARK: - 子模块

    func submodules() async throws -> [Submodule] {
        try await repository.client.submodules(in: repository.root)
    }

    func updateSubmodules(path: String?) async {
        await mutate {
            try await self.repository.perform(.updateSubmodules(path: path))
        }
    }
}
