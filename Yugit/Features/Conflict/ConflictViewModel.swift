import AIKit
import Foundation
import GitKit
import Observation

/// 内置三方合并编辑器的状态。
///
/// 支柱 4。终端里解冲突最难的不是操作，而是**看不懂对方为什么这么改**——
/// 于是要么全要自己的、要么全要对方的，两种都会丢东西。
/// 这里把三方并排摆出来，再让 AI 把「双方各改了什么」讲成中文。
@MainActor
@Observable
final class ConflictViewModel: Identifiable {

    /// 一处冲突的当前处理状态。
    struct BlockState {
        /// 用户最终采纳的内容。nil 表示还没处理。
        var resolvedLines: [String]?
        /// AI 的建议。
        var suggestion: ConflictSuggestion?
        var isSuggesting = false
        var errorMessage: String?

        var isResolved: Bool { resolvedLines != nil }
    }

    nonisolated let id = UUID()

    private let repository: RepositoryViewModel

    private(set) var paths: [String] = []
    var selectedPath: String?

    private(set) var file: ConflictedFile?
    private(set) var states: [Int: BlockState] = [:]

    private(set) var isLoading = false
    var errorMessage: String?

    init(repository: RepositoryViewModel) {
        self.repository = repository
    }

    // MARK: - 载入

    func loadPaths() async {
        do {
            paths = try await repository.conflictedPaths()
            if selectedPath == nil || !paths.contains(selectedPath ?? "") {
                selectedPath = paths.first
            }
            await loadSelectedFile()
        } catch {
            errorMessage = "读取冲突列表失败：\(error)"
        }
    }

    func loadSelectedFile() async {
        guard let path = selectedPath else {
            file = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            file = try await repository.conflictedFile(at: path)
            // 换文件就重置状态：块 id 是按文件内序号编的，跨文件复用会张冠李戴
            states = [:]

            // 双方内容一样的块直接判定，不必浪费用户一次点击
            for block in file?.blocks ?? [] where block.isTrivial {
                states[block.id] = BlockState(resolvedLines: block.ours)
            }
        } catch {
            errorMessage = "读取 \(path) 失败：\(error)"
        }
    }

    // MARK: - 采纳

    func take(_ choice: Choice, for block: ConflictBlock) {
        var state = states[block.id] ?? BlockState()
        state.resolvedLines =
            switch choice {
            case .ours: block.ours
            case .theirs: block.theirs
            // 我方在前是 git 自己的顺序，跟 `git checkout --ours` 的语义一致
            case .both: block.ours + block.theirs
            case .neither: []
            case .suggestion: state.suggestion?.resolvedLines ?? []
            }
        states[block.id] = state
    }

    enum Choice {
        case ours
        case theirs
        case both
        case neither
        case suggestion
    }

    /// 手工编辑某一块的结果。
    func setResolution(_ lines: [String], for blockID: Int) {
        var state = states[blockID] ?? BlockState()
        state.resolvedLines = lines
        states[blockID] = state
    }

    /// 撤回对某一块的处理，回到未解决。
    func reset(blockID: Int) {
        states[blockID]?.resolvedLines = nil
    }

    // MARK: - AI 建议

    func suggest(for block: ConflictBlock, using store: AISettingsStore) async {
        guard let (provider, model) = store.makeProvider() else {
            states[block.id, default: BlockState()].errorMessage =
                AIError.notConfigured.localizedMessage
            return
        }
        guard let file, let path = selectedPath else { return }

        var state = states[block.id] ?? BlockState()
        state.isSuggesting = true
        state.errorMessage = nil
        states[block.id] = state

        defer { states[block.id]?.isSuggesting = false }

        do {
            let resolver = ConflictResolver(provider: provider, model: model)
            let suggestion = try await resolver.suggest(
                for: ConflictContext(
                    path: path,
                    index: block.id,
                    ours: block.ours,
                    theirs: block.theirs,
                    base: block.base,
                    contextBefore: Self.context(before: block.id, in: file),
                    contextAfter: Self.context(after: block.id, in: file)
                ))
            states[block.id]?.suggestion = suggestion
        } catch let error as AIError {
            states[block.id]?.errorMessage = "\(error.localizedMessage)\n\(error.suggestion)"
        } catch {
            states[block.id]?.errorMessage = "\(error)"
        }
    }

    /// 给所有还没处理的块一次性要建议。
    func suggestAll(using store: AISettingsStore) async {
        guard let file else { return }
        for block in file.blocks where !(states[block.id]?.isResolved ?? false) {
            await suggest(for: block, using: store)
        }
    }

    /// 冲突块前后各取几行上下文。
    ///
    /// 只看冲突那几行常常判断不出这段代码在做什么——是函数签名还是配置项，
    /// 差别很大。给的行数刻意有限：整个文件塞进去既费 token 又会稀释重点。
    private static let contextLineCount = 6

    private static func context(before blockID: Int, in file: ConflictedFile) -> [String] {
        guard let index = segmentIndex(of: blockID, in: file), index > 0 else { return [] }
        guard case let .text(lines) = file.segments[index - 1] else { return [] }
        return Array(lines.suffix(contextLineCount))
    }

    private static func context(after blockID: Int, in file: ConflictedFile) -> [String] {
        guard let index = segmentIndex(of: blockID, in: file),
            index + 1 < file.segments.count,
            case let .text(lines) = file.segments[index + 1]
        else { return [] }
        return Array(lines.prefix(contextLineCount))
    }

    private static func segmentIndex(of blockID: Int, in file: ConflictedFile) -> Int? {
        file.segments.firstIndex {
            if case let .conflict(block) = $0 { block.id == blockID } else { false }
        }
    }

    // MARK: - 保存

    var unresolvedCount: Int {
        (file?.blocks ?? []).count { !(states[$0.id]?.isResolved ?? false) }
    }

    var canSave: Bool {
        file?.hasConflicts == true && unresolvedCount == 0
    }

    /// 把结果写回工作区并标记为已解决。
    func save() async -> Bool {
        guard let file, let path = selectedPath else { return false }

        let resolutions = states.compactMapValues(\.resolvedLines)
        let content = ConflictParser.render(file, resolutions: resolutions)

        do {
            try await repository.resolveConflict(at: path, content: content)
            await repository.refresh()
            await loadPaths()
            return true
        } catch {
            errorMessage = "保存失败：\(error)"
            return false
        }
    }

    /// 当前文件在解决后的预览。
    var preview: String {
        guard let file else { return "" }
        return ConflictParser.render(file, resolutions: states.compactMapValues(\.resolvedLines))
    }
}
