import Foundation
import Testing

@testable import GitKit

@Suite("单文件历史与分支对比")
struct FileHistoryTests {

    /// 造一个中途改过名的文件。
    private func makeRenamedFile() async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        try repo.write("v1\n", to: "old.txt")
        try await repo.commitAll("创建 old.txt")
        try repo.write("v2\n", to: "old.txt")
        try await repo.commitAll("改了 old.txt")
        try await repo.git("mv", "old.txt", "new.txt")
        try await repo.commitAll("改名成 new.txt")
        try repo.write("v3\n", to: "new.txt")
        try await repo.commitAll("改了 new.txt")
        return repo
    }

    // MARK: - 单文件历史

    /// 不跨改名的话，一个存在了三年、中途换过名字的文件
    /// 看起来像是上个月才被创建的。
    @Test("跟随改名，看得到改名之前的历史")
    func followsRenames() async throws {
        let repo = try await makeRenamedFile()

        let history = try await repo.client.fileHistory(of: "new.txt", in: repo.url)

        #expect(history.count == 4)
        #expect(history.map(\.subject).contains("创建 old.txt"))
    }

    @Test("关掉跟随就只看这个路径本身")
    func stopsAtTheRenameWithoutFollow() async throws {
        let repo = try await makeRenamedFile()

        let history = try await repo.client.fileHistory(
            of: "new.txt", in: repo.url, follow: false)

        #expect(history.count == 2)
        #expect(!history.map(\.subject).contains("创建 old.txt"))
    }

    /// `--follow` 只接受一个 pathspec，给两个会 fatal。
    /// 这个方法因此只收单个路径，而不是复用 `log(paths:)` 的数组。
    @Test("只收单个路径，签名上就不给传第二个的机会")
    func takesExactlyOnePath() async throws {
        let repo = try await makeRenamedFile()
        // 能跑通就说明没有把多个路径拼进去
        let history = try await repo.client.fileHistory(of: "new.txt", in: repo.url)
        #expect(!history.isEmpty)
    }

    @Test("没有历史的路径返回空数组而不是报错")
    func returnsEmptyForUnknownPaths() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")

        let history = try await repo.client.fileHistory(of: "从来没有过.txt", in: repo.url)
        #expect(history.isEmpty)
    }

    @Test("一条提交都没有的仓库上也不报错")
    func handlesUnbornRepositories() async throws {
        let repo = try await TemporaryRepository()
        #expect(try await repo.client.fileHistory(of: "f.txt", in: repo.url).isEmpty)
    }

    @Test("能限制条数")
    func respectsMaxCount() async throws {
        let repo = try await makeRenamedFile()
        let history = try await repo.client.fileHistory(
            of: "new.txt", in: repo.url, maxCount: 2)
        #expect(history.count == 2)
    }

    // MARK: - 分支对比

    private func makeDivergedBranches() async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        try repo.write("base\n", to: "shared.txt")
        try await repo.commitAll("共同起点")

        try await repo.git("switch", "--quiet", "--create", "feat")
        try repo.write("a\n", to: "a.txt")
        try await repo.commitAll("feat 加了 a")

        try await repo.git("switch", "--quiet", "main")
        try repo.write("b\n", to: "b.txt")
        try await repo.commitAll("main 加了 b")
        try repo.write("c\n", to: "c.txt")
        try await repo.commitAll("main 加了 c")
        return repo
    }

    @Test("分别列出两边各自独有的提交")
    func listsBothDirections() async throws {
        let repo = try await makeDivergedBranches()

        let comparison = try await repo.client.compareBranches(
            base: "main", target: "feat", in: repo.url)

        #expect(comparison.ahead.map(\.subject) == ["feat 加了 a"])
        #expect(comparison.behind.map(\.subject) == ["main 加了 c", "main 加了 b"])
        #expect(comparison.hasDiverged)
    }

    /// 这条是整个对比功能最容易做错的地方。两点比的是两个尖端，
    /// 会把 base 独有的文件列成「被删除」——而那些文件根本不是 target 删的，
    /// 它只是还没有它们。
    @Test("文件差异从共同祖先算起，不把对面的文件说成被删除")
    func usesThreeDotDiff() async throws {
        let repo = try await makeDivergedBranches()

        let comparison = try await repo.client.compareBranches(
            base: "main", target: "feat", in: repo.url)

        // feat 只加了 a.txt。b.txt 和 c.txt 是 main 后来加的，
        // 不该出现在「feat 干了什么」里
        #expect(comparison.files.map(\.path) == ["a.txt"])
        #expect(!comparison.files.contains { $0.path == "b.txt" })
        #expect(!comparison.files.contains { $0.path == "c.txt" })
    }

    /// 对照组：如果用了两点，结果会是什么样。
    /// 留着这条是为了让「为什么必须用三点」有据可查。
    @Test("两点会把对面独有的文件误报成删除")
    func twoDotDiffWouldMisreport() async throws {
        let repo = try await makeDivergedBranches()

        let result = try await repo.client.run(
            ["diff", "--name-status", "-z", "main..feat"], in: repo.url)
        let files = NameStatusParser.parse(result.standardOutput)

        // main 加的 b、c 在这里被说成是被删除的
        #expect(files.contains { $0.path == "b.txt" && $0.kind == .deleted })
        #expect(files.contains { $0.path == "c.txt" && $0.kind == .deleted })
    }

    @Test("找得到共同祖先")
    func findsTheMergeBase() async throws {
        let repo = try await makeDivergedBranches()

        let comparison = try await repo.client.compareBranches(
            base: "main", target: "feat", in: repo.url)

        let ancestor = try #require(comparison.mergeBase)
        let subject = try await repo.client.run(
            ["log", "--format=%s", "-1", ancestor], in: repo.url)
        #expect(subject.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines) == "共同起点")
    }

    /// 毫无关系的两条历史没有共同祖先。那是个正常答案，不是错误——
    /// 界面上要据此说明「这两条分支没有共同起点」。
    @Test("没有共同祖先时返回 nil 而不是抛错")
    func returnsNilForUnrelatedHistories() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("第一条历史")
        // --orphan 开一条毫无关系的历史
        try await repo.git("switch", "--quiet", "--orphan", "unrelated")
        try repo.write("y\n", to: "g.txt")
        try await repo.commitAll("另一条历史")

        let base = try await repo.client.mergeBase("main", "unrelated", in: repo.url)
        #expect(base == nil)
    }

    @Test("完全一样的两个分支：两边都没有独有提交")
    func reportsIdenticalBranches() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        try await repo.git("branch", "copy")

        let comparison = try await repo.client.compareBranches(
            base: "main", target: "copy", in: repo.url)

        #expect(comparison.ahead.isEmpty)
        #expect(comparison.behind.isEmpty)
        #expect(comparison.files.isEmpty)
        #expect(!comparison.hasDiverged)
    }

    @Test("只是落后而没分叉时，hasDiverged 为假")
    func detectsFastForwardOnly() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        try await repo.git("branch", "old")
        try repo.write("y\n", to: "g.txt")
        try await repo.commitAll("main 又走了一步")

        let comparison = try await repo.client.compareBranches(
            base: "old", target: "main", in: repo.url)

        #expect(comparison.ahead.count == 1)
        #expect(comparison.behind.isEmpty)
        #expect(!comparison.hasDiverged)
    }
}
