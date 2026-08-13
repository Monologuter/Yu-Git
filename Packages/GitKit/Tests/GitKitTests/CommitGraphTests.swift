import Foundation
import Testing

@testable import GitKit

@Suite("分支图布局")
struct CommitGraphTests {

    /// 造一条提交，只关心 hash 与父子关系。
    private func commit(_ hash: String, parents: [String] = []) -> Commit {
        let signature = Signature(name: "测试", email: "t@yugit.local", date: Date(timeIntervalSince1970: 0))
        return Commit(
            hash: hash,
            abbreviatedHash: String(hash.prefix(7)),
            parents: parents,
            author: signature,
            committer: signature,
            subject: "提交 \(hash)",
            body: "",
            refs: []
        )
    }

    @Test("线性历史全部落在第一条轨道上")
    func layoutsLinearHistory() {
        let graph = CommitGraph(commits: [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a"),
        ])

        #expect(graph.rows.count == 3)
        #expect(graph.rows.allSatisfy { $0.nodeLane == 0 })
        #expect(graph.maximumLaneCount == 1)
    }

    @Test("根提交之后轨道关闭")
    func closesLaneAtRootCommit() {
        let graph = CommitGraph(commits: [
            commit("b", parents: ["a"]),
            commit("a"),
        ])

        let root = try! #require(graph.rows.last)
        // 根提交没有父，不该再往下画线
        #expect(root.links.isEmpty)
    }

    @Test("分叉的两个分支各占一条轨道")
    func layoutsDivergedBranches() {
        //   d   c      两个分支各自的头
        //    \ /
        //     b
        //     a
        let graph = CommitGraph(commits: [
            commit("d", parents: ["b"]),
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a"),
        ])

        #expect(graph.rows[0].nodeLane == 0)
        #expect(graph.rows[1].nodeLane == 1, "第二个分支头要另开一条轨道")
        #expect(graph.maximumLaneCount == 2)

        // b 是汇合点：两条轨道并到一条
        let merged = graph.rows[2]
        #expect(merged.nodeLane == 0)
        let mergingLinks = merged.links.filter { $0.fromLane != $0.toLane }
        #expect(mergingLinks.count == 1, "第二条轨道要斜着并回主轨道")
        #expect(mergingLinks.first?.fromLane == 1)
        #expect(mergingLinks.first?.toLane == 0)
    }

    @Test("合并提交向第二个父分叉出新轨道")
    func layoutsMergeCommit() {
        //   m        合并提交
        //  / \
        // a   b
        //  \ /
        //   base
        let graph = CommitGraph(commits: [
            commit("m", parents: ["a", "b"]),
            commit("a", parents: ["base"]),
            commit("b", parents: ["base"]),
            commit("base"),
        ])

        let mergeRow = graph.rows[0]
        #expect(mergeRow.nodeLane == 0)

        // 第一个父沿用本轨道，第二个父分叉出去
        let branching = mergeRow.links.filter { $0.fromLane != $0.toLane }
        #expect(branching.count == 1)
        #expect(branching.first?.fromLane == 0)
        #expect(branching.first?.toLane == 1)

        #expect(graph.rows[1].nodeLane == 0, "第一个父继续走主轨道")
        #expect(graph.rows[2].nodeLane == 1, "第二个父走分叉出来的轨道")
    }

    @Test("无关的轨道竖直穿过当前行")
    func passesThroughUnrelatedLanes() {
        //  c    d      d 与 c 无关，c 那行要为 d 的线留出穿过的轨道
        //  |    |
        //  b    e
        let graph = CommitGraph(commits: [
            commit("c", parents: ["b"]),
            commit("d", parents: ["e"]),
            commit("b"),
            commit("e"),
        ])

        // 第二行（d）时，c→b 的线仍在轨道 0 上穿过
        let secondRow = graph.rows[1]
        let straightLinks = secondRow.links.filter { $0.fromLane == $0.toLane }
        #expect(straightLinks.contains { $0.fromLane == 0 }, "另一条分支线要竖直穿过")
    }

    @Test("多个根提交各自成线")
    func handlesMultipleRoots() {
        let graph = CommitGraph(commits: [
            commit("a"),
            commit("b"),
        ])

        #expect(graph.rows[0].nodeLane == 0)
        #expect(graph.rows[1].nodeLane == 0, "前一条线已结束，轨道可以复用")
    }

    @Test("轨道回收后不会无限变宽")
    func reusesFreedLanes() {
        // 反复分叉再收束，轨道数不该随提交数增长
        var commits: [Commit] = []
        for index in 0..<20 {
            commits.append(commit("side\(index)", parents: ["base\(index)"]))
            commits.append(commit("base\(index)", parents: ["base\(index + 1)"]))
        }
        commits.append(commit("base20"))

        let graph = CommitGraph(commits: commits)

        #expect(graph.maximumLaneCount <= 3, "轨道应当被回收复用，实得 \(graph.maximumLaneCount)")
    }

    @Test("同色分配给同一条分支线")
    func keepsColorStableAlongBranch() {
        let graph = CommitGraph(commits: [
            commit("c", parents: ["b"]),
            commit("b", parents: ["a"]),
            commit("a"),
        ])

        let colors = Set(graph.rows.map(\.colorIndex))
        #expect(colors.count == 1, "一条直线上的提交应当同色")
    }

    @Test("空输入不产生行")
    func handlesEmptyInput() {
        let graph = CommitGraph(commits: [])

        #expect(graph.rows.isEmpty)
        #expect(graph.maximumLaneCount == 0)
    }
}

@Suite("commit-graph 缓存")
struct CommitGraphCacheTests {

    @Test("写入后缓存文件存在")
    func writesCache() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")

        let before = await repository.client.hasCommitGraph(in: repository.url)
        try await repository.client.writeCommitGraph(in: repository.url)
        let after = await repository.client.hasCommitGraph(in: repository.url)

        #expect(!before)
        #expect(after)
    }

    @Test("缓存不影响历史读取结果")
    func doesNotChangeResults() async throws {
        let repository = try await TemporaryRepository()
        for index in 1...5 {
            try repository.write("v\(index)\n", to: "a.txt")
            try await repository.commitAll("第 \(index) 条")
        }

        let before = try await repository.client.log(
            in: repository.url, order: .topological)
        try await repository.client.writeCommitGraph(in: repository.url)
        let after = try await repository.client.log(
            in: repository.url, order: .topological)

        #expect(before.map(\.hash) == after.map(\.hash), "缓存只影响速度，不该改变结果")
    }

    @Test("空仓库上写缓存不报错")
    func toleratesEmptyRepository() async throws {
        let repository = try await TemporaryRepository()

        try await repository.client.writeCommitGraph(in: repository.url)
    }
}
