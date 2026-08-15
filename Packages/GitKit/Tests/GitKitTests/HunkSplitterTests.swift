import Foundation
import Testing

@testable import GitKit

/// hunk 是 git 排版出来的单位，不是语义单位——间隔不到七行的两处改动会被并进
/// 同一个 hunk。这一套测试锁死的是：我们的切分点和 `git add -p` 的 `s` 完全一致。
///
/// 期望值不是推导出来的，是**真跑 `git add -p` 抄下来的**（工程规范 §5.2）。
@Suite("hunk 切分")
struct HunkSplitterTests {

    /// 十行文件，改哪几行由调用方定。
    private func makeRepository(changing edits: [Int: String]) async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        var lines = (1...10).map { "line\($0)" }
        try repo.write(lines.joined(separator: "\n") + "\n", to: "a.txt")
        try await repo.commitAll("初始")

        for (number, text) in edits {
            lines[number - 1] = text
        }
        try repo.write(lines.joined(separator: "\n") + "\n", to: "a.txt")
        return repo
    }

    @Test("间隔一行上下文：切成两段，头与 git add -p 一字不差")
    func splitsAcrossSingleContextLine() async throws {
        let repo = try await makeRepository(changing: [3: "LINE3", 5: "LINE5"])
        let diff = try await repo.client.diff(of: "a.txt", in: repo.url)

        #expect(diff.hunks.count == 1, "前提不成立：两处改动应当在同一个 hunk 里")

        let slices = HunkSplitter.slices(of: diff)
        #expect(slices.count == 2)

        // 真实 `git add -p` + `s` 的输出，逐字抄录
        #expect(
            slices[0].text == """
                @@ -1,4 +1,4 @@
                 line1
                 line2
                -line3
                +LINE3
                 line4
                """)
        #expect(
            slices[1].text == """
                @@ -4,5 +4,5 @@
                 line4
                -line5
                +LINE5
                 line6
                 line7
                 line8
                """)

        // 中间那行上下文两段都要——两半都得靠它定位
        #expect(slices[0].range.contains(4))
        #expect(slices[1].range.contains(4))
    }

    @Test("间隔四行上下文：切法同样跟 git 一致")
    func splitsAcrossWiderGap() async throws {
        let repo = try await makeRepository(changing: [2: "LINE2", 3: "LINE3", 8: "LINE8"])
        let diff = try await repo.client.diff(of: "a.txt", in: repo.url)

        #expect(diff.hunks.count == 1)

        let slices = HunkSplitter.slices(of: diff)
        #expect(slices.count == 2)
        #expect(slices[0].text.hasPrefix("@@ -1,7 +1,7 @@"))
        #expect(slices[1].text.hasPrefix("@@ -4,7 +4,7 @@"))

        #expect(slices[0].addedLines == 2)
        #expect(slices[0].deletedLines == 2)
        #expect(slices[1].addedLines == 1)
        #expect(slices[1].deletedLines == 1)
    }

    @Test("改动连成一片时不切")
    func keepsContiguousChangeWhole() async throws {
        let repo = try await makeRepository(changing: [4: "LINE4", 5: "LINE5", 6: "LINE6"])
        let diff = try await repo.client.diff(of: "a.txt", in: repo.url)

        let slices = HunkSplitter.slices(of: diff)
        #expect(slices.count == 1)
        #expect(slices[0].changedLineIndices.count == 6, "三改三删共六行改动")
    }

    @Test("间隔七行以上本就是两个 hunk，各自不再切")
    func leavesDistantChangesToGit() async throws {
        let repo = try await makeRepository(changing: [1: "LINE1", 10: "LINE10"])
        let diff = try await repo.client.diff(of: "a.txt", in: repo.url)

        #expect(diff.hunks.count == 2, "隔得够远，git 自己就切开了")

        let slices = HunkSplitter.slices(of: diff)
        #expect(slices.count == 2)
        #expect(slices.map(\.hunkIndex) == [0, 1])
    }

    @Test("新文件全是新增行，切出来仍是一段")
    func handlesPureAddition() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("初始\n", to: "seed.txt")
        try await repo.commitAll("初始")

        try repo.write("甲\n乙\n丙\n", to: "new.txt")
        try await repo.git("add", "new.txt")
        let diff = try await repo.client.diffAgainstHead(of: "new.txt", in: repo.url)

        let slices = HunkSplitter.slices(of: diff)
        #expect(slices.count == 1)
        #expect(slices[0].deletedLines == 0)
        #expect(slices[0].addedLines == 3)
        #expect(slices[0].text.hasPrefix("@@ -0,0 +1,3 @@"), "无旧行时 git 写作 -0,0")
    }

    @Test("切出来的每一段都能单独暂存，合起来等于全部")
    func slicesStageIndependently() async throws {
        let repo = try await makeRepository(changing: [3: "LINE3", 5: "LINE5"])
        let diff = try await repo.client.diff(of: "a.txt", in: repo.url)
        let slices = HunkSplitter.slices(of: diff)
        #expect(slices.count == 2)

        // 只暂存第一段
        let patch = try #require(
            PatchBuilder.patch(
                for: diff,
                selecting: .lines([slices[0].hunkIndex: slices[0].changedLineIndices])
            ))
        try await repo.client.run(
            ["apply", "--cached", "--recount", "-"],
            in: repo.url,
            standardInput: Data(patch.utf8)
        )

        let staged = try await repo.client.run(["diff", "--cached"], in: repo.url)
            .standardOutputText
        #expect(staged.contains("+LINE3"))
        #expect(!staged.contains("+LINE5"), "第二段不该跟着进暂存区")
    }
}
