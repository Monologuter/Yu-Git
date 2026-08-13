import Foundation

/// 提交历史的分支图布局。
///
/// PRD 把 commit graph 列为门面——视觉质量决定第一印象。这里只算「哪条线画在哪个
/// 轨道上」，具体绘制交给视图层。
///
/// - Important: 输入必须是**拓扑序**（``CommitOrder/topological``）。按时间排的序列里
///   父提交可能出现在子提交之前，算出来的图会出现视觉上的交叉错乱。
public struct CommitGraph: Sendable {

    /// 一行的布局。
    public struct Row: Sendable, Equatable {
        /// 提交节点所在的轨道（0 起，自左向右）。
        public let nodeLane: Int
        /// 本行需要预留的轨道数，决定图形区宽度。
        public let laneCount: Int
        /// 本行要画的线段。节点本身不在其中，由视图单独绘制。
        public let links: [Link]
        /// 节点的配色索引，与所在分支线保持一致。
        public let colorIndex: Int
    }

    /// 一段从本行顶部连到本行底部的线。
    ///
    /// `fromLane == toLane` 是竖直穿过；不等则是分叉或合并的斜线。
    public struct Link: Sendable, Equatable {
        public let fromLane: Int
        public let toLane: Int
        public let colorIndex: Int
    }

    public let rows: [Row]

    /// 所有行中最宽的轨道数，用于给图形区定宽。
    public var maximumLaneCount: Int {
        rows.map(\.laneCount).max() ?? 0
    }

    /// 按拓扑序的提交列表算出布局。
    public init(commits: [Commit]) {
        var rows: [Row] = []
        rows.reserveCapacity(commits.count)

        /// 每条轨道当前「在等」哪个 commit。nil 表示轨道空闲。
        var expected: [String?] = []
        /// 轨道的配色。轨道被复用时重新取色，避免不同分支共用一个颜色显得混乱。
        var colors: [Int] = []
        var nextColor = 0

        func allocateLane(for hash: String) -> Int {
            if let free = expected.firstIndex(where: { $0 == nil }) {
                expected[free] = hash
                colors[free] = nextColor
                nextColor += 1
                return free
            }
            expected.append(hash)
            colors.append(nextColor)
            nextColor += 1
            return expected.count - 1
        }

        for commit in commits {
            // 有哪些轨道在等这条提交。多于一条说明这里是汇合点。
            let waiting = expected.indices.filter { expected[$0] == commit.hash }
            let nodeLane = waiting.first ?? allocateLane(for: commit.hash)
            let nodeColor = colors[nodeLane]

            var links: [Link] = []

            // 与本行无关的轨道竖直穿过
            for lane in expected.indices
            where expected[lane] != nil && !waiting.contains(lane) {
                links.append(Link(fromLane: lane, toLane: lane, colorIndex: colors[lane]))
            }

            // 其余等待本提交的轨道汇入节点所在轨道
            for lane in waiting.dropFirst() {
                links.append(Link(fromLane: lane, toLane: nodeLane, colorIndex: colors[lane]))
                expected[lane] = nil
            }

            // 第一个父沿用当前轨道，历史主线因此保持竖直
            if let firstParent = commit.parents.first {
                expected[nodeLane] = firstParent
                links.append(Link(fromLane: nodeLane, toLane: nodeLane, colorIndex: nodeColor))
            } else {
                // 根提交，这条线到此为止
                expected[nodeLane] = nil
            }

            // 其余父（合并提交才有）分叉到别的轨道
            for parent in commit.parents.dropFirst() {
                let targetLane: Int
                if let existing = expected.firstIndex(where: { $0 == parent }) {
                    // 已经有轨道在等这个父，连过去即可，不必新开
                    targetLane = existing
                } else {
                    targetLane = allocateLane(for: parent)
                }
                links.append(Link(fromLane: nodeLane, toLane: targetLane, colorIndex: colors[targetLane]))
            }

            // 尾部空闲轨道不占宽度
            let usedLaneCount = (expected.lastIndex { $0 != nil }).map { $0 + 1 } ?? 0
            rows.append(
                Row(
                    nodeLane: nodeLane,
                    laneCount: max(usedLaneCount, nodeLane + 1),
                    links: links,
                    colorIndex: nodeColor
                )
            )
        }

        self.rows = rows
    }
}
