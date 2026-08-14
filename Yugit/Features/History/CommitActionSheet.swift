import GitKit
import SwiftUI

/// 一个待确认的提交操作。`sheet(item:)` 需要 Identifiable。
struct PendingCommitAction: Identifiable {
    let action: CommitAction
    let commit: Commit
    var id: String { "\(commit.hash)-\(action.hashValue)" }
}

/// 挑取 / 撤销 / 重置 / 打标签的确认面板。
///
/// 三种 reset 走危险预警对话框（``HazardDialog``），因为它们改的是历史；
/// 打标签要先收一个名字；cherry-pick 压根不弹——它只往历史上加一条新提交，
/// 后悔了删掉就行，为它多问一次只会让人养成闭眼点确定的习惯。
struct CommitActionSheet: View {

    let pending: PendingCommitAction
    @Bindable var repository: RepositoryViewModel
    let onDismiss: () -> Void
    /// 重放停在冲突上时调用，把用户领到三方合并编辑器。
    let onConflict: () -> Void

    @State private var tagName = ""
    @State private var tagMessage = ""
    @State private var isRunning = false

    var body: some View {
        if pending.action == .tag {
            tagSheet
        } else if let warning = hazardWarning {
            HazardDialog(warning: warning, onConfirm: run, onCancel: onDismiss)
        } else {
            confirmationSheet
        }
    }

    /// 重置三兄弟自带 hazard，直接交给危险预警对话框——
    /// 「会发生什么、能不能撤、怎么撤」那三问不必在这里再写一遍。
    private var hazardWarning: HazardWarning? {
        pending.action.operation(for: pending.commit)?.warning(hasSnapshot: true)
    }

    // MARK: - 撤销：不改历史，但值得看一眼要撤的是什么

    private var confirmationSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Label(pending.action.title, systemImage: pending.action.systemImage)
                    .font(Theme.Font.title)
                Text(pending.action.explanation)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            commitCard

            if let command = pending.action.operation(for: pending.commit)?.equivalentCommand {
                EquivalentCommand(command)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { onDismiss() }
                Button(pending.action.title) { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning)
            }
        }
        .padding(Theme.Spacing.section)
        .frame(width: 460)
    }

    // MARK: - 打标签

    private var tagSheet: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Label("打标签", systemImage: "tag")
                    .font(Theme.Font.title)
                Text(
                    "填了说明就打**附注标签**——它是独立的 git 对象，带作者与日期，"
                        + "也只有它会被 `git describe` 计入。对外发版必须用附注标签。"
                        + "不填说明则是轻量标签，适合给自己做临时书签。"
                )
                .font(Theme.Font.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            commitCard

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                TextField("标签名，例如 v1.2.0", text: $tagName)
                    .textFieldStyle(.roundedBorder)

                Text("说明（可选）")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                TextEditor(text: $tagMessage)
                    .font(Theme.Font.callout)
                    .frame(height: 64)
                    .scrollContentBackground(.hidden)
                    .background(
                        Theme.Colors.contentBackground, in: .rect(cornerRadius: Theme.Radius.small)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.small)
                            .strokeBorder(Theme.Colors.separatorStrong, lineWidth: 1)
                    }
            }

            EquivalentCommand(
                GitOperation.createTag(
                    name: tagName.isEmpty ? "<标签名>" : tagName,
                    at: pending.commit.hash,
                    message: tagMessage
                ).equivalentCommand
            )

            HStack {
                Spacer()
                Button("取消", role: .cancel) { onDismiss() }
                Button("打标签") { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isRunning || tagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Spacing.section)
        .frame(width: 460)
    }

    // MARK: -

    private var commitCard: some View {
        HStack(spacing: Theme.Spacing.regular) {
            Text(pending.commit.abbreviatedHash)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text(pending.commit.subject)
                .font(Theme.Font.body)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.sunkenBackground, in: .rect(cornerRadius: Theme.Radius.medium))
    }

    private func run() {
        isRunning = true
        Task {
            switch pending.action {
            case .cherryPick:
                let outcome = await repository.cherryPick(pending.commit)
                finish(outcome)
            case .revert:
                let outcome = await repository.revert(pending.commit)
                finish(outcome)
            case .resetSoft, .resetMixed, .resetHard:
                await repository.reset(pending.commit, mode: pending.action)
                onDismiss()
            case .tag:
                await repository.createTag(
                    named: tagName, at: pending.commit, message: tagMessage)
                onDismiss()
            }
        }
    }

    /// 停在冲突上不是失败，所以不弹错误框，而是把人领到三方合并编辑器。
    private func finish(_ outcome: ReplayOutcome?) {
        onDismiss()
        if case .conflicted = outcome {
            onConflict()
        }
    }
}

/// 等价 git 命令的展示条。
///
/// 透明命令层：每一步都让用户看得见底下发生了什么。可选中，
/// 因为想拿去终端里跑一遍的人正是最该被照顾的那批。
struct EquivalentCommand: View {

    private let command: String

    init(_ command: String) {
        self.command = command
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.regular) {
            Text(command)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制这条命令")
        }
        .padding(Theme.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.sunkenBackground, in: .rect(cornerRadius: Theme.Radius.small))
    }
}
