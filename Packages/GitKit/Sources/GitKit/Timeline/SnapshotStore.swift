import Foundation

/// 一次工作区快照。
public struct Snapshot: Sendable, Equatable, Identifiable {

    public var id: String { reference }

    /// 快照 commit 的 hash。
    public let commit: String
    /// 完整引用名，如 `refs/yugit/timeline/1700000000-abc`。
    public let reference: String
    public let timestamp: Date
    /// 拍快照时 HEAD 指向的 commit；unborn 仓库为 nil。
    public let headCommit: String?
    /// 拍快照时所在的分支；detached 时为 nil。
    public let branchName: String?
    /// 关联操作的中文描述。
    public let summary: String

    public init(
        commit: String,
        reference: String,
        timestamp: Date,
        headCommit: String?,
        branchName: String?,
        summary: String
    ) {
        self.commit = commit
        self.reference = reference
        self.timestamp = timestamp
        self.headCommit = headCommit
        self.branchName = branchName
        self.summary = summary
    }
}

/// 工作区快照的存取。
///
/// 这是「无畏 Undo」（PRD 支柱 1）的物理基础：任何危险操作之前先拍一张，
/// 出事就能整个退回去。
///
/// 快照落在 `refs/yugit/` 私有命名空间，**不碰用户的 stash 栈与 reflog**——
/// 那两处是用户自己的工作区，被工具塞满会让人无法使用。
public actor SnapshotStore {

    // internal 而不是 private：`SnapshotPreview.swift` 里的扩展要用到它们，
    // 而 private 只在同一个文件内可见。仍然不对模块外暴露。
    let root: URL
    let client: GitClient
    let directory: URL

    /// 快照 commit 的作者署名。用固定署名而非用户身份，
    /// 免得这些内部对象混进「我的提交」之类的统计里。
    private static let author = "驭Git 时间线 <timeline@yugit.local>"

    public init(root: URL, client: GitClient, directory: URL) {
        self.root = root
        self.client = client
        self.directory = directory
    }

    public static func open(root: URL, client: GitClient) async throws -> SnapshotStore {
        let directory = try await GitNamespace.directory(in: root, client: client)
        return SnapshotStore(root: root, client: client, directory: directory)
    }

    // MARK: - 拍快照

    /// 把当前工作区（含未跟踪文件）整个存下来。
    ///
    /// - Parameter identifier: 引用名里用的唯一标识，由调用方保证唯一。
    /// - Returns: 工作区为空且无 HEAD 时返回 nil——没有任何内容可存。
    public func capture(summary: String, identifier: String) async throws -> Snapshot? {
        // 临时 index 必须放在 .git 内：放工作区会变成未跟踪文件，
        // 既出现在变更列表里，还会被这次快照自己收进去。
        let indexPath = directory.appendingPathComponent("snapshot-\(identifier).idx")
        let environment = ["GIT_INDEX_FILE": indexPath.path]
        defer {
            try? FileManager.default.removeItem(at: indexPath)
            try? FileManager.default.removeItem(at: indexPath.appendingPathExtension("lock"))
        }

        // 用独立 index 收集工作区全部内容。被 .gitignore 忽略的文件不会进来，
        // 这是想要的——构建产物没有快照的价值。
        try await client.run(
            ["add", "--all", "."], in: root, additionalEnvironment: environment)

        let treeResult = try await client.run(
            ["write-tree"], in: root, additionalEnvironment: environment)
        let tree = treeResult.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tree.isEmpty else { return nil }

        let head = await currentHead()
        let branch = await currentBranchName()

        var commitArguments = ["commit-tree", tree]
        if let head {
            // 挂在 HEAD 之下，快照因此能在 git 的对象图里被正常遍历
            commitArguments += ["-p", head]
        }
        commitArguments += ["-m", summary]

        let commitResult = try await client.run(
            commitArguments,
            in: root,
            additionalEnvironment: [
                "GIT_AUTHOR_NAME": "驭Git 时间线",
                "GIT_AUTHOR_EMAIL": "timeline@yugit.local",
                "GIT_COMMITTER_NAME": "驭Git 时间线",
                "GIT_COMMITTER_EMAIL": "timeline@yugit.local",
            ]
        )
        let commit = commitResult.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commit.isEmpty else { return nil }

        let reference = GitNamespace.timelineRefPrefix + identifier
        try await client.run(["update-ref", reference, commit], in: root)

        return Snapshot(
            commit: commit,
            reference: reference,
            timestamp: Date(),
            headCommit: head,
            branchName: branch,
            summary: summary
        )
    }

    // MARK: - 恢复

    /// 把工作区恢复到快照时的状态。
    ///
    /// - Important: 这会覆盖当前工作区。调用方必须先为「当前状态」也拍一张快照，
    ///   否则用户撤销之后就无法再重做——撤销本身也得是可撤销的。
    ///
    /// - Note: 快照不区分「已暂存」与「未暂存」，恢复后 index 统一退回 HEAD 状态。
    ///   保住文件内容是首要目标，暂存与否再手动分一次即可。
    public func restore(_ snapshot: Snapshot) async throws {
        let snapshotFiles = try await filesInSnapshot(snapshot)
        let currentFiles = try await filesInWorkTree()

        // 先删快照之后新增的文件。
        //
        // 不能指望 `read-tree -u --reset` 代劳：它只管被 index 跟踪的文件，
        // 而未跟踪文件恰恰是最需要时间线兜底的那部分——用户以为回到了那一刻，
        // 实际却留着后来生成的产物。
        //
        // 被 .gitignore 忽略的文件不在 currentFiles 里，因此不会被删——
        // 删掉别人的构建缓存是很讨人厌的行为。
        for path in currentFiles.subtracting(snapshotFiles) {
            try? FileManager.default.removeItem(at: root.appendingPathComponent(path))
        }

        // 再把快照内容写回工作区。走独立 index，免得未跟踪文件被顺带变成已暂存。
        let indexPath = directory.appendingPathComponent("restore.idx")
        let environment = ["GIT_INDEX_FILE": indexPath.path]
        defer {
            try? FileManager.default.removeItem(at: indexPath)
            try? FileManager.default.removeItem(at: indexPath.appendingPathExtension("lock"))
        }

        try await client.run(
            ["read-tree", snapshot.commit], in: root, additionalEnvironment: environment)
        try await client.run(
            ["checkout-index", "--all", "--force"], in: root, additionalEnvironment: environment)

        // 真正的 index 退回 HEAD
        if let head = snapshot.headCommit {
            try await client.run(["read-tree", head], in: root)
        }
    }

    private func filesInSnapshot(_ snapshot: Snapshot) async throws -> Set<String> {
        let result = try await client.run(
            ["ls-tree", "-r", "-z", "--name-only", snapshot.commit], in: root)
        return Set(
            result.standardOutput
                .split(separator: 0x00, omittingEmptySubsequences: true)
                .map { String(decoding: $0, as: UTF8.self) }
        )
    }

    /// 工作区当前的文件：被跟踪的 + 未跟踪的，不含被忽略的。
    private func filesInWorkTree() async throws -> Set<String> {
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

    // MARK: - 查询与清理

    /// 列出全部快照，按时间倒序。
    public func list() async throws -> [Snapshot] {
        let format = [
            "%(refname)",
            "%(objectname)",
            "%(committerdate:iso8601-strict)",
            "%(parent)",
            "%(contents:subject)",
        ].joined(separator: "%1f")

        let result = try await client.run(
            [
                "for-each-ref",
                "--format=\(format)",
                "--sort=-committerdate",
                GitNamespace.timelineRefPrefix,
            ],
            in: root,
            allowsOptionalLocks: false
        )

        return result.standardOutputText
            .split(separator: "\n")
            .compactMap { line -> Snapshot? in
                let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                guard fields.count >= 5 else { return nil }
                return Snapshot(
                    commit: String(fields[1]),
                    reference: String(fields[0]),
                    timestamp: LogParser.parseTimestamp(String(fields[2])) ?? Date(timeIntervalSince1970: 0),
                    headCommit: fields[3].isEmpty ? nil : String(fields[3]),
                    branchName: nil,
                    summary: String(fields[4])
                )
            }
    }

    /// 只保留最近的若干张快照，**标注过的一律留着**。
    ///
    /// 快照 ref 会让对象免于 gc，不清理的话仓库体积会一直涨。
    ///
    /// 标注是用户明确说过「这张重要」的信号——一个纯按数量的策略会把它删掉，
    /// 而那恰恰是最不该删的那张。所以标注过的不计入配额也不参与淘汰：
    /// 用户嫌多的话，取消标注即可。
    public func prune(keeping limit: Int) async throws {
        let snapshots = try await list()
        let labelled = await labelledCommits()

        // 配额只管没标注过的那些
        var remaining = limit
        for snapshot in snapshots {
            if labelled.contains(snapshot.commit) { continue }
            if remaining > 0 {
                remaining -= 1
                continue
            }
            // 删不掉某一条不该拖累其余的清理
            _ = try? await client.run(["update-ref", "-d", snapshot.reference], in: root)
        }
    }

    // MARK: - 内部

    private func currentHead() async -> String? {
        guard
            let result = try? await client.runReturningResult(["rev-parse", "HEAD"], in: root),
            result.isSuccess
        else { return nil }
        return result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentBranchName() async -> String? {
        guard
            let result = try? await client.runReturningResult(
                ["symbolic-ref", "--short", "HEAD"], in: root),
            result.isSuccess
        else { return nil }
        let name = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
