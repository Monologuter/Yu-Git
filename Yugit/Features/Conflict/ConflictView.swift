import AIKit
import GitKit
import SwiftUI

/// 内置三方合并编辑器。
///
/// 替掉 v0.3 的外部 mergetool。三方并排摆着，加上 AI 的中文解释——
/// 要解决的是「看不懂对方为什么这么改」这件事，而不只是「怎么操作」。
struct ConflictView: View {

    @Bindable var model: ConflictViewModel
    let onDismiss: () -> Void

    @Environment(AISettingsStore.self) private var aiSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.paths.isEmpty {
                EmptyStateView(
                    "没有冲突",
                    systemImage: "checkmark.circle",
                    description: "所有冲突都已处理完"
                )
            } else {
                HSplitView {
                    fileList
                        .frame(minWidth: 200, idealWidth: 240)
                    blockList
                        .frame(minWidth: 520)
                }
            }

            Divider()
            footer
        }
        .frame(width: 980, height: 680)
        .task { await model.loadPaths() }
    }

    // MARK: - 各区块

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("解决冲突")
                    .font(Theme.Font.title)
                Text("「我方」是当前分支上的内容，「对方」是正在合进来的内容。")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            Spacer()

            if aiSettings.isAvailable, model.file?.hasConflicts == true {
                Button {
                    Task { await model.suggestAll(using: aiSettings) }
                } label: {
                    Label("全部让 AI 分析", systemImage: "sparkles")
                }
                .disabled(model.unresolvedCount == 0)
            }
        }
        .padding(12)
    }

    private var fileList: some View {
        List(model.paths, id: \.self, selection: $model.selectedPath) { path in
            Label(path, systemImage: "exclamationmark.triangle")
                .lineLimit(1)
                .truncationMode(.head)
                .tag(path)
        }
        .listStyle(.sidebar)
        .onChange(of: model.selectedPath) { _, _ in
            Task { await model.loadSelectedFile() }
        }
    }

    @ViewBuilder
    private var blockList: some View {
        if model.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let file = model.file, file.hasConflicts {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(file.blocks) { block in
                        ConflictBlockCard(
                            block: block,
                            state: model.states[block.id] ?? .init(),
                            canUseAI: aiSettings.isAvailable,
                            onTake: { model.take($0, for: block) },
                            onReset: { model.reset(blockID: block.id) },
                            onSuggest: {
                                Task { await model.suggest(for: block, using: aiSettings) }
                            },
                            onEdit: { model.setResolution($0, for: block.id) }
                        )
                    }
                }
                .padding(12)
            }
        } else {
            EmptyStateView(
                "这个文件没有冲突标记",
                systemImage: "doc",
                description: "可能已经解决过了",
                compact: true
            )
        }
    }

    private var footer: some View {
        HStack {
            if let error = model.errorMessage {
                Label(error, systemImage: "xmark.circle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.danger)
                    .textSelection(.enabled)
            } else if model.unresolvedCount > 0 {
                Text("还有 \(model.unresolvedCount) 处没有处理")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
            } else if model.file?.hasConflicts == true {
                Label("都处理完了，可以保存", systemImage: "checkmark.circle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.success)
            }

            Spacer()

            Button("关闭") { onDismiss() }
                .keyboardShortcut(.cancelAction)

            Button("保存并标记为已解决") {
                Task {
                    if await model.save(), model.paths.isEmpty { onDismiss() }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSave)
        }
        .padding(12)
    }
}

// MARK: - 单个冲突块

private struct ConflictBlockCard: View {

    let block: ConflictBlock
    let state: ConflictViewModel.BlockState
    let canUseAI: Bool
    let onTake: (ConflictViewModel.Choice) -> Void
    let onReset: () -> Void
    let onSuggest: () -> Void
    let onEdit: ([String]) -> Void

    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if state.isResolved && !isEditing {
                resolvedPreview
            } else {
                threeWayPanes
                choiceButtons
            }

            if let suggestion = state.suggestion {
                SuggestionCard(suggestion: suggestion) { onTake(.suggestion) }
            }

            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .textSelection(.enabled)
            }

            if isEditing { editor }
        }
        .padding(12)
        .background(Theme.Colors.raisedBackground, in: .rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(state.isResolved ? Theme.Colors.success.opacity(0.4) : Theme.Colors.separator)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: state.isResolved ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(state.isResolved ? .green : .secondary)

            Text("第 \(block.id + 1) 处冲突")
                .font(Theme.Font.secondary.weight(.medium))

            if block.base == nil {
                // 没有共同祖先时判断难度陡增，值得显式提醒
                Label("没有共同祖先可参考", systemImage: "questionmark.circle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }

            Spacer()

            if state.isSuggesting {
                ProgressView().controlSize(.small)
            } else if canUseAI && state.suggestion == nil {
                Button("让 AI 分析", action: onSuggest)
                    .buttonStyle(.borderless)
                    .font(Theme.Font.secondary)
            }

            if state.isResolved {
                Button("重新选", action: onReset)
                    .buttonStyle(.borderless)
                    .font(Theme.Font.secondary)
            }
        }
    }

    private var threeWayPanes: some View {
        HStack(alignment: .top, spacing: 8) {
            pane("我方（\(block.oursLabel)）", lines: block.ours, tint: .blue)
            if let base = block.base {
                pane("共同祖先", lines: base, tint: .secondary)
            }
            pane("对方（\(block.theirsLabel)）", lines: block.theirs, tint: .purple)
        }
    }

    private func pane(_ title: String, lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Font.caption.weight(.medium))
                .foregroundStyle(tint)

            ScrollView(.horizontal) {
                Text(lines.isEmpty ? "（空）" : lines.joined(separator: "\n"))
                    .font(Theme.Font.mono)
                    .foregroundStyle(lines.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
            .padding(6)
            .background(Theme.Colors.contentBackground, in: .rect(cornerRadius: 4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var choiceButtons: some View {
        HStack(spacing: 6) {
            Button("要我方") { onTake(.ours) }
            Button("要对方") { onTake(.theirs) }
            Button("两个都要") { onTake(.both) }
            Button("都不要") { onTake(.neither) }
            Button("手动编辑") {
                draft = (state.resolvedLines ?? block.ours).joined(separator: "\n")
                isEditing = true
            }
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var resolvedPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("采用的内容")
                .font(Theme.Font.caption.weight(.medium))
                .foregroundStyle(Theme.Colors.success)

            Text(
                (state.resolvedLines ?? []).isEmpty
                    ? "（这一段整块删掉）" : (state.resolvedLines ?? []).joined(separator: "\n")
            )
            .font(Theme.Font.mono)
            .foregroundStyle((state.resolvedLines ?? []).isEmpty ? .tertiary : .primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(Theme.Colors.success.opacity(0.08), in: .rect(cornerRadius: 4))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $draft)
                .font(Theme.Font.mono)
                .frame(height: 120)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.contentBackground, in: .rect(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator) }

            HStack {
                Spacer()
                Button("取消") { isEditing = false }
                    .controlSize(.small)
                Button("用这段") {
                    // 空文本表示整块删掉，不能变成一个空行
                    onEdit(draft.isEmpty ? [] : draft.components(separatedBy: "\n"))
                    isEditing = false
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - AI 建议卡片

private struct SuggestionCard: View {

    let suggestion: ConflictSuggestion
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.Colors.brand)
                Text("AI 建议")
                    .font(Theme.Font.secondary.weight(.medium))

                // 置信度是色标不是开关：高置信度同样不会自动应用，
                // 它只帮用户决定哪几处可以快速扫过、哪几处要停下来细看
                Text(suggestion.confidence.displayName)
                    .font(Theme.Font.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.18), in: .capsule)
                    .foregroundStyle(tint)

                Spacer()

                Button("采用", action: onAccept)
                    .buttonStyle(.borderless)
                    .font(Theme.Font.secondary)
            }

            if !suggestion.reason.isEmpty {
                Text(suggestion.reason)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .textSelection(.enabled)
            }

            Text(
                suggestion.resolvedLines.isEmpty
                    ? "（建议整块删掉）" : suggestion.resolvedLines.joined(separator: "\n")
            )
            .font(Theme.Font.mono)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(Theme.Colors.contentBackground, in: .rect(cornerRadius: 4))

            Label("AI 可能判断错，采用前请核对", systemImage: "info.circle")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
        .padding(8)
        .background(Theme.Colors.accent.opacity(0.06), in: .rect(cornerRadius: 6))
    }

    private var tint: Color {
        // 置信度是色标不是开关：三档共用状态色板，
        // 和界面其他地方的「好 / 要注意 / 有问题」保持同一套语言
        switch suggestion.confidence {
        case .high: Theme.Colors.success
        case .medium: Theme.Colors.warning
        case .low: Theme.Colors.danger
        }
    }
}
