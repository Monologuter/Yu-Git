import Foundation
import Testing

@testable import GitKit

@Suite("搜索")
struct SearchTests {

    private func seeded() async throws -> TemporaryRepository {
        let repository = try await TemporaryRepository()
        try repository.write("第一行有关键词\n第二行没有\n第三行也有关键词\n", to: "目录/中 文.txt")
        try repository.write("plain file\nkeyword here\n", to: "plain.txt")
        try repository.write("忽略我\n", to: "build/产物.txt")
        try repository.write("build/\n", to: ".gitignore")
        try await repository.commitAll("初始提交，说明里也有关键词")
        return repository
    }

    // MARK: - 内容搜索

    @Test("搜索文件内容并给出行号")
    func searchesContents() async throws {
        let repository = try await seeded()

        let matches = try await repository.client.searchFileContents("关键词", in: repository.url)
        let first = try #require(matches.first)

        #expect(matches.count == 2)
        #expect(first.path == "目录/中 文.txt")
        #expect(first.lineNumber == 1)
        #expect(first.line.contains("第一行"))
        #expect(matches.last?.lineNumber == 3)
    }

    @Test("跳过被 gitignore 忽略的文件")
    func skipsIgnoredFiles() async throws {
        // 用 git grep 而不是自己遍历目录，天然跳过构建产物与依赖目录
        let repository = try await seeded()

        let matches = try await repository.client.searchFileContents("忽略我", in: repository.url)

        #expect(matches.isEmpty, "被忽略的文件不该出现在搜索结果里")
    }

    @Test("默认忽略大小写，可切换为区分")
    func honoursCaseSensitivity() async throws {
        let repository = try await seeded()

        let insensitive = try await repository.client.searchFileContents("KEYWORD", in: repository.url)
        let sensitive = try await repository.client.searchFileContents(
            "KEYWORD", in: repository.url, caseSensitive: true)

        #expect(insensitive.count == 1)
        #expect(sensitive.isEmpty)
    }

    @Test("查询按字面匹配，不当正则解释")
    func treatsQueryAsLiteral() async throws {
        // 用户在搜索框里打的 . 和 * 就是字符本身
        let repository = try await TemporaryRepository()
        try repository.write("a.b.c\naxbxc\n", to: "f.txt")
        try await repository.commitAll("base")

        let matches = try await repository.client.searchFileContents("a.b", in: repository.url)
        let match = try #require(matches.first)

        #expect(matches.count == 1)
        #expect(match.line == "a.b.c", "正则的话 axb 也会命中")
    }

    @Test("没有匹配时返回空数组而不是报错")
    func returnsEmptyWhenNoMatch() async throws {
        // git grep 无匹配时以 1 退出，那不是错误
        let repository = try await seeded()

        let matches = try await repository.client.searchFileContents("绝不会出现的内容", in: repository.url)

        #expect(matches.isEmpty)
    }

    @Test("结果数量受 limit 限制")
    func honoursLimit() async throws {
        let repository = try await TemporaryRepository()
        let manyLines = (1...50).map { "第 \($0) 行含目标\n" }.joined()
        try repository.write(manyLines, to: "f.txt")
        try await repository.commitAll("base")

        let matches = try await repository.client.searchFileContents(
            "目标", in: repository.url, limit: 10)

        #expect(matches.count == 10)
    }

    @Test("空查询直接返回空")
    func ignoresEmptyQuery() async throws {
        let repository = try await seeded()

        #expect(try await repository.client.searchFileContents("", in: repository.url).isEmpty)
        #expect(try await repository.client.searchFilePaths("", in: repository.url).isEmpty)
        #expect(try await repository.client.searchCommits("", in: repository.url).isEmpty)
    }

    // MARK: - 路径搜索

    @Test("按文件名片段搜索，支持中文与空格")
    func searchesPaths() async throws {
        let repository = try await seeded()

        let byName = try await repository.client.searchFilePaths("中 文", in: repository.url)
        let byDirectory = try await repository.client.searchFilePaths("目录", in: repository.url)
        let byExtension = try await repository.client.searchFilePaths(".txt", in: repository.url)

        #expect(byName == ["目录/中 文.txt"])
        #expect(byDirectory == ["目录/中 文.txt"])
        #expect(byExtension.count >= 2)
    }

    @Test("路径搜索忽略大小写")
    func searchesPathsCaseInsensitively() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("x\n", to: "README.md")
        try await repository.commitAll("base")

        let matches = try await repository.client.searchFilePaths("readme", in: repository.url)

        #expect(matches == ["README.md"])
    }

    // MARK: - 提交搜索

    @Test("按提交说明搜索")
    func searchesCommitMessages() async throws {
        let repository = try await seeded()
        try repository.write("x\n", to: "b.txt")
        try await repository.commitAll("另一条完全无关的提交")

        let matches = try await repository.client.searchCommits("关键词", in: repository.url)
        let match = try #require(matches.first)

        #expect(matches.count == 1)
        #expect(match.subject.contains("关键词"))
    }

    @Test("按作者搜索")
    func searchesByAuthor() async throws {
        let repository = try await seeded()
        try repository.write("x\n", to: "c.txt")
        try await repository.git("add", "--all")
        try await repository.git(
            "commit", "--quiet", "--message", "某人的提交",
            "--author", "特殊作者 <special@yugit.local>")

        let matches = try await repository.client.searchCommits("特殊作者", in: repository.url)

        #expect(matches.contains { $0.author.name == "特殊作者" })
    }

    @Test("按 hash 前缀直接定位")
    func searchesByHashPrefix() async throws {
        // 用户复制一段 hash 过来就是想直接跳过去
        let repository = try await seeded()
        let commits = try await repository.client.log(in: repository.url)
        let target = try #require(commits.first)

        let matches = try await repository.client.searchCommits(
            String(target.hash.prefix(8)), in: repository.url)

        #expect(matches.contains { $0.hash == target.hash })
    }

    @Test("搜索覆盖所有分支而不只是当前分支")
    func searchesAcrossBranches() async throws {
        // 用户搜提交时并不关心它在哪个分支上
        let repository = try await seeded()
        try await repository.git("checkout", "--quiet", "-b", "旁支")
        try repository.write("x\n", to: "side.txt")
        try await repository.commitAll("只在旁支上的独特提交")
        try await repository.git("checkout", "--quiet", "main")

        let matches = try await repository.client.searchCommits("独特", in: repository.url)

        #expect(matches.contains { $0.subject.contains("独特") })
    }
}
