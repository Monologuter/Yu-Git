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

    init(from error: Error) {
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
