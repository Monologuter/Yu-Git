import Foundation
import Testing

@testable import GitKit

/// fixture 取自真实 `git blame --porcelain` 输出。
@Suite("Blame 解析")
struct BlameParserTests {

    /// 真实输出的关键特征：第二行属于同一个 commit 时，元数据全部省略。
    static let porcelain = """
        38b8887f22e4f47760869ff470c3249d950a425d 1 1 2
        author 张三
        author-mail <zhang@example.com>
        author-time 1786650839
        author-tz -0700
        committer 张三
        committer-mail <zhang@example.com>
        committer-time 1786650839
        committer-tz -0700
        summary 人写的提交
        boundary
        filename f.txt
        \t第一行
        38b8887f22e4f47760869ff470c3249d950a425d 2 2
        \t第二行
        487638bf3611095edf1a1334dee91631fd385188 3 3 1
        author 李四
        author-mail <li@example.com>
        author-time 1786650900
        author-tz -0700
        committer 李四
        committer-mail <li@example.com>
        committer-time 1786650900
        committer-tz -0700
        summary feat: AI 写的提交
        previous 38b8887f22e4f47760869ff470c3249d950a425d f.txt
        filename f.txt
        \t第三行

        """

    @Test("逐行解析出归属与内容")
    func parsesLines() throws {
        let (lines, _) = BlameParser.parse(Data(Self.porcelain.utf8), path: "f.txt")

        #expect(lines.count == 3)
        #expect(lines.map(\.content) == ["第一行", "第二行", "第三行"])
        #expect(lines.map(\.finalLineNumber) == [1, 2, 3])
    }

    @Test("同一 commit 第二次出现时元数据被省略，不能因此丢掉作者")
    func reusesCachedCommitMetadata() throws {
        // 这是 porcelain 格式最容易踩的地方：第二行只有一行 sha
        let (lines, commits) = BlameParser.parse(Data(Self.porcelain.utf8), path: "f.txt")

        #expect(lines[0].commit == lines[1].commit)
        #expect(commits.count == 2)

        let first = try #require(commits["38b8887f22e4f47760869ff470c3249d950a425d"])
        #expect(first.authorName == "张三")
        #expect(first.authorEmail == "zhang@example.com")  // 尖括号要去掉
        #expect(first.summary == "人写的提交")
    }

    @Test("原始行号与当前行号分别记录")
    func recordsBothLineNumbers() throws {
        let (lines, _) = BlameParser.parse(Data(Self.porcelain.utf8), path: "f.txt")
        #expect(lines[2].originalLineNumber == 3)
        #expect(lines[2].finalLineNumber == 3)
    }

    @Test("元数据行凑巧有三段时不会被当成组头")
    func doesNotMisreadMetadataAsHeader() {
        // 组头的第一段必须是 40 位十六进制，不校验的话
        // `previous <sha> <file>` 这种行会被误认
        let text = """
            38b8887f22e4f47760869ff470c3249d950a425d 1 1 1
            author 张三
            author-mail <a@b>
            author-time 1
            summary 只有一行
            previous 0000000000000000000000000000000000000000 old.txt
            filename f.txt
            \t内容

            """
        let (lines, commits) = BlameParser.parse(Data(text.utf8), path: "f.txt")
        #expect(lines.count == 1)
        #expect(commits.count == 1)
    }

    @Test("空输入不产生行")
    func emptyInputYieldsNothing() {
        let (lines, commits) = BlameParser.parse(Data(), path: "f.txt")
        #expect(lines.isEmpty)
        #expect(commits.isEmpty)
    }

    @Test("空行内容能正确还原")
    func handlesEmptyContentLines() {
        let text = """
            38b8887f22e4f47760869ff470c3249d950a425d 1 1 1
            author 张三
            author-mail <a@b>
            author-time 1
            summary x
            filename f.txt
            \t

            """
        let (lines, _) = BlameParser.parse(Data(text.utf8), path: "f.txt")
        #expect(lines.count == 1)
        #expect(lines[0].content == "")
    }
}

@Suite("AI 归因识别")
struct AuthorshipDetectorTests {

    @Test(
        "认得出各家工具的署名",
        arguments: [
            ("feat: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>", "Claude"),
            ("fix: y\n\nco-authored-by: claude code", "Claude"),
            ("chore\n\nCo-authored-by: GitHub Copilot <copilot@github.com>", "Copilot"),
            ("feat\n\nCo-authored-by: Cursor Agent <agent@cursor.com>", "Cursor"),
            ("refactor\n\nCo-authored-by: aider (gpt-4) <aider@aider.chat>", "Aider"),
            ("docs\n\n🤖 Generated with [Claude Code](https://claude.com/claude-code)", "Claude"),
        ])
    func detectsKnownTools(message: String, expected: String) {
        #expect(AuthorshipDetector.detect(message: message) == .ai(tool: expected))
    }

    @Test("没有署名的算人工")
    func plainCommitIsHuman() {
        #expect(AuthorshipDetector.detect(message: "fix: 修一个空指针") == .human)
        #expect(AuthorshipDetector.detect(message: "") == .human)
    }

    @Test("人类的 Co-authored-by 不会被误判成 AI")
    func humanCoAuthorStaysHuman() {
        let message = "feat: 一起写的\n\nCo-authored-by: 李四 <li@example.com>"
        #expect(AuthorshipDetector.detect(message: message) == .human)
    }

    @Test("正文里提到 AI 不算 AI 生成")
    func mentioningAIInBodyIsNotAttribution() {
        // 只看署名类的行。搜全文的话，「让 Claude 看了一下」这种人写的提交
        // 会被错标成 AI 生成——把人写的代码标成 AI，比漏标更让人恼火
        let message = """
            fix: 修复登录超时

            这个问题是让 Claude 帮忙定位的，根因是连接池没有释放。
            另外顺手删掉了 copilot 生成的一段废弃代码。
            """
        #expect(AuthorshipDetector.detect(message: message) == .human)
    }

    @Test("大小写不敏感")
    func caseInsensitive() {
        for variant in ["Co-Authored-By: CLAUDE", "co-authored-by: Claude", "CO-AUTHORED-BY: claude"] {
            #expect(AuthorshipDetector.detect(message: "x\n\n\(variant)").isAI)
        }
    }
}

@Suite("Blame 端到端")
struct BlameClientTests {

    @Test("区分人写的行与 AI 参与的行")
    func separatesHumanAndAILines() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("第一行\n第二行\n", to: "f.txt")
        try await repo.commitAll("人写的提交")

        try repo.write("第一行\n第二行\n第三行\n", to: "f.txt")
        _ = try await repo.client.run(["add", "-A"], in: repo.url)
        _ = try await repo.client.run(
            [
                "commit", "-m",
                "feat: AI 写的\n\nCo-Authored-By: Claude <noreply@anthropic.com>",
            ],
            in: repo.url
        )

        let blame = try await repo.client.blame(path: "f.txt", in: repo.url)

        #expect(blame.lines.count == 3)
        #expect(!blame.authorship(ofLine: blame.lines[0]).isAI)
        #expect(!blame.authorship(ofLine: blame.lines[1]).isAI)
        #expect(blame.authorship(ofLine: blame.lines[2]) == .ai(tool: "Claude"))

        #expect(blame.aiLineCount == 1)
        #expect(abs(blame.aiRatio - 1.0 / 3.0) < 0.001)
    }

    @Test("按工具分组统计，多的在前")
    func breaksDownByTool() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("人写的一行\n", to: "f.txt")
        try await repo.commitAll("人写的")

        try repo.write("人写的一行\nAI 第一行\nAI 第二行\n", to: "f.txt")
        _ = try await repo.client.run(["add", "-A"], in: repo.url)
        _ = try await repo.client.run(
            ["commit", "-m", "feat\n\nCo-Authored-By: Claude <x@y>"], in: repo.url)

        let blame = try await repo.client.blame(path: "f.txt", in: repo.url)
        let breakdown = blame.breakdown

        #expect(breakdown.first?.tool == "Claude")
        #expect(breakdown.first?.lineCount == 2)
        #expect(breakdown.last?.tool == "人工")
        #expect(breakdown.last?.lineCount == 1)
    }

    @Test("全是人写的仓库不会误报")
    func allHumanRepositoryReportsZero() async throws {
        // 本项目自己的规范就要求提交信息不带 AI 署名，
        // 所以用驭Git blame 驭Git 应当是 0%
        let repo = try await TemporaryRepository()
        try repo.write("a\nb\nc\n", to: "f.txt")
        try await repo.commitAll("fix: 正常的提交信息")

        let blame = try await repo.client.blame(path: "f.txt", in: repo.url)
        #expect(blame.aiLineCount == 0)
        #expect(blame.aiRatio == 0)
    }

    @Test("批量取提交信息不受数量限制")
    func fetchesManyCommitMessages() async throws {
        // 改动频繁的文件 blame 出几百个 commit 很正常，
        // 全塞进命令行会撞上参数长度上限
        let repo = try await TemporaryRepository()
        var hashes: [String] = []

        for index in 1...40 {
            try repo.write("第 \(index) 版\n", to: "f.txt")
            try await repo.commitAll("第 \(index) 次提交")
            let head = try await repo.client.runReturningResult(
                ["rev-parse", "HEAD"], in: repo.url
            ).standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
            hashes.append(head)
        }

        let messages = try await repo.client.commitMessages(for: hashes, in: repo.url)
        #expect(messages.count == 40)
        #expect(messages.values.contains { $0.contains("第 40 次提交") })
    }

    @Test("空 sha 列表不发请求")
    func emptyHashListReturnsEmpty() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x", to: "f.txt")
        try await repo.commitAll("初始")

        #expect(try await repo.client.commitMessages(for: [], in: repo.url).isEmpty)
    }
}
