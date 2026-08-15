import Foundation

/// 退回某张快照会对工作区做什么。
///
/// 存在的理由：在此之前恢复是**盲跳**——点下去工作区就变了，
/// 而用户不知道会丢掉什么。「能不能撤」这个答案只有配上「撤了会怎样」
/// 才真正成立。
public struct SnapshotPreview: Sendable, Equatable {

    /// 会被写回来的文件：快照里有，现在没有。
    public let restored: [String]
    /// **会被删掉的文件**：现在有，快照里没有。这是最需要用户看清的一栏——
    /// 快照之后新建的文件会消失。
    public let removed: [String]
    /// 内容会被覆盖的文件：两边都有但不一样。
    public let overwritten: [String]

    public init(restored: [String], removed: [String], overwritten: [String]) {
        self.restored = restored
        self.removed = removed
        self.overwritten = overwritten
    }

    /// 一个文件都不会变。
    public var isEmpty: Bool {
        restored.isEmpty && removed.isEmpty && overwritten.isEmpty
    }

    public var totalCount: Int { restored.count + removed.count + overwritten.count }

    /// 有没有会丢东西的改动。
    ///
    /// 「被删掉」和「被覆盖」都算——两者都是当前工作区里的内容消失，
    /// 而那些内容可能是快照之后做的、还没提交的活。
    public var losesWork: Bool { !removed.isEmpty || !overwritten.isEmpty }
}

extension SnapshotStore {

    /// 算出退回这张快照会改动哪些文件。
    ///
    /// 只跑三条 git 命令，**不按文件逐个跑**：一个中等仓库有几千个文件，
    /// 每个文件启动一次进程要几十秒，而这个预览是要在点开对话框那一刻就显示的。
    /// - `ls-tree -r` 一次拿到快照里所有文件的 blob hash
    /// - `ls-files` 一次拿到工作区的文件清单
    /// - `hash-object --stdin-paths` 一次算完所有待比对文件的 hash
    public func preview(_ snapshot: Snapshot) async throws -> SnapshotPreview {
        let snapshotEntries = try await blobHashes(inTree: snapshot.commit)
        let currentFiles = try await workTreeFiles()

        let snapshotPaths = Set(snapshotEntries.keys)
        let restored = snapshotPaths.subtracting(currentFiles).sorted()
        let removed = currentFiles.subtracting(snapshotPaths).sorted()

        // 两边都有的才需要比内容
        let shared = snapshotPaths.intersection(currentFiles).sorted()
        let currentHashes = try await hashObjects(shared)

        let overwritten = shared.filter { path in
            guard let current = currentHashes[path] else {
                // 算不出 hash（文件刚被删、或是个符号链接指向不存在的地方）
                // 就当它变了——预览宁可多报也不能少报
                return true
            }
            return snapshotEntries[path] != current
        }

        return SnapshotPreview(restored: restored, removed: removed, overwritten: overwritten)
    }

    /// 只把指定的几个文件恢复到快照那一刻，其余一概不动。
    ///
    /// 存在的理由：整个工作区退回去往往下手太重。真实场景是「agent 把这一个文件
    /// 改坏了，但另外三个改得挺好」——全量恢复会把好的那三个也一起退掉，
    /// 于是用户宁可手工去改，时间线就白做了。
    ///
    /// 和全量恢复的两处关键差别：
    /// - **不动 index。** 全量恢复会把 index 退回 HEAD；这里是外科手术，
    ///   动了 index 会让用户已经暂存好的其他文件莫名其妙地掉出暂存区。
    /// - 只处理点名的路径。没点到的文件，无论快照里有没有，都保持原样。
    ///
    /// - Parameter paths: 要恢复的路径。快照里没有的路径表示「把它删掉」——
    ///   那是预览里「会被删掉」那一栏对应的操作。
    public func restore(_ snapshot: Snapshot, paths: [String]) async throws {
        guard !paths.isEmpty else { return }

        let inSnapshot = try await blobHashes(inTree: snapshot.commit)
        let selected = Set(paths)

        // 快照里没有的：这些是快照之后新建的，恢复即删除
        for path in selected.subtracting(inSnapshot.keys) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(path))
        }

        let toWrite = selected.intersection(inSnapshot.keys).sorted()
        guard !toWrite.isEmpty else { return }

        // 独立 index，免得污染真正的暂存区
        let indexPath = directory.appendingPathComponent("partial-restore.idx")
        let environment = ["GIT_INDEX_FILE": indexPath.path]
        defer {
            try? FileManager.default.removeItem(at: indexPath)
            try? FileManager.default.removeItem(at: indexPath.appendingPathExtension("lock"))
        }

        try await client.run(
            ["read-tree", snapshot.commit], in: root, additionalEnvironment: environment)
        try await client.run(
            ["checkout-index", "--force", "--"] + toWrite,
            in: root,
            additionalEnvironment: environment
        )
    }

    /// 一棵树里所有文件的 blob hash。
    private func blobHashes(inTree commit: String) async throws -> [String: String] {
        // `-z` 之后每条记录形如 `<mode> <type> <hash>\t<path>`
        let result = try await client.run(
            ["ls-tree", "-r", "-z", commit], in: root, allowsOptionalLocks: false)

        var entries: [String: String] = [:]
        for record in result.standardOutput.split(separator: 0x00, omittingEmptySubsequences: true) {
            let text = String(decoding: record, as: UTF8.self)
            guard let tab = text.firstIndex(of: "\t") else { continue }
            let meta = text[text.startIndex..<tab].split(separator: " ")
            guard meta.count >= 3 else { continue }
            entries[String(text[text.index(after: tab)...])] = String(meta[2])
        }
        return entries
    }

    private func workTreeFiles() async throws -> Set<String> {
        let result = try await client.run(
            ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            in: root,
            allowsOptionalLocks: false
        )
        return Set(
            result.standardOutput
                .split(separator: 0x00, omittingEmptySubsequences: true)
                .map { String(decoding: $0, as: UTF8.self) }
        )
    }

    /// 一次算完一批文件的 blob hash。
    ///
    /// `--stdin-paths` 从标准输入读路径，一次进程算完全部。逐个跑
    /// `hash-object <path>` 的话，几千个文件就是几千次进程启动。
    private func hashObjects(_ paths: [String]) async throws -> [String: String] {
        guard !paths.isEmpty else { return [:] }

        // 路径用换行分隔，所以**含换行的文件名会被切错**。
        // 那种文件名极其罕见，且这里最坏的后果只是预览里多报一个「会被覆盖」——
        // 宁可多报也不能少报，所以直接把它们排除在批量之外，当作变了处理。
        let safePaths = paths.filter { !$0.contains("\n") }
        guard !safePaths.isEmpty else { return [:] }

        let input = Data((safePaths.joined(separator: "\n") + "\n").utf8)
        let result = try await client.run(
            ["hash-object", "--stdin-paths"],
            in: root,
            allowsOptionalLocks: false,
            standardInput: input
        )

        let hashes = result.standardOutputText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        // 输出顺序和输入一一对应。对不上就整批作废——
        // 错位的 hash 会让预览指着完全不相干的文件说「它变了」
        guard hashes.count == safePaths.count else { return [:] }

        return Dictionary(uniqueKeysWithValues: zip(safePaths, hashes))
    }
}
