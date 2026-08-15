import Foundation
import GitKit

/// 驭Git 暴露给 agent 的那组工具。
///
/// 挑选标准是**只给 agent 做不到、或做起来很容易做错的事**。
/// agent 已经能直接跑 `git status`、`git log`——把那些包一层没有任何价值，
/// 还会让工具列表变长、模型选错。
///
/// 真正值得给的是驭Git 独有的那部分：
/// - **打快照**：agent 动手之前留一条退路。这是 Claude Code 的 checkpoint
///   覆盖不到的——它只管自己写的文件，管不了用户同时在编辑器里改的、
///   也管不了终端里跑的 git
/// - **查时间线 / 退回去**：出事之后有据可查、有路可退
/// - **危险预警**：一条 git 命令危不危险、能不能撤，我们有现成的判断
public enum YugitTools {

    /// 造出全部工具。
    ///
    /// - Parameter repository: 要操作的仓库。
    public static func all(for repository: RepoActor) -> [MCPTool] {
        [
            snapshot(repository),
            listTimeline(repository),
            restoreSnapshot(repository),
            explainCommand(repository),
            attribute(repository),
        ]
    }

    // MARK: - 归因

    static func attribute(_ repository: RepoActor) -> MCPTool {
        MCPTool(
            name: "yugit_attribute",
            description: """
                记下某条提交是哪次对话、哪条指令的产物。

                **提交完成之后调用它。** 驭Git 的归因 blame 靠提交信息里的
                `Co-Authored-By` 只能说到「这行是 Claude 写的」——那不够。
                人真正想知道的是「当初为什么这么写」，而那个答案在对话里。
                记下来之后，用户在 blame 上点到这一行就能看到当时的指令。

                只传**这一轮的指令**，不要传整段对话：内容会存进 git，
                跟着仓库跑到任何人手上，而对话里往往有用户的私密信息。
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "commit": .object([
                        "type": .string("string"),
                        "description": .string("提交的 hash，传 HEAD 也可以"),
                    ]),
                    "prompt": .object([
                        "type": .string("string"),
                        "description": .string("用户这一轮说了什么"),
                    ]),
                    "session_id": .object([
                        "type": .string("string"),
                        "description": .string("你的会话标识，用于把同一次对话里的多条提交串起来"),
                    ]),
                    "tool": .object([
                        "type": .string("string"),
                        "description": .string("工具名，例如 Claude Code"),
                    ]),
                ]),
                "required": .array([.string("commit"), .string("prompt")]),
            ])
        ) { arguments in
            guard let commit = arguments["commit"]?.stringValue, !commit.isEmpty else {
                throw ToolError.missingArgument("commit")
            }
            guard let prompt = arguments["prompt"]?.stringValue, !prompt.isEmpty else {
                throw ToolError.missingArgument("prompt")
            }

            let session = AISession(
                tool: arguments["tool"]?.stringValue ?? "未具名的 AI 工具",
                sessionID: arguments["session_id"]?.stringValue ?? "",
                prompt: prompt,
                timestamp: Date()
            )
            let resolved = try await repository.resolve(revision: commit)
            try await repository.client.recordSession(
                session, for: resolved, in: repository.root)

            return "已记下 \(String(resolved.prefix(7))) 的来历。用户在 blame 上点到这些行时会看到它。"
        }
    }

    // MARK: - 打快照

    static func snapshot(_ repository: RepoActor) -> MCPTool {
        MCPTool(
            name: "yugit_snapshot",
            description: """
                给当前工作区拍一张快照，之后可以整个退回来。

                **动手改代码之前调用它。** 这是编辑器与终端都覆盖不到的退路：
                它记的是整个工作区（含未跟踪文件），而不只是你自己写过的那几个文件。
                用户同时在编辑器里改的内容、终端里跑的 git 造成的改动，都在里面。

                起一个说清「这是什么时候」的名字，例如「重构登录模块之前」。
                起过名字的快照不会被自动清理掉。
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "label": .object([
                        "type": .string("string"),
                        "description": .string("这张快照叫什么，例如「重构登录模块之前」"),
                    ])
                ]),
                "required": .array([.string("label")]),
            ])
        ) { arguments in
            guard let label = arguments["label"]?.stringValue, !label.isEmpty else {
                throw ToolError.missingArgument("label")
            }
            guard let snapshot = await repository.captureExternalChange(summary: label) else {
                return "工作区是空的，没有内容需要存。"
            }
            try? await repository.setSnapshotLabel(label, for: snapshot)
            return "已拍下快照「\(label)」（\(String(snapshot.commit.prefix(7)))）。"
                + "要退回这一刻，用 yugit_restore 并传这个 id：\(snapshot.reference)"
        }
    }

    // MARK: - 查时间线

    static func listTimeline(_ repository: RepoActor) -> MCPTool {
        MCPTool(
            name: "yugit_timeline",
            description: """
                列出可以退回的时间点，最近的在前。

                每一条给出 id、时间、说明。要退回其中某一条时，
                把它的 id 传给 yugit_restore。
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("最多列几条，默认 20"),
                    ])
                ]),
            ])
        ) { arguments in
            let limit = arguments["limit"]?.intValue ?? 20
            let snapshots = try await repository.timelineSnapshots()
            guard !snapshots.isEmpty else {
                return "时间线是空的。用 yugit_snapshot 拍一张之后就能退回来了。"
            }

            let labelled = await repository.labelledSnapshots()
            let formatter = ISO8601DateFormatter()
            let lines = snapshots.prefix(limit).map { snapshot -> String in
                let mark = labelled.contains(snapshot.commit) ? "（已命名，不会被自动清理）" : ""
                return "- \(snapshot.reference)｜\(formatter.string(from: snapshot.timestamp))"
                    + "｜\(snapshot.summary)\(mark)"
            }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - 退回去

    static func restoreSnapshot(_ repository: RepoActor) -> MCPTool {
        MCPTool(
            name: "yugit_restore",
            description: """
                把工作区退回到某个时间点。

                **这一步会覆盖当前工作区。** 调用之前先用 yugit_timeline 看清楚
                要退到哪一条，并把 id 原样传进来。

                当前状态会先被自动存成一张新快照，所以退回这个动作本身
                也是可以再退回来的。
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "id": .object([
                        "type": .string("string"),
                        "description": .string("yugit_timeline 给出的那个 id"),
                    ])
                ]),
                "required": .array([.string("id")]),
            ])
        ) { arguments in
            guard let reference = arguments["id"]?.stringValue, !reference.isEmpty else {
                throw ToolError.missingArgument("id")
            }
            let snapshots = try await repository.timelineSnapshots()
            // 按 id 精确找，**不做模糊匹配**：这一步会覆盖工作区，
            // 猜错一条的代价是用户几个小时的活
            guard let target = snapshots.first(where: { $0.reference == reference }) else {
                throw ToolError.notFound(
                    "找不到 id 为 \(reference) 的时间点。先用 yugit_timeline 列一遍。")
            }

            let preview = try await repository.previewRestore(target)
            try await repository.restoreSnapshot(target)
            return "已退回到「\(target.summary)」。"
                + "本次改动了 \(preview.totalCount) 个文件："
                + "删除 \(preview.removed.count)、覆盖 \(preview.overwritten.count)、"
                + "恢复 \(preview.restored.count)。"
        }
    }

    // MARK: - 危险预警

    static func explainCommand(_ repository: RepoActor) -> MCPTool {
        MCPTool(
            name: "yugit_explain",
            description: """
                问一条 git 操作危不危险、能不能撤销。

                在替用户执行破坏性 git 命令之前调用它。返回这条操作会发生什么、
                能不能退回来、以及怎么退——这三个问题正是用户在意的。
                """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "operation": .object([
                        "type": .string("string"),
                        "description": .string(
                            "操作名，取值：reset-hard、reset-mixed、reset-soft、discard、"
                                + "amend、rebase、revert、cherry-pick、stash-drop"),
                    ])
                ]),
                "required": .array([.string("operation")]),
            ])
        ) { arguments in
            guard let name = arguments["operation"]?.stringValue else {
                throw ToolError.missingArgument("operation")
            }
            guard let operation = Self.operation(named: name) else {
                throw ToolError.notFound("不认识的操作：\(name)")
            }

            guard let warning = operation.warning(hasSnapshot: true) else {
                return "「\(operation.summary)」是安全操作，git 自己就能退回来，不需要额外准备。"
            }
            return """
                会发生什么：\(warning.consequence)

                能不能退回来：\(warning.recovery)

                等价命令：\(warning.equivalentCommand)
                """
        }
    }

    /// 把工具参数里的名字映射成真正的操作。
    ///
    /// 用一张固定的表而不是让 agent 传 git 参数：**这个 server 有能力写用户的仓库**，
    /// 让模型自由拼命令行等于把一把没有保险的枪交出去。白名单意味着
    /// 最坏情况也只是执行了表里某一条我们已经理解并加了预警的操作。
    static func operation(named name: String) -> GitOperation? {
        switch name {
        case "reset-hard": .resetHard(to: "HEAD~1")
        case "reset-mixed": .resetMixed(to: "HEAD~1")
        case "reset-soft": .resetSoft(to: "HEAD~1")
        case "discard": .discard(paths: ["<文件>"])
        case "amend": .commit(message: "<信息>", amend: true)
        case "rebase": .interactiveRebase(base: "HEAD~3", summary: "整理提交", backupTag: nil)
        case "revert": .revert(hash: "<hash>", subject: "<标题>")
        case "cherry-pick": .cherryPick(hash: "<hash>", subject: "<标题>")
        case "stash-drop": .stashDrop(index: 0, name: "<储藏>")
        default: nil
        }
    }
}

/// 工具执行失败。
///
/// 这些会被 `MCPServer` 转成带 `isError` 的正常结果而不是协议错误——
/// 模型看得到失败原因，可以自己决定下一步。
public enum ToolError: Error, LocalizedError, Sendable, Equatable {
    case missingArgument(String)
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .missingArgument(let name): "缺少参数：\(name)"
        case .notFound(let message): message
        }
    }
}
