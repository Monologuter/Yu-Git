import Foundation
import Testing

@testable import GitKit

@Suite("Issue 引用识别")
struct IssueReferenceTests {

    private func numbers(in text: String) -> [Int] {
        IssueReferenceScanner.scan(text).map(\.number)
    }

    @Test("认得出常见写法")
    func findsOrdinaryReferences() {
        #expect(numbers(in: "fix: 修复登录 #412") == [412])
        #expect(numbers(in: "#1 起手") == [1])
        #expect(numbers(in: "关掉 #12 和 #34") == [12, 34])
        #expect(numbers(in: "见 (#99)") == [99])
        #expect(numbers(in: "[#7] 前缀写法") == [7])
    }

    /// 规则刻意收紧，宁可漏也不误报：把不是引用的东西变成链接，
    /// 比不变成链接烦人得多——点开是 404，用户会以为 issue 被删了。
    @Test("不误伤看着像引用的东西")
    func avoidsFalsePositives() {
        // 语言名里的 #
        #expect(numbers(in: "改用 C#7 的语法").isEmpty)
        // 颜色值
        #expect(numbers(in: "背景改成 #4A3D8B").isEmpty)
        // 紧贴在别的字符后面
        #expect(numbers(in: "abc#12").isEmpty)
        // 数字后面跟着字母
        #expect(numbers(in: "见 #12a").isEmpty)
        // 前导 0
        #expect(numbers(in: "见 #007").isEmpty)
        // 光一个井号
        #expect(numbers(in: "# 标题").isEmpty)
        #expect(numbers(in: "###").isEmpty)
    }

    @Test("编号太大的不算 issue 号")
    func rejectsAbsurdNumbers() {
        #expect(numbers(in: "见 #123456789").isEmpty)
        #expect(numbers(in: "见 #12345678") == [12_345_678])
    }

    @Test("换行之后仍然认得出")
    func findsReferencesAcrossLines() {
        let message = """
            feat: 新功能

            关闭 #42
            相关 #43
            """
        #expect(numbers(in: message) == [42, 43])
    }

    @Test("范围指向的正是那一段文字")
    func rangesPointAtTheReference() throws {
        let text = "修复登录 #412 的问题"
        let reference = try #require(IssueReferenceScanner.scan(text).first)
        #expect(String(text[reference.range]) == "#412")
    }

    @Test("空文本与没有引用的文本都返回空")
    func handlesTextWithoutReferences() {
        #expect(numbers(in: "").isEmpty)
        #expect(numbers(in: "一句普通的提交信息").isEmpty)
    }

    // MARK: - 链接拼装

    /// 三家的 issue 路径不一样，拼错的话点开是 404——
    /// 那比不给链接更糟，用户会以为 issue 被删了。
    @Test("GitHub 与 Gitee 用 /issues/N")
    func buildsGitHubURLs() {
        #expect(
            IssueURLBuilder.url(forIssue: 42, remoteURL: "https://github.com/owner/repo.git")?
                .absoluteString == "https://github.com/owner/repo/issues/42")
        #expect(
            IssueURLBuilder.url(forIssue: 7, remoteURL: "https://gitee.com/owner/repo.git")?
                .absoluteString == "https://gitee.com/owner/repo/issues/7")
    }

    /// GitLab 是 `-/issues`，少了那个 `-` 就 404。
    @Test("GitLab 用 /-/issues/N")
    func buildsGitLabURLs() {
        #expect(
            IssueURLBuilder.url(forIssue: 42, remoteURL: "https://gitlab.com/owner/repo.git")?
                .absoluteString == "https://gitlab.com/owner/repo/-/issues/42")
        // 自建的也认，因为域名里带 gitlab
        #expect(
            IssueURLBuilder.url(forIssue: 1, remoteURL: "https://gitlab.内网.com/a/b.git")?
                .absoluteString.contains("/-/issues/1") == true)
    }

    @Test("SSH 形式的 remote 也拼得出网页地址")
    func handlesSSHRemotes() {
        #expect(
            IssueURLBuilder.webBase(from: "git@github.com:owner/repo.git")
                == "https://github.com/owner/repo")
        #expect(
            IssueURLBuilder.webBase(from: "ssh://git@github.com/owner/repo.git")
                == "https://github.com/owner/repo")
    }

    @Test("结尾的 .git 与斜杠都去掉")
    func normalizesTrailingParts() {
        #expect(
            IssueURLBuilder.webBase(from: "https://github.com/owner/repo/")
                == "https://github.com/owner/repo")
        #expect(
            IssueURLBuilder.webBase(from: "https://github.com/owner/repo.git/")
                == "https://github.com/owner/repo")
    }

    /// 认不出平台时返回 nil，界面只显示文本不做链接——
    /// 给一个点开是 404 的链接比不给链接糟。
    @Test("本地路径与残缺地址返回 nil")
    func rejectsUnusableRemotes() {
        #expect(IssueURLBuilder.webBase(from: "/Users/me/repo") == nil)
        #expect(IssueURLBuilder.webBase(from: "") == nil)
        // 只有 host 没有 owner/repo
        #expect(IssueURLBuilder.webBase(from: "https://github.com") == nil)
        #expect(IssueURLBuilder.url(forIssue: 1, remoteURL: "/Users/me/repo") == nil)
    }
}
