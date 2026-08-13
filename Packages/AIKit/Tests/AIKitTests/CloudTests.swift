import Foundation
import Testing

@testable import AIKit

@Suite("云服务订阅")
struct CloudSubscriptionTests {

    // MARK: - 订阅状态

    @Test("生效且有额度才算能用")
    func usableRequiresActiveAndQuota() {
        #expect(CloudSubscription(status: .active, remainingTokens: 1000).isUsable)
        // 额度用尽就不能用了，哪怕订阅还在生效期
        #expect(!CloudSubscription(status: .active, remainingTokens: 0).isUsable)
        #expect(!CloudSubscription(status: .expired, remainingTokens: 1000).isUsable)
        #expect(!CloudSubscription.none.isUsable)
    }

    @Test("服务端不报额度时按能用处理")
    func missingQuotaAssumesUsable() {
        // 不报额度可能是不限量套餐，不该因此拦住用户
        #expect(CloudSubscription(status: .active).isUsable)
    }

    @Test("已用比例")
    func computesUsedRatio() {
        let subscription = CloudSubscription(
            status: .active, remainingTokens: 250, totalTokens: 1000)
        #expect(subscription.usedRatio == 0.75)
    }

    @Test("算不出比例时返回 nil 而不是 0")
    func returnsNilRatioWhenUnknown() {
        // 返回 0 会让进度条显示「一点没用」，那是错的信息
        #expect(CloudSubscription(status: .active).usedRatio == nil)
        #expect(CloudSubscription(status: .active, remainingTokens: 5).usedRatio == nil)
        #expect(CloudSubscription(status: .active, remainingTokens: 5, totalTokens: 0).usedRatio == nil)
    }

    @Test("每种状态都有中文说法")
    func everyStatusHasChineseName() {
        for status in [
            CloudSubscription.Status.none, .active, .expired, .invalid,
        ] {
            #expect(!status.displayName.isEmpty)
        }
    }

    // MARK: - Provider

    @Test("服务尚未上线，明确标注而不是靠探测")
    func serviceAvailabilityIsExplicit() {
        // 探测失败和网络故障长得一模一样，用户会以为是自己的网络问题而反复重试
        #expect(!YugitCloudProvider.isServiceAvailable)
    }

    @Test("解析订阅响应")
    func parsesSubscriptionResponse() async throws {
        let session = StubURLProtocol.makeSession(
            json: """
                {"status":"active","remaining_tokens":120000,"total_tokens":500000,
                 "renews_at":"2026-09-01T00:00:00Z","message":"本月还剩 24%"}
                """)

        let provider = YugitCloudProvider(
            credential: "sub_test",
            endpoint: .literal("https://cloud.example.com/v1"),
            session: session
        )

        let subscription = try await provider.subscription()
        #expect(subscription.status == .active)
        #expect(subscription.remainingTokens == 120_000)
        #expect(subscription.usedRatio == 0.76)
        #expect(subscription.message == "本月还剩 24%")
    }

    @Test("查询订阅走 Bearer 认证")
    func subscriptionUsesBearerAuth() async throws {
        let session = StubURLProtocol.makeSession(json: #"{"status":"none"}"#)
        let provider = YugitCloudProvider(
            credential: "sub_abc",
            endpoint: .literal("https://cloud.example.com/v1"),
            session: session
        )
        _ = try await provider.subscription()

        let (request, _) = StubURLProtocol.recordedRequest(for: session)
        let recorded = try #require(request)
        #expect(recorded.value(forHTTPHeaderField: "authorization") == "Bearer sub_abc")
        #expect(recorded.url?.path.hasSuffix("/subscription") == true)
    }

    @Test("凭据无效时报 401 而不是解析失败")
    func invalidCredentialSurfacesAsUnauthorized() async throws {
        let session = StubURLProtocol.makeSession(
            json: #"{"error":{"message":"订阅凭据无效"}}"#, statusCode: 401)
        let provider = YugitCloudProvider(
            credential: "bad",
            endpoint: .literal("https://cloud.example.com/v1"),
            session: session
        )

        var caught: AIError?
        do {
            _ = try await provider.subscription()
        } catch let error as AIError {
            caught = error
        }

        guard case .unauthorized = try #require(caught) else {
            Issue.record("应归为凭据无效，实际是 \(String(describing: caught))")
            return
        }
    }

    @Test("补全走的是同一条 OpenAI 兼容路径")
    func completionReusesCompatibleProtocol() async throws {
        // 自建一套私有协议除了增加维护面没有好处；复用已有兼容层
        // 意味着云服务和用户自带 Key 走同一条经过测试的代码路径
        let session = StubURLProtocol.makeSession(
            sse: """
                data: {"choices":[{"delta":{"content":"云端回复"}}]}

                data: [DONE]

                """)

        let provider = YugitCloudProvider(
            credential: "sub_test",
            endpoint: .literal("https://cloud.example.com/v1"),
            session: session
        )

        let text = try await provider.complete(
            AIRequest(model: "yugit-standard", messages: [.user("你好")]))
        #expect(text == "云端回复")

        let (request, _) = StubURLProtocol.recordedRequest(for: session)
        #expect(request?.url?.absoluteString == "https://cloud.example.com/v1/chat/completions")
    }

    @Test("云服务的模型清单固定，不让用户手填")
    func modelListIsFixed() {
        // 订阅制下能用哪些模型由服务端决定，让用户填一个服务端不认的名字只会白报错
        #expect(!YugitCloudProvider.models.isEmpty)
        #expect(!AIConfiguration.ProtocolKind.yugitCloud.needsCustomModel)
        #expect(AIConfiguration.ProtocolKind.anthropic.needsCustomModel)
    }

    @Test("云服务不用填接口地址")
    func cloudNeedsNoEndpoint() {
        #expect(!AIConfiguration.ProtocolKind.yugitCloud.needsEndpoint)
        #expect(AIConfiguration.ProtocolKind.openAICompatible.needsEndpoint)
        // Anthropic 也不用填——默认地址就是对的
        #expect(!AIConfiguration.ProtocolKind.anthropic.needsEndpoint)
    }

    @Test("默认配置带上云服务的模型")
    func defaultConfigurationUsesCloudModel() {
        let configuration = AIConfiguration.makeDefault(kind: .yugitCloud)
        #expect(configuration.kind == .yugitCloud)
        #expect(configuration.model == YugitCloudProvider.models[0].id)
    }

    @Test("云配置能造出 provider")
    func buildsCloudProvider() throws {
        let configuration = AIConfiguration.makeDefault(kind: .yugitCloud)
        let provider = try configuration.makeProvider(apiKey: "sub_test")
        #expect(provider.displayName == "驭Git 云服务")
    }
}
