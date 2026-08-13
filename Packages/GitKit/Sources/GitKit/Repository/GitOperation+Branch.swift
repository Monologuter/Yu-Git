import Foundation

// MARK: - 分支

extension GitOperation {

    /// 新建分支。
    ///
    /// - Parameters:
    ///   - startPoint: 起点，可以是 commit、分支名或 tag。传 nil 表示从当前 HEAD 起。
    ///   - checkout: 建完就切过去。
    public static func createBranch(
        name: String,
        startPoint: String? = nil,
        checkout: Bool = true
    ) -> GitOperation {
        var arguments: [String]
        if checkout {
            // switch -c 比 checkout -b 语义更收敛，不会因为参数写错而意外 detach
            arguments = ["switch", "--create", name]
        } else {
            arguments = ["branch", name]
        }
        if let startPoint {
            arguments.append(startPoint)
        }

        return GitOperation(
            kind: .createBranch,
            arguments: arguments,
            summary: checkout ? "新建并切换到分支 \(name)" : "新建分支 \(name)",
            explanation: startPoint.map { "以 \($0) 为起点新建分支 \(name)。" }
                ?? "从当前 HEAD 新建分支 \(name)。"
                + (checkout ? "工作区随即切换到新分支。" : "当前分支不变。"),
            hazard: .none
        )
    }

    /// 切换分支。
    public static func switchBranch(to name: String) -> GitOperation {
        GitOperation(
            kind: .switchBranch,
            arguments: ["switch", name],
            summary: "切换到分支 \(name)",
            explanation: "把工作区切换到 \(name)。未提交的改动会带过去；"
                + "若与目标分支冲突，git 会拒绝切换而不是覆盖你的改动。",
            hazard: .none
        )
    }

    /// 切换到某个 commit（detached HEAD）。
    public static func checkoutCommit(_ commit: String) -> GitOperation {
        GitOperation(
            kind: .switchBranch,
            arguments: ["switch", "--detach", commit],
            summary: "查看提交 \(commit.prefix(7))",
            explanation: "把工作区切换到这条 commit，HEAD 将处于 detached 状态——"
                + "此时的新提交不属于任何分支，切走之后就很难找回。",
            hazard: .none
        )
    }

    /// 删除分支。
    ///
    /// - Parameter force: 用 `-D` 强删。未合并的分支只能强删，删掉后其独有的提交
    ///   将不被任何引用指向，只能靠 reflog 找回。
    public static func deleteBranch(name: String, force: Bool = false) -> GitOperation {
        var arguments = ["branch", "--delete"]
        if force {
            arguments.append("--force")
        }
        arguments.append(name)

        return GitOperation(
            kind: .deleteBranch,
            arguments: arguments,
            summary: force ? "强制删除分支 \(name)" : "删除分支 \(name)",
            explanation: force
                ? "删除 \(name)，**包括尚未合并的提交**。那些提交将不再被任何引用指向，"
                    + "只能通过 reflog 在有限时间内找回。"
                : "删除已合并的分支 \(name)。若它还有未合并的提交，git 会拒绝并提示。",
            hazard: force ? .rewritesHistory : .none
        )
    }

    /// 重命名分支。
    public static func renameBranch(from oldName: String, to newName: String) -> GitOperation {
        GitOperation(
            kind: .renameBranch,
            arguments: ["branch", "--move", oldName, newName],
            summary: "把分支 \(oldName) 改名为 \(newName)",
            explanation: "只改本地分支名。若它已有 upstream，远程分支不会跟着改名，"
                + "需要另行推送新名字并删除旧的远程分支。",
            hazard: .none
        )
    }

    /// 合并分支到当前分支。
    ///
    /// - Parameter noFastForward: 即使可以快进也强制生成合并提交，保留分支结构。
    public static func merge(_ branch: String, noFastForward: Bool = false) -> GitOperation {
        var arguments = ["merge"]
        if noFastForward {
            arguments.append("--no-ff")
        }
        arguments.append(branch)

        return GitOperation(
            kind: .merge,
            arguments: arguments,
            summary: "合并 \(branch) 到当前分支",
            explanation: noFastForward
                ? "把 \(branch) 合并进来，即使能快进也生成一条合并提交，保留分支的形状。"
                : "把 \(branch) 合并进来。若当前分支没有额外提交，会直接快进而不产生合并提交。"
                    + "存在冲突时合并会中断，等待逐个解决。",
            hazard: .none
        )
    }

    /// 设置分支的 upstream。
    public static func setUpstream(branch: String, to upstream: String) -> GitOperation {
        GitOperation(
            kind: .setUpstream,
            arguments: ["branch", "--set-upstream-to=\(upstream)", branch],
            summary: "把 \(branch) 的 upstream 设为 \(upstream)",
            explanation: "设置之后 \(branch) 就能显示领先/落后多少提交，push 与 pull 也不必再指定远程。",
            hazard: .none
        )
    }
}
