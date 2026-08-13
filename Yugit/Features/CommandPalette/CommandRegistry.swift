import GitKit
import SwiftUI

/// 把当前仓库状态翻译成一组可执行的命令。
///
/// 命令的文案与等价 git 命令都直接取自 ``GitOperation`` 的元数据——
/// 这正是把元数据长在操作上（而不是散落在各个按钮旁）换来的好处：
/// 面板、时间线、教学提示三处显示的说明天然一致。
@MainActor
enum CommandRegistry {

    static func commands(
        for repository: RepositoryViewModel,
        aiSettings: AISettingsStore,
        showSearch: @escaping () -> Void,
        showTimeline: @escaping () -> Void,
        showRebase: @escaping () -> Void,
        showCompose: @escaping () -> Void,
        closeRepository: @escaping () -> Void
    ) -> [PaletteCommand] {
        var commands: [PaletteCommand] = []

        // MARK: AI

        // 没配 AI 就不出现在面板里，和界面上其他 AI 入口保持一致
        if aiSettings.isAvailable {
            commands.append(
                PaletteCommand(
                    id: "ai.commitMessage",
                    title: "AI 起草提交信息",
                    subtitle: repository.stagedEntries.isEmpty
                        ? "先暂存一些改动" : "根据暂存的 \(repository.stagedEntries.count) 个文件起草",
                    systemImage: "sparkles",
                    isEnabled: !repository.stagedEntries.isEmpty && !repository.aiState.isRunning
                ) {
                    Task { await repository.generateCommitMessage(using: aiSettings) }
                })
        }

        commands.append(
            PaletteCommand(
                id: "ai.compose",
                title: "拆分提交",
                subtitle: "按意图把混在一起的改动分成几次提交",
                systemImage: "square.stack.3d.up",
                isEnabled: repository.hasChanges,
                run: showCompose
            ))

        // MARK: 暂存与提交

        let unstaged = repository.unstagedEntries.map(\.path)
        commands.append(
            PaletteCommand(
                id: "stage.all",
                title: "暂存全部改动",
                subtitle: unstaged.isEmpty ? "没有待暂存的改动" : "\(unstaged.count) 个文件",
                equivalentCommand: GitOperation.stage(paths: ["."]).equivalentCommand,
                systemImage: "plus.circle",
                isEnabled: !unstaged.isEmpty
            ) {
                Task { await repository.stage(unstaged) }
            })

        let staged = repository.stagedEntries.map(\.path)
        commands.append(
            PaletteCommand(
                id: "unstage.all",
                title: "取消暂存全部",
                subtitle: staged.isEmpty ? "暂存区是空的" : "\(staged.count) 个文件",
                equivalentCommand: GitOperation.unstage(paths: ["."]).equivalentCommand,
                systemImage: "minus.circle",
                isEnabled: !staged.isEmpty
            ) {
                Task { await repository.unstage(staged) }
            })

        commands.append(
            PaletteCommand(
                id: "stash.push",
                title: "把改动收进 stash",
                subtitle: "工作区恢复干净，改动稍后可取回",
                equivalentCommand: GitOperation.stashPush(includingUntracked: true).equivalentCommand,
                systemImage: "tray.and.arrow.down",
                isEnabled: repository.hasChanges
            ) {
                Task {
                    await repository.mutate {
                        try await repository.repository.perform(
                            .stashPush(includingUntracked: true))
                    }
                }
            })

        commands.append(
            PaletteCommand(
                id: "stash.pop",
                title: "取回最近一次 stash",
                equivalentCommand: GitOperation.stashPop().equivalentCommand,
                systemImage: "tray.and.arrow.up"
            ) {
                Task {
                    await repository.mutate {
                        try await repository.repository.perform(.stashPop())
                    }
                }
            })

        // MARK: 远程

        commands.append(
            PaletteCommand(
                id: "remote.fetch",
                title: "获取远程更新",
                subtitle: "只拉取引用与对象，不改动工作区",
                equivalentCommand: "git fetch --prune --tags --all",
                systemImage: "arrow.down.circle",
                isEnabled: !repository.isTransferring
            ) {
                Task { await repository.fetch() }
            })

        commands.append(
            PaletteCommand(
                id: "remote.pull",
                title: "拉取并合并",
                equivalentCommand: "git pull",
                systemImage: "arrow.down.to.line",
                isEnabled: !repository.isTransferring
            ) {
                Task { await repository.pull() }
            })

        commands.append(
            PaletteCommand(
                id: "remote.pull.rebase",
                title: "拉取并变基",
                subtitle: "用 rebase 代替 merge，历史更线性",
                equivalentCommand: "git pull --rebase",
                systemImage: "arrow.triangle.pull",
                isEnabled: !repository.isTransferring
            ) {
                Task { await repository.pull(rebase: true) }
            })

        commands.append(
            PaletteCommand(
                id: "remote.push",
                title: repository.needsUpstreamOnPush ? "推送并设置 upstream" : "推送到远程",
                subtitle: repository.needsUpstreamOnPush ? "当前分支还没有 upstream" : nil,
                equivalentCommand: repository.needsUpstreamOnPush
                    ? "git push --set-upstream origin <分支>" : "git push",
                systemImage: "arrow.up.to.line",
                isEnabled: !repository.isTransferring
            ) {
                Task { await repository.push(setUpstream: repository.needsUpstreamOnPush) }
            })

        // MARK: 分支

        for branch in repository.localBranches where !branch.isCurrent {
            commands.append(
                PaletteCommand(
                    id: "branch.switch.\(branch.name)",
                    title: "切换到 \(branch.name)",
                    subtitle: branch.lastCommitSubject,
                    equivalentCommand: GitOperation.switchBranch(to: branch.name).equivalentCommand,
                    systemImage: "arrow.triangle.branch"
                ) {
                    Task { await repository.switchBranch(to: branch.name) }
                })
        }

        for branch in repository.localBranches where !branch.isCurrent {
            commands.append(
                PaletteCommand(
                    id: "branch.merge.\(branch.name)",
                    title: "合并 \(branch.name) 到当前分支",
                    equivalentCommand: GitOperation.merge(branch.name).equivalentCommand,
                    systemImage: "arrow.triangle.merge"
                ) {
                    Task { await repository.merge(branch.name) }
                })
        }

        // MARK: 历史整理

        commands.append(
            PaletteCommand(
                id: "history.rebase",
                title: "整理提交历史",
                subtitle: "重排、合并、丢弃、改写最近的提交",
                equivalentCommand: "git rebase --interactive",
                systemImage: "checklist",
                isEnabled: !repository.hasChanges,
                run: showRebase
            ))

        // MARK: 时间线

        if let undoable = repository.mostRecentUndoableEntry {
            commands.append(
                PaletteCommand(
                    id: "timeline.undo",
                    title: "撤销「\(undoable.summary)」",
                    subtitle: "退回这一步之前的工作区状态",
                    systemImage: "arrow.uturn.backward"
                ) {
                    Task { await repository.undo(undoable) }
                })
        }

        // MARK: 导航

        commands.append(
            PaletteCommand(
                id: "view.search",
                title: "搜索仓库",
                subtitle: "内容、文件名、提交",
                systemImage: "magnifyingglass",
                run: showSearch
            ))

        commands.append(
            PaletteCommand(
                id: "view.timeline",
                title: "打开时间线",
                subtitle: "操作记录与可恢复的时间点",
                systemImage: "clock.arrow.circlepath",
                run: showTimeline
            ))

        commands.append(
            PaletteCommand(
                id: "view.refresh",
                title: "刷新仓库状态",
                systemImage: "arrow.clockwise"
            ) {
                Task { await repository.refresh() }
            })

        commands.append(
            PaletteCommand(
                id: "repo.close",
                title: "关闭仓库",
                systemImage: "xmark.circle",
                run: closeRepository
            ))

        return commands
    }
}
