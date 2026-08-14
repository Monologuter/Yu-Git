import Foundation

// remote 的增删改。
//
// 四个都是改配置，不动任何提交，所以 hazard 一律 `.none`——需要确认的地方
// 由界面用 `confirmationDialog` 处理，和删分支的做法一致。
// 把配置改动也归进 hazard 体系的话，时间线会为每次改 URL 拍一张工作区快照，
// 而那毫无意义。

extension GitOperation {

    /// 加一个远程。
    public static func addRemote(name: String, url: String) -> GitOperation {
        GitOperation(
            kind: .addRemote,
            arguments: ["remote", "add", name, url],
            summary: "添加远程 \(name)",
            explanation: "把 \(url) 记为名叫 \(name) 的远程。这一步只写配置，"
                + "不会去连它——加完之后要 fetch 一次才能看到那边有哪些分支。",
            hazard: .none
        )
    }

    /// 改一个远程的地址。
    public static func setRemoteURL(name: String, url: String) -> GitOperation {
        GitOperation(
            kind: .setRemoteURL,
            arguments: ["remote", "set-url", name, url],
            summary: "把 \(name) 指向 \(url)",
            explanation: "只改地址，\(name) 下已经拉下来的远程分支保持不变。"
                + "常见用途是仓库换了托管平台，或者从 HTTPS 换成 SSH。",
            hazard: .none
        )
    }

    /// 给远程改名。
    public static func renameRemote(from oldName: String, to newName: String) -> GitOperation {
        GitOperation(
            kind: .renameRemote,
            arguments: ["remote", "rename", oldName, newName],
            summary: "把远程 \(oldName) 改名为 \(newName)",
            explanation: "远程跟踪分支会跟着搬家（`\(oldName)/main` 变成 `\(newName)/main`），"
                + "本地分支的 upstream 配置也会一并更新，不需要手动重设。",
            hazard: .none
        )
    }

    /// 删掉一个远程。
    ///
    /// hazard 仍是 `.none`（没有任何提交被删），但**后果比另外三个重**：
    /// 它会连带删掉 `refs/remotes/<name>/*` 下的全部远程跟踪分支。
    /// 那些分支上如果有你没建过本地分支的提交，删完就没有引用指向它们了。
    /// 界面上必须显式确认，说明文案要把这一点讲清楚。
    public static func removeRemote(name: String) -> GitOperation {
        GitOperation(
            kind: .removeRemote,
            arguments: ["remote", "remove", name],
            summary: "删除远程 \(name)",
            explanation: "删掉 \(name) 的配置，**以及 `\(name)/` 下的全部远程跟踪分支**。"
                + "本地分支不受影响，但那些只在远程存在、你从没建过本地分支的提交，"
                + "删完就没有引用指向它们了。重新 `remote add` 再 fetch 一次可以拿回来。",
            hazard: .none
        )
    }
}
