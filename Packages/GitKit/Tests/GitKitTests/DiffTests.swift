import Foundation
import Testing

@testable import GitKit

@Suite("diff 解析")
struct DiffParsingTests {

    @Test("解析基本的增删改")
    func parsesBasicChanges() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("第一行\n第二行\n第三行\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("第一行\n改过的第二行\n第三行\n新增行\n", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        let hunk = try #require(diff.hunks.first)

        #expect(diff.path == "f.txt")
        #expect(diff.change == .modified)
        #expect(!diff.isBinary)
        #expect(diff.addedLineCount == 2)
        #expect(diff.deletedLineCount == 1)

        let deleted = try #require(hunk.lines.first { $0.kind == .deletion })
        #expect(deleted.text == "第二行")
        #expect(deleted.oldLineNumber == 2)
        #expect(deleted.newLineNumber == nil)

        let context = try #require(hunk.lines.first { $0.kind == .context })
        #expect(context.oldLineNumber != nil && context.newLineNumber != nil)
    }

    @Test("行号在增删混合时保持正确")
    func tracksLineNumbers() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("1\n2\n3\n4\n5\n", to: "f.txt")
        try await repository.commitAll("base")
        // 删掉第 2 行，在第 4 行后插入一行
        try repository.write("1\n3\n4\n新\n5\n", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        let lines = diff.hunks.flatMap(\.lines)

        let deleted = try #require(lines.first { $0.kind == .deletion })
        #expect(deleted.text == "2")
        #expect(deleted.oldLineNumber == 2)

        let added = try #require(lines.first { $0.kind == .addition })
        #expect(added.text == "新")
        #expect(added.newLineNumber == 4)
    }

    @Test("识别无尾换行标记")
    func detectsMissingNewline() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("没有尾换行", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("改过了也没有尾换行", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        let lines = diff.hunks.flatMap(\.lines)

        let allMissingNewline = lines.allSatisfy(\.isMissingNewline)
        #expect(allMissingNewline, "增删两行都应带上无尾换行标记")
        #expect(lines.count == 2)
    }

    @Test("新增文件与删除文件")
    func detectsAdditionAndDeletion() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("原有内容\n", to: "旧.txt")
        try await repository.commitAll("base")

        try repository.write("全新内容\n", to: "新.txt")
        try await repository.git("add", "新.txt")
        try repository.delete("旧.txt")
        try await repository.git("add", "--all")

        let added = try await repository.client.diff(of: "新.txt", in: repository.url, staged: true)
        let deleted = try await repository.client.diff(of: "旧.txt", in: repository.url, staged: true)

        #expect(added.change == .added)
        #expect(added.addedLineCount == 1)
        #expect(deleted.change == .deleted)
        #expect(deleted.deletedLineCount == 1)
    }

    @Test("二进制文件不产出行级 diff")
    func detectsBinaryFile() async throws {
        let repository = try await TemporaryRepository()
        let binaryURL = repository.url.appendingPathComponent("data.bin")
        try Data([0x00, 0x01, 0x02, 0xFF]).write(to: binaryURL)
        try await repository.commitAll("base")
        try Data([0x00, 0x01, 0x02, 0xFE, 0xFD]).write(to: binaryURL)

        let diff = try await repository.client.diff(of: "data.bin", in: repository.url)

        #expect(diff.isBinary)
        #expect(diff.hunks.isEmpty)
        #expect(PatchBuilder.patch(for: diff) == nil, "二进制无法做部分暂存")
    }

    @Test("中文与含空格的路径")
    func handlesUnicodePaths() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("原内容\n", to: "目录/中 文.txt")
        try await repository.commitAll("base")
        try repository.write("新内容\n", to: "目录/中 文.txt")

        let diff = try await repository.client.diff(of: "目录/中 文.txt", in: repository.url)

        #expect(diff.path == "目录/中 文.txt")
        #expect(diff.addedLineCount == 1)
        #expect(diff.header.contains("中 文.txt"), "header 里的路径应当未被转义")
    }

    @Test("未跟踪文件也能取到 diff")
    func diffsUntrackedFile() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "seed.txt")
        try await repository.commitAll("base")
        try repository.write("第一行\n第二行\n", to: "未跟踪.txt")

        let diff = try await repository.client.diffForUntrackedFile(
            at: "未跟踪.txt", in: repository.url)

        #expect(diff.addedLineCount == 2)
    }

    @Test("上下文行数可调")
    func honoursContextLines() async throws {
        let repository = try await TemporaryRepository()
        try repository.write((1...20).map(String.init).joined(separator: "\n") + "\n", to: "f.txt")
        try await repository.commitAll("base")
        var lines = (1...20).map(String.init)
        lines[9] = "改过的第十行"
        try repository.write(lines.joined(separator: "\n") + "\n", to: "f.txt")

        let narrow = try await repository.client.diff(of: "f.txt", in: repository.url, contextLines: 1)
        let wide = try await repository.client.diff(of: "f.txt", in: repository.url, contextLines: 8)

        #expect(narrow.hunks[0].lines.count == 4, "上下各 1 行 + 一增一删")
        #expect(wide.hunks[0].lines.count > narrow.hunks[0].lines.count)
    }

    @Test("统计增删行数时中文路径不被转义")
    func countsChangedLines() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\nb\n", to: "中 文.txt")
        try await repository.commitAll("base")
        try repository.write("A\nb\nc\n", to: "中 文.txt")

        let counts = try await repository.client.changedLineCounts(in: repository.url)
        let entry = try #require(counts["中 文.txt"])

        #expect(entry.added == 2)
        #expect(entry.deleted == 1)
    }

    @Test("hunk 头 count 为 1 时省略，还原时也要省略")
    func roundTripsHunkHeader() throws {
        let parsed = try DiffParser.parseHunkHeader("@@ -1 +1,3 @@ 函数名")

        #expect(parsed.oldStart == 1)
        #expect(parsed.oldCount == 1)
        #expect(parsed.newStart == 1)
        #expect(parsed.newCount == 3)
        #expect(parsed.heading == "函数名")

        let hunk = DiffHunk(oldStart: 1, oldCount: 1, newStart: 1, newCount: 3, heading: "函数名", lines: [])
        #expect(hunk.header == "@@ -1 +1,3 @@ 函数名")
    }
}

/// 往返测试：解析出的结构必须能还原成 git 认得的 patch，应用后结果与预期一致。
///
/// 这组测试守着工程规范 §6 的铁律 3——hunk / 行级暂存一旦生成错误的 patch，
/// 用户的文件就会被悄悄改坏，且往往到很久以后才被发现。
@Suite("patch 往返")
struct PatchRoundTripTests {

    /// 读 index 中的文件内容，用来验证暂存结果。
    private func indexContent(of path: String, in repository: TemporaryRepository) async throws -> String {
        try await repository.client.run(["show", ":\(path)"], in: repository.url).standardOutputText
    }

    @Test("全选暂存后工作区与 index 一致")
    func stagesEverything() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\nb\nc\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("A\nb\nc\nd\n", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        let patch = try #require(PatchBuilder.patch(for: diff))
        try await repository.client.applyToIndex(patch: patch, in: repository.url)

        let entry = try #require(await repository.entry(at: "f.txt"))
        #expect(entry.hasStagedChanges)
        #expect(!entry.hasUnstagedChanges, "全部暂存后不该再有未暂存改动")
        let stagedContent = try await indexContent(of: "f.txt", in: repository)
        #expect(stagedContent == "A\nb\nc\nd\n")
    }

    @Test("只暂存选中的那一行")
    func stagesSelectedLinesOnly() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("1\n2\n3\n", to: "f.txt")
        try await repository.commitAll("base")
        // 两处改动：第 1 行改写、末尾新增
        try repository.write("一\n2\n3\n四\n", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        let lines = diff.hunks[0].lines

        // 只选第一处：删掉 "1"、加上 "一"
        let firstChange = lines.indices.filter {
            (lines[$0].kind == .deletion && lines[$0].text == "1")
                || (lines[$0].kind == .addition && lines[$0].text == "一")
        }
        let patch = try #require(PatchBuilder.patch(for: diff, selecting: .lines([0: Set(firstChange)])))
        try await repository.client.applyToIndex(patch: patch, in: repository.url)

        let stagedContent = try await indexContent(of: "f.txt", in: repository)
        #expect(stagedContent == "一\n2\n3\n", "index 应只含选中的改动，末尾新增行不应被暂存")

        let entry = try #require(await repository.entry(at: "f.txt"))
        #expect(entry.hasStagedChanges)
        #expect(entry.hasUnstagedChanges, "未选中的改动仍留在工作区")
    }

    @Test("只暂存选中的 hunk")
    func stagesSelectedHunkOnly() async throws {
        let repository = try await TemporaryRepository()
        let original = (1...30).map(String.init).joined(separator: "\n") + "\n"
        try repository.write(original, to: "f.txt")
        try await repository.commitAll("base")

        // 相距足够远，git 会切成两个 hunk
        var lines = (1...30).map(String.init)
        lines[1] = "改了第二行"
        lines[27] = "改了第二十八行"
        try repository.write(lines.joined(separator: "\n") + "\n", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        #expect(diff.hunks.count == 2, "两处相距很远的改动应当切成两个 hunk")

        let patch = try #require(PatchBuilder.patch(for: diff, selecting: .hunks([0])))
        try await repository.client.applyToIndex(patch: patch, in: repository.url)

        let staged = try await indexContent(of: "f.txt", in: repository)
        #expect(staged.contains("改了第二行"))
        #expect(!staged.contains("改了第二十八行"), "第二个 hunk 不该被暂存")
    }

    @Test("暂存第二个 hunk 时行号偏移正确")
    func handlesLineOffsetWhenSkippingHunks() async throws {
        // 跳过前一个 hunk 时，后一个 hunk 在新文件里的起点会前移，
        // 算错这个偏移，git apply 会报 "patch does not apply"。
        let repository = try await TemporaryRepository()
        try repository.write((1...30).map(String.init).joined(separator: "\n") + "\n", to: "f.txt")
        try await repository.commitAll("base")

        var lines = (1...30).map(String.init)
        lines.insert("插入在开头附近", at: 2)
        lines.insert("插入在末尾附近", at: 28)
        try repository.write(lines.joined(separator: "\n") + "\n", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        #expect(diff.hunks.count == 2)

        // 只要第二个 hunk
        let patch = try #require(PatchBuilder.patch(for: diff, selecting: .hunks([1])))
        try await repository.client.applyToIndex(patch: patch, in: repository.url)

        let staged = try await indexContent(of: "f.txt", in: repository)
        #expect(staged.contains("插入在末尾附近"))
        #expect(!staged.contains("插入在开头附近"))
    }

    @Test("无尾换行的文件暂存后不会被偷偷补上换行")
    func preservesMissingNewline() async throws {
        // 漏掉 "\ No newline at end of file" 标记，git apply 会给文件补一个换行，
        // 这是 hunk 暂存最经典的损坏方式。
        let repository = try await TemporaryRepository()
        try repository.write("第一行\n没有尾换行", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("第一行\n改过但仍无尾换行", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        let patch = try #require(PatchBuilder.patch(for: diff))
        try await repository.client.applyToIndex(patch: patch, in: repository.url)

        let staged = try await indexContent(of: "f.txt", in: repository)
        #expect(staged == "第一行\n改过但仍无尾换行")
        #expect(!staged.hasSuffix("\n"), "文件本来就没有尾换行，暂存不该加上")
    }

    @Test("从有尾换行改成无尾换行")
    func handlesNewlineRemoval() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("内容\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("内容", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        let patch = try #require(PatchBuilder.patch(for: diff))
        try await repository.client.applyToIndex(patch: patch, in: repository.url)

        let stagedContent = try await indexContent(of: "f.txt", in: repository)
        #expect(stagedContent == "内容")
    }

    @Test("CRLF 行尾不被改成 LF")
    func preservesCRLF() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("第一行\r\n第二行\r\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("第一行\r\n改过的第二行\r\n", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        let patch = try #require(PatchBuilder.patch(for: diff))
        try await repository.client.applyToIndex(patch: patch, in: repository.url)

        let staged = try await indexContent(of: "f.txt", in: repository)
        #expect(staged == "第一行\r\n改过的第二行\r\n", "CRLF 必须原样保留")
    }

    @Test("中文路径的 patch 能被 git apply 接受")
    func appliesPatchForUnicodePath() async throws {
        // 自己拼 "--- a/<path>" 会在含空格的路径上出错，
        // 所以 PatchBuilder 复用 git 给的原始 header。
        let repository = try await TemporaryRepository()
        try repository.write("原内容\n", to: "目录/中 文.txt")
        try await repository.commitAll("base")
        try repository.write("新内容\n", to: "目录/中 文.txt")

        let diff = try await repository.client.diff(of: "目录/中 文.txt", in: repository.url)
        let patch = try #require(PatchBuilder.patch(for: diff))
        try await repository.client.applyToIndex(patch: patch, in: repository.url)

        let stagedContent = try await indexContent(of: "目录/中 文.txt", in: repository)
        #expect(stagedContent == "新内容\n")
    }

    @Test("反向应用可取消暂存")
    func unstagesWithReverseApply() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\nb\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("A\nb\n", to: "f.txt")
        try await repository.git("add", "f.txt")

        let staged = try await repository.client.diff(of: "f.txt", in: repository.url, staged: true)
        let patch = try #require(PatchBuilder.patch(for: staged, direction: .unstage))
        try await repository.client.applyToIndex(patch: patch, in: repository.url, reverse: true)

        let entry = try #require(await repository.entry(at: "f.txt"))
        #expect(!entry.hasStagedChanges, "改动应已退回工作区")
        #expect(entry.hasUnstagedChanges)
        let indexAfterUnstage = try await indexContent(of: "f.txt", in: repository)
        #expect(indexAfterUnstage == "a\nb\n")
    }

    @Test("没有选中任何改动时不生成 patch")
    func producesNilForEmptySelection() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("A\n", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)

        #expect(PatchBuilder.patch(for: diff, selecting: .hunks([])) == nil)
        #expect(PatchBuilder.patch(for: diff, selecting: .lines([:])) == nil)
    }

    @Test("已应用的新增行写成上下文，已应用的删除行不写")
    func rendersAlreadyAppliedLinesAgainstTheCurrentFile() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\nb\nc\n", to: "f.txt")
        try await repository.commitAll("base")
        try repository.write("A\nb\nC\n", to: "f.txt")

        let diff = try await repository.client.diff(of: "f.txt", in: repository.url)
        let lines = diff.hunks[0].lines
        func index(of kind: DiffLine.Kind, text: String) throws -> Int {
            try #require(lines.firstIndex { $0.kind == kind && $0.text == text })
        }

        // 第一处（a → A）当作已经提交过，这一次只提交第二处（c → C）
        let applied = try [index(of: .deletion, text: "a"), index(of: .addition, text: "A")]
        let selected = try [index(of: .deletion, text: "c"), index(of: .addition, text: "C")]

        let patch = try #require(
            PatchBuilder.patch(
                for: diff,
                selecting: .lines([0: Set(selected)]),
                alreadyApplied: [0: Set(applied)]
            ))

        #expect(patch.contains("\n A\n"), "已经加进文件的行必须作为上下文出现")
        #expect(!patch.contains("\n-a\n"), "已经删掉的行不该再出现在 patch 里")
        #expect(!patch.contains("\n a\n"))
        #expect(patch.contains("\n-c\n"))
        #expect(patch.contains("\n+C\n"))

        // 行数也要跟着算对，否则 git apply 直接拒
        #expect(patch.contains("@@ -1,3 +1,3 @@"))
    }
}
