import Foundation
import Testing

@testable import GitKit

@Suite("提交历史")
struct HistoryTests {

    // MARK: - 真实仓库

    @Test("空仓库返回空历史而不是报错")
    func handlesUnbornRepository() async throws {
        let repository = try await TemporaryRepository()

        let commits = try await repository.client.log(in: repository.url)

        #expect(commits.isEmpty)
    }

    @Test("解析基本字段：hash、作者、时间、subject、body")
    func parsesBasicFields() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("hello", to: "a.txt")
        try await repository.git("add", "--all")
        try await repository.git("commit", "--quiet", "--message", "首次提交\n\n正文第一行\n正文第二行")

        let commits = try await repository.client.log(in: repository.url)
        let commit = try #require(commits.first)

        #expect(commits.count == 1)
        #expect(commit.hash.count == 40)
        #expect(!commit.abbreviatedHash.isEmpty)
        #expect(commit.abbreviatedHash.count < 40)
        #expect(commit.subject == "首次提交")
        #expect(commit.body == "正文第一行\n正文第二行")
        #expect(commit.message == "首次提交\n\n正文第一行\n正文第二行")
        #expect(commit.author.name == "驭Git 测试")
        #expect(commit.author.email == "test@yugit.local")
        #expect(commit.isRoot)
        #expect(!commit.isMerge)
    }

    @Test("根提交没有父，普通提交有一个父")
    func parsesParents() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("第一条")
        try repository.write("b", to: "b.txt")
        try await repository.commitAll("第二条")

        let commits = try await repository.client.log(in: repository.url)

        #expect(commits.count == 2)
        #expect(commits[0].parents.count == 1, "最新的提交有一个父")
        #expect(commits[0].parents[0] == commits[1].hash)
        #expect(commits[1].parents.isEmpty, "根提交没有父")
        #expect(commits[1].isRoot)
    }

    @Test("合并提交带两个父且被标记为 merge")
    func detectsMergeCommit() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("base", to: "base.txt")
        try await repository.commitAll("base")

        try await repository.git("checkout", "--quiet", "-b", "feature")
        try repository.write("f", to: "f.txt")
        try await repository.commitAll("feature 的提交")

        try await repository.git("checkout", "--quiet", "main")
        try repository.write("m", to: "m.txt")
        try await repository.commitAll("main 的提交")
        try await repository.git("merge", "--quiet", "--no-ff", "feature", "--message", "合并 feature")

        let commits = try await repository.client.log(in: repository.url)
        let merge = try #require(commits.first)

        #expect(merge.isMerge)
        #expect(merge.parents.count == 2)
        #expect(merge.subject == "合并 feature")
    }

    @Test("ref 装饰区分本地分支、tag 与 HEAD")
    func parsesRefDecorations() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("首次提交")
        try await repository.git("tag", "--annotate", "v0.1.0", "--message", "第一个版本")

        let commits = try await repository.client.log(in: repository.url)
        let commit = try #require(commits.first)

        #expect(commit.refs.contains(.head))
        #expect(commit.refs.contains(.localBranch("main")))
        #expect(commit.refs.contains(.tag("v0.1.0")))
    }

    @Test("--all 能看到未被 HEAD 可达的分支提交")
    func includesAllRefs() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("base", to: "base.txt")
        try await repository.commitAll("base")

        try await repository.git("checkout", "--quiet", "-b", "side")
        try repository.write("s", to: "s.txt")
        try await repository.commitAll("只在 side 上的提交")
        try await repository.git("checkout", "--quiet", "main")

        let headOnly = try await repository.client.log(in: repository.url)
        let all = try await repository.client.log(in: repository.url, includingAllRefs: true)

        #expect(headOnly.count == 1)
        #expect(all.count == 2)
        #expect(all.contains { $0.subject == "只在 side 上的提交" })
    }

    @Test("分页参数生效")
    func supportsPagination() async throws {
        let repository = try await TemporaryRepository()
        for index in 1...5 {
            try repository.write("v\(index)", to: "a.txt")
            try await repository.commitAll("第 \(index) 条")
        }

        let firstPage = try await repository.client.log(in: repository.url, maxCount: 2)
        let secondPage = try await repository.client.log(in: repository.url, maxCount: 2, skip: 2)

        #expect(firstPage.count == 2)
        #expect(secondPage.count == 2)
        #expect(firstPage[0].subject == "第 5 条")
        #expect(secondPage[0].subject == "第 3 条")
    }

    @Test("按路径过滤历史")
    func filtersByPath() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "目录/中 文.txt")
        try await repository.commitAll("改中文文件")
        try repository.write("b", to: "other.txt")
        try await repository.commitAll("改另一个文件")

        let filtered = try await repository.client.log(in: repository.url, paths: ["目录/中 文.txt"])

        #expect(filtered.count == 1)
        #expect(filtered[0].subject == "改中文文件")
    }

    @Test("commit message 含分隔符字符时不会被切碎")
    func survivesSeparatorLikeContent() async throws {
        // 用户完全可能在 message 里写竖线、制表符甚至多行，
        // 所以字段分隔符必须用 0x1F/0x1E 这类正文中不会出现的控制字符。
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.git("add", "--all")
        try await repository.git(
            "commit", "--quiet", "--message",
            "带 | 竖线\t和制表符\n\n正文里也有 | 和\t还有第二行"
        )

        let commits = try await repository.client.log(in: repository.url)
        let commit = try #require(commits.first)

        #expect(commit.subject == "带 | 竖线\t和制表符")
        #expect(commit.body == "正文里也有 | 和\t还有第二行")
    }

    @Test("author 与 committer 分离时都能正确解析")
    func separatesAuthorAndCommitter() async throws {
        // amend / rebase / cherry-pick 都会让两者不同，历史界面要能显示这个差异。
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.git("add", "--all")
        try await repository.git(
            "commit", "--quiet", "--message", "作者与提交者不同",
            "--author", "原作者 <author@yugit.local>"
        )

        let commits = try await repository.client.log(in: repository.url)
        let commit = try #require(commits.first)

        #expect(commit.author.name == "原作者")
        #expect(commit.author.email == "author@yugit.local")
        #expect(commit.committer.name == "驭Git 测试")
    }

    @Test("统计提交总数")
    func countsCommits() async throws {
        let repository = try await TemporaryRepository()
        let emptyCount = try await repository.client.commitCount(in: repository.url)
        #expect(emptyCount == 0)

        for index in 1...3 {
            try repository.write("v\(index)", to: "a.txt")
            try await repository.commitAll("第 \(index) 条")
        }

        let count = try await repository.client.commitCount(in: repository.url)
        #expect(count == 3)
    }

    // MARK: - 解析器

    @Test("畸形记录报错而不是产出半个 commit")
    func rejectsTruncatedRecord() throws {
        let broken = Data("abc123\u{1f}abc\u{1f}\u{1e}".utf8)

        #expect(throws: GitError.self) {
            try LogParser.parse(broken)
        }
    }

    @Test("空输出解析为空数组")
    func parsesEmptyOutput() throws {
        #expect(try LogParser.parse(Data()).isEmpty)
    }
}

@Suite("ISO 8601 时间戳解析")
struct TimestampParsingTests {

    @Test("解析带正负时区偏移的时间戳")
    func parsesOffsets() throws {
        // 1970-01-01T00:00:00+00:00 = Unix 纪元原点
        let epoch = try #require(LogParser.parseTimestamp("1970-01-01T00:00:00+00:00"))
        #expect(epoch.timeIntervalSince1970 == 0)

        // 东八区的 08:00 就是 UTC 的 00:00
        let east = try #require(LogParser.parseTimestamp("1970-01-01T08:00:00+08:00"))
        #expect(east.timeIntervalSince1970 == 0)

        // 西七区的 -07:00 要加回 7 小时，即 UTC 的 2026-08-13T17:16:06Z
        let west = try #require(LogParser.parseTimestamp("2026-08-13T10:16:06-07:00"))
        let sameInstantInUTC = try #require(LogParser.parseTimestamp("2026-08-13T17:16:06+00:00"))
        #expect(west == sameInstantInUTC)
    }

    @Test("闰年 2 月 29 日与世纪年规则")
    func handlesLeapYears() throws {
        // 2000 年是闰年（能被 400 整除），1900 年不是
        let leap = try #require(LogParser.parseTimestamp("2000-02-29T00:00:00+00:00"))
        #expect(leap.timeIntervalSince1970 == 951782400)

        let afterCentury = try #require(LogParser.parseTimestamp("1900-03-01T00:00:00+00:00"))
        #expect(afterCentury.timeIntervalSince1970 == -2203891200)
    }

    @Test("与 Foundation 的实现结果一致")
    func matchesFoundation() throws {
        // 手写解析器换来了性能，但不能换掉正确性——拿 Foundation 当基准对照。
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let samples = [
            "2026-08-13T10:16:06-07:00",
            "1999-12-31T23:59:59+00:00",
            "2024-02-29T12:00:00+09:30",
            "1970-01-02T03:04:05-11:00",
        ]

        for sample in samples {
            let mine = try #require(LogParser.parseTimestamp(sample))
            let theirs = try #require(formatter.date(from: sample))
            #expect(mine == theirs, "\(sample) 解析结果与 Foundation 不一致")
        }
    }

    @Test("畸形输入返回 nil 而不是错误的日期")
    func rejectsMalformedInput() {
        #expect(LogParser.parseTimestamp("") == nil)
        #expect(LogParser.parseTimestamp("2026-08-13") == nil)
        #expect(LogParser.parseTimestamp("not-a-date-at-all-really!") == nil)
        #expect(LogParser.parseTimestamp("2026-13-13T10:16:06-07:00") == nil, "13 月无效")
        #expect(LogParser.parseTimestamp("2026-08-99T10:16:06-07:00") == nil, "99 日无效")
    }
}

@Suite("最近提交标题")
struct RecentSubjectsTests {

    @Test("按时间倒序取标题")
    func returnsSubjectsNewestFirst() async throws {
        let repo = try await TemporaryRepository()
        for subject in ["feat: 第一步", "fix: 第二步", "docs: 第三步"] {
            try repo.write(subject, to: "notes.md")
            try await repo.commitAll(subject)
        }

        let subjects = try await repo.client.recentSubjects(in: repo.url, limit: 2)
        #expect(subjects == ["docs: 第三步", "fix: 第二步"])
    }

    @Test("标题里有换行也不会被拆成两条")
    func keepsMultilineSubjectIntact() async throws {
        // 用 \u{1E} 而不是换行做记录分隔符，就是为了这个 case
        let repo = try await TemporaryRepository()
        try repo.write("x", to: "a.txt")
        try await repo.commitAll("正常标题")
        try repo.write("y", to: "a.txt")
        try await repo.commitAll("标题第一行\n标题第二行")

        let subjects = try await repo.client.recentSubjects(in: repo.url, limit: 5)
        #expect(subjects.count == 2)
        #expect(subjects.first?.contains("标题第一行") == true)
    }

    @Test("空仓库返回空数组而不是报错")
    func emptyRepositoryReturnsEmpty() async throws {
        let repo = try await TemporaryRepository()
        let subjects = try await repo.client.recentSubjects(in: repo.url)
        #expect(subjects.isEmpty)
    }
}
