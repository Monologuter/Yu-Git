import Foundation
import Testing

@testable import GitKit

/// 冲突文件 fixture 取自真实 `git merge` 的输出，不是手打的近似格式。
@Suite("冲突解析")
struct ConflictParserTests {

    /// 默认 merge 风格：没有共同祖先那一段。
    static let mergeStyle = """
        line1
        <<<<<<< HEAD
        MAIN 改动
        =======
        FEATURE 改动
        >>>>>>> feature
        line3

        """

    /// diff3 风格：多了 base 段，标签也变成 ours/theirs。
    static let diff3Style = """
        line1
        <<<<<<< ours
        MAIN 改动
        ||||||| base
        common
        =======
        FEATURE 改动
        >>>>>>> theirs
        line3
        far1
        <<<<<<< ours
        MAIN 尾部
        ||||||| base
        tail
        =======
        FEATURE 尾部
        >>>>>>> theirs

        """

    private func parse(_ text: String) -> ConflictedFile {
        ConflictParser.parse(Data(text.utf8), path: "f.txt")
    }

    // MARK: - 基本解析

    @Test("默认 merge 风格：拿到双方内容，base 为空")
    func parsesMergeStyle() throws {
        let file = parse(Self.mergeStyle)
        let block = try #require(file.blocks.first)

        #expect(file.blocks.count == 1)
        #expect(block.oursLabel == "HEAD")
        #expect(block.theirsLabel == "feature")
        #expect(block.ours == ["MAIN 改动"])
        #expect(block.theirs == ["FEATURE 改动"])
        // 没有共同祖先——这正是要用 diff3 重建的理由
        #expect(block.base == nil)
    }

    @Test("diff3 风格：拿到共同祖先")
    func parsesDiff3Style() throws {
        let file = parse(Self.diff3Style)
        #expect(file.blocks.count == 2)

        let first = try #require(file.blocks.first)
        #expect(first.ours == ["MAIN 改动"])
        #expect(first.base == ["common"])
        #expect(first.theirs == ["FEATURE 改动"])

        let second = try #require(file.blocks.last)
        #expect(second.id == 1)
        #expect(second.base == ["tail"])
    }

    @Test("冲突之外的内容按原样分段保留")
    func keepsSurroundingText() {
        let file = parse(Self.diff3Style)

        var texts: [[String]] = []
        for segment in file.segments {
            if case let .text(lines) = segment { texts.append(lines) }
        }
        #expect(texts.first == ["line1"])
        #expect(texts.dropFirst().first == ["line3", "far1"])
    }

    @Test("多行的一边")
    func handlesMultiLineSides() throws {
        let file = parse(
            """
            <<<<<<< ours
            我方第一行
            我方第二行
            ||||||| base
            原来的
            =======
            对方唯一一行
            >>>>>>> theirs

            """)

        let block = try #require(file.blocks.first)
        #expect(block.ours == ["我方第一行", "我方第二行"])
        #expect(block.theirs == ["对方唯一一行"])
    }

    @Test("空的一边（一方删掉了）")
    func handlesEmptySide() throws {
        let file = parse(
            """
            <<<<<<< ours
            我方留着
            ||||||| base
            我方留着
            =======
            >>>>>>> theirs

            """)

        let block = try #require(file.blocks.first)
        #expect(block.ours == ["我方留着"])
        #expect(block.theirs.isEmpty)
    }

    @Test("双方内容相同的块会被标出来")
    func detectsTrivialBlock() throws {
        let file = parse(
            """
            <<<<<<< ours
            一样的
            =======
            一样的
            >>>>>>> theirs

            """)
        #expect(try #require(file.blocks.first).isTrivial)
    }

    @Test("没有冲突的文件不产生块")
    func plainFileHasNoBlocks() {
        let file = parse("就是普通内容\n第二行\n")
        #expect(!file.hasConflicts)
    }

    // MARK: - 不该误判的情况

    @Test("Markdown 的分隔线不算冲突标记")
    func doesNotMisreadMarkdownRule() {
        // 标题下面的 ======= 分隔线，长度不定，也没有配对标记
        let file = parse("标题\n=======\n正文\n")
        #expect(!file.hasConflicts)
    }

    @Test("标记必须恰好 7 个字符")
    func requiresExactMarkerLength() {
        #expect(ConflictParser.marker("<<<<<<< ours", prefix: "<") == "ours")
        // 6 个和 8 个都不是 git 的写法
        #expect(ConflictParser.marker("<<<<<< ours", prefix: "<") == nil)
        #expect(ConflictParser.marker("<<<<<<<< ours", prefix: "<") == nil)
        // 7 个后面必须跟空格或行尾
        #expect(ConflictParser.marker("<<<<<<<ours", prefix: "<") == nil)
        #expect(ConflictParser.marker("=======", prefix: "=") == "")
    }

    @Test("讲冲突的文档里孤立的标记不被当成冲突")
    func ignoresUnpairedMarkers() {
        // 一份教程文档，写着 <<<<<<< 但没有配对的 ======= / >>>>>>>
        let file = parse("教程说：遇到 <<<<<<< 开头的行就是冲突。\n<<<<<<< HEAD\n只有开头没有结尾\n")
        #expect(!file.hasConflicts)
    }

    @Test("CRLF 文件也能解析")
    func handlesCRLF() throws {
        // Swift 把 "\r\n" 当作一个 Character，按 "\n" 切 String 根本切不开
        let text = "line1\r\n<<<<<<< ours\r\n我方\r\n=======\r\n对方\r\n>>>>>>> theirs\r\n"
        let file = ConflictParser.parse(Data(text.utf8), path: "f.txt")

        let block = try #require(file.blocks.first)
        // 行尾的 CR 被保留在行内容里，重新拼装时才能一字不差
        #expect(block.ours == ["我方\r"])
        #expect(block.theirs == ["对方\r"])
    }

    // MARK: - 拼装

    @Test("原样拼回去与输入完全一致")
    func roundTripsUnchanged() {
        // 解析与拼装同构，否则「只解一半就保存」会损坏文件
        for text in [Self.mergeStyle, Self.diff3Style, "普通文件\n没有冲突\n"] {
            let file = ConflictParser.parse(Data(text.utf8), path: "f.txt")
            #expect(ConflictParser.render(file, resolutions: [:]) == text)
        }
    }

    @Test("没有结尾换行的文件不会被凭空补上")
    func preservesMissingTrailingNewline() {
        let text = "第一行\n最后一行没有换行"
        let file = ConflictParser.parse(Data(text.utf8), path: "f.txt")
        #expect(ConflictParser.render(file, resolutions: [:]) == text)
    }

    @Test("解决一个块，其余保持冲突原样")
    func resolvesSingleBlock() {
        let file = parse(Self.diff3Style)
        let rendered = ConflictParser.render(file, resolutions: [0: ["最终内容"]])

        #expect(rendered.contains("最终内容"))
        #expect(!rendered.contains("MAIN 改动"))
        // 第二块还没处理，标记要留着
        #expect(rendered.contains("MAIN 尾部"))
        #expect(rendered.contains("<<<<<<<"))
    }

    @Test("全部解决后不再有标记")
    func removesAllMarkersWhenFullyResolved() {
        let file = parse(Self.diff3Style)
        let rendered = ConflictParser.render(
            file, resolutions: [0: ["解决一"], 1: ["解决二"]])

        #expect(!rendered.contains("<<<<<<<"))
        #expect(!rendered.contains("======="))
        #expect(!rendered.contains(">>>>>>>"))
        #expect(rendered.contains("line1"))
        #expect(rendered.contains("解决一"))
        #expect(rendered.contains("解决二"))
    }

    @Test("解决成空内容（两边都不要）")
    func resolvesToNothing() {
        let file = parse(Self.mergeStyle)
        let rendered = ConflictParser.render(file, resolutions: [0: []])
        #expect(rendered == "line1\nline3\n")
    }
}

@Suite("冲突读写")
struct ConflictClientTests {

    /// 造一个真实的合并冲突。
    private func makeConflict() async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        try repo.write("line1\ncommon\nline3\n", to: "f.txt")
        try await repo.commitAll("base")

        _ = try await repo.client.run(["checkout", "-q", "-b", "feature"], in: repo.url)
        try repo.write("line1\nFEATURE 改动\nline3\n", to: "f.txt")
        try await repo.commitAll("feature")

        _ = try await repo.client.run(["checkout", "-q", "main"], in: repo.url)
        try repo.write("line1\nMAIN 改动\nline3\n", to: "f.txt")
        try await repo.commitAll("main")

        // 合并必然冲突，失败是预期的
        _ = try? await repo.client.run(["merge", "feature"], in: repo.url)
        return repo
    }

    @Test("列出冲突文件")
    func listsConflictedPaths() async throws {
        let repo = try await makeConflict()
        #expect(try await repo.client.conflictedPaths(in: repo.url) == ["f.txt"])
    }

    @Test("读取时自动补上共同祖先")
    func addsBaseAutomatically() async throws {
        // git 默认的 merge 风格不写 base，没有它就没法判断双方各改了什么
        let repo = try await makeConflict()
        let file = try await repo.client.conflictedFile(at: "f.txt", in: repo.url)

        let block = try #require(file.blocks.first)
        #expect(block.base == ["common"])
        #expect(block.ours == ["MAIN 改动"])
        #expect(block.theirs == ["FEATURE 改动"])
    }

    @Test("三个 stage 都能取到完整文件")
    func readsAllStages() async throws {
        let repo = try await makeConflict()
        let stages = try await repo.client.conflictStages(at: "f.txt", in: repo.url)

        #expect(stages.base?.contains("common") == true)
        #expect(stages.ours?.contains("MAIN 改动") == true)
        #expect(stages.theirs?.contains("FEATURE 改动") == true)
    }

    @Test("写回解决结果并标记为已解决")
    func resolvesAndStages() async throws {
        let repo = try await makeConflict()
        try await repo.client.resolveConflict(
            at: "f.txt", content: "line1\n合并后的内容\nline3\n", in: repo.url)

        #expect(try await repo.client.conflictedPaths(in: repo.url).isEmpty)

        let status = try await repo.client.status(of: repo.url)
        let entry = try #require(status.entries.first { $0.path == "f.txt" })
        #expect(entry.hasStagedChanges)
    }

    @Test("内容里还留着标记时拒绝标记为已解决")
    func refusesContentWithMarkers() async throws {
        // git add 不检查这个，带标记的文件照样能提交进去——
        // 那种提交推出去，别人拉下来就是一份语法都不成立的代码
        let repo = try await makeConflict()

        await #expect(throws: GitError.self) {
            try await repo.client.resolveConflict(
                at: "f.txt",
                content: "line1\n<<<<<<< HEAD\nA\n=======\nB\n>>>>>>> feature\n",
                in: repo.url
            )
        }

        // 仍然是冲突状态
        #expect(try await repo.client.conflictedPaths(in: repo.url) == ["f.txt"])
    }

    @Test("已经手工改过的文件不会被重建覆盖")
    func doesNotClobberManualEdits() async throws {
        let repo = try await makeConflict()

        // 先读一次，把 base 补出来
        _ = try await repo.client.conflictedFile(at: "f.txt", in: repo.url)

        // 模拟用户手工解了一半
        let url = repo.url.appendingPathComponent("f.txt")
        let edited = "line1\n我手工写的\n<<<<<<< ours\nA\n||||||| base\nX\n=======\nB\n>>>>>>> theirs\nline3\n"
        try Data(edited.utf8).write(to: url)

        let file = try await repo.client.conflictedFile(at: "f.txt", in: repo.url)
        let rendered = ConflictParser.render(file, resolutions: [:])
        #expect(rendered.contains("我手工写的"))
    }
}
