import Foundation
import Testing

@testable import GitKit

@Suite("分支与 tag")
struct RefTests {

    // MARK: - 分支

    @Test("空仓库没有分支")
    func handlesUnbornRepository() async throws {
        let repository = try await TemporaryRepository()

        let branches = try await repository.client.branches(in: repository.url)

        #expect(branches.isEmpty, "分支要有提交才存在")
    }

    @Test("标记当前分支")
    func marksCurrentBranch() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("首次提交")
        try await repository.git("branch", "其他分支")

        let branches = try await repository.client.branches(in: repository.url)
        let current = try #require(await repository.client.currentBranch(in: repository.url))

        #expect(branches.count == 2)
        #expect(current.name == "main")
        #expect(current.isCurrent)
        #expect(branches.filter(\.isCurrent).count == 1)
    }

    @Test("带出最后一次提交的时间与标题")
    func carriesLastCommitInfo() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("最后这条提交的标题")

        let branch = try #require(await repository.client.currentBranch(in: repository.url))

        #expect(branch.lastCommitSubject == "最后这条提交的标题")
        #expect(branch.lastCommitDate != nil)
    }

    @Test("detached HEAD 时没有当前分支")
    func handlesDetachedHead() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("首次提交")
        try await repository.git("checkout", "--detach", "HEAD")

        let current = try await repository.client.currentBranch(in: repository.url)

        #expect(current == nil)
    }

    @Test("中文分支名不被破坏")
    func handlesUnicodeBranchNames() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("首次提交")
        try await repository.git("branch", "功能/新特性")

        let branches = try await repository.client.branches(in: repository.url)

        #expect(branches.contains { $0.name == "功能/新特性" })
    }

    @Test("过滤掉 refs/remotes/*/HEAD 这个符号引用")
    func skipsRemoteHeadSymbolicRef() async throws {
        // clone 出来的仓库带 refs/remotes/origin/HEAD，它指向默认分支而非真实分支，
        // 留着会在分支列表里多出一个幽灵条目。
        let origin = try await TemporaryRepository()
        try origin.write("a", to: "a.txt")
        try await origin.commitAll("首次提交")

        let clonePath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-clone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: clonePath) }
        try await origin.client.run(
            ["clone", "--quiet", origin.url.path, clonePath.path],
            in: URL(fileURLWithPath: NSTemporaryDirectory())
        )

        let branches = try await origin.client.branches(in: clonePath)

        #expect(!branches.contains { $0.fullName.hasSuffix("/HEAD") })
        #expect(branches.contains { $0.name == "origin/main" && $0.isRemote })
        #expect(branches.contains { $0.name == "main" && !$0.isRemote })
    }

    @Test("解析 upstream 与领先/落后计数")
    func parsesTrackingStatus() async throws {
        let origin = try await TemporaryRepository()
        try origin.write("a", to: "a.txt")
        try await origin.commitAll("首次提交")

        let clonePath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-clone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: clonePath) }
        try await origin.client.run(
            ["clone", "--quiet", origin.url.path, clonePath.path],
            in: URL(fileURLWithPath: NSTemporaryDirectory())
        )
        try await origin.client.run(["config", "user.email", "t@yugit.local"], in: clonePath)
        try await origin.client.run(["config", "user.name", "测试"], in: clonePath)

        // 本地做两次提交，就领先 upstream 两条
        for index in 1...2 {
            try "v\(index)".write(
                to: clonePath.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
            try await origin.client.run(["commit", "--quiet", "--all", "--message", "本地第 \(index) 条"], in: clonePath)
        }

        let branches = try await origin.client.branches(in: clonePath)
        let main = try #require(branches.first { $0.name == "main" })

        #expect(main.upstream == "origin/main")
        #expect(main.tracking.ahead == 2)
        #expect(main.tracking.behind == 0)
        #expect(!main.tracking.isInSync)
        #expect(!main.tracking.hasDiverged)
    }

    @Test("没有 upstream 的分支不报告跟踪状态")
    func handlesBranchWithoutUpstream() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("首次提交")

        let branch = try #require(await repository.client.currentBranch(in: repository.url))

        #expect(branch.upstream == nil)
        #expect(branch.tracking == .notTracking)
        #expect(branch.tracking.isInSync)
    }

    // MARK: - tag

    @Test("区分附注 tag 与轻量 tag")
    func distinguishesAnnotatedAndLightweightTags() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("首次提交")
        try await repository.git("tag", "轻量tag")
        try await repository.git("tag", "--annotate", "v0.1.0", "--message", "第一个版本")

        let tags = try await repository.client.tags(in: repository.url)
        let annotated = try #require(tags.first { $0.name == "v0.1.0" })
        let lightweight = try #require(tags.first { $0.name == "轻量tag" })

        #expect(annotated.isAnnotated)
        #expect(annotated.message == "第一个版本")
        #expect(annotated.tagObject != nil)
        #expect(annotated.tagger?.name == "驭Git 测试")

        #expect(!lightweight.isAnnotated)
        #expect(lightweight.tagObject == nil)
        #expect(lightweight.tagger == nil)
        #expect(
            lightweight.message == nil,
            "轻量 tag 没有自己的消息，不能把它指向的 commit 标题当成 tag 说明"
        )
    }

    @Test("附注 tag 解引用到 commit 而不是 tag 对象")
    func dereferencesAnnotatedTag() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("首次提交")
        try await repository.git("tag", "--annotate", "v0.1.0", "--message", "第一个版本")

        let commits = try await repository.client.log(in: repository.url)
        let tags = try await repository.client.tags(in: repository.url)
        let tag = try #require(tags.first)
        let head = try #require(commits.first)

        #expect(tag.commit == head.hash, "commit 字段要指向 commit，不是 tag 对象自身")
        #expect(tag.tagObject != head.hash)
    }

    @Test("按创建时间倒序排列")
    func sortsTagsByDate() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("首次提交")

        // 显式指定 tagger 时间：连着打三个 tag 会落在同一秒内，
        // 时间相同则排序不确定，测试就会时灵时不灵。
        let dates = [
            "v0.1.0": "2026-01-01T00:00:00+00:00",
            "v0.2.0": "2026-02-01T00:00:00+00:00",
            "v0.10.0": "2026-03-01T00:00:00+00:00",
        ]
        for (name, date) in dates.sorted(by: { $0.value < $1.value }) {
            try await repository.client.run(
                ["tag", "--annotate", name, "--message", "\(name) 的说明"],
                in: repository.url,
                additionalEnvironment: ["GIT_COMMITTER_DATE": date]
            )
        }

        let byDate = try await repository.client.tags(in: repository.url)
        let byName = try await repository.client.tags(in: repository.url, sortedByDate: false)

        #expect(byDate.map(\.name) == ["v0.10.0", "v0.2.0", "v0.1.0"], "最后创建的排在最前")
        #expect(
            byName.map(\.name) == ["v0.1.0", "v0.10.0", "v0.2.0"],
            "按名称是字典序——v0.10.0 会排在 v0.2.0 前面，所以版本列表要按日期排"
        )
    }

    @Test("没有 tag 时返回空数组")
    func handlesNoTags() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a", to: "a.txt")
        try await repository.commitAll("首次提交")

        let tags = try await repository.client.tags(in: repository.url)

        #expect(tags.isEmpty)
    }

    // MARK: - 跟踪状态解析

    @Test("解析各种 upstream:track 形态")
    func parsesTrackingFormats() {
        #expect(RefParser.parseTracking("") == .notTracking)
        #expect(RefParser.parseTracking("[ahead 3]") == TrackingStatus(ahead: 3, behind: 0, isGone: false))
        #expect(RefParser.parseTracking("[behind 5]") == TrackingStatus(ahead: 0, behind: 5, isGone: false))

        let diverged = RefParser.parseTracking("[ahead 1, behind 2]")
        #expect(diverged == TrackingStatus(ahead: 1, behind: 2, isGone: false))
        #expect(diverged.hasDiverged, "两边都有对方没有的提交，直接 push 会被拒")

        let gone = RefParser.parseTracking("[gone]")
        #expect(gone.isGone)
        #expect(!gone.isInSync)
    }
}
