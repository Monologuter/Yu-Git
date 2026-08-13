import Foundation
import Testing

@testable import GitKit

/// fixture 取自真实 `git worktree list --porcelain -z` 输出。
@Suite("Worktree 解析")
struct WorktreeParserTests {

    /// NUL 分隔的真实输出。条目之间是两个 NUL（一个字段结束 + 一个空行）。
    private func porcelain(_ entries: [[String]]) -> Data {
        var bytes = Data()
        for entry in entries {
            for field in entry {
                bytes.append(contentsOf: Array(field.utf8))
                bytes.append(0x00)
            }
            bytes.append(0x00)
        }
        return bytes
    }

    @Test("主 worktree 加一个附属")
    func parsesTwoWorktrees() throws {
        let data = porcelain([
            ["worktree /repo", "HEAD abc123", "branch refs/heads/main"],
            ["worktree /tmp/wt-feature", "HEAD def456", "branch refs/heads/feature"],
        ])

        let list = WorktreeParser.parse(data)
        #expect(list.count == 2)

        let main = try #require(list.first)
        #expect(main.isMain)
        #expect(main.path == "/repo")
        #expect(main.branch == "main")  // refs/heads/ 前缀要去掉
        #expect(main.head == "abc123")

        let feature = try #require(list.last)
        #expect(!feature.isMain)
        #expect(feature.branch == "feature")
        #expect(feature.displayName == "wt-feature")
    }

    @Test("中文路径、中文分支名、中文锁定原因都不转义")
    func handlesChineseWithoutEscaping() throws {
        // 不带 -z 时 git 会把这三样都转义成 \350\267\221 这种八进制串，
        // 中文用户的仓库里三样都很常见——这正是必须用 -z 的原因
        let data = porcelain([
            ["worktree /仓库", "HEAD abc", "branch refs/heads/主干"],
            ["worktree /tmp/工作树", "HEAD def", "branch refs/heads/特性分支", "locked 跑着测试"],
        ])

        let list = WorktreeParser.parse(data)
        #expect(list[0].branch == "主干")
        #expect(list[1].path == "/tmp/工作树")
        #expect(list[1].branch == "特性分支")
        #expect(list[1].lockReason == "跑着测试")
    }

    @Test("detached HEAD")
    func parsesDetached() throws {
        let data = porcelain([
            ["worktree /repo", "HEAD abc", "branch refs/heads/main"],
            ["worktree /tmp/wt", "HEAD def", "detached"],
        ])

        let wt = try #require(WorktreeParser.parse(data).last)
        #expect(wt.isDetached)
        #expect(wt.branch == nil)
        #expect(wt.head == "def")
    }

    @Test("裸仓库")
    func parsesBare() throws {
        let data = porcelain([["worktree /repo.git", "bare"]])
        let wt = try #require(WorktreeParser.parse(data).first)
        #expect(wt.isBare)
        #expect(wt.head == nil)
        #expect(wt.branch == nil)
    }

    @Test("没写原因的锁定也算锁定")
    func lockWithoutReasonStillLocks() throws {
        // 用空串而不是 nil 表示，否则 isLocked 会漏判
        let data = porcelain([
            ["worktree /repo", "HEAD abc", "branch refs/heads/main"],
            ["worktree /tmp/wt", "HEAD def", "branch refs/heads/x", "locked"],
        ])

        let wt = try #require(WorktreeParser.parse(data).last)
        #expect(wt.isLocked)
        #expect(wt.lockReason == "")
    }

    @Test("可清理的条目")
    func parsesPrunable() throws {
        let data = porcelain([
            ["worktree /repo", "HEAD abc", "branch refs/heads/main"],
            [
                "worktree /tmp/gone", "HEAD def", "branch refs/heads/x",
                "prunable gitdir file points to non-existent location",
            ],
        ])

        let wt = try #require(WorktreeParser.parse(data).last)
        #expect(wt.isPrunable)
        #expect(wt.prunableReason?.contains("non-existent") == true)
    }

    @Test("空输入不产生条目")
    func emptyInputYieldsNothing() {
        #expect(WorktreeParser.parse(Data()).isEmpty)
    }

    @Test("只有主 worktree 时也认得出它是主")
    func singleWorktreeIsMain() throws {
        let data = porcelain([["worktree /repo", "HEAD abc", "branch refs/heads/main"]])
        #expect(try #require(WorktreeParser.parse(data).first).isMain)
    }
}

@Suite("Worktree 操作")
struct WorktreeClientTests {

    private func makeRepository() async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        try repo.write("内容\n", to: "a.txt")
        try await repo.commitAll("初始")
        return repo
    }

    /// worktree 必须建在仓库外面，否则会变成仓库里的一个未跟踪大目录。
    private func siblingPath(of repo: TemporaryRepository, named name: String) -> URL {
        repo.url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: true)
    }

    @Test("新建并列出")
    func addsAndLists() async throws {
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-新特性")
        defer { try? FileManager.default.removeItem(at: path) }

        try await repo.client.addWorktree(
            at: path, branch: "新特性", createBranch: true, in: repo.url)

        let list = try await repo.client.worktrees(in: repo.url)
        #expect(list.count == 2)
        #expect(list[0].isMain)

        let added = try #require(list.last)
        #expect(added.branch == "新特性")
        #expect(!added.isMain)
    }

    @Test("签出已有分支")
    func checksOutExistingBranch() async throws {
        let repo = try await makeRepository()
        _ = try await repo.client.run(["branch", "已存在的"], in: repo.url)

        let path = siblingPath(of: repo, named: "wt-existing")
        defer { try? FileManager.default.removeItem(at: path) }

        try await repo.client.addWorktree(
            at: path, branch: "已存在的", createBranch: false, in: repo.url)

        let list = try await repo.client.worktrees(in: repo.url)
        #expect(list.contains { $0.branch == "已存在的" })
    }

    @Test("移除")
    func removes() async throws {
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-remove")

        try await repo.client.addWorktree(at: path, branch: "临时", createBranch: true, in: repo.url)
        #expect(try await repo.client.worktrees(in: repo.url).count == 2)

        try await repo.client.removeWorktree(
            at: path.path(percentEncoded: false), force: false, in: repo.url)
        #expect(try await repo.client.worktrees(in: repo.url).count == 1)
    }

    @Test("有未提交改动时不加 force 拒绝移除")
    func refusesRemovingDirtyWorktree() async throws {
        // 直接删会丢掉那些改动，界面上必须先问清楚
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-dirty")
        defer { try? FileManager.default.removeItem(at: path) }

        try await repo.client.addWorktree(at: path, branch: "有改动", createBranch: true, in: repo.url)
        try Data("改过了\n".utf8).write(to: path.appendingPathComponent("a.txt"))

        await #expect(throws: GitError.self) {
            try await repo.client.removeWorktree(
                at: path.path(percentEncoded: false), force: false, in: repo.url)
        }
        // 还在
        #expect(try await repo.client.worktrees(in: repo.url).count == 2)
    }

    @Test("锁定与解锁")
    func locksAndUnlocks() async throws {
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-lock")
        defer { try? FileManager.default.removeItem(at: path) }

        let raw = path.path(percentEncoded: false)
        try await repo.client.addWorktree(at: path, branch: "锁定测试", createBranch: true, in: repo.url)

        try await repo.client.lockWorktree(at: raw, reason: "正在跑长测试", in: repo.url)
        var found = try await repo.client.worktrees(in: repo.url).last
        #expect(found?.isLocked == true)
        #expect(found?.lockReason == "正在跑长测试")

        try await repo.client.unlockWorktree(at: raw, in: repo.url)
        found = try await repo.client.worktrees(in: repo.url).last
        #expect(found?.isLocked == false)
    }

    @Test("带状态的列表：领先、落后、脏文件数")
    func reportsStatus() async throws {
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-status")
        defer { try? FileManager.default.removeItem(at: path) }

        try await repo.client.addWorktree(at: path, branch: "干活", createBranch: true, in: repo.url)

        // 在 worktree 里提交两条，再留一个未提交的改动
        for index in 1...2 {
            try Data("第 \(index) 次\n".utf8).write(to: path.appendingPathComponent("b\(index).txt"))
            _ = try await repo.client.run(["add", "-A"], in: path)
            _ = try await repo.client.run(["commit", "-m", "worktree 第 \(index) 条"], in: path)
        }
        try Data("还没提交\n".utf8).write(to: path.appendingPathComponent("dirty.txt"))

        let statuses = try await repo.client.worktreeStatuses(in: repo.url, comparedTo: "main")
        #expect(statuses.count == 2)
        // 并发查完要按原顺序排回来，主 worktree 得在第一个
        #expect(statuses[0].worktree.isMain)

        let worker = try #require(statuses.last)
        #expect(worker.ahead == 2)
        #expect(worker.behind == 0)
        #expect(worker.dirtyFileCount == 1)
        #expect(worker.lastCommitSubject == "worktree 第 2 条")
        // 有东西可合但工作区不干净
        #expect(!worker.isReadyToMerge)
    }

    @Test("干净且领先时判定为可以合了")
    func detectsReadyToMerge() async throws {
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-ready")
        defer { try? FileManager.default.removeItem(at: path) }

        try await repo.client.addWorktree(at: path, branch: "完工", createBranch: true, in: repo.url)
        try Data("做完了\n".utf8).write(to: path.appendingPathComponent("done.txt"))
        _ = try await repo.client.run(["add", "-A"], in: path)
        _ = try await repo.client.run(["commit", "-m", "完成"], in: path)

        let statuses = try await repo.client.worktreeStatuses(in: repo.url, comparedTo: "main")
        let worker = try #require(statuses.last)
        #expect(worker.isReadyToMerge)
    }

    @Test("目录被人删掉后仍然出现在列表里")
    func keepsPrunableEntriesVisible() async throws {
        // 不列出来的话用户不知道该去清理它
        let repo = try await makeRepository()
        let path = siblingPath(of: repo, named: "wt-gone")

        try await repo.client.addWorktree(at: path, branch: "会消失", createBranch: true, in: repo.url)
        try FileManager.default.removeItem(at: path)

        let statuses = try await repo.client.worktreeStatuses(in: repo.url, comparedTo: "main")
        #expect(statuses.count == 2)

        // 查询全失败，但条目还在，状态归零而不是崩
        let gone = try #require(statuses.last)
        #expect(gone.dirtyFileCount == 0)
        #expect(gone.lastCommitSubject == nil)

        try await repo.client.pruneWorktrees(in: repo.url)
        #expect(try await repo.client.worktrees(in: repo.url).count == 1)
    }
}
