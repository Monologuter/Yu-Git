import Foundation
import Testing

@testable import GitKit

@Suite("新建仓库")
struct InitTests {

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-init-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func isolatedClient() throws -> GitClient {
        var environment = GitClient.makeEnvironment()
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_SYSTEM"] = "/dev/null"
        return try GitClient(environment: environment)
    }

    /// 不显式指定的话，默认分支名取决于用户的 `init.defaultBranch`，
    /// 同一个 app 在两台机器上会建出 main 和 master 两种仓库。
    @Test("默认分支名是显式指定的，不看机器上的配置")
    func pinsTheInitialBranch() async throws {
        let directory = try temporaryDirectory()
        let client = try isolatedClient()

        try await client.run(GitOperation.initRepository().arguments, in: directory)

        let head = try await client.run(["symbolic-ref", "--short", "HEAD"], in: directory)
        #expect(head.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines) == "main")
    }

    @Test("能建成别的分支名")
    func acceptsACustomBranchName() async throws {
        let directory = try temporaryDirectory()
        let client = try isolatedClient()

        try await client.run(
            GitOperation.initRepository(initialBranch: "trunk").arguments, in: directory)

        let head = try await client.run(["symbolic-ref", "--short", "HEAD"], in: directory)
        #expect(head.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines) == "trunk")
    }

    // MARK: - 事前检查

    @Test("空目录没有障碍")
    func reportsNoObstacleForEmptyDirectories() async throws {
        let directory = try temporaryDirectory()
        let obstacle = try await isolatedClient().initObstacle(at: directory)
        #expect(obstacle == nil)
    }

    /// `git init` 在已有仓库上会打印 "Reinitialized" 并**以 0 退出**，
    /// 用户拿不到任何提示，以为自己新建了一个仓库。
    @Test("已经是仓库时拦下来")
    func detectsAnExistingRepository() async throws {
        let repo = try await TemporaryRepository()

        let obstacle = try await isolatedClient().initObstacle(at: repo.url)

        #expect(obstacle == .alreadyARepository)
        #expect(obstacle?.isBlocking == true)
    }

    /// 在已有仓库的子目录里 init 会静默造出**嵌套仓库**：里层独立，
    /// 外层只把它看成一个未跟踪目录。这几乎从来不是用户想要的。
    @Test("在别的仓库里面时拦下来，并说清外层是谁")
    func detectsNesting() async throws {
        let repo = try await TemporaryRepository()
        let nested = repo.url.appendingPathComponent("子目录")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let obstacle = try await isolatedClient().initObstacle(at: nested)

        guard case .insideRepository(let root) = obstacle else {
            Issue.record("应当认出嵌套，实际是 \(String(describing: obstacle))")
            return
        }
        // 路径可能带 /private 前缀，比后缀就够
        #expect(root.hasSuffix(repo.url.lastPathComponent))
        #expect(obstacle?.isBlocking == true)
    }

    /// 目录非空不是错误，只是要说一声：那些文件会立刻以未跟踪身份出现。
    @Test("目录里有文件时提醒但不拦")
    func warnsAboutNonEmptyDirectories() async throws {
        let directory = try temporaryDirectory()
        try "x".write(
            to: directory.appendingPathComponent("已有文件.txt"), atomically: true, encoding: .utf8)

        let obstacle = try await isolatedClient().initObstacle(at: directory)

        #expect(obstacle == .directoryNotEmpty(fileCount: 1))
        #expect(obstacle?.isBlocking == false)
    }

    @Test("只有 .DS_Store 的目录仍算空")
    func ignoresFinderMetadata() async throws {
        let directory = try temporaryDirectory()
        try "".write(
            to: directory.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)

        #expect(try await isolatedClient().initObstacle(at: directory) == nil)
    }

    @Test("目录还不存在时也能检查，不会因为路径不存在就报错")
    func handlesMissingDirectories() async throws {
        let parent = try temporaryDirectory()
        let missing = parent.appendingPathComponent("还没建的目录")

        // 父目录不在任何仓库里，所以没有障碍
        #expect(try await isolatedClient().initObstacle(at: missing) == nil)
    }

    @Test("新建仓库不算危险操作")
    func initIsSafe() {
        #expect(GitOperation.initRepository().hazard == .none)
        #expect(GitOperation.initRepository().equivalentCommand.contains("--initial-branch"))
    }
}
