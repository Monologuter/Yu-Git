import Foundation

/// AI 服务的配置。
///
/// 除 API Key 之外的一切都存在这里，可以安全地落 UserDefaults；
/// Key 单独存 Keychain，靠 ``keychainAccount`` 关联。
public struct AIConfiguration: Codable, Sendable, Equatable, Identifiable {

    public enum ProtocolKind: String, Codable, Sendable, CaseIterable {
        case anthropic
        case openAICompatible

        public var displayName: String {
            switch self {
            case .anthropic: "Anthropic"
            case .openAICompatible: "OpenAI 兼容"
            }
        }
    }

    /// 这份配置的稳定标识，同时用作 Keychain 里的 account 名。
    public let id: UUID
    public var kind: ProtocolKind
    /// 用户给这份配置起的名字，例如「公司的 DeepSeek」。
    public var name: String
    /// 接口地址。Anthropic 一般不用改；OpenAI 兼容协议必填。
    public var baseURL: String
    public var model: String
    /// 关掉 AI 后所有入口都隐藏，不只是不发请求——
    /// 让不用 AI 的用户界面上看不到任何 AI 痕迹。
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        kind: ProtocolKind,
        name: String,
        baseURL: String,
        model: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.isEnabled = isEnabled
    }

    public var keychainAccount: String { id.uuidString }

    /// 新建一份指定协议的默认配置。
    public static func makeDefault(kind: ProtocolKind) -> AIConfiguration {
        switch kind {
        case .anthropic:
            AIConfiguration(
                kind: .anthropic,
                name: "Anthropic",
                baseURL: AnthropicProvider.defaultBaseURL.absoluteString,
                model: AIModelPresets.anthropicDefault
            )
        case .openAICompatible:
            AIConfiguration(
                kind: .openAICompatible,
                name: "OpenAI",
                baseURL: OpenAICompatibleProvider.defaultBaseURL.absoluteString,
                model: AIModelPresets.openAIDefault
            )
        }
    }

    /// 按配置造一个 Provider。
    public func makeProvider(apiKey: String, session: URLSession = .shared) throws -> any AIProvider {
        guard let url = URL(string: baseURL), url.scheme != nil else {
            throw AIError.notFound("接口地址不是合法 URL：\(baseURL)")
        }

        switch kind {
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey, baseURL: url, session: session)
        case .openAICompatible:
            return OpenAICompatibleProvider(
                apiKey: apiKey,
                baseURL: url,
                displayName: name,
                defaultModel: model,
                session: session
            )
        }
    }
}
