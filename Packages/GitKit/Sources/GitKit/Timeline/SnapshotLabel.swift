import Foundation

extension SnapshotStore {

    /// 存标注用的私有 notes 引用。
    ///
    /// 用 `git notes` 而不是自己存一个 JSON：notes 天生就是「给某个 commit 挂一段
    /// 附加文字」的机制，能被 git 正常遍历、gc 时不会丢，也不需要自己处理并发写。
    ///
    /// 走**私有 ref** 而不是默认的 `refs/notes/commits`：后者是用户自己的地盘，
    /// 而且默认会显示在 `git log` 里——把内部标注塞进去，用户的提交历史里
    /// 会平白多出一堆「执行 xxx 之前」。
    static let labelRef = "refs/yugit/timeline-labels"

    /// 给一张快照起个人话名字。
    ///
    /// 存在的理由：默认摘要是「执行「硬重置到 abc1234」之前」，
    /// 而用户三天后想找的是「Claude 大改那次之前」。机器生成的描述准确但不好找。
    ///
    /// - Parameter label: 传空字符串表示去掉标注。
    public func setLabel(_ label: String, for snapshot: Snapshot) async throws {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            // 本来就没有标注时 `notes remove` 会以非零退出，那不是错误
            _ = try? await client.run(
                ["notes", "--ref=\(Self.labelRef)", "remove", snapshot.commit], in: root)
            return
        }

        // `-f` 覆盖已有的。不加的话第二次标注会失败，而「改个名字」是常事。
        try await client.run(
            ["notes", "--ref=\(Self.labelRef)", "add", "-f", "-m", trimmed, snapshot.commit],
            in: root
        )
    }

    /// 读一张快照的标注。没有则返回 nil。
    public func label(for snapshot: Snapshot) async -> String? {
        guard
            let result = try? await client.runReturningResult(
                ["notes", "--ref=\(Self.labelRef)", "show", snapshot.commit],
                in: root,
                allowsOptionalLocks: false
            ),
            result.isSuccess
        else { return nil }

        let text = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// 哪些快照被标注过。
    ///
    /// 一次问完而不是逐张问：时间线一次显示几十条，逐张跑 `notes show`
    /// 就是几十次进程启动。
    public func labelledCommits() async -> Set<String> {
        guard
            let result = try? await client.runReturningResult(
                ["notes", "--ref=\(Self.labelRef)", "list"],
                in: root,
                allowsOptionalLocks: false
            ),
            result.isSuccess
        else { return [] }

        // 每行是 `<注释 blob> <被注释的对象>`
        return Set(
            result.standardOutputText
                .split(separator: "\n", omittingEmptySubsequences: true)
                .compactMap { line in
                    let parts = line.split(separator: " ")
                    return parts.count >= 2 ? String(parts[1]) : nil
                }
        )
    }
}
