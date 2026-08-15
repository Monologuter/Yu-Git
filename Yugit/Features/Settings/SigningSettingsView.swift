import GitKit
import Observation
import SwiftUI

/// 签名设置的状态。
@MainActor
@Observable
final class SigningViewModel: Identifiable {

    nonisolated let id = UUID()

    let repository: RepositoryViewModel

    private(set) var settings = SigningSettings(
        signsCommits: false, format: .openpgp, signingKey: "")
    private(set) var hasGPG = false
    private(set) var isLoading = false

    /// 编辑中的 key，还没写进配置。
    var draftKey = ""

    var blocker: SigningSettings.Blocker? { settings.blocker(hasGPG: hasGPG) }

    init(repository: RepositoryViewModel) {
        self.repository = repository
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        settings = await repository.signingSettings()
        hasGPG = await repository.isGPGAvailable()
        draftKey = settings.signingKey
    }

    func setSigning(_ enabled: Bool) async {
        await repository.setConfiguration(key: "commit.gpgsign", value: enabled ? "true" : "false")
        await reload()
    }

    func setFormat(_ format: SigningSettings.Format) async {
        await repository.setConfiguration(key: "gpg.format", value: format.rawValue)
        await reload()
    }

    func commitKey() async {
        await repository.setConfiguration(key: "user.signingkey", value: draftKey)
        await reload()
    }
}

/// 提交签名设置。
///
/// 这一页存在的意义不只是「能配」，更是**在配错之前拦住**：
/// 打开签名开关而缺 key 或缺 gpg，之后每一次提交都会失败，
/// 而用户看到的只是「提交失败」，完全联想不到是在这里做的事。
struct SigningSettingsView: View {

    @Bindable var model: SigningViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("提交签名", systemImage: "signature")
                    .font(Theme.Font.title)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            .padding(Theme.Spacing.loose)

            Divider()

            Form {
                Section {
                    Toggle(
                        "每条提交自动签名",
                        isOn: Binding(
                            get: { model.settings.signsCommits },
                            set: { enabled in Task { await model.setSigning(enabled) } }
                        )
                    )

                    Picker(
                        "签名方式",
                        selection: Binding(
                            get: { model.settings.format },
                            set: { format in Task { await model.setFormat(format) } }
                        )
                    ) {
                        ForEach(SigningSettings.Format.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }

                    Text(model.settings.format.requirement)
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.secondaryText)

                    HStack {
                        TextField(
                            model.settings.format == .ssh
                                ? "~/.ssh/id_ed25519.pub" : "key 指纹或邮箱",
                            text: $model.draftKey
                        )
                        .onSubmit { Task { await model.commitKey() } }

                        Button("保存") { Task { await model.commitKey() } }
                            .disabled(model.draftKey == model.settings.signingKey)
                    }
                } header: {
                    Text("这个仓库")
                } footer: {
                    // 说清作用范围：只改 .git/config，不动别的仓库。
                    // 不说的话，用户会以为自己改的是全局设置。
                    Text("以上只写进这个仓库的 `.git/config`，不影响你的其他仓库。")
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }

                if let blocker = model.blocker {
                    Section {
                        HStack(alignment: .top, spacing: Theme.Spacing.regular) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(Theme.Colors.warning)
                            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                                Text(blocker.displayName)
                                    .font(Theme.Font.body)
                                Text(blocker.suggestion)
                                    .font(Theme.Font.callout)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } header: {
                        Text("签名现在跑不起来")
                    } footer: {
                        Text("保持这样的话，**每一次提交都会直接失败**。")
                            .font(Theme.Font.secondary)
                            .foregroundStyle(Theme.Colors.warning)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("完成") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Theme.Spacing.loose)
        }
        .frame(width: 520, height: 440)
        .task { await model.reload() }
    }
}

/// 提交详情里的签名徽章。
///
/// 只在有话说的时候出现：未签名的提交什么都不显示。
/// 绝大多数仓库的绝大多数提交都没签名，给每一条都挂个标记等于没有标记。
struct SignatureBadge: View {

    let signature: CommitSignature

    var body: some View {
        if signature.status != .none {
            HStack(spacing: Theme.Spacing.tight) {
                Image(systemName: icon)
                Text(signature.status.displayName)
                if !signature.signer.isEmpty {
                    Text("· \(signature.signer)")
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            }
            .font(Theme.Font.secondary)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(wash, in: .capsule)
            .help(signature.status.explanation)
        }
    }

    private var icon: String {
        switch signature.status {
        case .good: "checkmark.seal"
        case .bad, .revokedKey: "xmark.seal"
        case .unknownTrust, .cannotCheck: "seal"
        case .expiredSignature, .expiredKey: "clock.badge.exclamationmark"
        case .none: "seal"
        }
    }

    private var tint: Color {
        if signature.status.isVerified { return Theme.Colors.success }
        if signature.status.needsAttention { return Theme.Colors.danger }
        return Theme.Colors.secondaryText
    }

    private var wash: Color {
        if signature.status.needsAttention { return Theme.Colors.warningWash }
        return Theme.Colors.sunkenBackground
    }
}
