import Foundation
import Testing

@testable import GitKit

@Suite("remote 管理")
struct RemoteManagementTests {

    private func actor(for repo: TemporaryRepository) async throws -> RepoActor {
        try await RepoActor(root: repo.url, client: repo.client, operationLog: InMemoryOperationLog())
    }

    @Test("加一个远程之后读得回来")
    func addsARemote() async throws {
        let repo = try await TemporaryRepository()

        try await actor(for: repo).perform(
            .addRemote(name: "origin", url: "https://example.com/a.git"))

        let remotes = try await repo.client.remotes(in: repo.url)
        #expect(remotes.map(\.name) == ["origin"])
        #expect(remotes.first?.fetchURL == "https://example.com/a.git")
    }

    @Test("重名的远程加不上去，报错而不是悄悄改掉原来的")
    func refusesDuplicateNames() async throws {
        let repo = try await TemporaryRepository()
        let repoActor = try await actor(for: repo)
        try await repoActor.perform(.addRemote(name: "origin", url: "https://example.com/a.git"))

        await #expect(throws: (any Error).self) {
            try await repoActor.perform(
                .addRemote(name: "origin", url: "https://example.com/b.git"))
        }
        // 原来那个地址必须没被动过
        let remotes = try await repo.client.remotes(in: repo.url)
        #expect(remotes.first?.fetchURL == "https://example.com/a.git")
    }

    @Test("改地址只动地址")
    func changesTheURL() async throws {
        let repo = try await TemporaryRepository()
        let repoActor = try await actor(for: repo)
        try await repoActor.perform(.addRemote(name: "origin", url: "https://example.com/a.git"))

        try await repoActor.perform(
            .setRemoteURL(name: "origin", url: "git@example.com:x/a.git"))

        let remote = try #require(try await repo.client.remotes(in: repo.url).first)
        #expect(remote.name == "origin")
        #expect(remote.fetchURL == "git@example.com:x/a.git")
        #expect(remote.usesSSH)
    }

    @Test("改名之后远程跟踪分支跟着搬家")
    func renameMovesTrackingBranches() async throws {
        let source = try await TemporaryRepository()
        try source.write("x\n", to: "f.txt")
        try await source.commitAll("base")

        let repo = try await TemporaryRepository()
        try repo.write("y\n", to: "g.txt")
        try await repo.commitAll("local")
        let repoActor = try await actor(for: repo)
        try await repoActor.perform(.addRemote(name: "origin", url: source.url.path))
        try await repo.git("fetch", "--quiet", "origin")

        // 搬家前后都要能列出这条跟踪分支，只是前缀变了
        let before = try await repo.client.branches(in: repo.url).filter(\.isRemote)
        #expect(before.contains { $0.name.hasPrefix("origin/") })

        try await repoActor.perform(.renameRemote(from: "origin", to: "upstream"))

        let after = try await repo.client.branches(in: repo.url).filter(\.isRemote)
        #expect(after.contains { $0.name.hasPrefix("upstream/") })
        #expect(!after.contains { $0.name.hasPrefix("origin/") })
    }

    @Test("改成已存在的名字会被拒绝")
    func refusesRenamingOntoAnExistingName() async throws {
        let repo = try await TemporaryRepository()
        let repoActor = try await actor(for: repo)
        try await repoActor.perform(.addRemote(name: "origin", url: "https://example.com/a.git"))
        try await repoActor.perform(.addRemote(name: "upstream", url: "https://example.com/b.git"))

        await #expect(throws: (any Error).self) {
            try await repoActor.perform(.renameRemote(from: "origin", to: "upstream"))
        }
        #expect(try await repo.client.remotes(in: repo.url).count == 2)
    }

    /// 这是删除远程真正的后果，也是说明文案里必须写清的那句：
    /// 它连带删掉 `refs/remotes/<name>/*`，本地分支则毫发无损。
    @Test("删除远程会连带删掉它的远程跟踪分支，本地分支不受影响")
    func removingDropsTrackingBranchesOnly() async throws {
        let source = try await TemporaryRepository()
        try source.write("x\n", to: "f.txt")
        try await source.commitAll("base")

        let repo = try await TemporaryRepository()
        try repo.write("y\n", to: "g.txt")
        try await repo.commitAll("local")
        let repoActor = try await actor(for: repo)
        try await repoActor.perform(.addRemote(name: "origin", url: source.url.path))
        try await repo.git("fetch", "--quiet", "origin")
        #expect(try await repo.client.branches(in: repo.url).contains { $0.isRemote })

        try await repoActor.perform(.removeRemote(name: "origin"))

        let branches = try await repo.client.branches(in: repo.url)
        #expect(!branches.contains { $0.isRemote })
        // 本地分支还在
        #expect(branches.contains { !$0.isRemote })
        #expect(try await repo.client.remotes(in: repo.url).isEmpty)
        #expect(GitOperation.removeRemote(name: "origin").explanation.contains("远程跟踪分支"))
    }

    @Test("删不存在的远程会报错")
    func refusesToRemoveAMissingRemote() async throws {
        let repo = try await TemporaryRepository()

        await #expect(throws: (any Error).self) {
            try await actor(for: repo).perform(.removeRemote(name: "nope"))
        }
    }

    /// 四个都只改配置，不动提交——所以时间线不该为它们拍工作区快照。
    @Test("remote 的增删改都不算危险操作")
    func remoteOperationsAreSafe() {
        #expect(GitOperation.addRemote(name: "a", url: "u").hazard == .none)
        #expect(GitOperation.setRemoteURL(name: "a", url: "u").hazard == .none)
        #expect(GitOperation.renameRemote(from: "a", to: "b").hazard == .none)
        #expect(GitOperation.removeRemote(name: "a").hazard == .none)
    }
}
