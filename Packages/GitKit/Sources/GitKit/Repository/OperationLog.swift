import Foundation

/// 仓库操作日志——v0.5 的「仓库时间线 + 无畏 Undo」建立在它之上。
///
/// v0.1 只负责如实记录；快照与回滚在 v0.5 补上。现在就把记录点定死，
/// 是为了避免后面回头给每个写操作补埋点。
public protocol OperationLogging: Sendable {
    func record(_ record: OperationRecord) async throws
    /// 返回最近的若干条记录，按时间正序。
    func recent(limit: Int) async throws -> [OperationRecord]
}

/// 一条操作记录。
public struct OperationRecord: Sendable, Equatable, Codable, Identifiable {

    public enum Outcome: Sendable, Equatable, Codable {
        case succeeded
        case failed(exitCode: Int32, message: String)

        public var isSuccess: Bool {
            if case .succeeded = self { true } else { false }
        }
    }

    public let id: UUID
    public let timestamp: Date
    public let operation: GitOperation

    /// 执行前 HEAD 指向的 commit；仓库尚无提交时为 nil。
    ///
    /// 这是 Undo 的锚点：v0.5 要靠它把 HEAD 挪回去。
    public let headBefore: String?

    /// 执行后 HEAD 指向的 commit。操作失败时与 ``headBefore`` 相同。
    public let headAfter: String?

    public let outcome: Outcome

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        operation: GitOperation,
        headBefore: String?,
        headAfter: String?,
        outcome: Outcome
    ) {
        self.id = id
        self.timestamp = timestamp
        self.operation = operation
        self.headBefore = headBefore
        self.headAfter = headAfter
        self.outcome = outcome
    }

    /// 这次操作确实让 HEAD 动了。
    public var movedHead: Bool {
        headBefore != headAfter
    }
}

/// 以 JSONL 追加写入 `<git-common-dir>/yugit/operations.jsonl` 的操作日志。
///
/// 放在 git 目录内而非 Application Support：仓库被移动或删除时日志跟着走、跟着消失，
/// 不留孤儿数据；v0.5 的快照 ref（`refs/yugit/*`）同样在仓库内，两者位置保持一致。
///
/// 用 `--git-common-dir` 而不是 `--git-dir`，让同一仓库的多个 worktree 共享一条
/// 时间线——支柱 3 的并行 agent 面板需要看到所有 worktree 上发生了什么。
public actor FileOperationLog: OperationLogging {

    public let fileURL: URL

    public init(repository: URL, client: GitClient) async throws {
        let result = try await client.run(["rev-parse", "--git-common-dir"], in: repository)
        let raw = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // git 可能返回相对路径（常见的就是 ".git"）。
        let gitDirectory =
            raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw, isDirectory: true)
            : repository.appendingPathComponent(raw, isDirectory: true)

        let directory = gitDirectory.appendingPathComponent("yugit", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("operations.jsonl")
    }

    public func record(_ record: OperationRecord) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var line = try encoder.encode(record)
        line.append(0x0A)

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
    }

    public func recent(limit: Int) throws -> [OperationRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try data
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .suffix(limit)
            .map { try decoder.decode(OperationRecord.self, from: Data($0)) }
    }
}
