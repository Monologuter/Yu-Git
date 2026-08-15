import Foundation
import Testing

@testable import GitKit

/// 并行 agent 最典型的翻车方式：两个 agent 各改各的，各自都很顺，
/// 合的时候才发现动的是同一个文件。这一套盯的就是「提前看见」。
@Suite("跨 worktree 汇总")
struct WorktreeOverviewTests {

    private func makeRepository() async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        try repo.write("共享\n", to: "shared.txt")
        try repo.write("甲的\n", to: "only-a.txt")
        try repo.write("乙的\n", to: "only-b.txt")
        try await repo.commitAll("初始")
        return repo
    }

    /// worktree 必须建在仓库外面，否则会变成仓库里的一个未跟踪大目录。
    private func siblingPath(of repo: TemporaryRepository, named name: String) -> URL {
        repo.url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
    }

    private func write(_ text: String, to name: String, in directory: URL) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent(name))
    }

    // MARK: - 按目录名查，不要按路径查
    //
    // 临时目录在 `/var/folders/…` 下，而 `/var` 是 `/private/var` 的软链。
    // git 报的是解开之后的真身（`/private/var/…`），Foundation 的
    // `resolvingSymlinksInPath()` 却**反过来**——它会主动把 `/private` 前缀抹掉，
    // 这是它的既定行为。两边永远对不上，所以一律按目录名找。

    private func status(named name: String, in overview: WorktreeOverview) throws -> WorktreeStatus {
        try #require(overview.statuses.first { $0.worktree.displayName == name })
    }

    private func touched(named name: String, in overview: WorktreeOverview) throws -> Set<String> {
        let status = try status(named: name, in: overview)
        return overview.touchedPaths[status.worktree.path] ?? []
    }

    // MARK: - 撞车预警

    @Test("两个 worktree 改了同一个文件时提前告警")
    func warnsWhenTwoWorktreesTouchTheSameFile() async throws {
        let repo = try await makeRepository()
        let pathA = siblingPath(of: repo, named: "wt-甲")
        let pathB = siblingPath(of: repo, named: "wt-乙")
        defer {
            try? FileManager.default.removeItem(at: pathA)
            try? FileManager.default.removeItem(at: pathB)
        }

        try await repo.client.addWorktree(at: pathA, branch: "甲", createBranch: true, in: repo.url)
        try await repo.client.addWorktree(at: pathB, branch: "乙", createBranch: true, in: repo.url)

        // 甲已经提交了，乙还没提交——两种状态都要算进来，
        // 只看未提交的会漏掉这一半
        try write("甲改的\n", to: "shared.txt", in: pathA)
        try write("只有甲\n", to: "only-a.txt", in: pathA)
        _ = try await repo.client.run(["add", "-A"], in: pathA)
        _ = try await repo.client.run(["commit", "-m", "甲的改动"], in: pathA)

        try write("乙改的\n", to: "shared.txt", in: pathB)
        try write("只有乙\n", to: "only-b.txt", in: pathB)

        let overview = try await repo.client.worktreeOverview(in: repo.url, comparedTo: "main")

        #expect(overview.overlaps.count == 1)
        let overlap = try #require(overview.overlaps.first)
        #expect(overlap.path == "shared.txt")
        #expect(overlap.worktreePaths.count == 2)
        #expect(overlap.worktreePaths.allSatisfy { $0.hasSuffix("wt-甲") || $0.hasSuffix("wt-乙") })

        // 各自独有的文件仍然记在名下，只是不算撞车
        #expect(try touched(named: "wt-甲", in: overview).contains("only-a.txt"))
        #expect(try touched(named: "wt-乙", in: overview).contains("only-b.txt"))
    }

    @Test("各改各的文件时不报警")
    func staysQuietWhenNobodyOverlaps() async throws {
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-独立")
        defer { try? FileManager.default.removeItem(at: path) }

        try await repo.client.addWorktree(at: path, branch: "独立", createBranch: true, in: repo.url)
        try write("改了\n", to: "only-a.txt", in: path)
        try repo.write("主仓库改的\n", to: "only-b.txt")

        let overview = try await repo.client.worktreeOverview(in: repo.url, comparedTo: "main")
        #expect(overview.overlaps.isEmpty)
    }

    @Test("一边改名一边修改也算撞上")
    func catchesRenameAgainstEdit() async throws {
        // 只记新名字的话这一对根本对不上：甲报 renamed.txt、乙报 shared.txt，
        // 看起来井水不犯河水，合的时候照样冲突
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-改名")
        defer { try? FileManager.default.removeItem(at: path) }

        try await repo.client.addWorktree(at: path, branch: "改名", createBranch: true, in: repo.url)
        _ = try await repo.client.run(["mv", "shared.txt", "renamed.txt"], in: path)
        _ = try await repo.client.run(["commit", "-m", "改个名"], in: path)

        try repo.write("主仓库也在改\n", to: "shared.txt")

        let overview = try await repo.client.worktreeOverview(in: repo.url, comparedTo: "main")
        let overlap = try #require(overview.overlaps.first { $0.path == "shared.txt" })
        #expect(overlap.worktreePaths.count == 2)
    }

    @Test("基线不存在时给不出结论，而不是硬给一个")
    func degradesWhenBaselineIsUnknown() async throws {
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-无基线")
        defer { try? FileManager.default.removeItem(at: path) }

        try await repo.client.addWorktree(at: path, branch: "无基线", createBranch: true, in: repo.url)
        try write("改了\n", to: "shared.txt", in: path)

        let overview = try await repo.client.worktreeOverview(
            in: repo.url, comparedTo: "查无此分支")

        // 已提交部分算不出来，但未提交的照样看得见
        #expect(overview.statuses.count == 2)
        #expect(try touched(named: "wt-无基线", in: overview).contains("shared.txt"))
    }

    // MARK: - agent 会话

    @Test("worktree 上带出最近一次 AI 会话")
    func surfacesTheLatestSession() async throws {
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-有会话")
        defer { try? FileManager.default.removeItem(at: path) }

        try await repo.client.addWorktree(at: path, branch: "有会话", createBranch: true, in: repo.url)
        try write("agent 写的\n", to: "only-a.txt", in: path)
        _ = try await repo.client.run(["add", "-A"], in: path)
        _ = try await repo.client.run(["commit", "-m", "agent 的提交"], in: path)

        let head = try await repo.client.run(["rev-parse", "HEAD"], in: path)
            .standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        try await repo.client.recordSession(
            AISession(
                tool: "Claude Code", sessionID: "s-1",
                prompt: "把登录重试抽出来", timestamp: Date(timeIntervalSince1970: 1)),
            for: head,
            in: repo.url
        )

        let overview = try await repo.client.worktreeOverview(in: repo.url, comparedTo: "main")
        let worker = try status(named: "wt-有会话", in: overview)
        #expect(worker.session?.tool == "Claude Code")
        #expect(worker.session?.summary == "把登录重试抽出来")

        // 主 worktree 那条提交上没记录，就该是 nil——不猜
        let main = try #require(overview.statuses.first)
        #expect(main.session == nil)
    }

    @Test("没有任何会话记录时不假装知道")
    func leavesSessionEmptyWithoutRecords() async throws {
        let repo = try await makeRepository()
        let overview = try await repo.client.worktreeOverview(in: repo.url, comparedTo: "main")
        #expect(overview.statuses.allSatisfy { $0.session == nil })
    }

    // MARK: - 排序

    @Test("撞的人越多排越前，同样多时按路径排")
    func ordersOverlapsDeterministically() {
        // 字典无序，不固定住的话同一个仓库每次刷新出来的排列都不一样
        let overlaps = WorktreeOverview.findOverlaps(
            in: [
                "/wt-1": ["三个人都碰.txt", "乙丙.txt"],
                "/wt-2": ["三个人都碰.txt", "乙丙.txt", "甲乙.txt"],
                "/wt-3": ["三个人都碰.txt", "甲乙.txt"],
            ],
            order: ["/wt-1", "/wt-2", "/wt-3"]
        )

        #expect(overlaps.map(\.path) == ["三个人都碰.txt", "乙丙.txt", "甲乙.txt"])
        #expect(overlaps[0].worktreePaths == ["/wt-1", "/wt-2", "/wt-3"])
        #expect(overlaps[1].worktreePaths == ["/wt-1", "/wt-2"])
    }

    @Test("只有一个 worktree 碰过的文件不算撞")
    func ignoresSingleOwnerPaths() {
        let overlaps = WorktreeOverview.findOverlaps(
            in: ["/wt-1": ["a.txt", "b.txt"], "/wt-2": ["c.txt"]],
            order: ["/wt-1", "/wt-2"]
        )
        #expect(overlaps.isEmpty)
    }
}
