import Foundation
import Testing

@testable import GitKit

/// 样本全部取自真实 `git status --porcelain=v2 --branch -z` 输出（git 2.42），
/// 不是照着文档手写的——文档与实现有出入时以实现为准。
@Suite("StatusParser")
struct StatusParserTests {

    /// 把可读的记录列表拼回 git 实际输出的 NUL 分隔字节流。
    private func porcelain(_ records: [String]) -> Data {
        var data = Data()
        for record in records {
            data.append(contentsOf: Array(record.utf8))
            data.append(0x00)
        }
        return data
    }

    // MARK: - HEAD 状态

    @Test("空仓库报告 unborn HEAD，但分支名已确定")
    func parsesUnbornRepository() throws {
        let status = try StatusParser.parse(
            porcelain([
                "# branch.oid (initial)",
                "# branch.head main",
            ]))

        #expect(status.branch.isUnborn)
        #expect(status.branch.commit == nil)
        #expect(status.branch.name == "main")
        #expect(!status.branch.isDetached)
        #expect(status.entries.isEmpty)
        #expect(status.isClean)
    }

    @Test("detached HEAD 没有分支名但有 commit")
    func parsesDetachedHead() throws {
        let status = try StatusParser.parse(
            porcelain([
                "# branch.oid 21647bd830a671baff3cffcdeb64131858aaf40c",
                "# branch.head (detached)",
            ]))

        #expect(status.branch.isDetached)
        #expect(status.branch.name == nil)
        #expect(status.branch.commit == "21647bd830a671baff3cffcdeb64131858aaf40c")
        #expect(!status.branch.isUnborn)
    }

    @Test("解析 upstream 与 ahead/behind")
    func parsesUpstreamTracking() throws {
        let status = try StatusParser.parse(
            porcelain([
                "# branch.oid e3ccba01f97b10fe5366ab53c39fab6bc1c6ba31",
                "# branch.head main",
                "# branch.upstream origin/main",
                "# branch.ab +3 -2",
            ]))

        #expect(status.branch.upstream == "origin/main")
        #expect(status.branch.ahead == 3)
        #expect(status.branch.behind == 2)
    }

    @Test("没有 upstream 时 ahead/behind 归零")
    func defaultsTrackingToZero() throws {
        let status = try StatusParser.parse(
            porcelain([
                "# branch.oid 21647bd830a671baff3cffcdeb64131858aaf40c",
                "# branch.head main",
            ]))

        #expect(status.branch.upstream == nil)
        #expect(status.branch.ahead == 0)
        #expect(status.branch.behind == 0)
    }

    @Test("未来 git 版本新增的 header 被忽略而不是报错")
    func ignoresUnknownHeaders() throws {
        let status = try StatusParser.parse(
            porcelain([
                "# branch.oid 21647bd830a671baff3cffcdeb64131858aaf40c",
                "# branch.head main",
                "# branch.future 某个还不存在的字段",
            ]))

        #expect(status.branch.name == "main")
    }

    // MARK: - 重命名（跨两个 NUL 段）

    @Test("重命名的来源路径来自下一个 NUL 段")
    func parsesRenameAcrossTwoRecords() throws {
        let hash = "ce013625030ba8dba906f756967f9e9ca394464a"
        let status = try StatusParser.parse(
            porcelain([
                "# branch.oid 19474a545e8a3cac4f36962de1bfaa3fc46bd208",
                "# branch.head main",
                "2 R. N... 100644 100644 100644 \(hash) \(hash) R100 b.txt",
                "a.txt",
            ]))

        let entry = try #require(status.entries.first)
        #expect(status.entries.count == 1, "来源路径不能被当成独立条目")
        #expect(entry.kind == .renamed)
        #expect(entry.path == "b.txt")
        #expect(entry.originalPath == "a.txt")
        #expect(entry.similarity == 100)
        #expect(entry.indexStatus == .renamed)
        #expect(entry.workTreeStatus == .unmodified)
        #expect(entry.hasStagedChanges)
    }

    @Test("重命名之后的条目不会因为错位而解析失败")
    func keepsAlignmentAfterRename() throws {
        let hash = "ce013625030ba8dba906f756967f9e9ca394464a"
        let status = try StatusParser.parse(
            porcelain([
                "# branch.head main",
                "2 R. N... 100644 100644 100644 \(hash) \(hash) R100 b.txt",
                "a.txt",
                "? 之后的文件.txt",
            ]))

        #expect(status.entries.count == 2)
        #expect(status.entries[1].kind == .untracked)
        #expect(status.entries[1].path == "之后的文件.txt")
    }

    @Test("复制条目按相似度前缀区分于重命名")
    func parsesCopyEntry() throws {
        let hash = "ce013625030ba8dba906f756967f9e9ca394464a"
        let status = try StatusParser.parse(
            porcelain([
                "# branch.head main",
                "2 C. N... 100644 100644 100644 \(hash) \(hash) C75 copy.txt",
                "origin.txt",
            ]))

        let entry = try #require(status.entries.first)
        #expect(entry.kind == .copied)
        #expect(entry.similarity == 75)
        #expect(entry.originalPath == "origin.txt")
    }

    // MARK: - 路径

    @Test("中文与含空格的路径原样保留")
    func preservesUnicodeAndSpacedPaths() throws {
        let hash = "0c3dd90b19be56e9cd94f052f74526aac2458521"
        let status = try StatusParser.parse(
            porcelain([
                "# branch.head main",
                "1 .M N... 100644 100644 100644 \(hash) \(hash) 目录/中 文.txt",
                "? 新 文件.txt",
            ]))

        #expect(status.entries[0].path == "目录/中 文.txt")
        #expect(status.entries[1].path == "新 文件.txt")
    }

    // MARK: - 各类改动

    @Test("区分已暂存的新增与未暂存的删除")
    func parsesOrdinaryEntries() throws {
        let empty = String(repeating: "0", count: 40)
        let hash = "ba2906d0666cf726c7eaadd2cd3db615dedfdf3a"
        let status = try StatusParser.parse(
            porcelain([
                "# branch.head main",
                "1 .D N... 100644 100644 000000 \(hash) \(hash) f.txt",
                "1 A. N... 000000 100644 100644 \(empty) 3e757656cf36eca53338e520d134963a44f793f8 h.txt",
            ]))

        let deleted = status.entries[0]
        #expect(deleted.workTreeStatus == .deleted)
        #expect(deleted.indexStatus == .unmodified)
        #expect(deleted.hasUnstagedChanges)
        #expect(!deleted.hasStagedChanges)

        let added = status.entries[1]
        #expect(added.indexStatus == .added)
        #expect(added.hasStagedChanges)
        #expect(!added.hasUnstagedChanges)
    }

    @Test("冲突条目有 11 个字段且被标为 unmerged")
    func parsesUnmergedEntry() throws {
        let status = try StatusParser.parse(
            porcelain([
                "# branch.oid 21647bd830a671baff3cffcdeb64131858aaf40c",
                "# branch.head main",
                "u UU N... 100644 100644 100644 100644 df967b96a579e45a18b8251732d16804b2e56a55"
                    + " ba2906d0666cf726c7eaadd2cd3db615dedfdf3a"
                    + " e45c9c2666d44e0327c1f9c239a74c508336053e f.txt",
            ]))

        let entry = try #require(status.entries.first)
        #expect(entry.kind == .unmerged)
        #expect(entry.path == "f.txt")
        #expect(entry.indexStatus == .updatedButUnmerged)
        #expect(entry.workTreeStatus == .updatedButUnmerged)
        #expect(status.hasConflicts)
        #expect(entry.hasUnstagedChanges, "冲突文件永远算作待处理")
    }

    @Test("忽略的文件与未跟踪文件分开标记")
    func parsesUntrackedAndIgnored() throws {
        let status = try StatusParser.parse(
            porcelain([
                "# branch.head main",
                "? 未跟踪.txt",
                "! .build/",
            ]))

        #expect(status.entries[0].kind == .untracked)
        #expect(status.entries[1].kind == .ignored)
        #expect(!status.entries[0].hasStagedChanges)
        #expect(status.entries.allSatisfy { !$0.hasUnstagedChanges })
    }

    // MARK: - submodule

    @Test("submodule 子状态按 S<c><m><u> 解析")
    func parsesSubmoduleState() throws {
        let hash = "315111a9ccd975c8786736416d8a0d3d9a8b47aa"
        let status = try StatusParser.parse(
            porcelain([
                "# branch.head main",
                "1 .M S.M. 160000 160000 160000 \(hash) \(hash) sub",
                "1 .M S..U 160000 160000 160000 \(hash) \(hash) sub2",
                "1 A. S... 000000 160000 160000 \(hash) \(hash) sub3",
                "1 .M N... 100644 100644 100644 \(hash) \(hash) 普通文件.txt",
            ]))

        let modified = try #require(status.entries[0].submodule)
        #expect(!modified.commitChanged)
        #expect(modified.hasModifiedContent)
        #expect(!modified.hasUntrackedContent)

        let untracked = try #require(status.entries[1].submodule)
        #expect(untracked.hasUntrackedContent)
        #expect(!untracked.hasModifiedContent)

        let clean = try #require(status.entries[2].submodule)
        #expect(!clean.commitChanged && !clean.hasModifiedContent && !clean.hasUntrackedContent)

        #expect(status.entries[3].submodule == nil, "N... 表示这不是 submodule")
    }

    // MARK: - 畸形输入

    @Test("重命名记录缺少来源路径时报错而不是静默错位")
    func rejectsRenameWithoutOriginalPath() throws {
        let hash = "ce013625030ba8dba906f756967f9e9ca394464a"
        #expect(throws: GitError.self) {
            try StatusParser.parse(
                porcelain([
                    "# branch.head main",
                    "2 R. N... 100644 100644 100644 \(hash) \(hash) R100 b.txt",
                ]))
        }
    }

    @Test("无法识别的记录类型报错")
    func rejectsUnknownRecordType() throws {
        #expect(throws: GitError.self) {
            try StatusParser.parse(porcelain(["x 这是什么"]))
        }
    }

    @Test("字段数不足的条目报错")
    func rejectsTruncatedEntry() throws {
        #expect(throws: GitError.self) {
            try StatusParser.parse(porcelain(["1 .M N... 100644"]))
        }
    }

    @Test("空输出解析为干净的 unborn 仓库")
    func parsesEmptyOutput() throws {
        let status = try StatusParser.parse(Data())

        #expect(status.entries.isEmpty)
        #expect(status.branch.isUnborn)
    }
}
