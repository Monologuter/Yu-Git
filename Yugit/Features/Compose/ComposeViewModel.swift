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
        /// 在该文件 ``FileDiff/hunks`` 里的下标。
        let hunkIndex: Int
        /// 这一段占的改动行下标。空集合表示「整份文件」——
        /// 未跟踪文件 git 没法做部分暂存，只能整个进某一组。
        let lineIndices: Set<Int>

        var id: String { hunk.id }
        var isWholeFile: Bool { lineIndices.isEmpty }
        /// 在文件里的先后，用来把同一组的改动按原顺序拼给 AI 看。
        var position: (Int, Int) { (hunkIndex, lineIndices.min() ?? 0) }
    }

    /// sheet(item:) 需要一个稳定标识；每次打开都是新实例，用对象身份即可。
    nonisolated let id = UUID()

    private let repository: RepositoryViewModel

    private(set) var blocks: [Block] = []
    private(set) var blocksByID: [String: Block] = [:]

    /// 提议出来的分组，可编辑。**数组顺序就是提交顺序。**
    var commits: [ComposedCommit] = []
    /// 还没归入任何一组的改动。
    var unassigned: [String] = []
    /// 排序时值得说明的事，比如依赖成环所以没排。
    private(set) var orderingNote: String?

    /// 每一组各自的评审结果。拆完之后逐个过一遍，比对着一大坨混合改动评审有用得多。
    private(set) var reviews: [UUID: DiffReview] = [:]
    private(set) var reviewErrors: [UUID: String] = [:]

    private(set) var isLoading = false
    private(set) var isReviewing = false
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
    ///
    /// 切到**比 hunk 更细**：hunk 是 git 排版出来的单位，间隔不到七行的两处改动
    /// 会被并进同一个 hunk，而它们完全可能属于两件事。切法见 ``HunkSplitter``。
    func loadBlocks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            var collected: [Block] = []
            var excluded: [String] = []
            let untracked = repository.untrackedPaths

            for path in repository.changedPaths {
                // 敏感文件不能进 AI 上下文。但它的改动**仍然存在**，
                // 只是不给 AI 看——界面上会提示，用户可以自己手动提交。
                if ContextRedactor.isSensitive(path: path) {
                    excluded.append(path)
                    continue
                }

                if untracked.contains(path) {
                    // 未跟踪文件 `git diff HEAD` 根本看不见（实测输出为空）。
                    // 不特殊处理的话，新加的文件在这个面板里完全不存在——
                    // 用户分完组提交完，它们还静静躺在工作区里。
                    let diff = try await repository.diffForUntrackedFile(at: path)
                    guard !diff.isBinary else { continue }
                    if let block = makeWholeFileBlock(from: diff) {
                        collected.append(block)
                    }
                    continue
                }

                let diff = try await repository.diffAgainstHead(for: path)
                guard !diff.isBinary else { continue }
                collected.append(contentsOf: makeSliceBlocks(from: diff))
            }

            blocks = collected
            blocksByID = Dictionary(uniqueKeysWithValues: collected.map { ($0.id, $0) })
            unassigned = collected.map(\.id)
            commits = []
            orderingNote = nil
            reviews = [:]
            reviewErrors = [:]

            redactionSummary =
                excluded.isEmpty
                ? nil
                : "已排除 \(excluded.count) 个敏感文件，它们的改动仍在工作区，需要手动提交：\(excluded.joined(separator: "、"))"
        } catch {
            errorMessage = "读取改动失败：\(error)"
        }
    }

    private func makeSliceBlocks(from diff: FileDiff) -> [Block] {
        HunkSplitter.slices(of: diff).map { slice in
            let (masked, _) = ContextRedactor.maskSecrets(in: slice.text)
            return Block(
                hunk: ComposableHunk(
                    id: "\(diff.path)#\(slice.id)",
                    path: diff.path,
                    heading: slice.heading,
                    patchText: masked,
                    addedLines: slice.addedLines,
                    deletedLines: slice.deletedLines
                ),
                path: diff.path,
                hunkIndex: slice.hunkIndex,
                lineIndices: slice.changedLineIndices
            )
        }
    }

    /// 整份文件一块，给未跟踪文件用。
    private func makeWholeFileBlock(from diff: FileDiff) -> Block? {
        let full = diff.hunks.flatMap { hunk in
            hunk.lines.map { "\($0.kind.prefix)\($0.text)" }
        }
        guard !full.isEmpty else { return nil }

        // 新文件可能有几千行，整个塞进提示词既贵又没必要——
        // 判断它属于哪个提交，看开头这些就够了。
        let limit = 120
        var text = full.prefix(limit).joined(separator: "\n")
        if full.count > limit {
            text += "\n…（新文件共 \(full.count) 行，其余略）"
        }
        let (masked, _) = ContextRedactor.maskSecrets(in: text)

        return Block(
            hunk: ComposableHunk(
                id: "\(diff.path)#新文件",
                path: diff.path,
                heading: "新文件",
                patchText: masked,
                addedLines: full.count
            ),
            path: diff.path,
            hunkIndex: 0,
            lineIndices: []
        )
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
            orderingNote = proposal.orderingNote
            reviews = [:]
            reviewErrors = [:]
        } catch let error as AIError {
            errorMessage = "\(error.localizedMessage)\n\(error.suggestion)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    // MARK: - 逐组评审

    /// 拆完之后每组各自过一遍评审。
    ///
    /// 分开评审比合起来评审有用：混在一起时模型看到的是一堆互不相干的改动，
    /// 只能泛泛而谈；一组只做一件事，它才说得出这件事本身有没有问题。
    func reviewEach(using store: AISettingsStore) async {
        guard let (provider, model) = store.makeProvider() else {
            errorMessage = AIError.notConfigured.localizedMessage
            return
        }

        let targets = commits.filter { !$0.hunkIDs.isEmpty }
        guard !targets.isEmpty else {
            errorMessage = "还没有任何一组包含改动"
            return
        }

        isReviewing = true
        defer { isReviewing = false }
        errorMessage = nil
        reviews = [:]
        reviewErrors = [:]

        let reviewer = DiffReviewer(provider: provider, model: model)
        let jobs = targets.map { (id: $0.id, diff: diffText(for: $0)) }

        // 同时最多跑三个。分组数不确定，一次全发出去可能撞上限流，
        // 而串行等下去五组就是几分钟。
        await withTaskGroup(of: (UUID, Result<DiffReview, any Error>).self) { group in
            var next = 0
            func addTask() {
                guard next < jobs.count else { return }
                let job = jobs[next]
                next += 1
                group.addTask {
                    do {
                        return (job.id, .success(try await reviewer.review(diff: job.diff)))
                    } catch {
                        return (job.id, .failure(error))
                    }
                }
            }

            for _ in 0..<min(3, jobs.count) { addTask() }

            for await (id, outcome) in group {
                switch outcome {
                case let .success(review): reviews[id] = review
                case let .failure(error):
                    reviewErrors[id] = (error as? AIError)?.localizedMessage ?? "\(error)"
                }
                addTask()
            }
        }
    }

    /// 把一组的改动拼成一份可评审的 diff。
    private func diffText(for commit: ComposedCommit) -> String {
        var byPath: [String: [Block]] = [:]
        for id in commit.hunkIDs {
            guard let block = blocksByID[id] else { continue }
            byPath[block.path, default: []].append(block)
        }

        return byPath.sorted { $0.key < $1.key }
            .map { path, blocks in
                let body =
                    blocks
                    .sorted { $0.position < $1.position }
                    .map(\.hunk.patchText)
                    .joined(separator: "\n")
                return """
                    diff --git a/\(path) b/\(path)
                    --- a/\(path)
                    +++ b/\(path)
                    \(body)
                    """
            }
            .joined(separator: "\n")
    }

    // MARK: - 调整

    /// 把一块改动挪到某一组；`commitID` 为 nil 表示挪回未分配。
    func move(blockID: String, to commitID: UUID?) {
        // 先从所有地方摘掉，再放进目标。一块改动只能在一处，
        // 忘了摘会让它同时出现在两组里，提交时第二次应用必然失败。
        for index in commits.indices where commits[index].hunkIDs.contains(blockID) {
            commits[index].hunkIDs.removeAll { $0 == blockID }
            // 内容变了，之前那份评审说的就不是这一组了，留着比没有更误导
            reviews[commits[index].id] = nil
            reviewErrors[commits[index].id] = nil
        }
        unassigned.removeAll { $0 == blockID }

        if let commitID, let index = commits.firstIndex(where: { $0.id == commitID }) {
            commits[index].hunkIDs.append(blockID)
            reviews[commitID] = nil
            reviewErrors[commitID] = nil
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
        reviews[commitID] = nil
        reviewErrors[commitID] = nil

        // 指向它的依赖成了悬空引用，留着只会让顺序检查报一个不存在的问题
        for index in commits.indices {
            commits[index].dependsOn.removeAll { $0 == commitID }
        }
    }

    /// 手动调整提交顺序。
    func moveCommits(fromOffsets source: IndexSet, toOffset destination: Int) {
        commits.move(fromOffsets: source, toOffset: destination)
    }

    /// 某一组必须排在它后面的那几组的标题。
    func dependencyTitles(of commit: ComposedCommit) -> [String] {
        commit.dependsOn.compactMap { id in
            commits.first { $0.id == id }.map { $0.title.isEmpty ? "（未命名分组）" : $0.title }
        }
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

        // 顺序不对的话，中间某个提交是编不过的，将来 bisect 会停在那儿
        var seen = Set<UUID>()
        for commit in commits {
            for dependency in commit.dependsOn where !seen.contains(dependency) {
                guard let title = commits.first(where: { $0.id == dependency })?.title else {
                    continue
                }
                let own = commit.title.isEmpty ? "（未命名分组）" : commit.title
                found.append("「\(own)」排在了它依赖的「\(title)」前面，中间那个提交可能编译不过")
            }
            seen.insert(commit.id)
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

            // 把块 ID 还原成「哪个文件的哪几行」
            var wholeFiles = Set<String>()
            var lines: [String: [Int: Set<Int>]] = [:]
            for id in commit.hunkIDs {
                guard let block = blocksByID[id] else { continue }
                if block.isWholeFile {
                    wholeFiles.insert(block.path)
                } else {
                    lines[block.path, default: [:]][block.hunkIndex, default: []]
                        .formUnion(block.lineIndices)
                }
            }

            var selection: [String: PatchBuilder.Selection] = [:]
            for path in wholeFiles {
                selection[path] = .whole
            }
            for (path, map) in lines where selection[path] == nil {
                selection[path] = .lines(map)
            }
            guard !selection.isEmpty else { return nil }

            return CommitBatch(message: commit.message, selection: selection)
        }

        result = await repository.commitInBatches(batches)
        await repository.refresh()
        await repository.reloadTimeline()
    }
}
