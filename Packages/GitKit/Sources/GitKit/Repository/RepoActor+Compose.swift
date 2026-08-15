import Foundation

/// 一组要一次提交掉的改动。
public struct CommitBatch: Sendable, Equatable {

    /// 提交信息（标题 + 正文）。
    public let message: String
    /// 每个文件里选中的内容，键是路径。
    ///
    /// 精确到行（``PatchBuilder/Selection/lines(_:)``）是有意义的：hunk 是 git
    /// 排版出来的单位，间隔不到七行的两处改动会被并进同一个 hunk，而它们完全
    /// 可能属于两个提交。见 ``HunkSplitter``。
    public let selection: [String: PatchBuilder.Selection]

    public init(message: String, selection: [String: PatchBuilder.Selection]) {
        self.message = message
        self.selection = selection
    }

    /// 便利入口：整个 hunk 一起选。
    ///
    /// 参数名不叫 `selection`——空字典字面量 `[:]` 在两个重载之间无法消歧，
    /// 编译器会当场报 ambiguous。
    public init(message: String, hunks: [String: Set<Int>]) {
        self.init(message: message, selection: hunks.mapValues { .hunks($0) })
    }

    public var isEmpty: Bool {
        selection.values.allSatisfy(\.isEmpty)
    }

    /// 提交信息的第一行，用来在提示里指认是哪一批。
    var title: String {
        message.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? message
    }
}

/// 分批提交的结果。
public struct BatchCommitResult: Sendable, Equatable {
    /// 成功提交的批次数。
    public let committed: Int
    /// 在第几批上失败（0 起），全部成功则为 nil。
    public let failedAt: Int?
    public let errorMessage: String?
    /// 没有失败、但结果和用户设想的不一样的地方。界面上要照实说——
    /// 「提交了 2 组」而用户明明分了 3 组，不解释一句就是个谜。
    public let notes: [String]

    public var isComplete: Bool { failedAt == nil }

    public init(committed: Int, failedAt: Int?, errorMessage: String?, notes: [String] = []) {
        self.committed = committed
        self.failedAt = failedAt
        self.errorMessage = errorMessage
        self.notes = notes
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
    /// - Note: 不抛错——每一批的失败都写进 ``BatchCommitResult``，
    ///   因为「第 3 批失败了、前 2 批已提交」这个信息比一个异常有用得多。
    public func commitInBatches(_ batches: [CommitBatch]) async -> BatchCommitResult {
        let previous = queueTail

        let work = Task { [self] in
            await previous?.value
            return await runBatches(batches)
        }
        queueTail = Task { _ = await work.value }

        return await work.value
    }

    /// 一批改动落到具体命令上的样子。
    private struct Plan {
        let batch: CommitBatch
        let patches: [String]
        let wholeFiles: [String]
        /// 这一批选的东西已经被前面的批次整份拿走了（未跟踪文件、二进制文件）。
        let wasClaimedEarlier: Bool

        var hasNothingToStage: Bool { patches.isEmpty && wholeFiles.isEmpty }
    }

    private func runBatches(_ batches: [CommitBatch]) async -> BatchCommitResult {
        var committed = 0
        var notes: [String] = []

        // 所有 patch 在动手之前一次性生成完。
        //
        // 这一步不能拖到每批临要提交时再做：hunk 下标是**分组那一刻**算出来的，
        // 而每提交一批 HEAD 就往前走一格，重新取 diff 时前面那些 hunk 已经不在了，
        // 下标全部错位——第二批会选中第三批的内容，或者干脆什么都选不到。
        let plans: [Plan]
        do {
            plans = try await makePlans(for: batches)
        } catch {
            return BatchCommitResult(
                committed: 0, failedAt: 0, errorMessage: "读取改动失败：\(error)")
        }

        for (index, plan) in plans.enumerated() {
            if plan.hasNothingToStage {
                // 整份文件只能进一批，后面那批注定是空的。这不是错误，
                // 但也不能不吭声——用户分了三组只提交了两组，得知道为什么。
                if plan.wasClaimedEarlier {
                    notes.append("第 \(index + 1) 批「\(plan.batch.title)」的文件只能整份提交，已随前面的批次一起进去了")
                    continue
                }
                // 选了文件却一份 patch 都生成不出来，说明那些改动已经不在了
                // （工作区在分组之后被人动过）。静默跳过会让用户以为提交完了。
                guard plan.batch.isEmpty else {
                    return BatchCommitResult(
                        committed: committed,
                        failedAt: index,
                        errorMessage: "第 \(index + 1) 批选中的改动已经不在工作区里了，可能是分组之后文件又被改过",
                        notes: notes
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
                    errorMessage: "第 \(index + 1) 批提交失败：\(error)",
                    notes: notes
                )
            }
        }

        return BatchCommitResult(
            committed: committed, failedAt: nil, errorMessage: nil, notes: notes)
    }

    /// 按当前工作区状态，把每一批翻译成具体的 patch。
    private func makePlans(for batches: [CommitBatch]) async throws -> [Plan] {
        // 同一个文件可能被多批引用，diff 只取一次
        var diffCache: [String: FileDiff] = [:]
        let status = try await client.status(of: root)
        let untracked = Set(status.entries.filter { $0.kind == .untracked }.map(\.path))

        /// 前面几批已经选走的行，按路径记账。同一个 hunk 被拆进两批时，
        /// 后一批的 patch 必须知道前一批已经改过哪些行，否则上下文对不上。
        var appliedLines: [String: [Int: Set<Int>]] = [:]
        /// 整份加进去的文件只能归一批。第二批再要它时暂存区里什么都不会多出来，
        /// 提交会以「没有可提交的内容」失败——那是个查起来很费劲的错。
        var wholeFileClaims = Set<String>()

        var plans: [Plan] = []

        for batch in batches {
            var patches: [String] = []
            var wholeFiles: [String] = []
            var claimedEarlier = false

            for (path, selection) in batch.selection.sorted(by: { $0.key < $1.key })
            where !selection.isEmpty {
                // 未跟踪文件 `git diff` 根本看不见（实测输出为空），只能整份加
                if untracked.contains(path) {
                    if wholeFileClaims.insert(path).inserted {
                        wholeFiles.append(path)
                    } else {
                        claimedEarlier = true
                    }
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
                    if wholeFileClaims.insert(path).inserted {
                        wholeFiles.append(path)
                    } else {
                        claimedEarlier = true
                    }
                    continue
                }

                if let patch = PatchBuilder.patch(
                    for: diff,
                    selecting: selection,
                    direction: .stage,
                    alreadyApplied: appliedLines[path] ?? [:]
                ) {
                    patches.append(patch)
                }

                appliedLines[path, default: [:]].merge(
                    PatchBuilder.selectedLines(of: diff, selecting: selection)
                ) { $0.union($1) }
            }

            plans.append(
                Plan(
                    batch: batch,
                    patches: patches,
                    wholeFiles: wholeFiles,
                    wasClaimedEarlier: claimedEarlier
                ))
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
