import Foundation

/// 一棵按路径组织的树。
///
/// 泛型是为了两处都能用：工作区变更列表装 `StatusEntry`，
/// 提交详情的文件列表装 `CommitFileChange`。树的形状逻辑只写一遍。
public struct PathTreeNode<Value>: Identifiable {

    /// 从根到这里的完整路径，同时用作 id——同一棵树里路径必然唯一。
    public let id: String
    /// 这一级显示的名字。目录被折叠时会是 `a/b/c` 这样的多段。
    public let name: String
    /// 叶子节点携带的值；目录为 nil。
    public let value: Value?
    public let children: [PathTreeNode<Value>]

    public var isLeaf: Bool { value != nil }

    /// 这个子树下有多少个叶子。目录行上显示的计数用它。
    public var leafCount: Int {
        isLeaf ? 1 : children.reduce(0) { $0 + $1.leafCount }
    }

    public init(id: String, name: String, value: Value?, children: [PathTreeNode<Value>]) {
        self.id = id
        self.name = name
        self.value = value
        self.children = children
    }

    /// 这个子树下的全部叶子值。目录上的批量操作（暂存整个目录）用它。
    public var allValues: [Value] {
        if let value { return [value] }
        return children.flatMap(\.allValues)
    }
}

/// 展平后的一行：节点本身加上它的缩进层级。
public struct FlattenedPathRow<Value>: Identifiable {
    public let node: PathTreeNode<Value>
    public let depth: Int
    public var id: String { node.id }
}

extension Array {

    /// 把树展平成一维，供 `List` 渲染。
    ///
    /// 不用 SwiftUI 的 `OutlineGroup` 而是自己展平，有两个实在的理由：
    ///
    /// 1. `List` 的选中与 `tag` 在嵌套结构里行为很拧巴，展平成一维之后，
    ///    选中逻辑和原来的平铺列表完全一样，不必为树再写一套。
    /// 2. 参数收的是**折叠**集合而不是展开集合，于是默认状态是全展开——
    ///    打开变更列表就是为了看有哪些文件，默认折叠等于每次都要先点开一遍。
    public func flattenedTree<Value>(collapsed: Set<String>) -> [FlattenedPathRow<Value>]
    where Element == PathTreeNode<Value> {
        flatMap { node -> [FlattenedPathRow<Value>] in
            let row = FlattenedPathRow(node: node, depth: 0)
            guard !node.children.isEmpty, !collapsed.contains(node.id) else { return [row] }
            return [row]
                + node.children.flattenedTree(collapsed: collapsed).map {
                    FlattenedPathRow(node: $0.node, depth: $0.depth + 1)
                }
        }
    }
}

public enum PathTree {

    /// 把一组带路径的东西建成树。
    ///
    /// - Parameters:
    ///   - collapsingSingleChildDirectories: 把只含一个子目录的层级合并成
    ///     `Sources/GitKit/Diff` 这样的一行。**默认开着**，因为不合并的话，
    ///     Swift 这类目录层级很深的项目会缩进出十几级，
    ///     每一级只有一个孩子，纯粹是白占宽度——而中栏本来就窄。
    public static func build<Value>(
        from items: [Value],
        path: (Value) -> String,
        collapsingSingleChildDirectories: Bool = true
    ) -> [PathTreeNode<Value>] {
        let root = MutableNode<Value>(name: "", fullPath: "")

        for item in items {
            let components = path(item)
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty else { continue }
            root.insert(components: components[...], value: item, parentPath: "")
        }

        return sorted(
            root.children.values.map {
                $0.finalize(collapsing: collapsingSingleChildDirectories)
            })
    }

    /// 目录在前、文件在后，各自按名称排。
    ///
    /// 这是文件浏览器的通行顺序，也确实好用：目录是"要不要展开"的决定点，
    /// 混在文件中间的话每次都得在一列里挑出哪些能点开。
    private static func sorted<Value>(_ nodes: [PathTreeNode<Value>]) -> [PathTreeNode<Value>] {
        nodes.sorted { left, right in
            if left.isLeaf != right.isLeaf { return !left.isLeaf }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    // MARK: - 建树时用的可变中间结构

    /// 用 class 而不是 struct：建树要反复往深处找同一个节点再往里加，
    /// 值语义每层都要复制回写，代码会绕成一团。
    ///
    /// 自身泛型而不是拿 `Any` 装值：用 `Any` 的话 `finalize` 得靠 `as?` 转回来，
    /// 编译器在建树处也推断不出类型，而转换失败会静默丢掉整个节点。
    private final class MutableNode<Value> {
        let name: String
        let fullPath: String
        var value: Value?
        /// 用字典而不是数组：同一个目录会被反复命中，线性查找在文件多时是平方级。
        var children: [String: MutableNode<Value>] = [:]

        init(name: String, fullPath: String) {
            self.name = name
            self.fullPath = fullPath
        }

        func insert(components: ArraySlice<String>, value: Value, parentPath: String) {
            guard let head = components.first else { return }
            let path = parentPath.isEmpty ? head : parentPath + "/" + head
            let rest = components.dropFirst()

            let child =
                children[head]
                ?? {
                    let node = MutableNode(name: head, fullPath: path)
                    children[head] = node
                    return node
                }()

            if rest.isEmpty {
                child.value = value
            } else {
                child.insert(components: rest, value: value, parentPath: path)
            }
        }

        func finalize(collapsing: Bool) -> PathTreeNode<Value> {
            // 合并只在「自己是目录、唯一的孩子也是目录」时发生。
            //
            // 三个条件缺一不可：
            // - `value == nil`：自己是文件就不能合并，否则同名的文件和目录
            //   并存时，那个文件会从树上消失。
            // - `children.count == 1`：有分叉就该保留层级，那正是结构信息。
            // - `only.value == nil`：**孩子必须也是目录**。少了这条，
            //   最后一级的文件名会被并进目录名，`a/b/c.txt` 塌成一行
            //   「a/b/c.txt」，整棵树没有任何可展开的东西。
            if collapsing, value == nil, children.count == 1,
                let only = children.values.first, only.value == nil
            {
                let merged = only.finalize(collapsing: true)
                return PathTreeNode(
                    id: merged.id,
                    name: name + "/" + merged.name,
                    value: merged.value,
                    children: merged.children
                )
            }

            return PathTreeNode(
                id: fullPath,
                name: name,
                value: value,
                children: sorted(children.values.map { $0.finalize(collapsing: collapsing) })
            )
        }
    }
}
