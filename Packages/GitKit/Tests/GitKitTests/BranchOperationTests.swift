import Foundation
import Testing

@testable import GitKit

@Suite("分支操作")
struct BranchOperationTests {

    private func makeActor(on repository: TemporaryRepository) -> RepoActor {
        RepoActor(root: repository.url, client: repository.client, operationLog: InMemoryOperationLog())
    }

    private func seeded() async throws -> (TemporaryRepository, RepoActor) {
        let repository = try await TemporaryRepository()
        try repository.write("初始\n", to: "a.txt")
        try await repository.commitAll("base")
        return (repository, makeActor(on: repository))
    }

    @Test("新建并切换分支")
    func createsAndSwitches() async throws {
        let (repository, actor) = try await seeded()

        try await actor.perform(.createBranch(name: "功能/新特性"))

        let current = try #require(await repository.client.currentBranch(in: repository.url))
        #expect(current.name == "功能/新特性")
    }

    @Test("新建分支但不切过去")
    func createsWithoutSwitching() async throws {
        let (repository, actor) = try await seeded()

        try await actor.perform(.createBranch(name: "旁支", checkout: false))

        let branches = try await repository.client.branches(in: repository.url)
        let current = try #require(await repository.client.currentBranch(in: repository.url))
        #expect(branches.contains { $0.name == "旁支" })
        #expect(current.name == "main", "不该切换当前分支")
    }

    @Test("以指定提交为起点新建分支")
    func createsFromStartPoint() async throws {
        let (repository, actor) = try await seeded()
        try repository.write("第二次\n", to: "a.txt")
        try await repository.commitAll("第二条")

        let commits = try await repository.client.log(in: repository.url)
        let firstCommit = try #require(commits.last)

        try await actor.perform(.createBranch(name: "从头开始", startPoint: firstCommit.hash))

        let branch = try #require(await repository.client.currentBranch(in: repository.url))
        #expect(branch.commit == firstCommit.hash)
    }

    @Test("切换分支")
    func switchesBranch() async throws {
        let (repository, actor) = try await seeded()
        try await actor.perform(.createBranch(name: "其他", checkout: false))

        try await actor.perform(.switchBranch(to: "其他"))

        let current = try #require(await repository.client.currentBranch(in: repository.url))
        #expect(current.name == "其他")
    }

    @Test("切到某个提交会进入 detached HEAD")
    func checksOutCommit() async throws {
        let (repository, actor) = try await seeded()
        let commits = try await repository.client.log(in: repository.url)
        let head = try #require(commits.first)

        try await actor.perform(.checkoutCommit(head.hash))

        let status = try await actor.status()
        #expect(status.branch.isDetached)
    }

    @Test("删除已合并的分支")
    func deletesMergedBranch() async throws {
        let (repository, actor) = try await seeded()
        try await actor.perform(.createBranch(name: "待删除", checkout: false))

        try await actor.perform(.deleteBranch(name: "待删除"))

        let branches = try await repository.client.branches(in: repository.url)
        #expect(!branches.contains { $0.name == "待删除" })
    }

    @Test("未合并的分支拒绝普通删除，强删才生效")
    func refusesToDeleteUnmergedBranch() async throws {
        // git 的这层保护很有价值：分支独有的提交删掉后只能靠 reflog 找回
        let (repository, actor) = try await seeded()
        try await actor.perform(.createBranch(name: "有独立提交"))
        try repository.write("只在这个分支上\n", to: "b.txt")
        try await repository.commitAll("独立提交")
        try await actor.perform(.switchBranch(to: "main"))

        await #expect(throws: GitError.self) {
            try await actor.perform(.deleteBranch(name: "有独立提交"))
        }

        try await actor.perform(.deleteBranch(name: "有独立提交", force: true))
        let branches = try await repository.client.branches(in: repository.url)
        #expect(!branches.contains { $0.name == "有独立提交" })
    }

    @Test("强制删除被标记为改写历史")
    func flagsForceDeleteAsHazard() {
        #expect(GitOperation.deleteBranch(name: "x").hazard == .none)
        #expect(GitOperation.deleteBranch(name: "x", force: true).hazard == .rewritesHistory)
        #expect(GitOperation.deleteBranch(name: "x", force: true).arguments == ["branch", "--delete", "--force", "x"])
    }

    @Test("重命名分支")
    func renamesBranch() async throws {
        let (repository, actor) = try await seeded()

        try await actor.perform(.renameBranch(from: "main", to: "主干"))

        let current = try #require(await repository.client.currentBranch(in: repository.url))
        #expect(current.name == "主干")
    }

    @Test("快进合并不产生合并提交")
    func mergesFastForward() async throws {
        let (repository, actor) = try await seeded()
        try await actor.perform(.createBranch(name: "功能"))
        try repository.write("功能内容\n", to: "feature.txt")
        try await repository.commitAll("功能提交")
        try await actor.perform(.switchBranch(to: "main"))

        try await actor.perform(.merge("功能"))

        let commits = try await repository.client.log(in: repository.url)
        #expect(commits.count == 2)
        let hasMergeCommit = commits.contains(where: \.isMerge)
        #expect(!hasMergeCommit, "能快进时不该产生合并提交")
    }

    @Test("--no-ff 强制生成合并提交")
    func mergesWithoutFastForward() async throws {
        let (repository, actor) = try await seeded()
        try await actor.perform(.createBranch(name: "功能"))
        try repository.write("功能内容\n", to: "feature.txt")
        try await repository.commitAll("功能提交")
        try await actor.perform(.switchBranch(to: "main"))

        try await actor.perform(.merge("功能", noFastForward: true))

        let commits = try await repository.client.log(in: repository.url)
        let merge = try #require(commits.first)
        #expect(merge.isMerge)
        #expect(merge.parents.count == 2)
    }

    @Test("合并冲突时操作失败并留下记录")
    func recordsFailedMerge() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("原始\n", to: "f.txt")
        try await repository.commitAll("base")

        let log = InMemoryOperationLog()
        let actor = RepoActor(root: repository.url, client: repository.client, operationLog: log)

        try await actor.perform(.createBranch(name: "分支A"))
        try repository.write("来自 A\n", to: "f.txt")
        try await repository.commitAll("A 的改动")
        try await actor.perform(.switchBranch(to: "main"))
        try repository.write("来自 main\n", to: "f.txt")
        try await repository.commitAll("main 的改动")

        await #expect(throws: GitError.self) {
            try await actor.perform(.merge("分支A"))
        }

        let status = try await actor.status()
        #expect(status.hasConflicts, "冲突应当留在工作区等待解决")

        let records = await log.recent(limit: 20)
        let mergeRecord = try #require(records.last { $0.operation.kind == .merge })
        #expect(!mergeRecord.outcome.isSuccess)
    }

    @Test("设置 upstream 后能报告领先落后")
    func setsUpstream() async throws {
        let origin = try await TemporaryRepository()
        try origin.write("a\n", to: "a.txt")
        try await origin.commitAll("base")

        let clonePath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-upstream-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: clonePath) }
        try await origin.client.run(
            ["clone", "--quiet", origin.url.path, clonePath.path],
            in: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        try await origin.client.run(["config", "user.email", "t@yugit.local"], in: clonePath)
        try await origin.client.run(["config", "user.name", "测试"], in: clonePath)

        let actor = RepoActor(root: clonePath, client: origin.client, operationLog: InMemoryOperationLog())
        try await actor.perform(.createBranch(name: "本地分支"))
        try await actor.perform(.setUpstream(branch: "本地分支", to: "origin/main"))

        let branches = try await origin.client.branches(in: clonePath)
        let branch = try #require(branches.first { $0.name == "本地分支" })
        #expect(branch.upstream == "origin/main")
    }

    @Test("每个分支操作都有中文摘要与等价命令")
    func carriesChineseMetadata() {
        let operations = [
            GitOperation.createBranch(name: "x"),
            GitOperation.switchBranch(to: "x"),
            GitOperation.checkoutCommit("abc1234"),
            GitOperation.deleteBranch(name: "x"),
            GitOperation.renameBranch(from: "a", to: "b"),
            GitOperation.merge("x"),
            GitOperation.setUpstream(branch: "a", to: "origin/a"),
        ]

        for operation in operations {
            #expect(!operation.summary.isEmpty)
            #expect(!operation.explanation.isEmpty)
            #expect(operation.equivalentCommand.hasPrefix("git "))
        }
    }
}
