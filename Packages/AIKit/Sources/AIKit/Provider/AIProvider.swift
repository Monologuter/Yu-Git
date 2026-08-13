import Foundation

// MARK: - 请求

/// 对话中的一条消息。
///
/// 两家协议对角色的叫法一致（user / assistant），system 的位置不同：
/// Anthropic 放在顶层 `system` 字段，OpenAI 兼容协议放在 messages 数组第一条。
/// 差异由各自的 Provider 消化，调用方只管填 ``AIRequest/system``。
public struct AIMessage: Sendable, Equatable {

    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ content: String) -> AIMessage {
        AIMessage(role: .user, content: content)
    }

    public static func assistant(_ content: String) -> AIMessage {
        AIMessage(role: .assistant, content: content)
    }
}

/// 一次补全请求。
public struct AIRequest: Sendable {

    public let model: String
    /// 系统提示。驭Git 里一律用中文写，因为输出也要是中文。
    public let system: String?
    public let messages: [AIMessage]
    public let maxTokens: Int

    public init(model: String, system: String? = nil, messages: [AIMessage], maxTokens: Int = 1024) {
        self.model = model
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
    }
}

// MARK: - 响应

/// 流式响应里的一个事件。
///
/// 只暴露驭Git 用得上的两类：文本增量和结束。thinking、tool_use 这些块被 Provider 丢弃——
/// 现阶段没有哪个 AI 功能需要它们，提前抽象只会让接口变形。
public enum AIStreamEvent: Sendable, Equatable {
    /// 一段新到的正文文本。
    case textDelta(String)
    /// 流正常结束。
    case completed(AIUsage?)
}

/// token 用量。用于在设置页显示「这次花了多少」，让 BYOK 用户对成本有数。
public struct AIUsage: Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

// MARK: - Provider

/// 一个大模型服务端点。
///
/// 驭Git 坚持 BYOK：用户自己的 Key、自己的额度、自己的服务商。所以这里必须能接
/// 两套协议——Anthropic 原生和 OpenAI 兼容（后者覆盖 OpenAI、DeepSeek、Kimi、
/// 通义、本地 Ollama 等一大票，它们都照抄了 `/v1/chat/completions`）。
public protocol AIProvider: Sendable {

    /// 人类可读的名字，显示在设置页。
    var displayName: String { get }

    /// 发起一次流式补全。
    ///
    /// 流式是硬性要求而非优化：commit message 要一个字一个字出现在提交框里，
    /// 用户能边看边改，而不是盯着转圈等十秒。
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, any Error>

    /// 打一次最便宜的招呼，用于设置页的「测试连接」。
    func validateCredentials() async throws
}

extension AIProvider {

    /// 把流式结果收成一整段文本。给不需要流式的调用方用。
    public func complete(_ request: AIRequest) async throws -> String {
        var text = ""
        for try await event in stream(request) {
            if case let .textDelta(delta) = event { text += delta }
        }
        return text
    }
}
