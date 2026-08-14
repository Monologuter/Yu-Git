import AIKit
import GitKit
import SwiftUI

/// AI Commit Composer。
///
/// 写代码时顺手改了三件事，提交时面对 `git add -p` 一块一块回答 y/n，
/// 还得自己记住哪块属于哪个主题——这个面板要替掉的就是那个过程。
struct ComposeView: View {

    @Bindable var model: ComposeViewModel
    let onDismiss: () -> Void

    @Environment(AISettingsStore.self) private var aiSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.isLoading && model.blocks.isEmpty {
                ProgressView("正在读取改动…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.blocks.isEmpty {
                EmptyStateView(
                    "没有可拆分的改动",
                    systemImage: "square.stack.3d.up.slash",
                    description: "工作区是干净的，或者只剩二进制与敏感文件"
                )
            } else {
                content
            }

            Divider()
            footer
        }
        .frame(width: 860, height: 620)
        .task { await model.loadBlocks() }
    }

    // MARK: - 各区块

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("拆分提交")
                    .font(.headline)
                Text("按「做的是哪件事」把改动分组，每组提交一次。AI 给的是草稿，可以随便改。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if aiSettings.isAvailable {
                Button {
                    Task { await model.propose(using: aiSettings) }
                } label: {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(model.commits.isEmpty ? "让 AI 提议分组" : "重新提议", systemImage: "sparkles")
                    }
                }
                .disabled(model.isLoading || model.blocks.isEmpty)
            }
        }
        .padding(12)
    }

    private var content: some View {
        HSplitView {
            // 左：待分配。AI 漏掉的、用户拿出来的，都堆在这里，一眼看得出还剩什么没安排
            unassignedColumn
                .frame(minWidth: 260, idealWidth: 300)

            // 右：分组
            groupsColumn
                .frame(minWidth: 380)
        }
    }

    private var unassignedColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("待分配（\(model.unassigned.count)）")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(10)

            Divider()

            if model.unassigned.isEmpty {
                EmptyStateView(
                    "都安排好了", systemImage: "checkmark.circle",
                    description: "每一块改动都归了组",
                    compact: true
                )
            } else {
                List {
                    ForEach(model.unassigned, id: \.self) { id in
                        if let block = model.blocksByID[id] {
                            BlockRow(block: block, targets: model.commits) { target in
                                model.move(blockID: id, to: target)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var groupsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("分组（\(model.commits.count)）")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("新建分组", action: model.addEmptyCommit)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(10)

            Divider()

            if model.commits.isEmpty {
                EmptyStateView(
                    "还没有分组",
                    systemImage: "square.stack.3d.up",
                    description: aiSettings.isAvailable
                        ? "点右上角让 AI 提议，或者自己新建一组" : "点「新建分组」开始，把左边的改动挪进来",
                    compact: true
                )
            } else {
                List {
                    ForEach($model.commits) { $commit in
                        GroupCard(
                            commit: $commit,
                            blocksByID: model.blocksByID,
                            onRemoveBlock: { id in model.move(blockID: id, to: nil) },
                            onRemoveGroup: { model.remove(commitID: commit.id) }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = model.redactionSummary {
                Label(summary, systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let result = model.result {
                resultLabel(result)
            }

            HStack {
                if !model.unassigned.isEmpty {
                    // 未分配的不会被提交，说清楚免得用户以为全提交了
                    Text("\(model.unassigned.count) 块改动没有分组，会留在工作区")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if model.isCommitting { ProgressView().controlSize(.small) }

                Button("取消") { onDismiss() }
                    .keyboardShortcut(.cancelAction)

                Button(commitButtonTitle) {
                    Task {
                        await model.commitAll()
                        if model.result?.isComplete == true { onDismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canCommit)
            }
        }
        .padding(12)
    }

    private var commitButtonTitle: String {
        let count = model.commits.count { !$0.hunkIDs.isEmpty }
        return count <= 1 ? "提交" : "提交这 \(count) 组"
    }

    @ViewBuilder
    private func resultLabel(_ result: BatchCommitResult) -> some View {
        if result.isComplete {
            Label("已提交 \(result.committed) 组", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            Label(
                result.errorMessage ?? "提交中断",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .textSelection(.enabled)
        }
    }
}

// MARK: - 一块改动

private struct BlockRow: View {

    let block: ComposeViewModel.Block
    let targets: [ComposedCommit]
    let onMove: (UUID?) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(block.path)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.head)

                    HStack(spacing: 6) {
                        if !block.hunk.heading.isEmpty {
                            Text(block.hunk.heading)
                                .lineLimit(1)
                        }
                        Text("+\(block.hunk.addedLines)")
                            .foregroundStyle(.green)
                        Text("−\(block.hunk.deletedLines)")
                            .foregroundStyle(.red)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                // 拖拽在 List 之间不好做得可靠，菜单更直接也更可达（键盘也能操作）
                Menu {
                    ForEach(targets) { target in
                        Button(target.title.isEmpty ? "（未命名分组）" : target.title) {
                            onMove(target.id)
                        }
                    }
                    if targets.isEmpty {
                        Text("还没有分组")
                    }
                } label: {
                    Image(systemName: "arrow.right.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("移到某个分组")
            }

            Button {
                isExpanded.toggle()
            } label: {
                Label(isExpanded ? "收起" : "看看改了什么", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)

            if isExpanded {
                ScrollView(.horizontal) {
                    Text(block.hunk.patchText)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .padding(6)
                .background(Color(nsColor: .underPageBackgroundColor), in: .rect(cornerRadius: 4))
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 一个分组

private struct GroupCard: View {

    @Binding var commit: ComposedCommit
    let blocksByID: [String: ComposeViewModel.Block]
    let onRemoveBlock: (String) -> Void
    let onRemoveGroup: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("提交标题，例如 feat(auth): 登录失败时自动重试", text: $commit.title)
                    .textFieldStyle(.roundedBorder)

                Button(role: .destructive, action: onRemoveGroup) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除这个分组，里面的改动退回待分配")
            }

            // AI 的分组理由只给用户看，不写进提交信息——
            // 要判断分组对不对，得知道它是怎么想的
            if !commit.reason.isEmpty {
                Label(commit.reason, systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            TextField("正文（可选）", text: $commit.body, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)

            if commit.hunkIDs.isEmpty {
                Text("这一组还是空的，从左边挪些改动进来")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(commit.hunkIDs, id: \.self) { id in
                    if let block = blocksByID[id] {
                        HStack(spacing: 6) {
                            Image(systemName: "text.alignleft")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(block.path)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.head)
                            if !block.hunk.heading.isEmpty {
                                Text(block.hunk.heading)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Button {
                                onRemoveBlock(id)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("移回待分配")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}
