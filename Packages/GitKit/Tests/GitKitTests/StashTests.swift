import Foundation
import Testing

@testable import GitKit

@Suite("stash 管理")
struct StashTests {

    private func actor(for repo: TemporaryRepository) async throws -> RepoActor {
        try await RepoActor(root: repo.url, client: repo.client, operationLog: InMemoryOperationLog())
    }

    // MARK: - subject 的两种形态

    /// `git stash list` 的 subject 有两种前缀，而它们的后半截含义完全不同。
    /// 只认一种的话，另一种会被切得面目全非。
    @Test("用户写了说明时，说明和分支名各归各位")
    func parsesUserProvidedMessage() {
        let parsed = StashParser.describe("On master: 改了一半的功能")

        #expect(parsed.branch == "master")
        #expect(parsed.message == "改了一半的功能")
        #expect(parsed.baseSubject == nil)
    }

    @Test("自动生成的描述里，储藏点的提交标题不是说明")
    func parsesGeneratedDescription() {
        let parsed = StashParser.describe("WIP on master: 78f2b67 修复登录")

        #expect(parsed.branch == "master")
        // 「修复登录」说的是储藏时 HEAD 停在哪，不是这条 stash 里改了什么
        #expect(parsed.message == nil)
        #expect(parsed.baseSubject == "修复登录")
    }

    /// 判前缀必须用 `hasPrefix`，不能用「包不包含」：
    /// `WIP on master: ...` 里面也含着一个 `on master`。
    @Test("自动生成的那种不会被当成用户写的说明")
    func doesNotMistakeGeneratedForUserMessage() {
        let parsed = StashParser.describe("WIP on master: 78f2b67 base")

        #expect(parsed.branch == "master")
        #expect(parsed.branch != " master")
        #expect(parsed.message == nil)
    }

    @Test("分支名里有斜杠也切得对")
    func handlesSlashesInBranchName() {
        let parsed = StashParser.describe("On feature/login: 半成品")

        #expect(parsed.branch == "feature/login")
        #expect(parsed.message == "半成品")
    }

    @Test("说明里有冒号不会被当成分支名的边界")
    func splitsOnTheFirstColonOnly() {
        let parsed = StashParser.describe("On main: 修复：登录页崩溃")

        #expect(parsed.branch == "main")
        #expect(parsed.message == "修复：登录页崩溃")
    }

    @Test("认不出的形态整段留作说明，不丢")
    func keepsUnrecognizedSubjects() {
        let parsed = StashParser.describe("某种没见过的写法")
        #expect(parsed.message == "某种没见过的写法")
    }

    @Test("从 stash@{12} 里取得出 12")
    func parsesSelectorIndex() {
        #expect(StashParser.index(from: "stash@{0}") == 0)
        #expect(StashParser.index(from: "stash@{12}") == 12)
        #expect(StashParser.index(from: "refs/stash") == nil)
        #expect(StashParser.index(from: "stash@{x}") == nil)
    }

    @Test("字段不全的记录被跳过而不是崩")
    func skipsMalformedRecords() {
        let data = Data("stash@{0}\u{1F}On main: x\u{00}".utf8)
        #expect(StashParser.parse(data).isEmpty)
    }

    // MARK: - 真实仓库

    @Test("读得出栈里每一条的说明、分支与时间")
    func readsTheStack() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("base\n", to: "f.txt")
        try await repo.commitAll("base")

        try repo.write("A\n", to: "f.txt")
        try await repo.git("stash", "push", "--quiet")
        try repo.write("B\n", to: "f.txt")
        try await repo.git("stash", "push", "--quiet", "--message", "改了一半的功能")

        let stack = try await repo.client.stashList(in: repo.url)

        #expect(stack.count == 2)
        // 最新的排在最前面
        #expect(stack[0].index == 0)
        #expect(stack[0].message == "改了一半的功能")
        #expect(stack[0].hasUserMessage)
        #expect(stack[1].index == 1)
        #expect(!stack[1].hasUserMessage)
        #expect(stack[1].branch == "main")
        #expect(!stack[0].hash.isEmpty)
    }

    /// **实测出来的坑**：一条只装着未跟踪文件的 stash，`git stash show` 不带
    /// `--include-untracked` 会返回空输出且退出码 0——界面上就成了「这条是空的」，
    /// 而它其实好好装着东西。不带这个参数的版本看不出任何异常。
    @Test("只装未跟踪文件的储藏也看得见内容")
    func showsUntrackedOnlyStashes() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("base\n", to: "f.txt")
        try await repo.commitAll("base")

        try repo.write("新文件\n", to: "new.txt")
        try await repo.git(
            "stash", "push", "--quiet", "--include-untracked", "--message", "只有未跟踪的")

        let stack = try await repo.client.stashList(in: repo.url)
        let files = try await repo.client.stashFiles(at: #require(stack.first).hash, in: repo.url)

        #expect(files.map(\.path) == ["new.txt"])
    }

    @Test("看得到某一条储藏改了哪些文件")
    func listsChangedFiles() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("base\n", to: "f.txt")
        try repo.write("base\n", to: "g.txt")
        try await repo.commitAll("base")

        try repo.write("改了\n", to: "f.txt")
        try await repo.git("stash", "push", "--quiet", "--message", "x")

        let stack = try await repo.client.stashList(in: repo.url)
        let files = try await repo.client.stashFiles(at: #require(stack.first).hash, in: repo.url)

        #expect(files.map(\.path) == ["f.txt"])
    }

    // MARK: - 索引漂移

    /// 这一组是这个模块里最要紧的部分。`git stash drop` 只认 `stash@{N}`，
    /// 而 N 会漂移；拿着旧的 N 去 drop，删掉的是另一条，
    /// **而被 drop 的 stash 没有正常途径找回来**。
    @Test("删掉中间一条之后，后面的索引全部前移")
    func indicesShiftAfterDropping() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("base\n", to: "f.txt")
        try await repo.commitAll("base")

        for name in ["一", "二", "三"] {
            try repo.write("\(name)\n", to: "f.txt")
            try await repo.git("stash", "push", "--quiet", "--message", name)
        }

        let before = try await repo.client.stashList(in: repo.url)
        // 栈顶是最后压进去的
        #expect(before.map(\.message) == ["三", "二", "一"])
        let oldest = try #require(before.last)
        #expect(oldest.index == 2)

        try await repo.git("stash", "drop", "stash@{0}")

        let after = try await repo.client.stashList(in: repo.url)
        // 同一条 stash，hash 没变，索引变了
        let sameStash = try #require(after.first { $0.hash == oldest.hash })
        #expect(sameStash.index == 1)
        #expect(sameStash.index != oldest.index)
    }

    @Test("丢弃前用 hash 现查位置，删掉的是指定那条")
    func dropsTheIntendedStash() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("base\n", to: "f.txt")
        try await repo.commitAll("base")

        for name in ["一", "二", "三"] {
            try repo.write("\(name)\n", to: "f.txt")
            try await repo.git("stash", "push", "--quiet", "--message", name)
        }

        let stack = try await repo.client.stashList(in: repo.url)
        let target = try #require(stack.first { $0.message == "二" })

        // 在拿到索引之后、执行之前，栈被别处改了——真实场景是用户在终端里
        // 又 stash 了一次，或者删了一条
        try await repo.git("stash", "drop", "stash@{0}")

        let dropped = try await actor(for: repo).dropStash(hash: target.hash, name: "二")

        #expect(dropped)
        let remaining = try await repo.client.stashList(in: repo.url)
        // 删掉的确实是「二」，不是那个索引位置上的新住户
        #expect(remaining.map(\.message) == ["一"])
    }

    @Test("要丢的那条已经不在了就报没做，而不是删掉别的")
    func refusesWhenTheStashIsGone() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("base\n", to: "f.txt")
        try await repo.commitAll("base")

        try repo.write("一\n", to: "f.txt")
        try await repo.git("stash", "push", "--quiet", "--message", "一")
        let stack = try await repo.client.stashList(in: repo.url)
        let target = try #require(stack.first)

        try repo.write("二\n", to: "f.txt")
        try await repo.git("stash", "push", "--quiet", "--message", "二")
        // 目标被别处删了，但它原来的位置上现在坐着「二」
        try await repo.git("stash", "drop", "stash@{1}")

        let dropped = try await actor(for: repo).dropStash(hash: target.hash, name: "一")

        #expect(!dropped)
        // 「二」必须毫发无损
        #expect(try await repo.client.stashList(in: repo.url).map(\.message) == ["二"])
    }

    // MARK: - apply 与 pop

    @Test("应用之后栈里那份还在，取回之后就没了")
    func applyKeepsAndPopRemoves() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("base\n", to: "f.txt")
        try await repo.commitAll("base")
        try repo.write("改了\n", to: "f.txt")
        try await repo.git("stash", "push", "--quiet", "--message", "x")

        let target = try #require(try await repo.client.stashList(in: repo.url).first)
        let repoActor = try await actor(for: repo)

        try await repoActor.perform(.stashApply(hash: target.hash, name: "x"))
        #expect(try await repo.client.stashList(in: repo.url).count == 1)

        // 应用两次会冲突，先把工作区收拾干净
        try await repo.git("checkout", "--", ".")
        let popped = try await repoActor.popStash(hash: target.hash, name: "x")
        #expect(popped)
        #expect(try await repo.client.stashList(in: repo.url).isEmpty)
    }

    // MARK: - 元数据

    /// stash 里装的正是从未提交过的改动，drop 之后 reflog 也管不到。
    @Test("丢弃储藏算作会丢掉未提交内容的操作")
    func droppingIsDestructive() throws {
        let operation = GitOperation.stashDrop(index: 0, name: "x")
        #expect(operation.hazard == .discardsUncommittedWork)

        let warning = try #require(operation.warning(hasSnapshot: true))
        #expect(warning.isDestructive)
    }

    @Test("应用与取回都不算危险操作")
    func applyingIsSafe() {
        #expect(GitOperation.stashApply(hash: "abc", name: "x").hazard == .none)
        #expect(GitOperation.stashPop(index: 0).hazard == .none)
    }

    @Test("没有用户说明时，界面上显示的是储藏点而不是空白")
    func fallsBackToTheBasePoint() {
        let generated = StashEntry(
            index: 0, hash: "abc", date: .init(timeIntervalSince1970: 0),
            branch: "main", message: nil, baseSubject: "修复登录"
        )
        #expect(!generated.hasUserMessage)
        #expect(generated.displayName.contains("修复登录"))

        let named = StashEntry(
            index: 0, hash: "abc", date: .init(timeIntervalSince1970: 0),
            branch: "main", message: "半成品", baseSubject: nil
        )
        #expect(named.displayName == "半成品")
    }
}
