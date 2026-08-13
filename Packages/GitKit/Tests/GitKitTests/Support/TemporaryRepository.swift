import Foundation

@testable import GitKit

/// 在临时目录里搭一个真实 git 仓库，实例释放时自动清理。
///
/// 用 `GIT_CONFIG_GLOBAL=/dev/null` 隔离用户的 `~/.gitconfig`——否则用户配置的
/// `init.defaultBranch`、`commit.gpgsign`、hooks 都会渗进测试，让结果时灵时不灵。
final class TemporaryRepository {

    let url: URL
    let client: GitClient

    init(initialBranch: String = "main") async throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        var environment = GitClient.makeEnvironment()
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_SYSTEM"] = "/dev/null"
        client = try GitClient(environment: environment)

        try await git("init", "--quiet", "--initial-branch", initialBranch)
        try await git("config", "user.email", "test@yugit.local")
        try await git("config", "user.name", "驭Git 测试")
        try await git("config", "commit.gpgsign", "false")
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - 操作

    @discardableResult
    func git(_ arguments: String...) async throws -> ProcessResult {
        try await client.run(arguments, in: url)
    }

    /// 执行可能以非零状态退出的命令（如产生冲突的 merge）。
    @discardableResult
    func gitAllowingFailure(_ arguments: String...) async throws -> ProcessResult {
        try await client.runReturningResult(arguments, in: url)
    }

    func write(_ contents: String, to relativePath: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func delete(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: url.appendingPathComponent(relativePath))
    }

    /// 暂存全部改动并提交。
    func commitAll(_ message: String) async throws {
        try await git("add", "--all")
        try await git("commit", "--quiet", "--message", message)
    }

    func status() async throws -> RepositoryStatus {
        try await client.status(of: url)
    }

    func entry(at path: String) async throws -> StatusEntry? {
        try await status().entries.first { $0.path == path }
    }
}
