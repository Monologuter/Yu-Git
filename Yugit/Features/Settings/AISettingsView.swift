import AIKit
import SwiftUI

/// AI 设置页。
///
/// 这一页要传达的第一件事不是「怎么配」，而是**不配也完全能用**：
/// 本地 Git 全功能永久免费，AI 是可选增强。所以顶上先说清这一点，
/// 免得用户以为不填 Key 就用不了这个客户端。
struct AISettingsView: View {

    @Bindable var store: AISettingsStore

    @State private var editing: AIConfiguration?
    @State private var isAddingKind: AIConfiguration.ProtocolKind?

    var body: some View {
        Form {
            Section {
                Label(
                    "AI 是可选增强。不配置也能使用全部本地 Git 功能。",
                    systemImage: "info.circle"
                )
                .foregroundStyle(Theme.Colors.secondaryText)
                .font(Theme.Font.callout)
            }

            Section("服务商") {
                if store.configurations.isEmpty {
                    EmptyStateView(
                        "还没有配置服务商",
                        systemImage: "sparkles",
                        description: "驭Git 用你自己的 API Key，不经过任何中转服务器。",
                        compact: true
                    ) {
                        addMenu
                    }
                } else {
                    ForEach(store.configurations) { configuration in
                        ConfigurationRow(
                            configuration: configuration,
                            isActive: store.activeConfiguration?.id == configuration.id,
                            onSelect: { store.activeID = configuration.id },
                            onEdit: { editing = configuration },
                            onRemove: { store.remove(configuration) }
                        )
                    }
                    addMenu
                }
            }

            if let error = store.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.Colors.warning)
                        .font(Theme.Font.callout)
                }
            }

            Section("隐私") {
                PrivacyNotice()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
        .sheet(item: $editing) { configuration in
            ConfigurationEditor(store: store, configuration: configuration, isNew: false)
        }
        .sheet(item: $isAddingKind) { kind in
            ConfigurationEditor(
                store: store,
                configuration: .makeDefault(kind: kind),
                isNew: true
            )
        }
    }

    private var addMenu: some View {
        Menu("添加服务商") {
            ForEach(AIConfiguration.ProtocolKind.allCases, id: \.self) { kind in
                // 云服务尚未上线，菜单里就说清楚，不让人配完才发现连不上
                if kind == .yugitCloud, !YugitCloudProvider.isServiceAvailable {
                    Button("\(kind.displayName)（尚未开放）") { isAddingKind = kind }
                } else {
                    Button(kind.displayName) { isAddingKind = kind }
                }
            }
        }
    }
}

// sheet(item:) 要求 Identifiable，枚举本身没有 id
extension AIConfiguration.ProtocolKind: Identifiable {
    public var id: String { rawValue }
}

// MARK: - 单条配置

private struct ConfigurationRow: View {

    let configuration: AIConfiguration
    let isActive: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Theme.Colors.accent : Theme.Colors.secondaryText)
                .onTapGesture(perform: onSelect)

            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.name)
                Text("\(configuration.kind.displayName) · \(configuration.model)")
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            Spacer()

            Button("编辑", action: onEdit)
                .buttonStyle(.borderless)
            Button("删除", role: .destructive, action: onRemove)
                .buttonStyle(.borderless)
        }
        .contentShape(.rect)
    }
}

// MARK: - 编辑表单

private struct ConfigurationEditor: View {

    @Bindable var store: AISettingsStore
    @State var configuration: AIConfiguration
    let isNew: Bool

    @State private var apiKey = ""
    @State private var testResult: String?
    @State private var isTesting = false

    private var isCloud: Bool { configuration.kind == .yugitCloud }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if configuration.kind == .yugitCloud, !YugitCloudProvider.isServiceAvailable {
                    Section {
                        Label(
                            "驭Git 云服务还没有上线。现在填的凭据保存下来没问题，"
                                + "但请求会连接失败。在此之前请用自带 Key 的方式。",
                            systemImage: "clock.badge.exclamationmark"
                        )
                        .foregroundStyle(Theme.Colors.warning)
                        .font(Theme.Font.callout)
                    }
                }

                Section {
                    TextField("名称", text: $configuration.name)
                        .help("给这份配置起个名字，例如「公司的 DeepSeek」")

                    if configuration.kind.needsEndpoint {
                        endpointField
                    }

                    modelField
                }

                Section(isCloud ? "订阅凭据" : "API Key") {
                    // SecureField：Key 不该以明文出现在屏幕上，
                    // 录屏、投屏、旁人一眼看见都是真实风险
                    //
                    // placeholder 要分开：云服务的凭据是 yg_ 开头，
                    // 统一写 sk-... 会让人以为这里也要填一个服务商的 API Key
                    SecureField(isCloud ? "yg_..." : "sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    if isCloud {
                        Label(
                            "凭据在订阅时发放，只显示一次。丢了只能重新签发——"
                                + "服务端只存它的哈希，找不回来。",
                            systemImage: "key"
                        )
                        .font(Theme.Font.secondary)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    }

                    Label(
                        isCloud
                            ? "凭据存放在系统钥匙串，不会写进配置文件，也不参与 iCloud 同步。"
                            : "Key 存放在系统钥匙串，不会写进配置文件，也不参与 iCloud 同步。",
                        systemImage: "lock"
                    )
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                }

                if let result = testResult {
                    Section {
                        Label(
                            result.isEmpty ? "连接正常" : result,
                            systemImage: result.isEmpty
                                ? "checkmark.circle" : "exclamationmark.triangle"
                        )
                        .foregroundStyle(result.isEmpty ? Theme.Colors.success : Theme.Colors.warning)
                        .font(Theme.Font.callout)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("测试连接") {
                    Task { await test() }
                }
                .disabled(isTesting || apiKey.isEmpty)

                if isTesting { ProgressView().controlSize(.small) }

                Spacer()

                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "添加" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(configuration.name.isEmpty || configuration.model.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 480, height: 420)
        .onAppear {
            // 已存在的配置不回显 Key：读出来填进输入框等于把它明文摆在屏幕上，
            // 而用户此刻多半只是想改模型名。留空表示「不改」。
            apiKey = isNew ? "" : ""
        }
    }

    private var endpointField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("接口地址", text: $configuration.baseURL)
            Menu("常见服务") {
                ForEach(AIModelPresets.knownEndpoints, id: \.url) { endpoint in
                    Button(endpoint.name) { configuration.baseURL = endpoint.url }
                }
            }
            .menuStyle(.borderlessButton)
            .font(Theme.Font.secondary)
        }
    }

    @ViewBuilder
    private var modelField: some View {
        if configuration.kind.needsCustomModel {
            customModelField
        } else {
            // 订阅制下能用哪些模型由服务端决定，让用户手填只会白报错
            Picker("模型", selection: $configuration.model) {
                ForEach(YugitCloudProvider.models) { suggestion in
                    Text("\(suggestion.displayName) — \(suggestion.note)").tag(suggestion.id)
                }
            }
        }
    }

    private var customModelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("模型", text: $configuration.model)
            // 只给建议不做白名单：模型迭代比客户端发版快，
            // 写死清单必然过期，得允许直接手填
            Menu("常用模型") {
                ForEach(suggestions) { suggestion in
                    Button("\(suggestion.displayName) — \(suggestion.note)") {
                        configuration.model = suggestion.id
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .font(Theme.Font.secondary)
        }
    }

    private var suggestions: [AIModelPresets.Suggestion] {
        switch configuration.kind {
        case .anthropic: AIModelPresets.anthropic
        case .openAICompatible: AIModelPresets.openAICompatible
        case .yugitCloud: YugitCloudProvider.models
        }
    }

    private func save() {
        if isNew {
            store.add(configuration, apiKey: apiKey)
        } else {
            store.update(configuration)
            // 留空表示不改 Key
            if !apiKey.isEmpty { store.setKey(apiKey, for: configuration) }
        }
        dismiss()
    }

    private func test() async {
        isTesting = true
        defer { isTesting = false }

        // 测试要用当前输入框里的 Key，所以先落盘再测
        if isNew {
            store.add(configuration, apiKey: apiKey)
        } else if !apiKey.isEmpty {
            store.setKey(apiKey, for: configuration)
        }

        testResult = await store.testConnection(configuration) ?? ""
    }
}

// MARK: - 隐私说明

private struct PrivacyNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("请求直连你填写的服务商，不经过驭Git 的任何服务器")
            row("只有你主动点击 AI 功能时才会发送内容")
            row(".env、私钥、凭据等敏感文件永不发送")
            row("每次发送前会告诉你哪些文件被排除了")
            row("本地 Git 全功能永久免费，不配 AI 也能用全部功能")
        }
        .font(Theme.Font.callout)
        .foregroundStyle(Theme.Colors.secondaryText)
    }

    private func row(_ text: String) -> some View {
        Label(text, systemImage: "checkmark")
            .labelStyle(.titleAndIcon)
    }
}
