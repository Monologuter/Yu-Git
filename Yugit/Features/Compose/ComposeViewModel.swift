import AIKit
import Foundation
import GitKit
import Observation

/// AI Commit Composer 的状态。
///
/// 支柱 2：把混在一起的改动按意图拆成若干个提交。AI 给的是**提议**，
/// 分组权始终在用户手上——可以改标题、可以把某块挪到别的组、可以整组删掉。
@MainActor
@Observable
final class ComposeViewModel: Identifiable {

    /// 一块改动加上它在仓库里的坐标。
    struct Block: Identifiable {
        let hunk: ComposableHunk
        let path: String
        /// 在该文件 ``FileDiff/hunks`` 里的下标。提交时按它生成 patch。
        let hunkIndex: Int

        var id: String { hunk.id }
    }

    /// sheet(item:) 需要一个稳定标识；每次打开都是新实例，用对象身份即可。
    nonisolated let id = UUID()

    private let repository: RepositoryViewModel

    private(set) var blocks: [Block] = []
    private(set) var blocksByID: [String: Block] = [:]

    /// 提议出来的分组，可编辑。
    var commits: [ComposedCommit] = []
    /// 还没归入任何一组的改动。
    var unassigned: [String] = []

    private(set) var isLoading = false
    private(set) var isCommitting = false
    var errorMessage: String?
    /// 脱敏做了什么，如实展示。
    var redactionSummary: String?
    var result: BatchCommitResult?

    init(repository: RepositoryViewModel) {
        self.repository = repository
    }

    // MARK: - 载入

    /// 读取工作区所有未提交的改动，切成块。
    func loadBlocks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var collected: [Block] = []
            var excluded: [String] = []

            for entry in repository.changedPaths {
                let diff = try await repository.diffAgainstHead(for: entry)
                guard !diff.isBinary else { continue }

                // 敏感文件不能进 AI 上下文。但它的改动**仍然存在**，
                // 只是不给 AI 看——界面上会提示，用户可以自己手动提交。
                if ContextRedactor.isSensitive(path: diff.path) {
                    excluded.append(diff.path)
                    continue
                }

                for (index, hunk) in diff.hunks.enumerated() {
                    let text = ([hunk.header] + hunk.lines.map { "\($0.kind.prefix)\($0.text)" })
                        .joined(separator: "\n")
                    let (masked, _) = ContextRedactor.maskSecrets(in: text)

                    collected.append(
                        Block(
                            hunk: ComposableHunk(
                                id: "\(diff.path)#\(index)",
                                path: diff.path,
                                heading: hunk.heading,
                                patchText: masked,
                                addedLines: hunk.lines.count { $0.kind == .addition },
                                deletedLines: hunk.lines.count { $0.kind == .deletion }
                            ),
                            path: diff.path,
                            hunkIndex: index
                        ))
                }
            }

            blocks = collected
            blocksByID = Dictionary(uniqueKeysWithValues: collected.map { ($0.id, $0) })
            unassigned = collected.map(\.id)
            commits = []

            redactionSummary =
                excluded.isEmpty
                ? nil
                : "已排除 \(excluded.count) 个敏感文件，它们的改动仍在工作区，需要手动提交：\(excluded.joined(separator: "、"))"
        } catch {
            errorMessage = "读取改动失败：\(error)"
        }
    }

    // MARK: - 提议

    func propose(using store: AISettingsStore) async {
        guard let (provider, model) = store.makeProvider() else {
            errorMessage = AIError.notConfigured.localizedMessage
            return
        }
        guard !blocks.isEmpty else {
            errorMessage = "工作区没有可以分组的改动"
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            let composer = CommitComposer(provider: provider, model: model)
            let proposal = try await composer.propose(hunks: blocks.map(\.hunk))
            commits = proposal.commits
            unassigned = proposal.unassignedHunkIDs
        } catch let error as AIError {
            errorMessage = "\(error.localizedMessage)\n\(error.suggestion)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    // MARK: - 调整

    /// 把一块改动挪到某一组；`commitID` 为 nil 表示挪回未分配。
    func move(blockID: String, to commitID: UUID?) {
        // 先从所有地方摘掉，再放进目标。一块改动只能在一处，
        // 忘了摘会让它同时出现在两组里，提交时第二次应用必然失败。
        for index in commits.indices {
            commits[index].hunkIDs.removeAll { $0 == blockID }
        }
        unassigned.removeAll { $0 == blockID }

        if let commitID, let index = commits.firstIndex(where: { $0.id == commitID }) {
            commits[index].hunkIDs.append(blockID)
        } else {
            unassigned.append(blockID)
        }

        // 挪空的组留着没意义，但不自动删——用户可能正准备往里放东西
    }

    func addEmptyCommit() {
        commits.append(ComposedCommit(title: "", hunkIDs: []))
    }

    func remove(commitID: UUID) {
        guard let index = commits.firstIndex(where: { $0.id == commitID }) else { return }
        // 组里的改动退回未分配，不能跟着组一起消失
        unassigned.append(contentsOf: commits[index].hunkIDs)
        commits.remove(at: index)
    }

    // MARK: - 校验

    var problems: [String] {
        var found: [String] = []

        let usable = commits.filter { !$0.hunkIDs.isEmpty }
        if usable.isEmpty {
            found.append("还没有任何一组包含改动")
        }
        if usable.contains(where: { $0.title.trimmingCharacters(in: .whitespaces).isEmpty }) {
            found.append("有分组还没有填标题")
        }
        return found
    }

    var canCommit: Bool {
        !isCommitting && problems.isEmpty
    }

    // MARK: - 提交

    func commitAll() async {
        isCommitting = true
        defer { isCommitting = false }
        errorMessage = nil

        let batches = commits.compactMap { commit -> CommitBatch? in
            guard !commit.hunkIDs.isEmpty else { return nil }

            // 把块 ID 还原成「哪个文件的哪几个 hunk」
            var selection: [String: Set<Int>] = [:]
            for id in commit.hunkIDs {
                guard let block = blocksByID[id] else { continue }
                selection[block.path, default: []].insert(block.hunkIndex)
            }
            guard !selection.isEmpty else { return nil }

            return CommitBatch(message: commit.message, hunks: selection)
        }

        result = await repository.commitInBatches(batches)
        await repository.refresh()
        await repository.reloadTimeline()
    }
}
