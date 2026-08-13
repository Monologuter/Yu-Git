import AIKit
import Foundation
import Observation

/// AI 配置的存放与取用。
///
/// 配置本身（服务商、地址、模型）存 UserDefaults，API Key 存 Keychain，
/// 两者靠 ``AIConfiguration/keychainAccount`` 关联。
///
/// 之所以支持多份配置：BYOK 用户往往手上不止一个 Key——工作用公司的、
/// 私人项目用自己的、离线时用本地 Ollama。切换比重填一遍舒服得多。
@MainActor
@Observable
final class AISettingsStore {

    private static let configurationsKey = "com.chenya.yugit.ai.configurations"
    private static let activeIDKey = "com.chenya.yugit.ai.activeConfiguration"

    private let defaults: UserDefaults
    private let keychain = KeychainStore()

    private(set) var configurations: [AIConfiguration] = []
    var activeID: UUID? {
        didSet {
            persistActiveID()
            refreshAvailability()
        }
    }

    /// AI 功能是否可用。界面上所有 AI 入口都以此为准。
    ///
    /// 是缓存的存储属性而不是每次现算，有两个原因：
    /// - 判断可用要读一次 Keychain，那是一次 XPC 调用，而 SwiftUI 的 `body`
    ///   求值极其频繁，放在计算属性里等于每帧都去敲 securityd 的门
    /// - `@Observable` 追踪不到 Keychain 这种外部状态的变化，存起来才能驱动界面刷新
    private(set) var isAvailable = false

    /// 上一次操作的错误，供设置页展示。
    var lastError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        refreshAvailability()
    }

    // MARK: - 查询

    var activeConfiguration: AIConfiguration? {
        guard let activeID else { return configurations.first(where: \.isEnabled) }
        return configurations.first { $0.id == activeID && $0.isEnabled }
            ?? configurations.first(where: \.isEnabled)
    }

    private func refreshAvailability() {
        guard let configuration = activeConfiguration else {
            isAvailable = false
            return
        }
        isAvailable = (try? keychain.key(for: configuration.keychainAccount))?.isEmpty == false
    }

    func apiKey(for configuration: AIConfiguration) -> String? {
        do {
            return try keychain.key(for: configuration.keychainAccount)
        } catch let error as KeychainError {
            lastError = error.localizedMessage
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// 造一个可用的 Provider。任何一步缺失都返回 nil。
    func makeProvider() -> (provider: any AIProvider, model: String)? {
        guard
            let configuration = activeConfiguration,
            let key = apiKey(for: configuration), !key.isEmpty
        else { return nil }

        do {
            return (try configuration.makeProvider(apiKey: key), configuration.model)
        } catch let error as AIError {
            lastError = error.localizedMessage
            return nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: - 增删改

    func add(_ configuration: AIConfiguration, apiKey: String) {
        configurations.append(configuration)
        setKey(apiKey, for: configuration)
        if activeID == nil { activeID = configuration.id }
        persist()
        refreshAvailability()
    }

    func update(_ configuration: AIConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else {
            return
        }
        configurations[index] = configuration
        persist()
        refreshAvailability()
    }

    func setKey(_ key: String, for configuration: AIConfiguration) {
        do {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try keychain.remove(for: configuration.keychainAccount)
            } else {
                try keychain.store(trimmed, for: configuration.keychainAccount)
            }
            lastError = nil
            refreshAvailability()
        } catch let error as KeychainError {
            lastError = error.localizedMessage
        } catch {
            lastError = error.localizedDescription
        }
    }

    func remove(_ configuration: AIConfiguration) {
        configurations.removeAll { $0.id == configuration.id }
        // Key 必须跟着一起删。留一条无主的 Keychain 记录，
        // 既是用户看不见的残留，也是一份没人再用的密钥。
        try? keychain.remove(for: configuration.keychainAccount)
        if activeID == configuration.id { activeID = configurations.first?.id }
        persist()
        refreshAvailability()
    }

    /// 测试连接。成功返回 nil，失败返回给用户看的说明。
    func testConnection(_ configuration: AIConfiguration) async -> String? {
        guard let key = apiKey(for: configuration), !key.isEmpty else {
            return "还没有填 API Key"
        }

        do {
            let provider = try configuration.makeProvider(apiKey: key)
            try await provider.validateCredentials()
            return nil
        } catch let error as AIError {
            return "\(error.localizedMessage)\n建议：\(error.suggestion)"
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - 持久化

    private func load() {
        if let data = defaults.data(forKey: Self.configurationsKey),
            let decoded = try? JSONDecoder().decode([AIConfiguration].self, from: data)
        {
            configurations = decoded
        }
        if let raw = defaults.string(forKey: Self.activeIDKey) {
            activeID = UUID(uuidString: raw)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        defaults.set(data, forKey: Self.configurationsKey)
    }

    private func persistActiveID() {
        defaults.set(activeID?.uuidString, forKey: Self.activeIDKey)
    }
}
