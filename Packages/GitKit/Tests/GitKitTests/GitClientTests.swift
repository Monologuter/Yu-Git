import Foundation
import Testing

@testable import GitKit

/// 跑在真实 git 仓库上的集成测试。
///
/// 解析器单测保证「给定字节流解析正确」，这里保证「我们发给 git 的命令确实能拿到
/// 那样的字节流」——参数写错、锁冲突、环境污染都只有真跑一遍才会暴露。
@Suite("GitClient · 真实仓库")
struct GitClientTests {

    // MARK: - HEAD 状态

    @Test("空仓库：unborn HEAD，无任何条目")
    func readsUnbornRepository() async throws {
        let repository = try await TemporaryRepository()

        let status = try await repository.status()

        #expect(status.branch.isUnborn)
        #expect(status.branch.name == "main")
        #expect(status.entries.isEmpty)
        #expect(status.isClean)
    }

    @Test("detached HEAD 被正确识别")
    func readsDetachedHead() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("hello", to: "a.txt")
        try await repository.commitAll("首次提交")

        try await repository.git("checkout", "--detach", "HEAD")
        let status = try await repository.status()

        #expect(status.branch.isDetached)
        #expect(status.branch.name == nil)
        #expect(status.branch.commit?.count == 40)
    }

    // MARK: - 路径处理

    @Test("中文与含空格的文件名原样返回")
    func handlesUnicodeAndSpacedPaths() async throws {
        // 这条测试守着两个配置：-z（不引用路径）和 core.quotepath=false。
        // 任何一个丢了，路径都会变成 "\346\226\260..." 这种转义形式。
        let repository = try await TemporaryRepository()
        try repository.write("内容", to: "目录/中 文.txt")
        try repository.write("内容", to: "新 文件.txt")

        let paths = try await repository.status().entries.map(\.path).sorted()

        #expect(paths == ["新 文件.txt", "目录/中 文.txt"])
    }

    @Test("带变音符号的文件名不被规范化破坏")
    func handlesDiacritics() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("x", to: "händler-café.txt")

        let entry = try await repository.entry(at: "händler-café.txt")

        #expect(entry != nil, "macOS 的 NFD 与 git 的 NFC 不一致时这里会失配")
    }

    // MARK: - 各类改动

    @Test("重命名带来源路径与相似度")
    func detectsRename() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("hello", to: "a.txt")
        try await repository.commitAll("首次提交")

        try await repository.git("mv", "a.txt", "b.txt")
        let entry = try #require(await repository.entry(at: "b.txt"))

        #expect(entry.kind == .renamed)
        #expect(entry.originalPath == "a.txt")
        #expect(entry.similarity == 100)
        #expect(entry.hasStagedChanges)
    }

    @Test("同一文件可同时有已暂存与未暂存的改动")
    func detectsPartiallyStagedFile() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("v1", to: "f.txt")
        try await repository.commitAll("首次提交")

        try repository.write("v2", to: "f.txt")
        try await repository.git("add", "f.txt")
        try repository.write("v3", to: "f.txt")

        let entry = try #require(await repository.entry(at: "f.txt"))

        #expect(entry.indexStatus == .modified)
        #expect(entry.workTreeStatus == .modified)
        #expect(entry.hasStagedChanges)
        #expect(entry.hasUnstagedChanges)
    }

    @Test("删除的文件被标记为工作区删除")
    func detectsDeletion() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("hello", to: "a.txt")
        try await repository.commitAll("首次提交")

        try repository.delete("a.txt")
        let entry = try #require(await repository.entry(at: "a.txt"))

        #expect(entry.workTreeStatus == .deleted)
        #expect(entry.hasUnstagedChanges)
    }

    @Test("未跟踪目录被展开为逐个文件")
    func expandsUntrackedDirectories() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("x", to: "新目录/一.txt")
        try repository.write("y", to: "新目录/二.txt")

        let paths = try await repository.status().entries.map(\.path).sorted()

        #expect(paths == ["新目录/一.txt", "新目录/二.txt"], "GUI 要逐个文件暂存，只报告目录不够用")
    }

    @Test("合并冲突被标记为 unmerged")
    func detectsMergeConflict() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("base", to: "f.txt")
        try await repository.commitAll("base")

        try await repository.git("checkout", "--quiet", "-b", "other")
        try repository.write("来自 other 分支", to: "f.txt")
        try await repository.commitAll("other")

        try await repository.git("checkout", "--quiet", "main")
        try repository.write("来自 main 分支", to: "f.txt")
        try await repository.commitAll("main")

        // 冲突会让 merge 以退出码 1 结束，这是预期结果而非错误。
        let merge = try await repository.gitAllowingFailure("merge", "other")
        #expect(!merge.isSuccess)

        let status = try await repository.status()
        let entry = try #require(status.entries.first { $0.path == "f.txt" })

        #expect(status.hasConflicts)
        #expect(entry.kind == .unmerged)
        #expect(entry.indexStatus == .updatedButUnmerged)
    }

    // MARK: - submodule

    @Test("含 submodule 的仓库能解析且带出子状态")
    func handlesSubmodules() async throws {
        let inner = try await TemporaryRepository()
        try inner.write("hi", to: "a.txt")
        try await inner.commitAll("submodule 首次提交")

        let outer = try await TemporaryRepository()
        try outer.write("x", to: "x.txt")
        try await outer.commitAll("首次提交")

        // git 2.38 起默认禁止 file:// 协议的 submodule，测试里显式放行。
        try await outer.git(
            "-c", "protocol.file.allow=always",
            "submodule", "add", "--quiet", inner.url.path, "sub"
        )
        try await outer.commitAll("加入 submodule")

        try outer.write("changed", to: "sub/a.txt")
        let entry = try #require(await outer.entry(at: "sub"))

        #expect(entry.submodule?.hasModifiedContent == true)
        #expect(entry.workTreeStatus == .modified)
    }

    // MARK: - 仓库定位

    @Test("从子目录能找到仓库根")
    func findsRepositoryRoot() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("x", to: "深/层/文件.txt")
        try await repository.commitAll("首次提交")

        let root = try await repository.client.repositoryRoot(
            containing: repository.url.appendingPathComponent("深/层")
        )

        // 用 path 比较而不是 URL：目录 URL 带尾随斜杠，直接 == 会失配。
        #expect(root.resolvingSymlinksInPath().path == repository.url.resolvingSymlinksInPath().path)
    }

    @Test("非仓库路径抛出 notARepository")
    func rejectsNonRepository() async throws {
        let client = try GitClient()
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-not-a-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        await #expect(throws: GitError.self) {
            _ = try await client.repositoryRoot(containing: temporary)
        }
    }
}

@Suite("GitClient · 执行环境")
struct GitClientEnvironmentTests {

    @Test("清除会把 git 指向其他仓库的继承变量")
    func stripsRepositoryScopedVariables() {
        // App 若被 git hook 拉起，会继承 GIT_DIR 之类的变量，
        // 之后每条命令都会作用到那个仓库上——这是灾难性的静默错误。
        let polluted = [
            "GIT_DIR": "/别的/仓库/.git",
            "GIT_WORK_TREE": "/别的/仓库",
            "GIT_INDEX_FILE": "/tmp/some.index",
            "PATH": "/usr/bin",
        ]

        let environment = GitClient.makeEnvironment(basedOn: polluted)

        #expect(environment["GIT_DIR"] == nil)
        #expect(environment["GIT_WORK_TREE"] == nil)
        #expect(environment["GIT_INDEX_FILE"] == nil)
        #expect(environment["PATH"] == "/usr/bin", "无关变量应当保留")
    }

    @Test("禁用一切会导致挂起的交互")
    func disablesInteractivePrompts() {
        let environment = GitClient.makeEnvironment(basedOn: [:])

        #expect(environment["GIT_TERMINAL_PROMPT"] == "0")
        #expect(environment["GIT_PAGER"] == "cat")
        #expect(environment["GIT_EDITOR"] == "true")
    }

    @Test("能在系统上定位到 git")
    func locatesGitExecutable() throws {
        let executable = try #require(GitExecutable.locate())

        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
    }
}
