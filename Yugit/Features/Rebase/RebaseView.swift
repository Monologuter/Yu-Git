import GitKit
import SwiftUI

/// 可视化 interactive rebase。
///
/// 终端里的 interactive rebase 要人先看懂一份 todo 文件的语法，再在 vim 里
/// 把行首的 pick 改成 squash——这是 Git 最劝退的一道门槛。这里把它变成
/// 拖动排序加下拉选择，每个动作旁边写清楚会发生什么。
struct RebaseView: View {

    @Bindable var repository: RepositoryViewModel
    let onDismiss: () -> Void

    @State private var plan: RebaseTodo?
    @State private var isLoading = true
    @State private var isRunning = false
    @State private var errorMessage: String?
    /// 正在编辑提交信息的条目。
    @State private var editingHash: String?

    /// 一次整理多少条。再多就该考虑分批了，一屏放不下的计划人也审不动。
    private let commitCount = 20

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("正在读取提交…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let plan {
                list(plan)
            } else {
                EmptyStateView(
                    "没有可整理的提交",
                    systemImage: "checklist",
                    description: "当前分支还没有提交，或者提交都已经推送给别人了"
                )
            }

            Divider()
            footer
        }
        .frame(width: 720, height: 560)
        .task { await load() }
    }

    // MARK: - 各区块

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("整理提交历史")
                .font(Theme.Font.title)
            Text("拖动可以调整顺序，最上面的最旧。开始前会自动打一个备份 tag，随时能退回来。")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func list(_ plan: RebaseTodo) -> some View {
        List {
            ForEach(Array(plan.items.enumerated()), id: \.element.id) { index, item in
                RebaseItemRow(
                    item: item,
                    // 第一条没有「上一条」可并，把这两个选项去掉比让人选完再报错友好
                    allowsSquash: index > 0,
                    isEditingMessage: editingHash == item.hash,
                    onChangeAction: { action in update(index: index) { $0.action = action } },
                    onChangeMessage: { message in update(index: index) { $0.message = message } },
                    onToggleEditor: {
                        editingHash = editingHash == item.hash ? nil : item.hash
                    }
                )
            }
            .onMove { source, destination in
                self.plan?.items.move(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 校验结果一直显示，而不是等用户点了「开始」才告诉他不行
            ForEach(problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.warning)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "xmark.circle")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.danger)
                    .textSelection(.enabled)
            }

            HStack {
                if let plan, plan.hasChanges {
                    Text(summary(of: plan))
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                Spacer()

                if isRunning { ProgressView().controlSize(.small) }

                Button("取消") { onDismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("开始整理") {
                    Task { await run() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canRun)
            }
        }
        .padding(12)
    }

    // MARK: - 状态

    private var problems: [String] {
        guard let plan else { return [] }
        // 去重：三条 reword 都没填信息时说一次就够了
        var seen = Set<String>()
        return plan.validate().compactMap { problem in
            let text = problem.localizedMessage
            return seen.insert(text).inserted ? text : nil
        }
    }

    private var canRun: Bool {
        guard let plan, !isRunning else { return false }
        return plan.hasChanges && plan.validate().isEmpty
    }

    private func summary(of plan: RebaseTodo) -> String {
        let dropped = plan.items.filter { $0.action == .drop }.count
        let merged = plan.items.filter { $0.action == .squash || $0.action == .fixup }.count
        let reworded = plan.items.filter { $0.action == .reword }.count

        var parts: [String] = []
        if dropped > 0 { parts.append("丢弃 \(dropped) 条") }
        if merged > 0 { parts.append("合并 \(merged) 条") }
        if reworded > 0 { parts.append("改写 \(reworded) 条信息") }
        return parts.isEmpty ? "顺序有调整" : parts.joined(separator: "，")
    }

    private func update(index: Int, _ mutate: (inout RebaseTodo.Item) -> Void) {
        guard var current = plan, current.items.indices.contains(index) else { return }
        mutate(&current.items[index])
        plan = current
    }

    // MARK: - 动作

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            plan = try await repository.makeRebasePlan(commitCount: commitCount)
        } catch {
            errorMessage = "\(error)"
        }
    }

    private func run() async {
        guard let plan else { return }
        isRunning = true
        defer { isRunning = false }

        let result = await repository.runRebase(plan, summary: summary(of: plan))
        switch result {
        case .completed:
            onDismiss()
        case let .conflicted(paths, _):
            errorMessage =
                "重放到某条提交时发生冲突：\(paths.joined(separator: "、"))。"
                + "已停在这一步，可以在变更列表里解决冲突后继续，或者放弃这次整理。"
            onDismiss()
        case let .failed(message):
            errorMessage = message
        }
    }
}

// MARK: - 单条

private struct RebaseItemRow: View {

    let item: RebaseTodo.Item
    let allowsSquash: Bool
    let isEditingMessage: Bool
    let onChangeAction: (RebaseTodo.Action) -> Void
    let onChangeMessage: (String) -> Void
    let onToggleEditor: () -> Void

    @State private var draft = ""

    private var availableActions: [RebaseTodo.Action] {
        allowsSquash
            ? RebaseTodo.Action.allCases
            : RebaseTodo.Action.allCases.filter { $0 != .squash && $0 != .fixup }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(Theme.Colors.tertiaryText)
                    .font(Theme.Font.secondary)

                Picker("", selection: actionBinding) {
                    ForEach(availableActions, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .labelsHidden()
                .frame(width: 190)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.message?.firstLine ?? item.originalSubject)
                        .lineLimit(1)
                        // 丢弃的画删除线：一眼看出这条不会留下
                        .strikethrough(item.action == .drop)
                        .foregroundStyle(item.action == .drop ? .secondary : .primary)

                    Text(item.hash.prefix(7))
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }

                Spacer(minLength: 4)

                if item.action.needsMessage {
                    Button(isEditingMessage ? "收起" : "写新信息", action: onToggleEditor)
                        .buttonStyle(.borderless)
                        .font(Theme.Font.secondary)
                }
            }

            // 选中动作后就把「会发生什么」摆出来，不必先做一遍再体会
            Text(item.action.explanation)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            if isEditingMessage {
                TextEditor(text: $draft)
                    .font(Theme.Font.mono)
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .background(Theme.Colors.contentBackground, in: .rect(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator) }
                    .onChange(of: draft) { _, value in onChangeMessage(value) }
                    .onAppear {
                        // 带上原来的信息作起点，改一句比从头写一遍常见得多
                        draft = item.message ?? item.originalSubject
                        onChangeMessage(draft)
                    }
            }
        }
        .padding(.vertical, 3)
    }

    private var actionBinding: Binding<RebaseTodo.Action> {
        Binding(get: { item.action }, set: onChangeAction)
    }
}

extension String {
    /// 多行提交信息的第一行，列表里只显示标题。
    fileprivate var firstLine: String {
        split(separator: "\n", maxSplits: 1).first.map(String.init) ?? self
    }
}
