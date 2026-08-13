import Foundation

/// 设置页里的模型候选。
///
/// 只是**建议**，不是白名单：模型迭代比客户端发版快得多，写死一份清单必然过期。
/// 设置页允许直接手填模型名，这里的列表只为省掉常见情况下的打字。
public enum AIModelPresets {

    /// Anthropic 默认模型。
    public static let anthropicDefault = "claude-opus-5"

    /// OpenAI 兼容协议的默认模型。
    public static let openAIDefault = "gpt-5"

    public struct Suggestion: Sendable, Identifiable, Equatable {
        public let id: String
        public let displayName: String
        /// 一句话说清什么时候选它。
        public let note: String

        public init(id: String, displayName: String, note: String) {
            self.id = id
            self.displayName = displayName
            self.note = note
        }
    }

    public static let anthropic: [Suggestion] = [
        Suggestion(id: "claude-opus-5", displayName: "Claude Opus 5", note: "最强，复杂改动的解释和评审最准"),
        Suggestion(id: "claude-sonnet-5", displayName: "Claude Sonnet 5", note: "速度与质量平衡，日常够用"),
        Suggestion(id: "claude-haiku-4-5", displayName: "Claude Haiku 4.5", note: "最快最省，适合高频生成提交信息"),
    ]

    public static let openAICompatible: [Suggestion] = [
        Suggestion(id: "gpt-5", displayName: "GPT-5", note: "OpenAI 官方"),
        Suggestion(id: "deepseek-chat", displayName: "DeepSeek Chat", note: "国内可直连，价格低"),
        Suggestion(id: "qwen-max", displayName: "通义千问 Max", note: "阿里云百炼"),
    ]

    /// 常见 OpenAI 兼容服务的接口地址，省掉用户查文档。
    public static let knownEndpoints: [(name: String, url: String)] = [
        ("OpenAI", "https://api.openai.com/v1"),
        ("DeepSeek", "https://api.deepseek.com/v1"),
        ("月之暗面 Kimi", "https://api.moonshot.cn/v1"),
        ("阿里云百炼", "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        ("智谱 GLM", "https://open.bigmodel.cn/api/paas/v4"),
        ("本地 Ollama", "http://localhost:11434/v1"),
    ]
}
