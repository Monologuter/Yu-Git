import Foundation
import GitKit

/// 需要呈现给用户的失败信息。
///
/// git 的英文报错对中文用户既看不懂也不知道该干嘛，所以除了「出了什么事」
/// 还要给「下一步做什么」，原始输出折叠起来备查。
struct FailurePresentation: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
    let suggestion: String?
    let details: String?

    /// 从一个错误构造要弹给用户的说明；**取消返回 nil**，不弹。
    ///
    /// 取消不是失败。SwiftUI 的 `.task(id:)` 在 id 变化时会取消上一个任务，
    /// 于是每次换选中的提交或文件，上一条正在跑的 git 命令都会被中断，
    /// `ProcessRunner` 抛出 `CancellationError`。把它当失败弹窗的话，
    /// 用户在列表里连点几下就会收到一串「操作失败 CancellationError()」，
    /// 而实际上什么都没坏。
    ///
    /// 做成 failable init 而不是在每个 catch 里各判一次：调用点全都是
    /// `failure = FailurePresentation(from:)`，而 `failure` 本就是可选的，
    /// 于是这一处改动让所有调用点自动获得正确行为，将来新增的也不会漏。
    init?(from error: Error) {
        guard !error.isCancellation else { return nil }

        if let failure = error as? RemoteFailure {
            title = "远程操作失败"
            message = failure.message
            suggestion = failure.suggestion
            details = failure.rawOutput
        } else if let gitError = error as? GitError {
            title = "操作失败"
            message = Self.summarize(gitError)
            suggestion = nil
            details = "\(gitError)"
        } else {
            title = "操作失败"
            message = "\(error)"
            suggestion = nil
            details = nil
        }
    }

    private static func summarize(_ error: GitError) -> String {
        switch error {
        case let .commandFailed(_, _, standardError):
            // git 的第一行通常就是要害，整段 stderr 留给详情
            let firstLine =
                standardError
                .split(separator: "\n")
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return firstLine.map(String.init) ?? "git 命令执行失败"
        case let .notARepository(path):
            return "\(path) 不是 git 仓库"
        case .executableNotFound:
            return "找不到 git"
        case let .parseFailure(reason, _):
            return "无法解析 git 的输出：\(reason)"
        }
    }
}

// MARK: - 分支

extension RepositoryViewModel {

    func createBranch(named name: String, from startPoint: String? = nil, checkout: Bool = true) async {
        await mutate {
            try await self.repository.perform(
                .createBranch(name: name, startPoint: startPoint, checkout: checkout))
        }
    }

    func switchBranch(to name: String) async {
        await mutate { try await self.repository.perform(.switchBranch(to: name)) }
    }

    func checkout(commit: String) async {
        await mutate { try await self.repository.perform(.checkoutCommit(commit)) }
    }

    func deleteBranch(named name: String, force: Bool = false) async {
        await mutate { try await self.repository.perform(.deleteBranch(name: name, force: force)) }
    }

    func renameBranch(from oldName: String, to newName: String) async {
        await mutate {
            try await self.repository.perform(.renameBranch(from: oldName, to: newName))
        }
    }

    func merge(_ branch: String, noFastForward: Bool = false) async {
        await mutate {
            try await self.repository.perform(.merge(branch, noFastForward: noFastForward))
        }
    }

    // MARK: - 远程

    func fetch() async {
        await transfer { client, root, onProgress in
            try await client.fetch(in: root, onProgress: onProgress)
        }
    }

    func pull(rebase: Bool = false) async {
        await transfer { client, root, onProgress in
            try await client.pull(in: root, rebase: rebase, onProgress: onProgress)
        }
    }

    func push(setUpstream: Bool = false, forceWithLease: Bool = false) async {
        let branchName = currentBranch?.name
        await transfer { client, root, onProgress in
            try await client.push(
                in: root,
                remote: setUpstream ? "origin" : nil,
                branch: setUpstream ? branchName : nil,
                setUpstream: setUpstream,
                forceWithLease: forceWithLease,
                onProgress: onProgress
            )
        }
    }

    /// 当前分支还没有 upstream，首次推送需要带 `--set-upstream`。
    var needsUpstreamOnPush: Bool {
        guard let branch = currentBranch else { return false }
        return branch.upstream == nil
    }
}
