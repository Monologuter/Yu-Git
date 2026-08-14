import Foundation

/// 重放一条提交的结果。cherry-pick 与 revert 共用。
///
/// 冲突**不是失败**，是一个需要人接手的正常中间状态——所以它是返回值里的一种情况，
/// 而不是抛出来的错误。区别体现在界面上：失败弹错误框，冲突把人领到三方合并编辑器。
public enum ReplayOutcome: Sendable, Equatable {
    /// 顺利重放完，已经生成新提交。
    case completed
    /// 停在冲突上，仓库正处于半途状态，等人解决。
    case conflicted(paths: [String])
}

// 挑提交、撤提交、退指针、打标签。
//
// 这四样是每天都要用的基础操作，缺了用户十分钟就退回终端。
// 它们共用同一套骨架（`GitOperation` + hazard + 自动快照 + 危险预警 + 透明命令层），
// 所以放在一个文件里，改一处能顺手看到另外三处。
//
// 中文说明里反复出现同一组对照，因为那正是新手最容易搞混的地方：
// **revert 是「记录下我撤销了它」，reset 是「当它没发生过」。**
// 已经推送出去的提交只能用 revert。

// MARK: - 挑提交与撤提交

extension GitOperation {

    /// 把某条提交的改动重放到当前分支上，生成一条新提交。
    ///
    /// hazard 是 `.none`：它只往历史上加东西，不动任何已有的提交。
    /// 出问题了 `git cherry-pick --abort` 或者删掉新提交就回去了。
    ///
    /// - Note: 冲突时 git 返回退出码 1 并停在半路等人处理，
    ///   那**不是失败**。走 ``RepoActor/performAllowingConflict(_:)`` 执行，
    ///   它会把这种情况识别成一个正常的结果。
    public static func cherryPick(hash: String, subject: String) -> GitOperation {
        GitOperation(
            kind: .cherryPick,
            arguments: ["cherry-pick", hash],
            summary: "挑取提交 \(abbreviate(hash))",
            explanation: "把「\(subject)」这条提交的改动重放到当前分支，生成一条**新的**提交。"
                + "原提交仍留在它自己的分支上，两边各有一份内容相同、hash 不同的提交。"
                + "如果重放时和当前内容冲突，操作会停下来等你解决。",
            hazard: .none
        )
    }

    /// 生成一条反向提交，抵消某条提交的改动。
    ///
    /// hazard 是 `.none`：原提交原封不动留在历史里，只是后面多了一条把它抵消掉的提交。
    /// 这正是它和 reset 的根本区别，也是**已推送的提交唯一安全的撤销方式**。
    public static func revert(hash: String, subject: String) -> GitOperation {
        GitOperation(
            kind: .revert,
            // --no-edit 用 git 自动生成的说明，不打开编辑器。
            // 环境里已经设了 GIT_EDITOR=true 兜底，但依赖环境变量不如把意图写在命令里——
            // 这条命令是要展示给用户、也能被复制到终端里跑的。
            arguments: ["revert", "--no-edit", hash],
            summary: "撤销提交 \(abbreviate(hash))",
            explanation: "生成一条新提交，内容正好是「\(subject)」的反向改动。"
                + "**原提交仍然留在历史里**——revert 记录的是「我撤销了它」，"
                + "而 reset 是「当它没发生过」。已经推送给别人的提交只能用 revert，"
                + "因为改写已推送的历史会让别人手上的版本和你对不上。",
            hazard: .none
        )
    }
}

// MARK: - reset

extension GitOperation {

    /// `reset --soft`：只把分支指针挪走，index 与工作区都不动。
    ///
    /// 三种模式**拆成三个方法而不是一个带参数的**，是为了让调用方在写代码时
    /// 就得想清楚要哪一种。写成 `reset(to:mode:)` 的话，`.hard` 只是参数列表里
    /// 一个不起眼的枚举值，而它和另外两个的后果差着一整个「能不能找回来」。
    public static func resetSoft(to revision: String) -> GitOperation {
        GitOperation(
            kind: .resetSoft,
            arguments: ["reset", "--soft", revision],
            summary: "软重置到 \(abbreviate(revision))",
            explanation: "把当前分支指向 \(abbreviate(revision))，"
                + "**index 和工作区一个字都不改**。被跳过的那些提交里的改动会全部留在暂存区，"
                + "可以重新组织成新的提交。想把几条提交合成一条时用这个。",
            hazard: .rewritesHistory
        )
    }

    /// `reset --mixed`：挪指针并清空 index，工作区内容不变。
    ///
    /// 这是 `git reset` 不带参数时的默认模式。
    public static func resetMixed(to revision: String) -> GitOperation {
        GitOperation(
            kind: .resetMixed,
            arguments: ["reset", "--mixed", revision],
            summary: "混合重置到 \(abbreviate(revision))",
            explanation: "把当前分支指向 \(abbreviate(revision))，并清空暂存区，"
                + "**但工作区里的文件内容不变**。被跳过的提交里的改动会变成未暂存的改动，"
                + "原本就是新增的文件会变回未跟踪状态。这是 `git reset` 的默认模式。",
            hazard: .rewritesHistory
        )
    }

    /// `reset --hard`：挪指针，并把 index 与工作区一并重置。
    ///
    /// **整个 app 最危险的一条命令。** 它是唯一一个会丢掉「从未进过 git 对象库」
    /// 内容的重置模式，而那种内容 reflog 也救不回来——时间线快照是唯一的退路。
    public static func resetHard(to revision: String) -> GitOperation {
        GitOperation(
            kind: .resetHard,
            arguments: ["reset", "--hard", revision],
            summary: "硬重置到 \(abbreviate(revision))",
            // 「未跟踪文件不受影响」是实测出来的，必须说：
            // 不说的话用户会以为新建的文件也没了，从而不敢用；
            // 说反了则更糟——他会以为新文件已经被清掉，转头去别处找。
            explanation: "把当前分支指向 \(abbreviate(revision))，"
                + "**并且用那个提交的内容覆盖暂存区和工作区**。"
                + "所有未提交的改动都会消失。未跟踪的文件不受影响，仍然留在磁盘上。",
            hazard: .discardsUncommittedWork
        )
    }
}

// MARK: - tag

extension GitOperation {

    /// 打一个标签。
    ///
    /// - Parameter message: 给了说明就打**附注 tag**（`-a -m`），否则是轻量 tag。
    ///   两者不是「带不带说明」这么简单：附注 tag 是一个独立的 git 对象，
    ///   带作者和日期，且只有它会被 `git describe` 计入——发版必须用它。
    ///   轻量 tag 只是一个指向提交的引用，适合给自己做临时书签。
    public static func createTag(
        name: String,
        at revision: String? = nil,
        message: String? = nil
    ) -> GitOperation {
        let annotated = !(message ?? "").isEmpty
        var arguments = ["tag"]
        if annotated, let message {
            arguments += ["--annotate", "--message", message]
        }
        arguments.append(name)
        if let revision {
            arguments.append(revision)
        }

        return GitOperation(
            kind: .createTag,
            arguments: arguments,
            summary: "打标签 \(name)",
            explanation: annotated
                ? "在\(revision.map { "提交 \(abbreviate($0))" } ?? "当前 HEAD")上打一个**附注标签**。"
                    + "附注标签是一个独立的 git 对象，带打标签的人、时间和说明，"
                    + "也只有它会被 `git describe` 计入——发版用的就是这种。"
                : "在\(revision.map { "提交 \(abbreviate($0))" } ?? "当前 HEAD")上打一个**轻量标签**。"
                    + "轻量标签只是一个指向该提交的引用，不带任何附加信息，"
                    + "`git describe` 也不会算上它。适合做临时书签；对外发版请填写说明，"
                    + "那样会改打附注标签。",
            hazard: .none
        )
    }

    /// 删掉本地的一个标签。
    ///
    /// hazard 是 `.none`：标签指向的提交不会被删，丢的只是这个名字。
    /// 知道 hash 的话重新打一个就回来了。
    public static func deleteTag(name: String) -> GitOperation {
        GitOperation(
            kind: .deleteTag,
            arguments: ["tag", "--delete", name],
            summary: "删除标签 \(name)",
            explanation: "只删掉本地的这个标签名。它指向的提交不受影响，仍然在历史里。"
                + "如果这个标签已经推送过，远程那边还留着，下次 fetch 会把它拉回来——"
                + "要一并删掉远程的才算真删。",
            hazard: .none
        )
    }

    /// 把一个标签推到远程。
    public static func pushTag(name: String, remote: String = "origin") -> GitOperation {
        GitOperation(
            kind: .pushTag,
            arguments: ["push", remote, "refs/tags/\(name)"],
            summary: "推送标签 \(name)",
            explanation: "把标签 \(name) 推到 \(remote)。"
                + "标签不会跟着 `git push` 自动上去，得单独推一次。",
            hazard: .none
        )
    }

    /// 删掉远程上的一个标签。
    ///
    /// hazard 是 `.rewritesHistory`：这一条**影响的是别人**。
    /// 已经 fetch 过这个标签的人，本地那份不会自动消失，于是同一个标签名
    /// 在不同人手上指向不同的东西——比自己丢个名字麻烦得多。
    public static func deleteRemoteTag(name: String, remote: String = "origin") -> GitOperation {
        GitOperation(
            kind: .deleteRemoteTag,
            arguments: ["push", remote, "--delete", "refs/tags/\(name)"],
            summary: "删除远程标签 \(name)",
            explanation: "从 \(remote) 上删掉标签 \(name)。"
                + "**已经拉取过这个标签的人，本地那一份不会自动消失。**"
                + "如果之后又有人用同一个名字打了别的提交，同一个标签名就会在不同人手上"
                + "指向不同的东西。对外发布过的版本号标签尤其不要删。",
            hazard: .rewritesHistory
        )
    }
}

// MARK: -

/// 把 hash 缩到七位用于展示。不是 hash（如分支名、`HEAD~1`）就原样返回。
///
/// 只按长度和字符集判断，不去问 git：这个函数是给摘要文案用的，
/// 为了一句话去跑一次 `rev-parse --short` 不划算，认错了最坏也只是显示得长一点。
private func abbreviate(_ revision: String) -> String {
    let isHash =
        revision.count >= 7
        && revision.allSatisfy { $0.isHexDigit }
    return isHash ? String(revision.prefix(7)) : revision
}
