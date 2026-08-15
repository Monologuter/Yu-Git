import Foundation
import Testing

@testable import GitKit

@Suite("仓库速览")
struct RepositoryGlanceTests {

    /// 读文件而不是起 git 进程：十个仓库就是十次进程启动，
    /// 而这个列表可能只是被扫一眼。
    @Test("读得出当前分支")
    func readsTheCurrentBranch() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")

        let glance = try #require(RepositoryGlance.read(at: repo.url))

        #expect(glance.branch == "main")
        #expect(!glance.isDetached)
        #expect(glance.name == repo.url.lastPathComponent)
    }

    @Test("认得出别的分支名，含带斜杠的")
    func readsBranchNamesWithSlashes() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        try await repo.git("switch", "--quiet", "--create", "feature/登录")

        let glance = try #require(RepositoryGlance.read(at: repo.url))
        #expect(glance.branch == "feature/登录")
    }

    @Test("detached HEAD 时没有分支名，但标出来了")
    func detectsDetachedHead() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        try repo.write("y\n", to: "g.txt")
        try await repo.commitAll("第二条")
        try await repo.git("checkout", "--quiet", "HEAD~1")

        let glance = try #require(RepositoryGlance.read(at: repo.url))

        #expect(glance.branch == nil)
        #expect(glance.isDetached)
    }

    /// 「最近打开」里出现一个已经被删掉的仓库是很正常的事，
    /// 那时该返回 nil 让调用方决定，而不是崩或者猜一个分支名。
    @Test("不是仓库的目录返回 nil")
    func returnsNilForNonRepositories() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(RepositoryGlance.read(at: directory) == nil)
    }

    @Test("路径不存在时返回 nil 而不是崩")
    func returnsNilForMissingPaths() {
        let missing = URL(fileURLWithPath: "/根本不存在的路径/\(UUID().uuidString)")
        #expect(RepositoryGlance.read(at: missing) == nil)
    }

    /// worktree 与 submodule 里的 `.git` 是**文件**不是目录，
    /// 内容是 `gitdir: <路径>`。猜错分支名比不显示更糟。
    @Test("worktree 里的 .git 文件不会被当成 HEAD 猜出个分支来")
    func doesNotGuessForWorktrees() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // .git 是文件，所以 .git/HEAD 这个路径根本读不到
        try "gitdir: /somewhere/.git/worktrees/x\n".write(
            to: directory.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        #expect(RepositoryGlance.read(at: directory) == nil)
    }

    @Test("HEAD 指向非分支引用时不当作分支")
    func handlesNonBranchRefs() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-ref-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "ref: refs/tags/v1\n".write(
            to: directory.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)

        let glance = try #require(RepositoryGlance.read(at: directory))
        #expect(glance.branch == nil)
        #expect(!glance.isDetached)
    }
}
