import Foundation
import Testing

@testable import ForgeKit

@Suite("Remote URL 识别")
struct RemoteLocatorTests {

    @Test(
        "各种 URL 形式都能认出来",
        arguments: [
            // HTTPS
            ("https://github.com/owner/repo.git", ForgeKind.github, "github.com", "owner/repo"),
            ("https://github.com/owner/repo", ForgeKind.github, "github.com", "owner/repo"),
            // scp 语法：长得像 URL 但不是，URL(string:) 解析出来 host 是 nil
            ("git@github.com:owner/repo.git", ForgeKind.github, "github.com", "owner/repo"),
            ("git@gitee.com:owner/repo.git", ForgeKind.gitee, "gitee.com", "owner/repo"),
            // ssh:// 带端口
            ("ssh://git@gitlab.example.com:2222/group/repo.git", ForgeKind.gitlab, "gitlab.example.com", "group/repo"),
            // GitLab 嵌套 group
            ("https://gitlab.com/组/子组/仓库.git", ForgeKind.gitlab, "gitlab.com", "组/子组/仓库"),
            // 自建实例
            ("https://gitlab.mycorp.cn/team/app.git", ForgeKind.gitlab, "gitlab.mycorp.cn", "team/app"),
            ("https://github.mycorp.com/team/app.git", ForgeKind.github, "github.mycorp.com", "team/app"),
        ])
    func parsesVariousForms(
        url: String, kind: ForgeKind, host: String, path: String
    ) throws {
        let locator = try #require(RemoteLocator.parse(remoteURL: url))
        #expect(locator.kind == kind)
        #expect(locator.host == host)
        #expect(locator.fullPath == path)
    }

    @Test("URL 里带凭据时不会把凭据当成主机名")
    func stripsCredentialsFromURL() throws {
        let locator = try #require(
            RemoteLocator.parse(remoteURL: "https://user:token@gitlab.example.com/group/repo.git"))
        #expect(locator.host == "gitlab.example.com")
        #expect(locator.fullPath == "group/repo")
    }

    @Test("主机名大小写归一")
    func lowercasesHost() throws {
        let locator = try #require(RemoteLocator.parse(remoteURL: "https://GitHub.COM/Owner/Repo.git"))
        #expect(locator.host == "github.com")
        // 仓库路径的大小写要保留——GitHub 不区分但 GitLab 区分
        #expect(locator.fullPath == "Owner/Repo")
    }

    @Test("嵌套 group 的 owner 与 name")
    func splitsNestedPath() throws {
        let locator = try #require(
            RemoteLocator.parse(remoteURL: "https://gitlab.com/a/b/c/repo.git"))
        #expect(locator.owner == "a/b/c")
        #expect(locator.name == "repo")
    }

    @Test(
        "认不出来的一律返回 nil",
        arguments: [
            "", "   ",
            "https://example.com/owner/repo.git",  // 不认识的主机
            "https://github.com/onlyowner",  // 没有仓库名
            "不是一个 URL",
        ])
    func rejectsUnknown(url: String) {
        #expect(RemoteLocator.parse(remoteURL: url) == nil)
    }

    // MARK: - API 地址

    @Test("GitHub.com 与 Enterprise 的 API 地址不同")
    func githubAPIBase() throws {
        let cloud = try #require(RemoteLocator.parse(remoteURL: "https://github.com/o/r.git"))
        #expect(cloud.apiBaseURL?.absoluteString == "https://api.github.com")

        // Enterprise 走 /api/v3，用的是自己的域名
        let enterprise = try #require(
            RemoteLocator.parse(remoteURL: "https://github.mycorp.com/o/r.git"))
        #expect(enterprise.apiBaseURL?.absoluteString == "https://github.mycorp.com/api/v3")
    }

    @Test("自建 GitLab 的 API 地址跟着自己的域名走")
    func gitlabAPIBase() throws {
        let locator = try #require(
            RemoteLocator.parse(remoteURL: "https://gitlab.mycorp.cn/t/a.git"))
        #expect(locator.apiBaseURL?.absoluteString == "https://gitlab.mycorp.cn/api/v4")
    }

    @Test("Gitee 只有云端一个地址")
    func giteeAPIBase() throws {
        let locator = try #require(RemoteLocator.parse(remoteURL: "git@gitee.com:o/r.git"))
        #expect(locator.apiBaseURL?.absoluteString == "https://gitee.com/api/v5")
    }

    @Test("GitLab 的项目路径要 URL 编码")
    func encodesGitLabPath() throws {
        // GitLab 用编码后的完整路径当项目 ID，斜杠必须被编码
        let locator = try #require(RemoteLocator.parse(remoteURL: "https://gitlab.com/组/仓库.git"))
        #expect(!locator.urlEncodedPath.contains("/"))
        #expect(!locator.urlEncodedPath.contains("组"))
    }

    @Test("网页地址")
    func buildsWebURL() throws {
        let locator = try #require(RemoteLocator.parse(remoteURL: "git@github.com:owner/repo.git"))
        #expect(locator.webURL?.absoluteString == "https://github.com/owner/repo")
    }

    // MARK: - 叫法

    @Test("按平台用它自己的叫法")
    func usesPlatformTerminology() {
        // GitLab 叫 MR，界面上跟着平台走，否则用户对不上号
        #expect(ForgeKind.github.shortNoun == "PR")
        #expect(ForgeKind.gitee.shortNoun == "PR")
        #expect(ForgeKind.gitlab.shortNoun == "MR")
        #expect(ForgeKind.gitlab.requestNoun == "Merge Request")
    }
}
