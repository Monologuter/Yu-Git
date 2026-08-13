import Foundation
import Testing

@testable import GitKit

@Suite("分批提交")
struct ComposeTests {

    /// 造一个含两处不相干改动的文件：开头一处，结尾一处。
    ///
    /// 两处离得够远，git 才会切成两个独立 hunk——挨得太近会被合并成一个，
    /// 那就测不出「只提交其中一块」了。
    private func makeRepositoryWithTwoHunks() async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        let original = (1...30).map { "第 \($0) 行" }.joined(separator: "\n") + "\n"
        try repo.write(original, to: "app.swift")
        try await repo.commitAll("初始")

        var lines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines[1] = "第 2 行（登录相关改动）"
        lines[27] = "第 28 行（文档相关改动）"
        try repo.write(lines.joined(separator: "\n"), to: "app.swift")

        return repo
    }

    private func makeActor(_ repo: TemporaryRepository) async throws -> RepoActor {
        try await RepoActor(root: repo.url, client: repo.client, operationLog: InMemoryOperationLog())
    }

    private func subjects(_ repo: TemporaryRepository) async throws -> [String] {
        try await repo.client.recentSubjects(in: repo.url, limit: 20)
    }

    @Test("两块改动分两次提交，各自只带自己那块")
    func commitsEachBatchSeparately() async throws {
        let repo = try await makeRepositoryWithTwoHunks()
        let actor = try await makeActor(repo)

        let diff = try await repo.client.diff(of: "app.swift", in: repo.url)
        #expect(diff.hunks.count == 2, "前提不成立：应当切成两个 hunk")

        let result = try await actor.commitInBatches([
            CommitBatch(message: "feat: 登录相关", selection: ["app.swift": [0]]),
            CommitBatch(message: "docs: 文档相关", selection: ["app.swift": [1]]),
        ])

        #expect(result.isComplete)
        #expect(result.committed == 2)
        #expect(try await subjects(repo) == ["docs: 文档相关", "feat: 登录相关", "初始"])

        // 关键：第一次提交只能包含第一块。串批的话第一条会把两处都带走
        let first = try await repo.client.runReturningResult(
            ["show", "--format=", "--unified=0", "HEAD~1"], in: repo.url
        ).standardOutputText
        #expect(first.contains("登录相关改动"))
        #expect(!first.contains("文档相关改动"))

        let second = try await repo.client.runReturningResult(
            ["show", "--format=", "--unified=0", "HEAD"], in: repo.url
        ).standardOutputText
        #expect(second.contains("文档相关改动"))
        #expect(!second.contains("登录相关改动"))
    }

    @Test("全部提交完后工作区是干净的")
    func leavesCleanWorkingTreeWhenAllAssigned() async throws {
        let repo = try await makeRepositoryWithTwoHunks()
        let actor = try await makeActor(repo)

        _ = try await actor.commitInBatches([
            CommitBatch(message: "feat: 第一块", selection: ["app.swift": [0]]),
            CommitBatch(message: "docs: 第二块", selection: ["app.swift": [1]]),
        ])

        let status = try await repo.client.status(of: repo.url)
        #expect(status.isClean)
    }

    @Test("没分配到的改动留在工作区，不会被顺手提交掉")
    func keepsUnassignedChangesInWorkingTree() async throws {
        let repo = try await makeRepositoryWithTwoHunks()
        let actor = try await makeActor(repo)

        let result = try await actor.commitInBatches([
            CommitBatch(message: "feat: 只提交第一块", selection: ["app.swift": [0]])
        ])
        #expect(result.isComplete)

        // 第二块必须还在
        let status = try await repo.client.status(of: repo.url)
        #expect(!status.isClean)

        let remaining = try await repo.client.diff(of: "app.swift", in: repo.url)
        let text = remaining.hunks.flatMap(\.lines).map(\.text).joined(separator: "\n")
        #expect(text.contains("文档相关改动"))
    }

    @Test("上一批的暂存残留不会被下一批带走")
    func clearsIndexBetweenBatches() async throws {
        let repo = try await makeRepositoryWithTwoHunks()
        let actor = try await makeActor(repo)

        // 先手动把整个文件暂存了——模拟用户在打开分组前已经 add 过
        _ = try await repo.client.run(["add", "app.swift"], in: repo.url)

        let result = try await actor.commitInBatches([
            CommitBatch(message: "feat: 只要第一块", selection: ["app.swift": [0]])
        ])
        #expect(result.isComplete)

        // 不清空暂存区的话，这一条会把两块一起提交掉
        let committed = try await repo.client.runReturningResult(
            ["show", "--format=", "--unified=0", "HEAD"], in: repo.url
        ).standardOutputText
        #expect(committed.contains("登录相关改动"))
        #expect(!committed.contains("文档相关改动"))
    }

    @Test("跨文件分组")
    func groupsAcrossFiles() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("原始 a\n", to: "a.swift")
        try repo.write("原始 b\n", to: "b.swift")
        try repo.write("原始 c\n", to: "c.md")
        try await repo.commitAll("初始")

        try repo.write("改过 a\n", to: "a.swift")
        try repo.write("改过 b\n", to: "b.swift")
        try repo.write("改过 c\n", to: "c.md")

        let actor = try await makeActor(repo)
        let result = try await actor.commitInBatches([
            CommitBatch(message: "feat: 代码改动", selection: ["a.swift": [0], "b.swift": [0]]),
            CommitBatch(message: "docs: 文档改动", selection: ["c.md": [0]]),
        ])

        #expect(result.committed == 2)

        let code = try await repo.client.runReturningResult(
            ["show", "--name-only", "--format=", "HEAD~1"], in: repo.url
        ).standardOutputText
        #expect(code.contains("a.swift"))
        #expect(code.contains("b.swift"))
        #expect(!code.contains("c.md"))
    }

    @Test("空批次被跳过，不产生空提交")
    func skipsEmptyBatches() async throws {
        let repo = try await makeRepositoryWithTwoHunks()
        let actor = try await makeActor(repo)

        let result = try await actor.commitInBatches([
            CommitBatch(message: "chore: 什么都没有", selection: [:]),
            CommitBatch(message: "feat: 有内容", selection: ["app.swift": [0]]),
        ])

        #expect(result.committed == 1)
        #expect(try await subjects(repo).first == "feat: 有内容")
    }

    @Test("中途失败时如实报告到第几批，已成功的保留")
    func reportsFailurePosition() async throws {
        let repo = try await makeRepositoryWithTwoHunks()
        let actor = try await makeActor(repo)

        let result = try await actor.commitInBatches([
            CommitBatch(message: "feat: 这批没问题", selection: ["app.swift": [0]]),
            // 指向一个不存在的文件，必然失败
            CommitBatch(message: "fix: 这批会失败", selection: ["不存在.swift": [0]]),
        ])

        #expect(!result.isComplete)
        #expect(result.committed == 1)
        #expect(result.failedAt == 1)
        #expect(result.errorMessage?.contains("第 2 批") == true)

        // 已经成的那批不回滚——回滚要动已生成的 commit，那本身就是改写历史
        #expect(try await subjects(repo).first == "feat: 这批没问题")
    }

    @Test("每一批都进时间线")
    func recordsEveryBatch() async throws {
        let repo = try await makeRepositoryWithTwoHunks()
        let actor = try await makeActor(repo)

        _ = try await actor.commitInBatches([
            CommitBatch(message: "feat: 第一批", selection: ["app.swift": [0]]),
            CommitBatch(message: "docs: 第二批", selection: ["app.swift": [1]]),
        ])

        let entries = try await actor.timelineEntries()
        let commits = entries.filter { $0.record.operation.kind == .commit }
        #expect(commits.count == 2)
        #expect(commits.allSatisfy { $0.record.outcome.isSuccess })
    }

    @Test("已经 add 过的改动也能被正确分批")
    func handlesPreStagedChanges() async throws {
        // 用 `git diff` 取改动的话，已暂存的部分在那里根本看不见，
        // 整批会被当成「没有改动」漏掉——所以必须用相对 HEAD 的 diff
        let repo = try await makeRepositoryWithTwoHunks()
        _ = try await repo.client.run(["add", "app.swift"], in: repo.url)

        let actor = try await makeActor(repo)
        let result = try await actor.commitInBatches([
            CommitBatch(message: "feat: 第一块", selection: ["app.swift": [0]]),
            CommitBatch(message: "docs: 第二块", selection: ["app.swift": [1]]),
        ])

        #expect(result.isComplete)
        #expect(result.committed == 2)
        #expect(try await subjects(repo) == ["docs: 第二块", "feat: 第一块", "初始"])
        #expect(try await repo.client.status(of: repo.url).isClean)
    }

    @Test("分组之后文件又被改过时如实报错，不静默跳过")
    func reportsVanishedChanges() async throws {
        let repo = try await makeRepositoryWithTwoHunks()
        let actor = try await makeActor(repo)

        // 指向一个根本没改过的文件
        try repo.write("没动过\n", to: "untouched.txt")
        try await repo.commitAll("加个没动过的文件")

        let result = try await actor.commitInBatches([
            CommitBatch(message: "fix: 指向没有改动的文件", selection: ["untouched.txt": [0]])
        ])

        #expect(!result.isComplete)
        #expect(result.committed == 0)
        #expect(result.errorMessage?.contains("已经不在工作区") == true)
    }

    @Test("二进制文件整份进，不尝试部分暂存")
    func stagesBinaryFilesWholesale() async throws {
        let repo = try await TemporaryRepository()
        let url = repo.url.appendingPathComponent("icon.bin")
        try Data([0x00, 0x01, 0x02, 0xFF]).write(to: url)
        try repo.write("占位\n", to: "keep.txt")
        try await repo.commitAll("初始")

        try Data([0x00, 0xAA, 0xBB, 0xFF, 0x00]).write(to: url)

        let actor = try await makeActor(repo)
        let result = try await actor.commitInBatches([
            CommitBatch(message: "chore: 换图标", selection: ["icon.bin": [0]])
        ])

        #expect(result.isComplete)
        let files = try await repo.client.runReturningResult(
            ["show", "--name-only", "--format=", "HEAD"], in: repo.url
        ).standardOutputText
        #expect(files.contains("icon.bin"))
    }
}
