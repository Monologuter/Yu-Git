import Foundation
import Testing

@testable import GitKit

@Suite("子模块")
struct SubmoduleTests {

    // MARK: - 解析

    /// **状态字符是第一列，正常时是一个空格。** 直接 trim 掉行首空白，
    /// 「已同步」就会和别的状态混在一起——剩下的部分长得一模一样。
    @Test("行首那个空格是「已同步」，不是可以随手去掉的空白")
    func treatsLeadingSpaceAsAState() {
        let modules = SubmoduleParser.parse(
            " 3cb3e6a4c74e69af873f1057481fa2c2f72c47cf vendor/lib (heads/main)\n")

        #expect(modules.count == 1)
        #expect(modules[0].state == .current)
        #expect(modules[0].path == "vendor/lib")
        #expect(modules[0].describedRef == "heads/main")
        #expect(modules[0].recordedCommit == "3cb3e6a4c74e69af873f1057481fa2c2f72c47cf")
    }

    @Test("认得出未初始化、不同步与冲突")
    func parsesEveryState() {
        let text = """
            -aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa vendor/none
            +bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb vendor/drifted (heads/other)
            Ucccccccccccccccccccccccccccccccccccccccc vendor/conflicted
            """
        let modules = SubmoduleParser.parse(text)

        #expect(modules.map(\.state) == [.notInitialized, .outOfSync, .conflicted])
        #expect(modules.filter(\.state.needsAttention).count == 3)
        // 未初始化的没有 (…) 那一段
        #expect(modules[0].describedRef.isEmpty)
    }

    @Test("路径里有空格也切得对")
    func handlesSpacesInPaths() {
        let modules = SubmoduleParser.parse(
            " aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa vendor/my lib (heads/main)\n")

        #expect(modules.count == 1)
        #expect(modules[0].path == "vendor/my lib")
    }

    @Test("空输出与残缺行都不会崩")
    func toleratesGarbage() {
        #expect(SubmoduleParser.parse("").isEmpty)
        #expect(SubmoduleParser.parse("\n\n").isEmpty)
        #expect(SubmoduleParser.parse(" 没有路径\n").isEmpty)
    }

    @Test("每种状态都有中文说法和解释")
    func everyStateIsExplained() {
        for state in [
            Submodule.State.current, .notInitialized, .outOfSync, .conflicted,
        ] {
            #expect(!state.displayName.isEmpty)
            #expect(!state.explanation.isEmpty)
        }
    }

    // MARK: - 真实仓库

    /// 造一个带子模块的父仓库。
    ///
    /// `protocol.file.allow=always` 是必需的：git 2.38 起默认禁止用 `file://`
    /// 协议添加子模块（CVE-2022-39253）。只在测试里放开。
    private func makeParentWithSubmodule() async throws -> (
        parent: TemporaryRepository, child: TemporaryRepository
    ) {
        let child = try await TemporaryRepository()
        try child.write("v1\n", to: "lib.txt")
        try await child.commitAll("子模块第一版")

        let parent = try await TemporaryRepository()
        try parent.write("main\n", to: "app.txt")
        try await parent.commitAll("base")
        try await parent.git(
            "-c", "protocol.file.allow=always",
            "submodule", "add", "--quiet", child.url.path, "vendor/lib")
        try await parent.commitAll("加入子模块")
        return (parent, child)
    }

    @Test("列得出子模块的路径、记录的提交与签出的引用")
    func listsSubmodules() async throws {
        let (parent, child) = try await makeParentWithSubmodule()
        // 子仓库要一直活着：TemporaryRepository 析构时会删掉目录，
        // 用 _ 接住等于当场把子模块的来源删了
        defer { _ = child }

        let modules = try await parent.client.submodules(in: parent.url)

        #expect(modules.count == 1)
        let module = try #require(modules.first)
        #expect(module.path == "vendor/lib")
        #expect(module.state == .current)
        #expect(module.describedRef.contains("main"))
    }

    @Test("没有子模块的仓库返回空数组")
    func handlesRepositoriesWithoutSubmodules() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")

        let modules = try await repo.client.submodules(in: repo.url)
        #expect(modules.isEmpty)
    }

    /// 子模块里切了分支之后，父仓库记录的和实际签出的就对不上了。
    @Test("子模块签到别的提交上会被标成不同步")
    func detectsDrift() async throws {
        let (parent, child) = try await makeParentWithSubmodule()
        // 子仓库要一直活着：TemporaryRepository 析构时会删掉目录，
        // 用 _ 接住等于当场把子模块的来源删了
        defer { _ = child }
        let submodule = parent.url.appendingPathComponent("vendor/lib")

        // 在子模块里再走一步，父仓库记录的还是旧的那个
        try "v2\n".write(
            to: submodule.appendingPathComponent("lib.txt"), atomically: true, encoding: .utf8)
        try await parent.client.run(["add", "--all"], in: submodule)
        try await parent.client.run(["commit", "--quiet", "--message", "子模块第二版"], in: submodule)

        let modules = try await parent.client.submodules(in: parent.url)
        #expect(modules.first?.state == .outOfSync)
    }

    /// 「代码拉下来编译不过」最常见的原因之一：克隆时没带 `--recursive`。
    @Test("克隆时不带 recursive，子模块目录是空的")
    func detectsUninitializedAfterPlainClone() async throws {
        let (parent, child) = try await makeParentWithSubmodule()
        // 子仓库要一直活着：TemporaryRepository 析构时会删掉目录，
        // 用 _ 接住等于当场把子模块的来源删了
        defer { _ = child }

        let clonePath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-clone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: clonePath) }
        try await parent.client.run(
            [
                "-c", "protocol.file.allow=always",
                "clone", "--quiet", parent.url.path, clonePath.path,
            ],
            in: parent.url
        )

        let modules = try await parent.client.submodules(in: clonePath)
        #expect(modules.first?.state == .notInitialized)
        #expect(modules.first?.state.needsAttention == true)
    }

    @Test("更新一次就把没初始化的拉下来")
    func updateInitializes() async throws {
        let (parent, child) = try await makeParentWithSubmodule()
        // 子仓库要一直活着：TemporaryRepository 析构时会删掉目录，
        // 用 _ 接住等于当场把子模块的来源删了
        defer { _ = child }

        let clonePath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("yugit-clone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: clonePath) }
        try await parent.client.run(
            [
                "-c", "protocol.file.allow=always",
                "clone", "--quiet", parent.url.path, clonePath.path,
            ],
            in: parent.url
        )

        try await parent.client.run(
            ["-c", "protocol.file.allow=always"]
                + GitOperation.updateSubmodules().arguments,
            in: clonePath
        )

        let updated = try await parent.client.submodules(in: clonePath)
        #expect(updated.first?.state == .current)
        #expect(
            FileManager.default.fileExists(
                atPath: clonePath.appendingPathComponent("vendor/lib/lib.txt").path))
    }

    /// 「更新」在用户脑子里就包含「先弄下来」，而没初始化恰恰是最常见的
    /// 那种需要更新的状态。
    @Test("更新默认带 --init")
    func updateInitializesByDefault() {
        let operation = GitOperation.updateSubmodules()
        #expect(operation.arguments.contains("--init"))
        #expect(operation.arguments.contains("--recursive"))
        #expect(operation.hazard == .none)
    }

    @Test("可以只更新某一个子模块")
    func updatesASingleSubmodule() {
        let operation = GitOperation.updateSubmodules(path: "vendor/lib")
        // `--` 之后才是路径，否则以 - 开头的路径会被当成选项
        #expect(operation.arguments.contains("--"))
        #expect(operation.arguments.last == "vendor/lib")
    }
}
