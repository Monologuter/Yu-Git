import Foundation
import Testing

@testable import GitKit

@Suite("提交文件列表解析")
struct NameStatusParserTests {

    /// 把 `|` 当 NUL 写，测试里看得清楚。
    private func bytes(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "|", with: "\0").utf8)
    }

    @Test("普通改动")
    func parsesPlainChanges() {
        let changes = NameStatusParser.parse(
            bytes("A|Yugit/DesignSystem/Theme.swift|M|Yugit/Features/Detail/DetailView.swift|"))

        #expect(changes.count == 2)
        #expect(changes[0].kind == .added)
        #expect(changes[0].path == "Yugit/DesignSystem/Theme.swift")
        #expect(changes[1].kind == .modified)
    }

    @Test("重命名占两个路径，不能按状态-路径交替读")
    func parsesRenameWithTwoPaths() {
        // 这是从真实 git 抓的格式：R100 后面跟着**旧路径和新路径两个**字段。
        // 按「状态、路径」交替读的话，从这里开始后面所有条目都会错位。
        let changes = NameStatusParser.parse(
            bytes("R100|原始 文件.txt|改名后的 文件.txt|M|别的.swift|"))

        #expect(changes.count == 2)

        guard case let .renamed(from, similarity) = changes[0].kind else {
            Issue.record("第一条应该是重命名，实际是 \(changes[0].kind)")
            return
        }
        #expect(from == "原始 文件.txt")
        #expect(similarity == 100)
        #expect(changes[0].path == "改名后的 文件.txt")
        #expect(changes[0].sourcePath == "原始 文件.txt")

        // 关键断言：重命名后面那条没有跟着错位
        #expect(changes[1].kind == .modified)
        #expect(changes[1].path == "别的.swift")
    }

    @Test("复制也占两个路径")
    func parsesCopy() {
        let changes = NameStatusParser.parse(bytes("C75|模板.swift|副本.swift|"))
        #expect(changes.count == 1)
        guard case let .copied(from, similarity) = changes[0].kind else {
            Issue.record("应该是复制")
            return
        }
        #expect(from == "模板.swift")
        #expect(similarity == 75)
    }

    @Test("带空格与中文的路径原样保留")
    func keepsPathsVerbatim() {
        // 用 -z 就是为了这个：默认输出会把这些路径加引号并转义
        let changes = NameStatusParser.parse(bytes("M|docs/01-竞品调研与功能设计.md|A|a b/c d.txt|"))
        #expect(changes[0].path == "docs/01-竞品调研与功能设计.md")
        #expect(changes[1].path == "a b/c d.txt")
    }

    @Test("空输出不炸")
    func handlesEmpty() {
        #expect(NameStatusParser.parse(Data()).isEmpty)
        #expect(NameStatusParser.parse(bytes("|")).isEmpty)
    }

    @Test("末尾截断时丢掉残缺的那条，而不是编一个出来")
    func dropsTruncatedTail() {
        // 状态说要两个路径但只给了一个——宁可少一条，也不能拿新路径当旧路径
        let changes = NameStatusParser.parse(bytes("M|好的.swift|R100|只有旧路径.txt|"))
        #expect(changes.count == 1)
        #expect(changes[0].path == "好的.swift")
    }

    @Test("认不出的状态字母原样留着")
    func keepsUnknownStatus() {
        let changes = NameStatusParser.parse(bytes("X|奇怪的.txt|"))
        #expect(changes.count == 1)
        #expect(changes[0].kind == .other("X"))
        #expect(changes[0].path == "奇怪的.txt")
    }

    @Test("类型变化")
    func parsesTypeChange() {
        let changes = NameStatusParser.parse(bytes("T|link.txt|"))
        #expect(changes[0].kind == .typeChanged)
    }
}

@Suite("提交文件列表（真实仓库）")
struct CommitFilesIntegrationTests {

    private func head(of sandbox: TemporaryRepository) async throws -> String {
        try await sandbox.git("rev-parse", "HEAD")
            .standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("根提交、重命名、merge 三种形态都能列出文件")
    func listsFilesForEveryCommitShape() async throws {
        let sandbox = try await TemporaryRepository()
        let repo = sandbox.url
        let client = sandbox.client

        // 根提交
        try sandbox.write("one\n", to: "一号.txt")
        try await sandbox.commitAll("根提交")
        let root = try await head(of: sandbox)

        // 重命名
        try await sandbox.git("mv", "一号.txt", "二号.txt")
        try await sandbox.commitAll("改个名")
        let renameCommit = try await head(of: sandbox)

        // 造一个 merge
        try await sandbox.git("checkout", "--quiet", "-b", "side", root)
        try sandbox.write("side\n", to: "侧边.txt")
        try await sandbox.commitAll("侧边提交")
        try await sandbox.git("checkout", "--quiet", "main")
        try await sandbox.git("merge", "--quiet", "--no-ff", "side", "-m", "合并侧边")
        let mergeCommit = try await head(of: sandbox)

        // 根提交没有父，diff-tree 默认输出为空，要靠 --root 才拿得到
        let rootFiles = try await client.filesChanged(inCommit: root, in: repo)
        #expect(rootFiles.map(\.path) == ["一号.txt"])
        #expect(rootFiles.first?.kind == .added)

        let renamed = try await client.filesChanged(inCommit: renameCommit, in: repo)
        #expect(renamed.count == 1)
        #expect(renamed.first?.path == "二号.txt")
        #expect(renamed.first?.sourcePath == "一号.txt")

        // merge 有多个父，diff-tree 不知道跟谁比，默认同样是空输出。
        // 加 --first-parent 也没用（实测），必须显式写 <hash>^1 <hash>。
        let merged = try await client.filesChanged(inCommit: mergeCommit, in: repo)
        #expect(merged.contains { $0.path == "侧边.txt" })
    }
}
