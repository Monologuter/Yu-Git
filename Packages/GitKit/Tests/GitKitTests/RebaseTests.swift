import Foundation
import Testing

@testable import GitKit

@Suite("Interactive rebase 计划")
struct RebaseTodoTests {

    private func todo(_ actions: [(String, RebaseTodo.Action)]) -> RebaseTodo {
        RebaseTodo(
            base: "base",
            items: actions.enumerated().map { index, pair in
                RebaseTodo.Item(hash: pair.0, originalSubject: "第 \(index + 1) 条", action: pair.1)
            }
        )
    }

    // MARK: - 渲染

    @Test("全 pick 原样渲染")
    func rendersAllPick() {
        let rendered = todo([("aaa", .pick), ("bbb", .pick)]).render(messageFile: { _ in "/tmp/m" })
        #expect(
            rendered == """
                pick aaa 第 1 条
                pick bbb 第 2 条

                """)
    }

    @Test("drop 写成 drop 而不是省略这一行")
    func rendersDropExplicitly() {
        // 留着这行，出问题时看 todo 就知道是有意丢的，不是漏生成
        let rendered = todo([("aaa", .pick), ("bbb", .drop)]).render(messageFile: { _ in "/tmp/m" })
        #expect(rendered.contains("drop bbb"))
    }

    @Test("reword 翻译成 pick 加 exec amend")
    func rendersRewordAsExec() {
        var plan = todo([("aaa", .pick), ("bbb", .reword)])
        plan.items[1].message = "新的标题"

        let rendered = plan.render(messageFile: { _ in "/tmp/msg-bbb" })
        let lines = rendered.split(separator: "\n").map(String.init)

        #expect(lines[1] == "pick bbb 第 2 条")
        #expect(lines[2].hasPrefix("exec git commit --amend"))
        #expect(lines[2].contains("--file='/tmp/msg-bbb'"))
        // rebase 重放历史提交时不该跑钩子，否则会因「旧提交不符合今天的规则」半路失败
        #expect(lines[2].contains("--no-verify"))
    }

    @Test("squash 用 fixup 加 exec，避开合并信息的编辑器")
    func rendersSquashAsFixupPlusAmend() {
        var plan = todo([("aaa", .pick), ("bbb", .squash)])
        plan.items[1].message = "合并后的信息"

        let rendered = plan.render(messageFile: { _ in "/tmp/msg" })
        #expect(rendered.contains("fixup bbb"))
        #expect(rendered.contains("exec git commit --amend"))
        // 不能出现 squash：它会调起编辑器让人合并两条信息，而我们已经拿到了最终信息
        #expect(!rendered.contains("squash "))
    }

    @Test("fixup 不带 exec")
    func rendersFixupAlone() {
        let rendered = todo([("aaa", .pick), ("bbb", .fixup)]).render(messageFile: { _ in "/tmp/m" })
        #expect(rendered.contains("fixup bbb"))
        #expect(!rendered.contains("exec"))
    }

    @Test("标题里的换行会被压平")
    func flattensMultilineSubject() {
        // 不压平的话一行 todo 会被拆成两行，git 解析直接失败
        let plan = RebaseTodo(
            base: "base",
            items: [RebaseTodo.Item(hash: "aaa", originalSubject: "第一行\n第二行")]
        )
        let rendered = plan.render(messageFile: { _ in "/tmp/m" })
        #expect(rendered == "pick aaa 第一行 第二行\n")
    }

    @Test("路径含空格时 exec 行仍然合法")
    func quotesPathsWithSpaces() {
        var plan = todo([("aaa", .pick), ("bbb", .reword)])
        plan.items[1].message = "x"

        let rendered = plan.render(messageFile: { _ in "/Users/我的 项目/.git/yugit/msg" })
        #expect(rendered.contains("--file='/Users/我的 项目/.git/yugit/msg'"))
    }

    // MARK: - 校验

    @Test("第一条不能是 squash")
    func rejectsLeadingSquash() {
        let problems = todo([("aaa", .squash), ("bbb", .pick)]).validate()
        #expect(problems.contains(.leadingSquash))
    }

    @Test("把第一条丢掉后，第二条变成新的第一条，同样不能是 squash")
    func rejectsSquashAfterLeadingDrop() {
        // 只看原始的第一条会漏掉这个 case，而它跑起来就是 git 报错
        let problems = todo([("aaa", .drop), ("bbb", .squash)]).validate()
        #expect(problems.contains(.leadingSquash))
    }

    @Test("全部丢弃被拦下")
    func rejectsDroppingEverything() {
        let problems = todo([("aaa", .drop), ("bbb", .drop)]).validate()
        #expect(problems.contains(.everythingDropped))
    }

    @Test("reword 必须填新信息")
    func requiresMessageForReword() {
        let problems = todo([("aaa", .pick), ("bbb", .reword)]).validate()
        #expect(problems.contains(.missingMessage(hash: "bbb")))
    }

    @Test("只填空白也算没填")
    func treatsBlankMessageAsMissing() {
        var plan = todo([("aaa", .pick), ("bbb", .reword)])
        plan.items[1].message = "   \n  "
        #expect(plan.validate().contains(.missingMessage(hash: "bbb")))
    }

    @Test("合法计划没有问题")
    func acceptsValidPlan() {
        var plan = todo([("aaa", .pick), ("bbb", .squash), ("ccc", .drop)])
        plan.items[1].message = "合并后的信息"
        #expect(plan.validate().isEmpty)
    }

    @Test("全 pick 时无事可做")
    func detectsNoOpPlan() {
        #expect(!todo([("aaa", .pick), ("bbb", .pick)]).hasChanges)
        #expect(todo([("aaa", .pick), ("bbb", .drop)]).hasChanges)
    }

    @Test("从 log 顺序建计划时翻转成 git 的顺序")
    func reversesLogOrder() {
        // git log 最新在前，rebase todo 最旧在前——搞反了会把历史整个倒过来
        let commits = [
            Commit.stub(hash: "ccc", subject: "最新"),
            Commit.stub(hash: "bbb", subject: "中间"),
            Commit.stub(hash: "aaa", subject: "最旧"),
        ]
        let plan = RebaseTodo.fromLogOrder(commits, base: "base")
        #expect(plan.items.map(\.hash) == ["aaa", "bbb", "ccc"])
    }
}

@Suite("Rebase 执行")
struct RebaseExecutionTests {

    /// 造一个有若干条独立提交的仓库（各改各的文件，互不冲突）。
    private func makeRepository(commits: Int) async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        for index in 1...commits {
            try repo.write("内容 \(index)\n", to: "file\(index).txt")
            try await repo.commitAll("第 \(index) 条提交")
        }
        return repo
    }

    private func subjects(_ repo: TemporaryRepository) async throws -> [String] {
        try await repo.client.recentSubjects(in: repo.url, limit: 20)
    }

    @Test("丢弃中间一条提交")
    func dropsMiddleCommit() async throws {
        let repo = try await makeRepository(commits: 3)
        let log = try await repo.client.log(in: repo.url, maxCount: 2)

        var plan = RebaseTodo.fromLogOrder(log, base: "HEAD~2")
        plan.items[0].action = .drop  // 最旧的那条（第 2 条提交）

        let outcome = try await repo.client.performInteractiveRebase(plan, in: repo.url)
        #expect(outcome == .completed)

        let remaining = try await subjects(repo)
        #expect(remaining == ["第 3 条提交", "第 1 条提交"])
    }

    @Test("改写一条提交的信息")
    func rewordsCommit() async throws {
        let repo = try await makeRepository(commits: 3)
        let log = try await repo.client.log(in: repo.url, maxCount: 2)

        var plan = RebaseTodo.fromLogOrder(log, base: "HEAD~2")
        plan.items[1].action = .reword
        plan.items[1].message = "refactor: 换了个说法\n\n正文也在。\n"

        let outcome = try await repo.client.performInteractiveRebase(plan, in: repo.url)
        #expect(outcome == .completed)

        let remaining = try await subjects(repo)
        #expect(remaining.first == "refactor: 换了个说法")
        // 改的是信息不是内容，文件必须还在
        let listing = try await repo.client.runReturningResult(
            ["ls-files"], in: repo.url
        ).standardOutputText
        #expect(listing.contains("file3.txt"))
    }

    @Test("把两条合并成一条")
    func squashesCommits() async throws {
        let repo = try await makeRepository(commits: 3)
        let log = try await repo.client.log(in: repo.url, maxCount: 2)

        var plan = RebaseTodo.fromLogOrder(log, base: "HEAD~2")
        plan.items[1].action = .squash
        plan.items[1].message = "feat: 合并后的一条"

        let outcome = try await repo.client.performInteractiveRebase(plan, in: repo.url)
        #expect(outcome == .completed)

        let remaining = try await subjects(repo)
        #expect(remaining == ["feat: 合并后的一条", "第 1 条提交"])
        // 两条的改动都要保住
        let listing = try await repo.client.runReturningResult(
            ["ls-files"], in: repo.url
        ).standardOutputText
        #expect(listing.contains("file2.txt"))
        #expect(listing.contains("file3.txt"))
    }

    @Test("fixup 保留改动但丢掉信息")
    func fixupKeepsPreviousMessage() async throws {
        let repo = try await makeRepository(commits: 3)
        let log = try await repo.client.log(in: repo.url, maxCount: 2)

        var plan = RebaseTodo.fromLogOrder(log, base: "HEAD~2")
        plan.items[1].action = .fixup

        let outcome = try await repo.client.performInteractiveRebase(plan, in: repo.url)
        #expect(outcome == .completed)

        let remaining = try await subjects(repo)
        #expect(remaining == ["第 2 条提交", "第 1 条提交"])
    }

    @Test("冲突时停下来并报出冲突文件")
    func reportsConflict() async throws {
        // 让两条提交改同一个文件的同一处，丢掉前一条必然冲突
        let repo = try await TemporaryRepository()
        try repo.write("第一版\n", to: "shared.txt")
        try await repo.commitAll("基础")
        try repo.write("第二版\n", to: "shared.txt")
        try await repo.commitAll("改成第二版")
        try repo.write("第三版\n", to: "shared.txt")
        try await repo.commitAll("改成第三版")

        let log = try await repo.client.log(in: repo.url, maxCount: 2)
        var plan = RebaseTodo.fromLogOrder(log, base: "HEAD~2")
        plan.items[0].action = .drop

        let outcome = try await repo.client.performInteractiveRebase(plan, in: repo.url)

        guard case let .conflicted(paths, _) = outcome else {
            Issue.record("应当报告冲突，实际是 \(outcome)")
            return
        }
        #expect(paths == ["shared.txt"])

        // 卡在冲突里时必须能查到进度，否则界面不知道该显示什么
        let progress = try await repo.client.rebaseProgress(in: repo.url)
        #expect(progress != nil)

        // 放弃之后要回到原样
        try await repo.client.abortRebase(in: repo.url)
        #expect(try await repo.client.rebaseProgress(in: repo.url) == nil)
        let restored = try await subjects(repo)
        #expect(restored == ["改成第三版", "改成第二版", "基础"])
    }

    @Test("非法计划不会真的跑起来")
    func refusesInvalidPlan() async throws {
        let repo = try await makeRepository(commits: 2)
        let before = try await subjects(repo)

        let plan = RebaseTodo(
            base: "HEAD~1",
            items: [RebaseTodo.Item(hash: "aaa", originalSubject: "x", action: .squash)]
        )
        let outcome = try await repo.client.performInteractiveRebase(plan, in: repo.url)

        guard case .failed = outcome else {
            Issue.record("非法计划应当直接失败，实际是 \(outcome)")
            return
        }
        #expect(try await subjects(repo) == before)
    }

    @Test("干净的仓库不认为有 rebase 在进行")
    func noProgressWhenIdle() async throws {
        let repo = try await makeRepository(commits: 2)
        #expect(try await repo.client.rebaseProgress(in: repo.url) == nil)
    }
}

@Suite("备份 tag")
struct BackupTagTests {

    @Test("建 tag 并能列出来")
    func createsAndListsTag() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x", to: "a.txt")
        try await repo.commitAll("初始")

        let name = try await repo.client.createBackupTag(in: repo.url, label: "整理提交")
        #expect(name.hasPrefix("yugit-backup/"))

        let tags = try await repo.client.backupTags(in: repo.url)
        #expect(tags.contains(name))
    }

    @Test("同一秒内连建两个不会撞名")
    func avoidsNameCollision() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x", to: "a.txt")
        try await repo.commitAll("初始")

        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try await repo.client.createBackupTag(
            in: repo.url, label: "整理", timestamp: fixed)
        let second = try await repo.client.createBackupTag(
            in: repo.url, label: "整理", timestamp: fixed)

        #expect(first != second)
        #expect(try await repo.client.backupTags(in: repo.url).count == 2)
    }

    @Test("备份 tag 指向操作前的 HEAD，能靠它退回去")
    func tagPointsAtPreRebaseHead() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("1", to: "a.txt")
        try await repo.commitAll("第 1 条")
        try repo.write("2", to: "b.txt")
        try await repo.commitAll("第 2 条")

        let tag = try await repo.client.createBackupTag(in: repo.url, label: "rebase")

        // 改写历史
        var plan = RebaseTodo.fromLogOrder(
            try await repo.client.log(in: repo.url, maxCount: 1), base: "HEAD~1")
        plan.items[0].action = .reword
        plan.items[0].message = "改写过的第 2 条"
        _ = try await repo.client.performInteractiveRebase(plan, in: repo.url)
        #expect(try await repo.client.recentSubjects(in: repo.url).first == "改写过的第 2 条")

        // 靠 tag 退回去——这正是安全网要提供的能力
        _ = try await repo.client.run(["reset", "--hard", tag], in: repo.url)
        #expect(try await repo.client.recentSubjects(in: repo.url).first == "第 2 条")
    }

    @Test(
        "tag 名里的非法字符被压掉",
        arguments: [
            ("整理 提交", "整理-提交"),
            ("feat: 新功能", "feat-新功能"),
            ("a~b^c:d?e*f[g", "a-b-c-d-e-f-g"),
            ("...", "backup"),
            ("", "backup"),
        ])
    func sanitizesTagComponent(input: String, expected: String) {
        #expect(GitClient.sanitizeTagComponent(input) == expected)
    }

    @Test("压过的 tag 名 git 一定收")
    func sanitizedNamesAreAcceptedByGit() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x", to: "a.txt")
        try await repo.commitAll("初始")

        // 挑一批真会出现在操作名里的刁钻字符
        for label in ["整理 提交", "feat: 新功能", "fix/网络~超时", "a..b", "结尾的点."] {
            let name = try await repo.client.createBackupTag(in: repo.url, label: label)
            let check = try await repo.client.runReturningResult(
                ["rev-parse", "--verify", "refs/tags/\(name)"], in: repo.url)
            #expect(check.isSuccess, "git 拒绝了 tag 名：\(name)")
        }
    }
}

@Suite("Rebase 进时间线")
struct RebaseTimelineTests {

    @Test("rebase 会先拍快照并留下记录")
    func recordsAndSnapshots() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("1", to: "a.txt")
        try await repo.commitAll("第 1 条")
        try repo.write("2", to: "b.txt")
        try await repo.commitAll("第 2 条")

        let log = InMemoryOperationLog()
        let actor = try await RepoActor(root: repo.url, client: repo.client, operationLog: log)

        var plan = RebaseTodo.fromLogOrder(
            try await repo.client.log(in: repo.url, maxCount: 1), base: "HEAD~1")
        plan.items[0].action = .reword
        plan.items[0].message = "改写过的第 2 条"

        let (outcome, backupTag) = try await actor.performRebase(plan, summary: "整理最近 1 条提交")
        #expect(outcome == .completed)

        // 安全网必须真的建起来，且指向改写前的 HEAD
        let tag = try #require(backupTag)
        #expect(tag.hasPrefix("yugit-backup/"))

        // 时间线上要看得见这一步，且被标为改写历史
        let entries = try await actor.timelineEntries()
        let rebaseEntry = try #require(entries.last)
        #expect(rebaseEntry.record.operation.kind == .interactiveRebase)
        #expect(rebaseEntry.record.operation.hazard == .rewritesHistory)
        #expect(rebaseEntry.record.outcome.isSuccess)
        // 改写历史属于危险操作，执行前必须留了快照
        #expect(rebaseEntry.record.snapshotReference != nil)
    }

    @Test("冲突停下时记成失败而不是成功")
    func recordsConflictAsFailure() async throws {
        // performInteractiveRebase 遇冲突是「正常返回一个冲突结果」而不是抛错，
        // 不特别处理的话时间线上会显示成做成了
        let repo = try await TemporaryRepository()
        try repo.write("第一版\n", to: "shared.txt")
        try await repo.commitAll("基础")
        try repo.write("第二版\n", to: "shared.txt")
        try await repo.commitAll("第二版")
        try repo.write("第三版\n", to: "shared.txt")
        try await repo.commitAll("第三版")

        let log = InMemoryOperationLog()
        let actor = try await RepoActor(root: repo.url, client: repo.client, operationLog: log)

        var plan = RebaseTodo.fromLogOrder(
            try await repo.client.log(in: repo.url, maxCount: 2), base: "HEAD~2")
        plan.items[0].action = .drop

        let (outcome, _) = try await actor.performRebase(plan, summary: "丢掉中间一条")
        guard case .conflicted = outcome else {
            Issue.record("应当冲突，实际是 \(outcome)")
            return
        }

        let entries = try await actor.timelineEntries()
        let entry = try #require(entries.last)
        #expect(!entry.record.outcome.isSuccess)

        try await repo.client.abortRebase(in: repo.url)
    }
}
