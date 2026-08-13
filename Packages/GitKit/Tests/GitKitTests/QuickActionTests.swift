import Foundation
import Testing

@testable import GitKit

@Suite("Quick Actions")
struct QuickActionTests {

    /// git log 顺序：最新在前。
    private let commits = [
        Commit.stub(hash: "d4", subject: "第 4 条"),
        Commit.stub(hash: "c3", subject: "第 3 条"),
        Commit.stub(hash: "b2", subject: "第 2 条"),
        Commit.stub(hash: "a1", subject: "第 1 条"),
    ]

    // MARK: - 计划生成

    @Test("并进父提交：把自己标成 fixup，不重排任何提交")
    func fixupMarksSelfWithoutReordering() throws {
        // 反过来做（并进更新的那条）需要把两条对调，而对调会让 git 按新顺序
        // 重放补丁，凭空引入本来不存在的冲突
        let plan = try #require(
            QuickAction.fixupIntoParent.makePlan(target: commits[1], in: commits))

        // 范围从 target 的父提交一直到 HEAD——rebase 总是重放到 HEAD，
        // 比 target 更新的提交必然在内，这不是可以省的
        #expect(plan.items.map(\.hash) == ["b2", "c3", "d4"])
        #expect(plan.base == "HEAD~3")
        // 但只有 target 被改标记，其余原样 pick
        #expect(plan.items.first { $0.hash == "c3" }?.action == .fixup)
        #expect(plan.items.filter { $0.action == .pick }.map(\.hash) == ["b2", "d4"])
    }

    @Test("改写信息只覆盖到这一条")
    func rewordTouchesOnlyTarget() throws {
        let plan = try #require(
            QuickAction.reword.makePlan(target: commits[1], in: commits, message: "换个说法"))

        #expect(plan.items.map(\.hash) == ["c3", "d4"])
        let target = try #require(plan.items.first { $0.hash == "c3" })
        #expect(target.action == .reword)
        #expect(target.message == "换个说法")
        // 其余条目不该被改动
        #expect(plan.items.first { $0.hash == "d4" }?.action == .pick)
    }

    @Test("丢弃只标这一条")
    func dropMarksOnlyTarget() throws {
        let plan = try #require(QuickAction.drop.makePlan(target: commits[2], in: commits))
        #expect(plan.items.first { $0.hash == "b2" }?.action == .drop)
        #expect(plan.items.filter { $0.action == .drop }.count == 1)
    }

    @Test("改写最新那条也可以")
    func rewordsNewestCommit() throws {
        let plan = try #require(
            QuickAction.reword.makePlan(target: commits[0], in: commits, message: "新说法"))
        #expect(plan.items.map(\.hash) == ["d4"])
        #expect(plan.base == "HEAD~1")
    }

    @Test("最新那条没有更新的提交，但仍能并进父提交")
    func fixupWorksForNewestCommit() throws {
        let plan = try #require(
            QuickAction.fixupIntoParent.makePlan(target: commits[0], in: commits))
        #expect(plan.items.map(\.hash) == ["c3", "d4"])
        #expect(plan.items[1].action == .fixup)
    }

    @Test("父提交没加载出来时不生成计划")
    func refusesWhenParentNotLoaded() {
        // 只加载了一条，要并进父提交却看不见父提交
        let onlyOne = [commits[0]]
        #expect(QuickAction.fixupIntoParent.makePlan(target: commits[0], in: onlyOne) == nil)
    }

    @Test("目标不在列表里时不生成计划")
    func refusesUnknownTarget() {
        let stranger = Commit.stub(hash: "zz", subject: "别处的提交")
        for action in QuickAction.allCases {
            #expect(action.makePlan(target: stranger, in: commits) == nil)
        }
    }

    @Test("生成的计划本身必须合法")
    func generatedPlansValidate() throws {
        let fixup = try #require(QuickAction.fixupIntoParent.makePlan(target: commits[1], in: commits))
        #expect(fixup.validate().isEmpty)

        let reword = try #require(
            QuickAction.reword.makePlan(target: commits[1], in: commits, message: "有信息"))
        #expect(reword.validate().isEmpty)

        let drop = try #require(QuickAction.drop.makePlan(target: commits[1], in: commits))
        #expect(drop.validate().isEmpty)
    }

    @Test("只加载了一条时丢弃它会被计划校验拦下")
    func droppingTheOnlyLoadedCommitIsRejected() throws {
        let plan = try #require(QuickAction.drop.makePlan(target: commits[0], in: [commits[0]]))
        #expect(plan.validate().contains(.everythingDropped))
    }

    // MARK: - 可用性

    @Test("并进父提交需要父提交在已加载范围内")
    func fixupAvailabilityNeedsParent() {
        #expect(QuickAction.fixupIntoParent.isAvailable(at: 0, loadedCount: 4))
        #expect(QuickAction.fixupIntoParent.isAvailable(at: 2, loadedCount: 4))
        // 最后一条的父提交还没加载
        #expect(!QuickAction.fixupIntoParent.isAvailable(at: 3, loadedCount: 4))
    }

    @Test("改写和丢弃对已加载的任意一条都可用")
    func rewordAndDropAvailableForLoaded() {
        for index in 0..<4 {
            #expect(QuickAction.reword.isAvailable(at: index, loadedCount: 4))
            #expect(QuickAction.drop.isAvailable(at: index, loadedCount: 4))
        }
    }

    @Test("每个动作都有中文标题和说明")
    func allActionsHaveChineseText() {
        for action in QuickAction.allCases {
            #expect(!action.title.isEmpty)
            #expect(!action.explanation.isEmpty)
            #expect(!action.summary(subject: "某条提交").isEmpty)
        }
    }
}

@Suite("Quick Actions 端到端")
struct QuickActionExecutionTests {

    private func makeRepository(commits: Int) async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        for index in 1...commits {
            try repo.write("内容 \(index)\n", to: "file\(index).txt")
            try await repo.commitAll("第 \(index) 条提交")
        }
        return repo
    }

    @Test("并进父提交后只剩一条，保留父提交的信息")
    func fixupIntoParentRuns() async throws {
        let repo = try await makeRepository(commits: 3)
        let log = try await repo.client.log(in: repo.url, maxCount: 3)

        // 把最新那条（第 3 条）并进第 2 条
        let plan = try #require(QuickAction.fixupIntoParent.makePlan(target: log[0], in: log))
        let outcome = try await repo.client.performInteractiveRebase(plan, in: repo.url)
        #expect(outcome == .completed)

        let subjects = try await repo.client.recentSubjects(in: repo.url, limit: 10)
        #expect(subjects == ["第 2 条提交", "第 1 条提交"])

        // 改动要保住：并进去的是内容，不是删掉
        let listing = try await repo.client.runReturningResult(["ls-files"], in: repo.url)
            .standardOutputText
        #expect(listing.contains("file3.txt"))
    }

    @Test("改写中间一条的信息")
    func rewordRuns() async throws {
        let repo = try await makeRepository(commits: 3)
        let log = try await repo.client.log(in: repo.url, maxCount: 3)

        let plan = try #require(
            QuickAction.reword.makePlan(target: log[1], in: log, message: "docs: 换过的说法"))
        let outcome = try await repo.client.performInteractiveRebase(plan, in: repo.url)
        #expect(outcome == .completed)

        let subjects = try await repo.client.recentSubjects(in: repo.url, limit: 10)
        #expect(subjects == ["第 3 条提交", "docs: 换过的说法", "第 1 条提交"])
    }

    @Test("丢弃一条独立的提交")
    func dropRuns() async throws {
        let repo = try await makeRepository(commits: 3)
        let log = try await repo.client.log(in: repo.url, maxCount: 3)

        let plan = try #require(QuickAction.drop.makePlan(target: log[1], in: log))
        let outcome = try await repo.client.performInteractiveRebase(plan, in: repo.url)
        #expect(outcome == .completed)

        let subjects = try await repo.client.recentSubjects(in: repo.url, limit: 10)
        #expect(subjects == ["第 3 条提交", "第 1 条提交"])

        // 被丢的那条的文件也该没了
        let listing = try await repo.client.runReturningResult(["ls-files"], in: repo.url)
            .standardOutputText
        #expect(!listing.contains("file2.txt"))
    }
}
