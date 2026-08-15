import GitKit
import SwiftUI

/// 恢复到某个时间点之前，先把会发生什么摆出来。
///
/// **在此之前恢复是盲跳**：点下去工作区就变了，而用户不知道会丢掉什么。
/// 危险预警的三答里，「能不能撤」这个答案只有配上「撤了会怎样」才真正成立。
struct RestorePreviewSheet: View {

    let snapshot: Snapshot
    @Bindable var repository: RepositoryViewModel
    let onDismiss: () -> Void

    @State private var preview: SnapshotPreview?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Label("恢复到这个时间点", systemImage: "clock.arrow.circlepath")
                    .font(Theme.Font.title)
                Text("「\(snapshot.summary)」· \(snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

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

            HStack {
                Spacer()
                Button("取消", role: .cancel) { onDismiss() }
                Button(confirmLabel) {
                    Task {
                        await repository.restore(snapshot)
                        onDismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLoading)
            }
        }
        .padding(Theme.Spacing.section)
        .frame(width: 520)
        .task {
            preview = await repository.previewRestore(snapshot)
            isLoading = false
        }
    }

    /// 按钮上写清后果，而不是一个「确定」。
    ///
    /// 会丢东西的时候尤其要写明白——用户在点之前会再读一遍自己要做什么。
    private var confirmLabel: String {
        guard let preview, preview.losesWork else { return "恢复" }
        return "恢复，并丢弃 \(preview.removed.count + preview.overwritten.count) 个文件的当前内容"
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
        .frame(maxHeight: 240)
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
                }
                Text(note)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.tertiaryText)

                // 只列前二十条。一次恢复动上千个文件是可能的，
                // 而把它们全铺出来既没人看，也把对话框撑成一根面条。
                ForEach(paths.prefix(20), id: \.self) { path in
                    Text(path)
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if paths.count > 20 {
                    Text("还有 \(paths.count - 20) 个")
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
}
