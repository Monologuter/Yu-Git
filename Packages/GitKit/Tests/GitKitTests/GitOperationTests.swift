import Foundation
import Testing

@testable import GitKit

@Suite("GitOperation")
struct GitOperationTests {

    @Test("暂存操作带中文摘要与等价命令")
    func describesStaging() {
        let single = GitOperation.stage(paths: ["a.txt"])
        #expect(single.summary == "暂存 a.txt")
        #expect(single.equivalentCommand == "git add -- a.txt")
        #expect(!single.rewritesHistory)

        let multiple = GitOperation.stage(paths: ["a.txt", "b.txt"])
        #expect(multiple.summary == "暂存 2 个文件")
    }

    @Test("路径前有 -- 分隔符，以免 -foo 这样的文件名被当成选项")
    func separatesPathsFromOptions() {
        let operation = GitOperation.stage(paths: ["-奇怪的文件名"])

        #expect(operation.arguments == ["add", "--", "-奇怪的文件名"])
    }

    @Test("展示用命令给含空格的参数加引号，实际参数不带引号")
    func quotesArgumentsForDisplayOnly() {
        let operation = GitOperation.stage(paths: ["新 文件.txt"])

        #expect(operation.equivalentCommand == "git add -- '新 文件.txt'")
        #expect(operation.arguments.last == "新 文件.txt", "实际执行走参数数组，不经过 shell")
    }

    @Test("提交信息里的单引号被正确转义，命令可直接粘贴到终端")
    func escapesSingleQuotes() {
        let operation = GitOperation.commit(message: "修复 don't 的问题")

        #expect(operation.equivalentCommand.contains(#"'修复 don'\''t 的问题'"#))
    }

    @Test("amend 被标记为改写历史")
    func flagsHistoryRewrites() {
        let amend = GitOperation.commit(message: "x", amend: true)
        let plain = GitOperation.commit(message: "x")

        #expect(amend.kind == .amend)
        #expect(amend.rewritesHistory, "时间线要靠这个标记决定执行前是否打快照")
        #expect(plain.kind == .commit)
        #expect(!plain.rewritesHistory)
    }

    @Test("每个操作都有非空的中文摘要与注解")
    func alwaysCarriesChineseMetadata() {
        let operations = [
            GitOperation.stage(paths: ["a.txt"]),
            GitOperation.commit(message: "x"),
            GitOperation.commit(message: "x", amend: true),
        ]

        for operation in operations {
            #expect(!operation.summary.isEmpty)
            #expect(!operation.explanation.isEmpty)
        }
    }

    @Test("经 JSON 往返后不失真——时间线要跨 session 持久化")
    func roundTripsThroughJSON() throws {
        let original = GitOperation.commit(message: "包含 中文 与 'quote'", amend: true)

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(GitOperation.self, from: data)

        #expect(restored == original)
    }
}
