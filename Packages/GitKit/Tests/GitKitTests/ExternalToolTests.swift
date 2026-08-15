import Foundation
import Testing

@testable import GitKit

@Suite("外部 diff / merge 工具")
struct ExternalToolTests {

    /// 取自真实的 `git difftool --tool-help` 输出。
    private let toolHelp = """
        'git difftool --tool=<tool>' may be set to one of the following:
        \t\topendiff         Use FileMerge (requires a graphical session)
        \t\tvimdiff          Use Vim

        \tuser-defined:
        \t\tsourcetree.cmd opendiff "$LOCAL" "$REMOTE"

        The following tools are valid, but not currently available:
        \t\taraxis           Use Araxis Merge (requires a graphical session)
        \t\tbc               Use Beyond Compare (requires a graphical session)
        """

    @Test("三段分得清：可用、自定义、装了才可用")
    func splitsTheThreeSections() {
        let tools = ExternalToolParser.parse(toolHelp)

        let opendiff = tools.first { $0.name == "opendiff" }
        #expect(opendiff?.isAvailable == true)
        #expect(opendiff?.isUserDefined == false)
        #expect(opendiff?.detail.contains("FileMerge") == true)

        let araxis = tools.first { $0.name == "araxis" }
        #expect(araxis?.isAvailable == false)
    }

    /// 用户自定义那段的条目形如 `mytool.cmd <命令>`，工具名要去掉 `.cmd`——
    /// 留着的话 `--tool sourcetree.cmd` 是认不出来的。
    @Test("自定义工具名去掉 .cmd 后缀")
    func stripsCmdSuffix() {
        let tools = ExternalToolParser.parse(toolHelp)
        let custom = tools.first { $0.isUserDefined }

        #expect(custom?.name == "sourcetree")
        #expect(custom?.isAvailable == true)
    }

    @Test("空输出与只有标题的输出都不会崩")
    func toleratesEmptyOutput() {
        #expect(ExternalToolParser.parse("").isEmpty)
        #expect(
            ExternalToolParser.parse("'git difftool --tool=<tool>' may be set to one of the following:")
                .isEmpty)
    }

    @Test("顶格的说明文字不会被当成工具")
    func ignoresUnindentedProse() {
        let text = """
            'git difftool --tool=<tool>' may be set to one of the following:
            \t\topendiff         Use FileMerge
            某段顶格的说明文字
            """
        let tools = ExternalToolParser.parse(text)
        #expect(tools.map(\.name) == ["opendiff"])
    }

    // MARK: - 真实仓库

    @Test("没配过时读出 nil，不是空字符串")
    func readsUnconfiguredTools() async throws {
        let repo = try await TemporaryRepository()

        #expect(await repo.client.configuredDiffTool(in: repo.url) == nil)
        #expect(await repo.client.configuredMergeTool(in: repo.url) == nil)
    }

    @Test("配过之后读得回来")
    func readsConfiguredTools() async throws {
        let repo = try await TemporaryRepository()
        try await repo.git("config", "diff.tool", "opendiff")
        try await repo.git("config", "merge.tool", "vimdiff")

        #expect(await repo.client.configuredDiffTool(in: repo.url) == "opendiff")
        #expect(await repo.client.configuredMergeTool(in: repo.url) == "vimdiff")
    }

    @Test("列得出这台机器上的工具")
    func listsToolsFromGit() async throws {
        let repo = try await TemporaryRepository()

        let tools = await repo.client.diffTools(in: repo.url)

        // git 至少认识 vimdiff
        #expect(tools.contains { $0.name == "vimdiff" })
    }

    /// **`-y` 不能省。** 不带它 git 会对每个文件在 stdin 上问
    /// `Launch 'xxx' [Y/n]?` 并一直等——从 GUI 调起就是永久挂死，
    /// 而那个提问根本没人看得到。
    @Test("调起外部工具时带 -y，不会停在确认提示上")
    func launchesWithoutPrompting() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        try repo.write("y\n", to: "f.txt")

        // 用一个只回显的假工具，避免真的弹窗
        try await repo.git("config", "diff.tool", "echoer")
        try await repo.git(
            "config", "difftool.echoer.cmd", "echo TOOL_RAN")

        // 挂死的话这里会超时；能返回就说明没停在提示上
        try await repo.client.launchDiffTool(path: "f.txt", in: repo.url)
    }

    @Test("能指定用哪个工具，而不只是默认的那个")
    func launchesASpecificTool() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        try repo.write("y\n", to: "f.txt")
        try await repo.git("config", "difftool.echoer.cmd", "echo TOOL_RAN")

        try await repo.client.launchDiffTool(path: "f.txt", tool: "echoer", in: repo.url)
    }
}
