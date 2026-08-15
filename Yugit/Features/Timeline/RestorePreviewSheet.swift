import GitKit
import SwiftUI

/// 恢复到某个时间点之前，先把会发生什么摆出来，并让人挑要恢复哪几个。
///
/// **在此之前恢复是盲跳**：点下去工作区就变了，而用户不知道会丢掉什么。
/// 危险预警的三答里，「能不能撤」这个答案只有配上「撤了会怎样」才真正成立。
///
/// 勾选的意义更进一层：真实场景是「agent 把这一个文件改坏了，但另外三个改得挺好」。
/// 只能全量恢复的话，用户宁可手工去改，时间线就白做了。
struct RestorePreviewSheet: View {

    let snapshot: Snapshot
    @Bindable var repository: RepositoryViewModel
    let onDismiss: () -> Void

    @State private var preview: SnapshotPreview?
    @State private var isLoading = true
    /// 勾选了哪几个。默认全选——「整个退回去」仍是最常见的意图。
    @State private var selected: Set<String> = []
    @State private var label = ""
    @State private var isEditingLabel = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            header

            if isLoading {
                HStack(spacing: Theme.Spacing.regular) {
                    ProgressView().controlSize(.small)
                    Text("正在算这一步会改动什么…")
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if let preview {
                if preview.isEmpty {
                    Label(
                        "工作区和那一刻完全一样，恢复不会改动任何文件。",
                        systemImage: "checkmark.circle"
                    )
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Colors.success)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                } else {
                    changeList(preview)
                }
            }

            Text("当前状态会先被存成一张快照，所以这一步本身也是可以再退回来的。")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            footer
        }
        .padding(Theme.Spacing.section)
        .frame(width: 560)
        .task {
            let result = await repository.previewRestore(snapshot)
            preview = result
            // 默认全选：整个退回去仍是最常见的意图，勾选是给例外情况用的
            selected = Set(
                (result?.removed ?? []) + (result?.overwritten ?? []) + (result?.restored ?? []))
            label = await repository.snapshotLabel(for: snapshot) ?? ""
            isLoading = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack {
                Label("恢复到这个时间点", systemImage: "clock.arrow.circlepath")
                    .font(Theme.Font.title)
                Spacer()
                Button {
                    isEditingLabel.toggle()
                } label: {
                    Label(label.isEmpty ? "起个名字" : "改名字", systemImage: "tag")
                }
                .buttonStyle(.borderless)
                .help("标注过的快照不会被自动清理掉")
            }

            Text(
                "「\(label.isEmpty ? snapshot.summary : label)」· "
                    + snapshot.timestamp.formatted(date: .abbreviated, time: .shortened)
            )
            .font(Theme.Font.callout)
            .foregroundStyle(Theme.Colors.secondaryText)

            if isEditingLabel {
                // 自动摘要是「执行「硬重置到 abc1234」之前」，而用户三天后
                // 想找的是「Claude 大改那次之前」。机器生成的描述准确但不好找。
                HStack {
                    TextField("例如：Claude 第 3 轮改动前", text: $label)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(commitLabel)
                    Button("保存", action: commitLabel)
                }
                Text("起过名字的快照不会被自动清理掉——名字就是「这张重要」的信号。")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let preview, !preview.isEmpty {
                Button(selected.count == preview.totalCount ? "全不选" : "全选") {
                    if selected.count == preview.totalCount {
                        selected.removeAll()
                    } else {
                        selected = Set(preview.removed + preview.overwritten + preview.restored)
                    }
                }
                .buttonStyle(.borderless)
            }
            Spacer()
            Button("取消", role: .cancel) { onDismiss() }
            Button(confirmLabel) {
                Task {
                    await restore()
                    onDismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isLoading || (preview.map { !$0.isEmpty && selected.isEmpty } ?? false))
        }
    }

    private func commitLabel() {
        Task {
            await repository.setSnapshotLabel(label, for: snapshot)
            isEditingLabel = false
        }
    }

    private func restore() async {
        guard let preview, !preview.isEmpty else {
            await repository.restore(snapshot)
            return
        }
        // 全选就走整体恢复：它还会把 index 一并退回 HEAD，
        // 那是「整个回到那一刻」应有的效果，选择性恢复刻意不做这件事
        if selected.count == preview.totalCount {
            await repository.restore(snapshot)
        } else {
            await repository.restore(snapshot, paths: Array(selected))
        }
    }

    /// 按钮上写清后果，而不是一个「确定」。
    private var confirmLabel: String {
        guard let preview, !preview.isEmpty else { return "恢复" }
        let losing = selected.intersection(Set(preview.removed + preview.overwritten)).count
        guard losing > 0 else { return "恢复 \(selected.count) 个文件" }
        return "恢复，并丢弃 \(losing) 个文件的当前内容"
    }

    private func changeList(_ preview: SnapshotPreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.regular) {
                // 「会被删掉」排最前面：那是最需要用户看清的一栏，
                // 快照之后新建的文件会消失
                group(
                    "这些文件会被删掉", preview.removed,
                    systemImage: "trash", tint: Theme.Colors.danger,
                    note: "它们是快照之后新建的，快照里没有它们")
                group(
                    "这些文件的内容会被覆盖", preview.overwritten,
                    systemImage: "arrow.counterclockwise", tint: Theme.Colors.warning,
                    note: "当前内容会换成快照那一刻的")
                group(
                    "这些文件会被写回来", preview.restored,
                    systemImage: "arrow.down.doc", tint: Theme.Colors.success,
                    note: "它们在快照里有，现在没有")
            }
        }
        .frame(maxHeight: 260)
    }

    @ViewBuilder
    private func group(
        _ title: String,
        _ paths: [String],
        systemImage: String,
        tint: Color,
        note: String
    ) -> some View {
        if !paths.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                HStack(spacing: Theme.Spacing.tight) {
                    Image(systemName: systemImage)
                        .foregroundStyle(tint)
                    Text("\(title)（\(paths.count)）")
                        .font(Theme.Font.body)
                    Spacer()
                    // 整栏勾选。真实用法往往就是「只把被删的那些恢复回来」
                    Button(paths.allSatisfy(selected.contains) ? "取消这组" : "选中这组") {
                        if paths.allSatisfy(selected.contains) {
                            paths.forEach { selected.remove($0) }
                        } else {
                            paths.forEach { selected.insert($0) }
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(Theme.Font.secondary)
                }
                Text(note)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.tertiaryText)

                // 只列前二十条。一次恢复动上千个文件是可能的，
                // 而把它们全铺出来既没人看，也把对话框撑成一根面条。
                ForEach(paths.prefix(20), id: \.self) { path in
                    Toggle(isOn: binding(for: path)) {
                        Text(path)
                            .font(Theme.Font.mono)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .toggleStyle(.checkbox)
                }
                if paths.count > 20 {
                    // 说清剩下的那些跟着整组走，不然用户会以为它们没被处理
                    Text("还有 \(paths.count - 20) 个，跟着这一组的勾选走")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            }
            .padding(Theme.Spacing.regular)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.Colors.sunkenBackground, in: .rect(cornerRadius: Theme.Radius.medium))
        }
    }

    private func binding(for path: String) -> Binding<Bool> {
        Binding(
            get: { selected.contains(path) },
            set: { isOn in
                if isOn {
                    selected.insert(path)
                } else {
                    selected.remove(path)
                }
            }
        )
    }
}
