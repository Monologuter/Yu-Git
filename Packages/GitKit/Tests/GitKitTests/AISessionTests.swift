import Foundation
import Testing

@testable import GitKit

@Suite("AI 会话归因")
struct AISessionTests {

    private func session(
        prompt: String = "把登录模块重构一下",
        id: String = "sess-001"
    ) -> AISession {
        AISession(
            tool: "Claude Code",
            sessionID: id,
            prompt: prompt,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func head(of repo: TemporaryRepository) async throws -> String {
        let result = try await repo.client.run(["rev-parse", "HEAD"], in: repo.url)
        return result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("记下来的会话读得回来，字段一个不少")
    func roundTripsASession() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let commit = try await head(of: repo)

        try await repo.client.recordSession(session(), for: commit, in: repo.url)

        let all = await repo.client.sessions(in: repo.url)
        let stored = try #require(all[commit])
        #expect(stored.tool == "Claude Code")
        #expect(stored.sessionID == "sess-001")
        #expect(stored.prompt == "把登录模块重构一下")
    }

    @Test("没有记录时返回空，不假装知道")
    func returnsNothingWithoutRecords() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")

        #expect(await repo.client.sessions(in: repo.url).isEmpty)
    }

    /// prompt 是用户写的任意文本。走 `-m` 参数的话，长文本会撞命令行长度上限，
    /// 带换行和引号的更容易被咬到——所以走 stdin。
    @Test("带换行、引号、中文的 prompt 原样存得住")
    func handlesArbitraryPromptText() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let commit = try await head(of: repo)

        let tricky = "第一行\n第二行有个 \"引号\" 和 '单引号'\n还有 $VAR 与 `反引号`"
        try await repo.client.recordSession(
            session(prompt: tricky), for: commit, in: repo.url)

        let stored = try #require(await repo.client.sessions(in: repo.url)[commit])
        #expect(stored.prompt == tricky)
    }

    @Test("很长的 prompt 也存得下")
    func handlesLongPrompts() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let commit = try await head(of: repo)

        let long = String(repeating: "把这段代码重构一下。", count: 2000)
        try await repo.client.recordSession(
            session(prompt: long), for: commit, in: repo.url)

        let stored = try #require(await repo.client.sessions(in: repo.url)[commit])
        #expect(stored.prompt == long)
    }

    /// 一屏 blame 可能涉及几十个 commit。逐条 `notes show` 就是几十次进程启动，
    /// 所以这里是两条命令读完全部。
    @Test("一次读出多条提交的记录")
    func readsManySessionsAtOnce() async throws {
        let repo = try await TemporaryRepository()
        var commits: [String] = []
        for index in 0..<12 {
            try repo.write("v\(index)\n", to: "f.txt")
            try await repo.commitAll("第 \(index) 条")
            commits.append(try await head(of: repo))
        }
        for (index, commit) in commits.enumerated() {
            try await repo.client.recordSession(
                session(prompt: "第 \(index) 轮", id: "sess-\(index)"),
                for: commit, in: repo.url)
        }

        let all = await repo.client.sessions(in: repo.url)

        #expect(all.count == 12)
        for (index, commit) in commits.enumerated() {
            #expect(all[commit]?.sessionID == "sess-\(index)")
        }
    }

    @Test("重复记录是覆盖，不是报错")
    func overwritesAnExistingRecord() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let commit = try await head(of: repo)

        try await repo.client.recordSession(
            session(prompt: "第一次"), for: commit, in: repo.url)
        try await repo.client.recordSession(
            session(prompt: "改过了"), for: commit, in: repo.url)

        #expect(await repo.client.sessions(in: repo.url)[commit]?.prompt == "改过了")
    }

    /// 和快照标注分开放：两者的生命周期和含义都不同，
    /// 混在一个 ref 里之后，清理其中一类会连带影响另一类。
    @Test("会话记录和快照标注互不干扰")
    func staysSeparateFromSnapshotLabels() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let commit = try await head(of: repo)
        let store = try await SnapshotStore.open(root: repo.url, client: repo.client)
        let snapshot = try #require(try await store.capture(summary: "快照", identifier: "s"))

        try await repo.client.recordSession(session(), for: commit, in: repo.url)
        try await store.setLabel("快照的名字", for: snapshot)

        #expect(await repo.client.sessions(in: repo.url)[commit] != nil)
        #expect(await store.label(for: snapshot) == "快照的名字")
        // 各存各的：会话那一份不该出现在标注列表里
        #expect(!(await store.labelledCommits()).contains(commit))
    }

    @Test("不落进用户自己的 notes")
    func doesNotTouchTheUsersNotes() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")
        let commit = try await head(of: repo)

        try await repo.client.recordSession(session(), for: commit, in: repo.url)

        let userNotes = try await repo.client.runReturningResult(["notes", "list"], in: repo.url)
        #expect(
            userNotes.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - 展示

    @Test("很长的 prompt 在列表里被截短，短的原样显示")
    func summarizesLongPrompts() {
        let short = session(prompt: "改个名字")
        #expect(short.summary == "改个名字")

        let long = session(prompt: String(repeating: "很长", count: 100))
        #expect(long.summary.count <= 61)
        #expect(long.summary.hasSuffix("…"))
    }

    /// 列表里一行放不下多行文本，换行要压成空格，不然行高会炸。
    @Test("多行 prompt 压成一行")
    func flattensMultilinePrompts() {
        let multiline = session(prompt: "第一行\n第二行\n第三行")
        #expect(!multiline.summary.contains("\n"))
        #expect(multiline.summary.contains("第一行 第二行"))
    }
}
