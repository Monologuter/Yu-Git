import Foundation
import Testing

@testable import GitKit

/// cherry-pick / revert / reset / tag 四组基础写操作。
///
/// 全部跑真实仓库而不是拼字符串断言：这四样的价值恰恰在于「做完之后仓库变成什么样」，
/// 而那是 git 说了算的。只断言参数拼得对，等于测了我们自己的想象。
@Suite("基础写操作")
struct HistoryOperationTests {

    /// 造一个分叉：main 与 side 各改了同一行，挑取/撤销必然冲突。
    private func makeDivergedRepository() async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        try repo.write("a\nb\nc\n", to: "f.txt")
        try await repo.commitAll("base")

        try await repo.git("switch", "--quiet", "--create", "side")
        try repo.write("a\nSIDE\nc\n", to: "f.txt")
        try await repo.commitAll("side 改了中间那行")

        try await repo.git("switch", "--quiet", "main")
        try repo.write("a\nMAIN\nc\n", to: "f.txt")
        try await repo.commitAll("main 改了中间那行")
        return repo
    }

    private func head(
        of repo: TemporaryRepository, _ revision: String = "HEAD"
    ) async throws
        -> String
    {
        let result = try await repo.client.run(["rev-parse", revision], in: repo.url)
        return result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func subjects(of repo: TemporaryRepository) async throws -> [String] {
        let result = try await repo.client.run(
            ["log", "--format=%s"], in: repo.url)
        return result.standardOutputText.split(separator: "\n").map(String.init)
    }

    private func actor(for repo: TemporaryRepository) async throws -> RepoActor {
        try await RepoActor(root: repo.url, client: repo.client, operationLog: InMemoryOperationLog())
    }

    // MARK: - cherry-pick

    @Test("挑取一条提交会在当前分支生成内容相同、hash 不同的新提交")
    func cherryPicksACommit() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("base\n", to: "f.txt")
        try await repo.commitAll("base")
        try await repo.git("switch", "--quiet", "--create", "side")
        try repo.write("base\n", to: "g.txt")
        try await repo.commitAll("side 加了新文件")
        let sideHead = try await head(of: repo)
        try await repo.git("switch", "--quiet", "main")

        let outcome = try await actor(for: repo).performAllowingConflict(
            .cherryPick(hash: sideHead, subject: "side 加了新文件"))

        #expect(outcome == .completed)
        #expect(try await subjects(of: repo).first == "side 加了新文件")
        // 内容一样，但这是一条新提交
        #expect(try await head(of: repo) != sideHead)
        #expect(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("g.txt").path))
    }

    /// 冲突时 git 返回退出码 1。那**不是失败**，是等人接手的中间状态——
    /// 如果它被当成错误抛出去，界面上就只剩一句「操作失败」，
    /// 而仓库其实正停在一个能解决的地方。
    @Test("挑取冲突时返回冲突结果而不是抛错")
    func reportsCherryPickConflictAsAnOutcome() async throws {
        let repo = try await makeDivergedRepository()
        let sideHead = try await head(of: repo, "side")

        let outcome = try await actor(for: repo).performAllowingConflict(
            .cherryPick(hash: sideHead, subject: "side 改了中间那行"))

        #expect(outcome == .conflicted(paths: ["f.txt"]))
        // 仓库确实停在半途，等着被解决
        let conflicted = try await repo.client.conflictedPaths(in: repo.url)
        #expect(conflicted == ["f.txt"])
    }

    @Test("挑取一个不存在的提交仍然按失败抛出")
    func stillThrowsOnRealFailure() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")

        await #expect(throws: (any Error).self) {
            _ = try await actor(for: repo).performAllowingConflict(
                .cherryPick(hash: "0000000000000000000000000000000000000000", subject: "不存在"))
        }
    }

    // MARK: - revert

    @Test("撤销会生成反向提交，原提交仍在历史里")
    func revertsWithoutRemovingTheOriginal() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("one\n", to: "f.txt")
        try await repo.commitAll("第一条")
        try repo.write("two\n", to: "f.txt")
        try await repo.commitAll("第二条")
        let target = try await head(of: repo)

        let outcome = try await actor(for: repo).performAllowingConflict(
            .revert(hash: target, subject: "第二条"))

        #expect(outcome == .completed)
        let log = try await subjects(of: repo)
        // 原提交还在，只是后面多了一条抵消它的
        #expect(log.contains("第二条"))
        #expect(log.count == 3)
        let contents = try String(contentsOf: repo.url.appendingPathComponent("f.txt"), encoding: .utf8)
        #expect(contents == "one\n")
    }

    /// `--no-edit` 必须在参数里。环境变量 `GIT_EDITOR=true` 兜得住，
    /// 但这条命令是要展示给用户、也能被复制到终端里跑的——在别人的终端里
    /// 没有那个环境变量，少了 `--no-edit` 就会弹出编辑器。
    @Test("撤销命令自带 --no-edit，复制到终端也不会弹编辑器")
    func revertDoesNotRelyOnTheEditorEnvironment() {
        let operation = GitOperation.revert(hash: "abc1234", subject: "x")
        #expect(operation.arguments.contains("--no-edit"))
        #expect(operation.equivalentCommand == "git revert --no-edit abc1234")
    }

    @Test("撤销冲突时同样返回冲突结果")
    func reportsRevertConflictAsAnOutcome() async throws {
        let repo = try await makeDivergedRepository()
        try await repo.git("merge", "--quiet", "--no-edit", "--strategy=ours", "side")
        // 现在 main 上有一条合并提交；撤销 base 之后那条会冲突
        let base = try await head(of: repo, "HEAD~1^")

        let outcome = try await actor(for: repo).performAllowingConflict(
            .revert(hash: base, subject: "base"))

        guard case .conflicted(let paths) = outcome else {
            Issue.record("应当停在冲突上，实际是 \(outcome)")
            return
        }
        #expect(paths == ["f.txt"])
    }

    // MARK: - reset

    /// 三种模式的差别全在这三条断言里。它们也是「拆成三个工厂方法」的理由：
    /// 后果差着一整个「能不能找回来」，不该是参数列表里一个不起眼的枚举值。
    @Test("软重置留下暂存的改动")
    func softResetKeepsEverythingStaged() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("one\n", to: "f.txt")
        try await repo.commitAll("第一条")
        try repo.write("two\n", to: "f.txt")
        try await repo.commitAll("第二条")

        try await actor(for: repo).perform(.resetSoft(to: "HEAD~1"))

        let status = try await repo.status()
        #expect(status.entries.first { $0.path == "f.txt" }?.indexStatus == .modified)
        #expect(try await subjects(of: repo) == ["第一条"])
    }

    @Test("混合重置把改动退回未暂存")
    func mixedResetUnstagesButKeepsTheWorkingTree() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("one\n", to: "f.txt")
        try await repo.commitAll("第一条")
        try repo.write("two\n", to: "f.txt")
        try await repo.commitAll("第二条")

        try await actor(for: repo).perform(.resetMixed(to: "HEAD~1"))

        let entry = try await repo.entry(at: "f.txt")
        #expect(entry?.workTreeStatus == .modified)
        // 文件内容没被动过
        let contents = try String(contentsOf: repo.url.appendingPathComponent("f.txt"), encoding: .utf8)
        #expect(contents == "two\n")
    }

    @Test("硬重置清掉工作区改动")
    func hardResetDiscardsTheWorkingTree() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("one\n", to: "f.txt")
        try await repo.commitAll("第一条")
        try repo.write("two\n", to: "f.txt")
        try await repo.commitAll("第二条")

        try await actor(for: repo).perform(.resetHard(to: "HEAD~1"))

        #expect(try await repo.status().entries.isEmpty)
        let contents = try String(contentsOf: repo.url.appendingPathComponent("f.txt"), encoding: .utf8)
        #expect(contents == "one\n")
    }

    /// 实测得来的事实：`reset --hard` **不删未跟踪文件**。
    /// 说明文案照这个写；说反了比不说更糟——用户会以为新建的文件已经没了，
    /// 转头去别处找。
    @Test("硬重置不碰未跟踪的文件")
    func hardResetLeavesUntrackedFilesAlone() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("one\n", to: "f.txt")
        try await repo.commitAll("第一条")
        try repo.write("草稿\n", to: "scratch.txt")

        try await actor(for: repo).perform(.resetHard(to: "HEAD"))

        #expect(
            FileManager.default.fileExists(
                atPath: repo.url.appendingPathComponent("scratch.txt").path))
        #expect(GitOperation.resetHard(to: "HEAD").explanation.contains("未跟踪的文件不受影响"))
    }

    @Test("只有硬重置会丢掉未提交的内容，另外两种不会")
    func onlyHardResetDiscardsUncommittedWork() {
        #expect(GitOperation.resetSoft(to: "HEAD~1").hazard == .rewritesHistory)
        #expect(GitOperation.resetMixed(to: "HEAD~1").hazard == .rewritesHistory)
        #expect(GitOperation.resetHard(to: "HEAD~1").hazard == .discardsUncommittedWork)
    }

    // MARK: - tag

    @Test("填了说明就打附注 tag，没填是轻量 tag")
    func choosesTagKindByMessage() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let repoActor = try await actor(for: repo)

        try await repoActor.perform(.createTag(name: "v1", message: "第一个版本"))
        try await repoActor.perform(.createTag(name: "bookmark"))

        let result = try await repo.client.run(
            ["for-each-ref", "--format=%(refname:short) %(objecttype)", "refs/tags"], in: repo.url)
        let lines = result.standardOutputText.split(separator: "\n").map(String.init)
        // 附注 tag 是独立的 tag 对象；轻量 tag 直接指向 commit
        #expect(lines.contains("v1 tag"))
        #expect(lines.contains("bookmark commit"))
    }

    /// 只有附注 tag 会被 `git describe` 计入，所以发版必须用它。
    /// 这不是偏好，是 `describe` 的行为——说明文案里写了，这里锁住。
    @Test("git describe 只认附注 tag")
    func describeOnlyCountsAnnotatedTags() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let repoActor = try await actor(for: repo)
        try await repoActor.perform(.createTag(name: "light"))

        let lightweight = try await repo.client.runReturningResult(["describe"], in: repo.url)
        #expect(!lightweight.isSuccess)

        try await repoActor.perform(.createTag(name: "v1", message: "第一个版本"))
        let annotated = try await repo.client.run(["describe"], in: repo.url)
        #expect(annotated.standardOutputText.hasPrefix("v1"))
    }

    @Test("可以在指定提交上打 tag，不只是 HEAD")
    func tagsAnArbitraryCommit() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("one\n", to: "f.txt")
        try await repo.commitAll("第一条")
        let first = try await head(of: repo)
        try repo.write("two\n", to: "f.txt")
        try await repo.commitAll("第二条")

        try await actor(for: repo).perform(
            .createTag(name: "v1", at: first, message: "打在第一条上"))

        let resolved = try await head(of: repo, "v1^{commit}")
        #expect(resolved == first)
    }

    @Test("删掉 tag 之后它指向的提交还在")
    func deletingATagKeepsTheCommit() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let target = try await head(of: repo)
        let repoActor = try await actor(for: repo)
        try await repoActor.perform(.createTag(name: "v1", message: "x"))

        try await repoActor.perform(.deleteTag(name: "v1"))

        let tags = try await repo.client.run(["tag", "--list"], in: repo.url)
        #expect(tags.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        // 提交本身没受影响
        #expect(try await head(of: repo) == target)
    }

    @Test("重名的 tag 打不上去，报错而不是悄悄挪走原来那个")
    func refusesToOverwriteAnExistingTag() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let repoActor = try await actor(for: repo)
        try await repoActor.perform(.createTag(name: "v1", message: "x"))

        await #expect(throws: (any Error).self) {
            try await repoActor.perform(.createTag(name: "v1", message: "又一个"))
        }
    }

    /// 删远程 tag 影响的是别人，不是自己——已经拉过的人本地那份不会消失。
    /// 所以它的 hazard 比删本地 tag 高一档。
    @Test("删远程 tag 的危险等级高于删本地 tag")
    func remoteTagDeletionIsMoreDangerous() {
        #expect(GitOperation.deleteTag(name: "v1").hazard == .none)
        #expect(GitOperation.deleteRemoteTag(name: "v1").hazard == .rewritesHistory)
        #expect(GitOperation.deleteRemoteTag(name: "v1").warning(hasSnapshot: true) != nil)
    }

    // MARK: - 元数据

    /// 架构铁律 2：每个操作都得带上能直接复制到终端的等价命令。
    /// 漏了就是透明命令层和 ⌘K 命令面板缺一块。
    @Test("每个操作都给得出可复制的等价命令")
    func everyOperationCarriesItsCommand() {
        let operations: [GitOperation] = [
            .cherryPick(hash: "abc1234def", subject: "x"),
            .revert(hash: "abc1234def", subject: "x"),
            .resetSoft(to: "HEAD~1"),
            .resetMixed(to: "HEAD~1"),
            .resetHard(to: "HEAD~1"),
            .createTag(name: "v1", message: "第一个版本"),
            .deleteTag(name: "v1"),
            .pushTag(name: "v1"),
            .deleteRemoteTag(name: "v1"),
        ]

        for operation in operations {
            #expect(operation.equivalentCommand.hasPrefix("git "))
            #expect(!operation.summary.isEmpty)
            #expect(!operation.explanation.isEmpty)
        }
    }

    /// 带空格的说明必须被引起来，否则复制到终端里会被拆成两个参数。
    @Test("说明里有空格时等价命令会加引号")
    func quotesArgumentsWithSpaces() {
        let operation = GitOperation.createTag(name: "v1", message: "第一个 版本")
        #expect(operation.equivalentCommand.contains("'第一个 版本'"))
    }

    @Test("摘要里的 hash 缩到七位，分支名和 HEAD~1 原样保留")
    func abbreviatesHashesButNotRevisionNames() {
        #expect(GitOperation.resetSoft(to: "HEAD~1").summary.contains("HEAD~1"))
        #expect(GitOperation.resetSoft(to: "feature/x").summary.contains("feature/x"))
        #expect(
            GitOperation.resetSoft(to: "abc1234def5678").summary.contains("abc1234"))
        #expect(
            !GitOperation.resetSoft(to: "abc1234def5678").summary.contains("abc1234def5678"))
    }
}
