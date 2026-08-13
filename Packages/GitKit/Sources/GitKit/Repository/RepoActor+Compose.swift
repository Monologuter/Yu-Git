import Foundation

/// 一组要一次提交掉的改动。
public struct CommitBatch: Sendable, Equatable {

    /// 提交信息（标题 + 正文）。
    public let message: String
    /// 每个文件里选中的 hunk 下标。键是路径，值是 ``FileDiff/hunks`` 的下标集合。
    public let selection: [String: Set<Int>]

    public init(message: String, selection: [String: Set<Int>]) {
        self.message = message
        self.selection = selection
    }

    public var isEmpty: Bool {
        selection.values.allSatisfy(\.isEmpty)
    }
}

/// 分批提交的结果。
public struct BatchCommitResult: Sendable, Equatable {
    /// 成功提交的批次数。
    public let committed: Int
    /// 在第几批上失败（0 起），全部成功则为 nil。
    public let failedAt: Int?
    public let errorMessage: String?

    public var isComplete: Bool { failedAt == nil }

    public init(committed: Int, failedAt: Int?, errorMessage: String?) {
        self.committed = committed
        self.failedAt = failedAt
        self.errorMessage = errorMessage
    }
}

extension RepoActor {

    /// 按分组逐批提交。
    ///
    /// 支柱 2 的落地。每一批的流程是：清空暂存区 → 只把这一批的 hunk 暂存进去 →
    /// 提交。**清空是必须的**：上一批留下的残留会被下一批一起带走，用户看到的
    /// 分组就成了摆设。
    ///
    /// - Important: 出错就地停下，已经提交的批次**不回滚**。回滚要动已经生成的
    ///   commit，那本身就是改写历史；而停在半路的状态是干净可续的——用户能看到
    ///   哪几批成了、剩下的还在工作区，接着手动处理即可。时间线上每批都有记录。
    public func commitInBatches(_ batches: [CommitBatch]) async throws -> BatchCommitResult {
        let previous = queueTail

        let work = Task { [self] in
            await previous?.value
            return await runBatches(batches)
        }
        queueTail = Task { _ = try? await work.value }

        return try await work.value
    }

    private func runBatches(_ batches: [CommitBatch]) async -> BatchCommitResult {
        var committed = 0

        // 所有 patch 在动手之前一次性生成完。
        //
        // 这一步不能拖到每批临要提交时再做：hunk 下标是**分组那一刻**算出来的，
        // 而每提交一批 HEAD 就往前走一格，重新取 diff 时前面那些 hunk 已经不在了，
        // 下标全部错位——第二批会选中第三批的内容，或者干脆什么都选不到。
        let plans: [(batch: CommitBatch, patches: [String], wholeFiles: [String])]
        do {
            plans = try await makePlans(for: batches)
        } catch {
            return BatchCommitResult(
                committed: 0, failedAt: 0, errorMessage: "读取改动失败：\(error)")
        }

        for (index, plan) in plans.enumerated() {
            // 选了文件却一份 patch 都生成不出来，说明那些改动已经不在了
            // （工作区在分组之后被人动过）。静默跳过会让用户以为提交完了。
            if plan.patches.isEmpty && plan.wholeFiles.isEmpty {
                guard plan.batch.isEmpty else {
                    return BatchCommitResult(
                        committed: committed,
                        failedAt: index,
                        errorMessage: "第 \(index + 1) 批选中的改动已经不在工作区里了，可能是分组之后文件又被改过"
                    )
                }
                continue
            }

            do {
                try await stage(patches: plan.patches, wholeFiles: plan.wholeFiles)
                _ = try await executeRecorded(.commit(message: plan.batch.message))
                committed += 1
            } catch {
                return BatchCommitResult(
                    committed: committed,
                    failedAt: index,
                    errorMessage: "第 \(index + 1) 批提交失败：\(error)"
                )
            }
        }

        return BatchCommitResult(committed: committed, failedAt: nil, errorMessage: nil)
    }

    /// 按当前工作区状态，把每一批翻译成具体的 patch。
    private func makePlans(
        for batches: [CommitBatch]
    ) async throws -> [(batch: CommitBatch, patches: [String], wholeFiles: [String])] {
        // 同一个文件可能被多批引用，diff 只取一次
        var diffCache: [String: FileDiff] = [:]
        let status = try await client.status(of: root)
        let untracked = Set(status.entries.filter { $0.kind == .untracked }.map(\.path))

        var plans: [(batch: CommitBatch, patches: [String], wholeFiles: [String])] = []

        for batch in batches {
            var patches: [String] = []
            var wholeFiles: [String] = []

            for (path, hunkIndices) in batch.selection.sorted(by: { $0.key < $1.key })
            where !hunkIndices.isEmpty {
                // 未跟踪文件 `git diff` 根本看不见，只能整份加
                if untracked.contains(path) {
                    wholeFiles.append(path)
                    continue
                }

                let diff: FileDiff
                if let cached = diffCache[path] {
                    diff = cached
                } else {
                    diff = try await client.diffAgainstHead(of: path, in: root)
                    diffCache[path] = diff
                }

                // 二进制文件没法做部分暂存
                guard !diff.isBinary else {
                    wholeFiles.append(path)
                    continue
                }

                if let patch = PatchBuilder.patch(
                    for: diff,
                    selecting: .hunks(hunkIndices),
                    direction: .stage
                ) {
                    patches.append(patch)
                }
            }

            plans.append((batch, patches, wholeFiles))
        }

        return plans
    }

    /// 让暂存区里**只有**这一批的内容。
    private func stage(patches: [String], wholeFiles: [String]) async throws {
        // 先整体清空。用 `reset` 而不是逐文件 unstage：后者要先知道当前暂存了什么，
        // 多一次查询也多一处会漏的地方。
        _ = try await client.run(["reset", "--quiet"], in: root)

        for path in wholeFiles {
            _ = try await client.run(["add", "--", path], in: root)
        }

        for patch in patches {
            // patch 是对着这一轮开始前的 HEAD 算的，而前面几批已经把 HEAD 往前推了。
            // 只要各批改的位置不重叠，git 会自己按上下文找到新位置（"offset N lines"）；
            // `--recount` 让它容忍 hunk 头里的行数与实际不完全吻合。
            _ = try await client.run(
                ["apply", "--cached", "--recount", "-"],
                in: root,
                standardInput: Data(patch.utf8)
            )
        }
    }
}
