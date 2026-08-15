import GitKit
import SwiftUI

/// 仓库时间线面板。
///
/// 这是驭Git 与其他客户端最大的差别：不只记录「做了什么」，还留着「做之前长什么样」。
/// 终端里的 git、编辑器保存、agent 写的代码，都在同一条线上。
struct TimelineView: View {

    @Bindable var repository: RepositoryViewModel
    @State private var pendingUndo: TimelineEntry?
    @State private var pendingRestore: Snapshot?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if repository.timelineEntries.isEmpty && repository.timelineSnapshots.isEmpty {
                EmptyStateView(
                    "时间线还是空的",
                    systemImage: "clock.arrow.circlepath",
                    description: "做过的操作会记在这里，危险操作会自动留下可恢复的时间点",
                    compact: true
                )
            } else {
                list
            }
        }
        .confirmationDialog(
            "撤销这一步？",
            isPresented: Binding(
                get: { pendingUndo != nil },
                set: { if !$0 { pendingUndo = nil } }
            ),
            presenting: pendingUndo
        ) { entry in
            Button("退回到「\(entry.summary)」之前", role: .destructive) {
                Task { await repository.undo(entry) }
                pendingUndo = nil
            }
            Button("取消", role: .cancel) { pendingUndo = nil }
        } message: { _ in
            // 撤销本身也会先拍一张，所以这一步同样是可逆的
            Text("工作区会退回那一刻的状态。当前状态会先被存下来，撤销之后仍可再退回来。")
        }
        // 用 sheet 而不是 confirmationDialog：后者装不下文件列表，
        // 而「会改动哪些文件」正是这一步要回答的问题
        .sheet(
            item: Binding(
                get: { pendingRestore },
                set: { if $0 == nil { pendingRestore = nil } }
            )
        ) { snapshot in
            RestorePreviewSheet(snapshot: snapshot, repository: repository) {
                pendingRestore = nil
            }
        }
        .task {
            await repository.reloadTimeline()
        }
    }

    private var header: some View {
        HStack {
            Label("时间线", systemImage: "clock.arrow.circlepath")
                .font(.headline)
            Spacer()
            Button {
                Task { await repository.reloadTimeline() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("刷新时间线")
        }
        .padding(12)
    }

    private var list: some View {
        List {
            if !repository.timelineEntries.isEmpty {
                Section("操作") {
                    // 最近的排最前
                    ForEach(repository.timelineEntries.reversed()) { entry in
                        TimelineEntryRow(entry: entry) {
                            pendingUndo = entry
                        }
                    }
                }
            }

            if !repository.timelineSnapshots.isEmpty {
                Section("时间点") {
                    ForEach(repository.timelineSnapshots) { snapshot in
                        SnapshotRow(snapshot: snapshot) {
                            pendingRestore = snapshot
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }
}

struct TimelineEntryRow: View {

    let entry: TimelineEntry
    let onUndo: () -> Void

    @State private var isHovering = false
    @State private var showsCommand = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(iconColor)
                    .frame(width: 14)

                Text(entry.summary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if isHovering && entry.canUndo {
                    Button("撤销", action: onUndo)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            HStack(spacing: 6) {
                Text(entry.timestamp, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if !entry.record.outcome.isSuccess {
                    Text("失败")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if entry.canUndo {
                    Label("可撤销", systemImage: "arrow.uturn.backward")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .labelStyle(.compact)
                }
            }

            // 透明命令层：随时能看到这一步等价于哪条 git 命令（差异化设计 ⑦）
            if showsCommand {
                Text(entry.record.operation.equivalentCommand)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .underPageBackgroundColor), in: .rect(cornerRadius: 4))

                Text(entry.record.operation.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onTapGesture { showsCommand.toggle() }
        .help("点击查看等价的 git 命令")
    }

    private var icon: String {
        switch entry.record.operation.hazard {
        case .none: "circle.fill"
        case .rewritesHistory: "pencil.circle.fill"
        case .discardsUncommittedWork: "trash.circle.fill"
        }
    }

    private var iconColor: Color {
        guard entry.record.outcome.isSuccess else { return .orange }
        switch entry.record.operation.hazard {
        case .none: return .secondary
        case .rewritesHistory: return .purple
        case .discardsUncommittedWork: return .red
        }
    }
}

struct SnapshotRow: View {

    let snapshot: Snapshot
    let onRestore: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "camera.fill")
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.summary)
                    .lineLimit(1)
                Text(snapshot.timestamp, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if isHovering {
                Button("恢复", action: onRestore)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
    }
}
