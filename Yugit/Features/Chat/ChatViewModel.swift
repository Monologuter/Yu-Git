import AIKit
import Foundation
import GitKit
import Observation

/// 对话式 Git 操作。
///
/// 远期规划里的最后一块。三条不可动摇的规矩：
/// 模型只能从白名单里选动作、计划一定先预览、执行走 `RepoActor.perform`
/// 所以每一步都进时间线、都能撤销。
@MainActor
@Observable
final class ChatViewModel: Identifiable {

    nonisolated let id = UUID()

    /// 计划里的一步，已经翻译成可执行的 ``GitOperation``。
    struct ResolvedStep: Identifiable {
        let id: UUID
        let operation: GitOperation
        /// 模型为什么加这一步。
        let reason: String

        var isDestructive: Bool { operation.hazard == .discardsUncommittedWork }
    }

    enum Outcome: Equatable {
        case idle
        case clarification(String)
        case unsupported(String)
        case ready(understanding: String)
        case executed(completed: Int, total: Int)
        case failed(String)
    }

    private let repository: RepositoryViewModel

    var request = ""
    private(set) var steps: [ResolvedStep] = []
    private(set) var outcome: Outcome = .idle
    private(set) var isWorking = false

    init(repository: RepositoryViewModel) {
        self.repository = repository
    }

    // MARK: - 规划

    func plan(using store: AISettingsStore) async {
        guard let (provider, model) = store.makeProvider() else {
            outcome = .failed(AIError.notConfigured.localizedMessage)
            return
        }

        isWorking = true
        defer { isWorking = false }
        steps = []

        do {
            let planner = OperationPlanner(provider: provider, model: model)
            let plan = try await planner.plan(request: request, context: makeContext())

            switch plan {
            case let .needsClarification(question):
                outcome = .clarification(question)
            case let .unsupported(reason):
                outcome = .unsupported(reason)
            case let .plan(understanding, planned):
                // 第二道校验：白名单动作翻译成 GitOperation 时再过一遍参数。
                // AIKit 那边校验的是「模型说的对不对得上仓库状态」，
                // 这里校验的是「翻译出来的东西是不是一条合法的 git 操作」。
                steps = planned.compactMap(Self.resolve)
                outcome =
                    steps.isEmpty
                    ? .unsupported("没有一步能翻译成可执行的操作")
                    : .ready(understanding: understanding)
            }
        } catch let error as AIError {
            outcome = .failed("\(error.localizedMessage)\n\(error.suggestion)")
        } catch {
            outcome = .failed("\(error)")
        }
    }

    /// 把白名单动作翻译成 ``GitOperation``。
    ///
    /// 翻译成 `GitOperation` 而不是拼命令字符串，意味着这些操作和界面上
    /// 手点出来的走的是同一条路：同样排队、同样拍快照、同样进时间线。
    private static func resolve(_ step: PlannedStep) -> ResolvedStep? {
        let operation: GitOperation?

        switch step.action {
        case let .stage(paths):
            operation = paths.isEmpty ? nil : .stage(paths: paths)
        case let .unstage(paths):
            operation = paths.isEmpty ? nil : .unstage(paths: paths)
        case let .commit(message):
            operation = message.isEmpty ? nil : .commit(message: message)
        case let .createBranch(name, from):
            operation = .createBranch(name: name, startPoint: from)
        case let .switchBranch(name):
            operation = .switchBranch(to: name)
        case let .merge(branch):
            operation = .merge(branch)
        case let .stashPush(includingUntracked):
            operation = .stashPush(includingUntracked: includingUntracked)
        case .stashPop:
            operation = .stashPop()
        case let .discard(paths):
            operation = paths.isEmpty ? nil : .discard(paths: paths)
        case .fetch, .pull, .push:
            // 远程操作要走带进度回调的通道，不是一条普通的 GitOperation。
            // 计划里出现它们时单独处理，见 execute()。
            operation = nil
        }

        guard let operation else { return nil }
        return ResolvedStep(id: step.id, operation: operation, reason: step.reason)
    }

    // MARK: - 执行

    /// 计划里是否含会丢东西的步骤。界面上据此加一道确认。
    var hasDestructiveStep: Bool { steps.contains(where: \.isDestructive) }

    var canExecute: Bool { !steps.isEmpty && !isWorking }

    func execute() async {
        isWorking = true
        defer { isWorking = false }

        var completed = 0
        for step in steps {
            do {
                // 走单一写入口：排队、快照、时间线一样不少，所以每一步都能撤销
                try await repository.repository.perform(step.operation)
                completed += 1
            } catch {
                outcome = .failed("第 \(completed + 1) 步「\(step.operation.summary)」失败：\(error)")
                await repository.refresh()
                await repository.reloadTimeline()
                return
            }
        }

        outcome = .executed(completed: completed, total: steps.count)
        steps = []
        await repository.refresh()
        await repository.reloadTimeline()
    }

    func reset() {
        steps = []
        outcome = .idle
        request = ""
    }

    // MARK: - 上下文

    private func makeContext() -> OperationPlanner.Context {
        OperationPlanner.Context(
            currentBranch: repository.currentBranch?.name,
            stagedPaths: repository.stagedEntries.map(\.path),
            unstagedPaths: repository.unstagedEntries.map(\.path),
            localBranches: repository.localBranches.map(\.name),
            hasUpstream: !repository.needsUpstreamOnPush,
            ahead: repository.status?.branch.ahead ?? 0,
            behind: repository.status?.branch.behind ?? 0
        )
    }
}
