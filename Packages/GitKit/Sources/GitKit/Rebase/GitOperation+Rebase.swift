import Foundation

extension GitOperation {

    /// 一次可视化 interactive rebase。
    ///
    /// `arguments` 里放的是**用户在终端敲得出同样效果的那条命令**，而不是驭Git 实际
    /// 跑的那条——实际执行还带着 `GIT_SEQUENCE_EDITOR` 和一个临时 todo 文件，
    /// 把那些原样展示给用户既看不懂也复制不走。透明命令层要的是「这一步等价于什么」，
    /// 不是「这个程序内部怎么实现的」。
    public static func interactiveRebase(
        base: String,
        summary: String,
        backupTag: String?
    ) -> GitOperation {
        // 「会得到新的 commit hash」这句话属于这里，不属于 `.rewritesHistory` 的通用文案：
        // 同一档 hazard 下的 reset 只是挪分支指针，被跳过的提交一个字没改。
        // 把只对某一类成立的话写进通用文案，等于对另一类说了假话。
        var explanation =
            "把 \(base) 之后的提交按你排的顺序重新走一遍，生成新的提交——"
            + "内容可能一样，但它们会得到新的 commit hash。"
        if let backupTag {
            explanation += "原来的历史已经用 tag `\(backupTag)` 标住，随时可以退回去。"
        }

        return GitOperation(
            kind: .interactiveRebase,
            arguments: ["rebase", "--interactive", base],
            summary: summary,
            explanation: explanation,
            hazard: .rewritesHistory
        )
    }
}
