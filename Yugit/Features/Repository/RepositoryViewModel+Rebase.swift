import Foundation
import GitKit

extension RepositoryViewModel {

    /// 为「整理最近 N 条提交」准备一份默认计划。
    ///
    /// 只取当前分支上的提交，且**不越过 upstream**——已经推给别人的提交改写之后
    /// 就得 force push，那是 Git 里最容易把同事的工作弄丢的操作。默认不给这个机会。
    func makeRebasePlan(commitCount: Int) async throws -> RebaseTodo? {
        let available = try await rebaseableCommitCount(limit: commitCount)
        guard available > 0 else { return nil }

        let commits = try await repository.client.log(
            in: repository.root,
            maxCount: available
        )
        guard !commits.isEmpty else { return nil }

        // base 用 HEAD~N 而不是具体 hash：根提交没有父提交，写 hash 会取不到
        return RebaseTodo.fromLogOrder(commits, base: "HEAD~\(commits.count)")
    }

    /// 有多少条提交是可以安全整理的。
    private func rebaseableCommitCount(limit: Int) async throws -> Int {
        let client = repository.client
        let root = repository.root

        // 本地领先 upstream 多少条。没有 upstream 时这条命令会失败，那就退回按总数算。
        let aheadResult = try? await client.runReturningResult(
            ["rev-list", "--count", "@{upstream}..HEAD"], in: root)

        if let aheadResult, aheadResult.isSuccess,
            let ahead = Int(aheadResult.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return min(ahead, limit)
        }

        let totalResult = try await client.runReturningResult(
            ["rev-list", "--count", "HEAD"], in: root)
        guard totalResult.isSuccess,
            let total = Int(totalResult.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return 0 }

        // 留一条作为 base：HEAD~N 要求 N 条之外还有个落脚点
        return min(max(total - 1, 0), limit)
    }

    /// 执行整理。走 ``RepoActor/performRebase(_:summary:)`` 以进时间线。
    func runRebase(_ plan: RebaseTodo, summary: String) async -> RebaseOutcome {
        do {
            let (outcome, backupTag) = try await repository.performRebase(plan, summary: summary)
            lastBackupTag = backupTag
            await refresh()
            await reloadTimeline()
            return outcome
        } catch {
            return .failed(message: "\(error)")
        }
    }

    /// 放弃进行中的 rebase。
    func abortRebase() async {
        try? await repository.client.abortRebase(in: repository.root)
        await refresh()
    }

    /// 冲突处理完后继续。
    @discardableResult
    func continueRebase() async -> RebaseOutcome {
        do {
            let outcome = try await repository.client.continueRebase(in: repository.root)
            await refresh()
            return outcome
        } catch {
            return .failed(message: "\(error)")
        }
    }

    /// 刷新「是否卡在 rebase 中」的状态。
    func reloadRebaseProgress() async {
        rebaseProgress = try? await repository.client.rebaseProgress(in: repository.root)
    }
}
