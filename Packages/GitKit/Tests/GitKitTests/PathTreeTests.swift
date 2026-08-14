import Foundation
import Testing

@testable import GitKit

@Suite("路径树")
struct PathTreeTests {

    /// 测试里只关心路径，装一个字符串就够。
    private func build(
        _ paths: [String],
        collapsing: Bool = true
    ) -> [PathTreeNode<String>] {
        PathTree.build(from: paths, path: { $0 }, collapsingSingleChildDirectories: collapsing)
    }

    /// 把树摊平成 "缩进 + 名字" 的文本，方便一眼看出形状。
    private func render(_ nodes: [PathTreeNode<String>], depth: Int = 0) -> [String] {
        nodes.flatMap { node in
            [String(repeating: "  ", count: depth) + node.name]
                + render(node.children, depth: depth + 1)
        }
    }

    @Test("同目录下的文件归到一起")
    func groupsSiblings() {
        let tree = build(["src/a.swift", "src/b.swift", "readme.md"])
        #expect(
            render(tree) == [
                "src",
                "  a.swift",
                "  b.swift",
                "readme.md",
            ])
    }

    @Test("目录排在文件前面")
    func directoriesComeFirst() {
        // 按纯字母序的话 a.txt 会排在 zzz 前面，那样目录就散落在文件中间，
        // 每次都得在一列里挑出哪些能点开
        let tree = build(["a.txt", "zzz/b.txt"])
        #expect(render(tree) == ["zzz", "  b.txt", "a.txt"])
    }

    @Test("只有一个孩子的目录链合并成一行")
    func collapsesSingleChildChain() {
        // Swift 项目的目录层级很深，不合并的话会缩进出十几级，
        // 每级只有一个孩子，纯粹白占宽度
        let tree = build(["Packages/GitKit/Sources/GitKit/Diff/A.swift"])
        #expect(
            render(tree) == [
                "Packages/GitKit/Sources/GitKit/Diff",
                "  A.swift",
            ])
    }

    @Test("分叉处停止合并")
    func stopsCollapsingAtBranch() {
        let tree = build([
            "a/b/c/one.txt",
            "a/b/d/two.txt",
        ])
        #expect(
            render(tree) == [
                "a/b",
                "  c",
                "    one.txt",
                "  d",
                "    two.txt",
            ])
    }

    @Test("可以关掉合并")
    func collapsingIsOptional() {
        let tree = build(["a/b/c.txt"], collapsing: false)
        #expect(render(tree) == ["a", "  b", "    c.txt"])
    }

    @Test("合并后 id 仍是叶子的完整路径")
    func mergedNodeKeepsLeafIdentity() {
        // id 拿去做选中态和展开态的键，指错了会选中另一个节点
        let tree = build(["a/b/c.txt"])
        #expect(tree[0].id == "a/b")
        #expect(tree[0].children[0].id == "a/b/c.txt")
    }

    @Test("目录知道自己底下有多少文件")
    func countsLeaves() {
        let tree = build(["src/x/1.txt", "src/x/2.txt", "src/y/3.txt"])
        #expect(tree[0].leafCount == 3)
        #expect(tree[0].name == "src")
    }

    @Test("目录能取出底下所有文件，供批量暂存用")
    func collectsAllValues() {
        let tree = build(["src/a.txt", "src/sub/b.txt"])
        #expect(Set(tree[0].allValues) == ["src/a.txt", "src/sub/b.txt"])
    }

    @Test("带中文和空格的路径原样保留")
    func keepsUnicodePaths() {
        let tree = build(["文档 目录/说明 文件.md"])
        #expect(render(tree) == ["文档 目录", "  说明 文件.md"])
    }

    @Test("空输入和畸形路径不炸")
    func handlesEdgeCases() {
        #expect(build([]).isEmpty)
        // 前导斜杠、连续斜杠都不该产生空名字的节点
        #expect(render(build(["/a.txt"])) == ["a.txt"])
        #expect(render(build(["a//b.txt"])) == ["a", "  b.txt"])
    }

    // MARK: - 展平

    @Test("默认全展开：不传折叠集合时每个节点都在")
    func flattensFullyExpandedByDefault() {
        let tree = build(["src/a.txt", "src/b.txt"])
        let rows = tree.flattenedTree(collapsed: [])
        #expect(rows.map(\.node.name) == ["src", "a.txt", "b.txt"])
        #expect(rows.map(\.depth) == [0, 1, 1])
    }

    @Test("折叠一个目录会连它的整个子树一起收起")
    func collapseHidesWholeSubtree() {
        let tree = build(["src/deep/a.txt", "src/deep/b.txt", "top.txt"])
        // src/deep 被合并成一行，id 是合并链末端的路径
        let directory = tree[0].id
        let rows = tree.flattenedTree(collapsed: [directory])
        #expect(rows.map(\.node.name) == ["src/deep", "top.txt"])
    }

    @Test("折叠集合里有不存在的 id 也不影响")
    func ignoresUnknownCollapsedIDs() {
        // 目录改名或文件被提交后，旧 id 会留在折叠集合里
        let tree = build(["a/x.txt"])
        let rows = tree.flattenedTree(collapsed: ["早就没了的目录"])
        #expect(rows.count == 2)
    }

    @Test("同名的文件和目录并存时，文件不会被合并吞掉")
    func doesNotSwallowFileSharingNameWithDirectory() {
        // git 里同一路径不会既是文件又是目录，但历史对比、
        // 大小写不敏感的文件系统上都可能出现近似情形。
        // 真出现时宁可多一层缩进，也不能让某个文件从树上消失。
        let tree = build(["a", "a/b.txt"])
        let names = render(tree)
        #expect(names.contains { $0.hasSuffix("b.txt") })
    }
}
