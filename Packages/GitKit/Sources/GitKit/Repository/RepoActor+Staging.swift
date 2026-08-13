import Foundation

extension RepoActor {

    /// 暂存文件中选中的部分改动。
    ///
    /// 取 diff、生成 patch 都在写队列之外完成，中途文件若被改动，patch 的上下文就对不上，
    /// `git apply` 会直接拒绝——它自带的这层校验就是安全网，不会写出错误的结果。
    ///
    /// - Returns: 是否真的暂存了内容。没有选中任何改动时返回 `false`。
    @discardableResult
    public func stagePartial(
        path: String,
        selecting selection: PatchBuilder.Selection,
        contextLines: Int = 3
    ) async throws -> Bool {
        let diff = try await client.diff(
            of: path, in: root, staged: false, contextLines: contextLines)
        guard let patch = PatchBuilder.patch(for: diff, selecting: selection, direction: .stage) else {
            return false
        }

        try await perform(
            .stagePartial(path: path, changeCount: changeCount(in: diff, selecting: selection)),
            standardInput: Data(patch.utf8)
        )
        return true
    }

    /// 取消暂存文件中选中的部分改动。
    @discardableResult
    public func unstagePartial(
        path: String,
        selecting selection: PatchBuilder.Selection,
        contextLines: Int = 3
    ) async throws -> Bool {
        let diff = try await client.diff(
            of: path, in: root, staged: true, contextLines: contextLines)
        guard let patch = PatchBuilder.patch(for: diff, selecting: selection, direction: .unstage) else {
            return false
        }

        try await perform(
            .unstagePartial(path: path, changeCount: changeCount(in: diff, selecting: selection)),
            standardInput: Data(patch.utf8)
        )
        return true
    }

    /// 统计选中了多少处改动，用于操作摘要。
    private func changeCount(in diff: FileDiff, selecting selection: PatchBuilder.Selection) -> Int {
        switch selection {
        case .whole:
            return diff.hunks.reduce(0) { $0 + $1.lines.count(where: { $0.kind != .context }) }
        case let .hunks(indices):
            return indices.reduce(0) { total, index in
                guard diff.hunks.indices.contains(index) else { return total }
                return total + diff.hunks[index].lines.count(where: { $0.kind != .context })
            }
        case let .lines(map):
            return map.values.reduce(0) { $0 + $1.count }
        }
    }
}
