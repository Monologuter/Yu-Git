import Foundation
import Testing

@testable import ForgeKit

@Suite("平台适配")
struct ForgeClientTests {

    private func locator(_ url: String) throws -> RemoteLocator {
        try #require(RemoteLocator.parse(remoteURL: url))
    }

    // MARK: - GitHub

    /// GitHub 的 PR 列表响应（按官方文档的字段形状）。
    static let githubList = """
        [
          {"number":42,"title":"feat: 新增导出","state":"open","draft":false,
           "merged_at":null,"html_url":"https://github.com/o/r/pull/42",
           "created_at":"2026-08-01T10:00:00Z",
           "user":{"login":"zhangsan"},
           "head":{"ref":"feature/export"},"base":{"ref":"main"}},
          {"number":41,"title":"fix: 超时","state":"closed","draft":false,
           "merged_at":"2026-07-30T08:00:00Z","html_url":"https://github.com/o/r/pull/41",
           "created_at":"2026-07-29T10:00:00Z",
           "user":{"login":"lisi"},
           "head":{"ref":"fix/timeout"},"base":{"ref":"main"}},
          {"number":40,"title":"chore: 关掉的","state":"closed","draft":false,
           "merged_at":null,"html_url":"https://github.com/o/r/pull/40",
           "created_at":"2026-07-20T10:00:00Z",
           "user":{"login":"wangwu"},
           "head":{"ref":"chore/x"},"base":{"ref":"main"}}
        ]
        """

    @Test("GitHub：已合并与已关闭必须区分开")
    func githubDistinguishesMergedFromClosed() async throws {
        // GitHub 把已合并的 PR 也报成 state: "closed"，
        // 只能靠 merged_at 区分——两者对用户的意义完全不同
        let session = StubURLProtocol.makeSession(json: Self.githubList)
        let client = ForgeClient(
            locator: try locator("https://github.com/o/r.git"), token: "t", session: session)

        let list = try await client.pullRequests(state: nil)
        #expect(list.count == 3)
        #expect(list[0].state == .open)
        #expect(list[1].state == .merged)  // closed + merged_at
        #expect(list[2].state == .closed)  // closed 且没合并
    }

    @Test("GitHub：字段映射")
    func githubFieldMapping() async throws {
        let session = StubURLProtocol.makeSession(json: Self.githubList)
        let client = ForgeClient(
            locator: try locator("https://github.com/o/r.git"), token: "t", session: session)

        let first = try #require(try await client.pullRequests(state: nil).first)
        #expect(first.number == 42)
        #expect(first.title == "feat: 新增导出")
        #expect(first.authorName == "zhangsan")
        #expect(first.sourceBranch == "feature/export")
        #expect(first.targetBranch == "main")
        #expect(first.webURL?.absoluteString == "https://github.com/o/r/pull/42")
    }

    @Test("GitHub：认证头是 Bearer")
    func githubUsesBearerToken() async throws {
        let session = StubURLProtocol.makeSession(json: "[]")
        let client = ForgeClient(
            locator: try locator("https://github.com/o/r.git"), token: "ghp_test", session: session)
        _ = try await client.pullRequests()

        let (request, _) = StubURLProtocol.recordedRequest(for: session)
        let recorded = try #require(request)
        #expect(recorded.value(forHTTPHeaderField: "authorization") == "Bearer ghp_test")
        // 不带版本头时可能返回旧格式
        #expect(recorded.value(forHTTPHeaderField: "x-github-api-version") == "2022-11-28")
        #expect(recorded.url?.path.contains("/repos/o/r/pulls") == true)
    }

    // MARK: - GitLab

    static let gitlabList = """
        [
          {"id":99999,"iid":7,"title":"Draft: 正在做","state":"opened","draft":true,
           "web_url":"https://gitlab.com/g/p/-/merge_requests/7",
           "created_at":"2026-08-01T10:00:00.000Z",
           "author":{"name":"张三","username":"zhangsan"},
           "source_branch":"feature/x","target_branch":"main"},
          {"id":99998,"iid":6,"title":"已合并的","state":"merged",
           "web_url":"https://gitlab.com/g/p/-/merge_requests/6",
           "created_at":"2026-07-30T10:00:00.000Z",
           "author":{"name":"李四","username":"lisi"},
           "source_branch":"fix/y","target_branch":"main"}
        ]
        """

    @Test("GitLab：用 iid 而不是 id")
    func gitlabUsesIID() async throws {
        // id 是全局唯一的内部 id，和界面上显示的 !7 对不上
        let session = StubURLProtocol.makeSession(json: Self.gitlabList)
        let client = ForgeClient(
            locator: try locator("https://gitlab.com/g/p.git"), token: "t", session: session)

        let list = try await client.pullRequests(state: nil)
        #expect(list.map(\.number) == [7, 6])
    }

    @Test("GitLab：状态与草稿")
    func gitlabStateAndDraft() async throws {
        let session = StubURLProtocol.makeSession(json: Self.gitlabList)
        let client = ForgeClient(
            locator: try locator("https://gitlab.com/g/p.git"), token: "t", session: session)

        let list = try await client.pullRequests(state: nil)
        #expect(list[0].state == .open)
        #expect(list[0].isDraft)
        #expect(list[1].state == .merged)
        #expect(list[0].authorName == "张三")  // 优先用 name 而不是 username
    }

    @Test("GitLab：老版本用 work_in_progress 表示草稿")
    func gitlabLegacyDraftField() async throws {
        let session = StubURLProtocol.makeSession(
            json: """
                [{"iid":1,"title":"WIP: x","state":"opened","work_in_progress":true,
                  "source_branch":"a","target_branch":"b"}]
                """)
        let client = ForgeClient(
            locator: try locator("https://gitlab.com/g/p.git"), token: "t", session: session)

        #expect(try await client.pullRequests(state: nil).first?.isDraft == true)
    }

    @Test("GitLab：认证头是 PRIVATE-TOKEN，项目路径要编码")
    func gitlabUsesPrivateToken() async throws {
        let session = StubURLProtocol.makeSession(json: "[]")
        let client = ForgeClient(
            locator: try locator("https://gitlab.com/组/仓库.git"), token: "glpat_x", session: session)
        _ = try await client.pullRequests()

        let (request, _) = StubURLProtocol.recordedRequest(for: session)
        let recorded = try #require(request)
        #expect(recorded.value(forHTTPHeaderField: "private-token") == "glpat_x")
        #expect(recorded.value(forHTTPHeaderField: "authorization") == nil)
        // 路径里不能出现未编码的斜杠或中文
        let path = try #require(recorded.url?.absoluteString)
        #expect(path.contains("/projects/"))
        #expect(!path.contains("/组/"))
    }

    @Test("GitLab：状态名与 GitHub 不同")
    func gitlabStateNames() async throws {
        let session = StubURLProtocol.makeSession(json: "[]")
        let client = ForgeClient(
            locator: try locator("https://gitlab.com/g/p.git"), token: "t", session: session)
        _ = try await client.pullRequests(state: .open)

        let (request, _) = StubURLProtocol.recordedRequest(for: session)
        // GitLab 是 opened 不是 open
        #expect(try #require(request?.url?.query()).contains("state=opened"))
    }

    // MARK: - Gitee

    @Test("Gitee：认证头是 token 前缀，昵称优先")
    func giteeUsesTokenPrefix() async throws {
        let session = StubURLProtocol.makeSession(
            json: """
                [{"number":3,"title":"新功能","state":"open","merged_at":null,
                  "user":{"login":"zhangsan","name":"张三"},
                  "head":{"ref":"f"},"base":{"ref":"master"}}]
                """)
        let client = ForgeClient(
            locator: try locator("git@gitee.com:o/r.git"), token: "gt_x", session: session)

        let list = try await client.pullRequests(state: nil)
        #expect(list.first?.authorName == "张三")

        let (request, _) = StubURLProtocol.recordedRequest(for: session)
        #expect(request?.value(forHTTPHeaderField: "authorization") == "token gt_x")
    }

    // MARK: - 创建

    @Test("创建 PR：GitHub 用 head/base")
    func createsGitHubPullRequest() async throws {
        let session = StubURLProtocol.makeSession(
            json: """
                {"number":50,"title":"新的","state":"open","merged_at":null,"draft":false,
                 "user":{"login":"me"},"head":{"ref":"topic"},"base":{"ref":"main"}}
                """)
        let client = ForgeClient(
            locator: try locator("https://github.com/o/r.git"), token: "t", session: session)

        let created = try await client.createPullRequest(
            NewPullRequest(title: "新的", body: "说明", sourceBranch: "topic", targetBranch: "main"))
        #expect(created.number == 50)

        let (request, body) = StubURLProtocol.recordedRequest(for: session)
        #expect(request?.httpMethod == "POST")

        let data = try #require(body)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let json = try #require(decoded)
        #expect(json["head"] as? String == "topic")
        #expect(json["base"] as? String == "main")
        #expect(json["body"] as? String == "说明")
    }

    @Test("创建 MR：GitLab 用 source_branch/target_branch，草稿靠标题前缀")
    func createsGitLabMergeRequest() async throws {
        let session = StubURLProtocol.makeSession(
            json: """
                {"iid":8,"title":"Draft: 新的","state":"opened","draft":true,
                 "source_branch":"topic","target_branch":"main"}
                """)
        let client = ForgeClient(
            locator: try locator("https://gitlab.com/g/p.git"), token: "t", session: session)

        _ = try await client.createPullRequest(
            NewPullRequest(title: "新的", sourceBranch: "topic", targetBranch: "main", isDraft: true))

        let (_, body) = StubURLProtocol.recordedRequest(for: session)
        let data = try #require(body)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let json = try #require(decoded)

        #expect(json["source_branch"] as? String == "topic")
        #expect(json["target_branch"] as? String == "main")
        // GitLab 没有独立的 draft 字段，用标题前缀
        #expect(json["title"] as? String == "Draft: 新的")
    }

    // MARK: - 错误

    @Test(
        "HTTP 状态码分类",
        arguments: [
            (401, #"{"message":"Bad credentials"}"#, ForgeError.unauthorized),
            (404, #"{"message":"Not Found"}"#, ForgeError.notFound("Not Found")),
            (429, #"{"message":"slow"}"#, ForgeError.rateLimited(retryAfter: nil)),
        ])
    func mapsStatusCodes(status: Int, body: String, expected: ForgeError) async throws {
        let session = StubURLProtocol.makeSession(json: body, statusCode: status)
        let client = ForgeClient(
            locator: try locator("https://github.com/o/r.git"), token: "t", session: session)

        var caught: ForgeError?
        do {
            _ = try await client.pullRequests()
        } catch let error as ForgeError {
            caught = error
        }
        #expect(caught == expected)
    }

    @Test("GitHub 用 403 同时表示没权限和限流，靠报文区分")
    func distinguishesRateLimitFrom403() async throws {
        // 归错类的话，被限流的用户会去检查令牌权限，白折腾
        let session = StubURLProtocol.makeSession(
            json: #"{"message":"API rate limit exceeded for user."}"#, statusCode: 403)
        let client = ForgeClient(
            locator: try locator("https://github.com/o/r.git"), token: "t", session: session)

        var caught: ForgeError?
        do {
            _ = try await client.pullRequests()
        } catch let error as ForgeError {
            caught = error
        }

        guard case .rateLimited = try #require(caught) else {
            Issue.record("应归为限流，实际是 \(String(describing: caught))")
            return
        }
        #expect(caught?.isTransient == true)
    }

    @Test("GitLab 的嵌套错误结构也能挖出人话")
    func extractsGitLabNestedError() async throws {
        let session = StubURLProtocol.makeSession(
            json: #"{"message":{"source_branch":["can't be blank"]}}"#, statusCode: 400)
        let client = ForgeClient(
            locator: try locator("https://gitlab.com/g/p.git"), token: "t", session: session)

        var caught: ForgeError?
        do {
            _ = try await client.pullRequests()
        } catch let error as ForgeError {
            caught = error
        }
        #expect(caught?.localizedMessage.contains("source_branch") == true)
    }

    @Test("响应不是预期结构时报错而不是崩")
    func throwsOnUnexpectedShape() async throws {
        let session = StubURLProtocol.makeSession(json: #"{"unexpected":true}"#)
        let client = ForgeClient(
            locator: try locator("https://github.com/o/r.git"), token: "t", session: session)

        await #expect(throws: ForgeError.self) {
            _ = try await client.pullRequests()
        }
    }
}
