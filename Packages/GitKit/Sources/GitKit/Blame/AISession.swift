import Foundation

/// 一次 AI 会话在某条提交上留下的记录。
///
/// 归因 blame 现在只能说到「这行是 Claude 写的」——那来自提交信息里的
/// `Co-Authored-By` trailer。但**今天的提交信息里没有会话信息**：
/// Claude Code 只写工具名和一个链接，不带 session id，也不带当时的 prompt。
/// 所以「哪次对话、哪个 prompt」这个问题，靠解析提交信息是答不出来的——
/// 得先有地方让 agent 把它写下来。
///
/// 这个类型就是那个格式，配套的写入口是 MCP 工具 `yugit_attribute`：
/// agent 知道自己的会话，提交之后调一次即可。没有记录时，blame 退回到
/// 今天的行为（只说工具名），不假装知道自己不知道的事。
public struct AISession: Sendable, Equatable, Codable {

    /// 工具名，如 `Claude Code`。
    public let tool: String
    /// 会话标识。agent 自己的会话 id，我们不解释它的含义，原样存原样显示。
    public let sessionID: String
    /// 用户当时说了什么。
    ///
    /// 只存**这一轮的指令**，不存整段对话——对话可能很长，而且里面往往有
    /// 用户的私密内容。存进 git 的东西会跟着仓库跑到任何人手上。
    public let prompt: String
    public let timestamp: Date

    public init(tool: String, sessionID: String, prompt: String, timestamp: Date) {
        self.tool = tool
        self.sessionID = sessionID
        self.prompt = prompt
        self.timestamp = timestamp
    }

    /// 展示用的一句话。prompt 可能很长，列表里只放得下开头。
    public var summary: String {
        let condensed =
            prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard condensed.count > 60 else { return condensed }
        return String(condensed.prefix(60)) + "…"
    }
}

extension GitClient {

    /// 存 AI 会话记录的私有 notes 引用。
    ///
    /// 和快照标注分开放（那个是 `timeline-labels`）：两者的生命周期和含义都不同，
    /// 混在一个 ref 里之后，清理其中一类会连带影响另一类。
    static let sessionRef = "refs/yugit/ai-sessions"

    /// 给某条提交记一次 AI 会话。
    public func recordSession(
        _ session: AISession,
        for commit: String,
        in repository: URL
    ) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        // 用 `--file=-` 从 stdin 读，而不是塞进 `-m` 参数：
        // prompt 是用户写的任意文本，可能很长、可能有换行，
        // 走参数会撞上命令行长度上限，也更容易被 shell 语义咬到。
        try await run(
            ["notes", "--ref=\(Self.sessionRef)", "add", "-f", "--file=-", commit],
            in: repository,
            standardInput: data
        )
    }

    /// 一次读出多条提交的会话记录。
    ///
    /// **批量而不是逐条问。** blame 一屏可能涉及几十个 commit，
    /// 逐条跑 `notes show` 就是几十次进程启动。这里两条命令解决：
    /// `notes list` 拿到全部（注释 blob，被注释对象）对，
    /// `cat-file --batch` 一次读完所有 blob 内容。
    public func sessions(in repository: URL) async -> [String: AISession] {
        guard
            let listing = try? await runReturningResult(
                ["notes", "--ref=\(Self.sessionRef)", "list"],
                in: repository,
                allowsOptionalLocks: false
            ),
            listing.isSuccess
        else { return [:] }

        // 每行是 `<注释 blob> <被注释的对象>`
        var blobToCommit: [String: String] = [:]
        for line in listing.standardOutputText.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { continue }
            blobToCommit[String(parts[0])] = String(parts[1])
        }
        guard !blobToCommit.isEmpty else { return [:] }

        let blobs = Array(blobToCommit.keys)
        let input = Data((blobs.joined(separator: "\n") + "\n").utf8)
        guard
            let batch = try? await runReturningResult(
                ["cat-file", "--batch"],
                in: repository,
                allowsOptionalLocks: false,
                standardInput: input
            ),
            batch.isSuccess
        else { return [:] }

        return parseBatch(batch.standardOutput, blobs: blobs, blobToCommit: blobToCommit)
    }

    /// 解析 `git cat-file --batch` 的输出。
    ///
    /// 格式是**头行加正文**交替：`<sha> <type> <size>\n<正文><换行>`。
    /// 正文按字节数取，不能按换行找——JSON 里本来就可能有换行。
    private func parseBatch(
        _ data: Data,
        blobs: [String],
        blobToCommit: [String: String]
    ) -> [String: AISession] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var result: [String: AISession] = [:]
        var cursor = data.startIndex

        while cursor < data.endIndex {
            guard let newline = data[cursor...].firstIndex(of: 0x0A) else { break }
            let header = String(decoding: data[cursor..<newline], as: UTF8.self)
            let fields = header.split(separator: " ")
            // `<sha> missing` 这种也可能出现，字段数不对就跳过
            guard fields.count >= 3, let size = Int(fields[2]) else { break }

            let bodyStart = data.index(after: newline)
            let bodyEnd = data.index(bodyStart, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
            let body = data[bodyStart..<bodyEnd]

            if let commit = blobToCommit[String(fields[0])],
                let session = try? decoder.decode(AISession.self, from: Data(body))
            {
                result[commit] = session
            }

            // 正文之后还有一个换行
            cursor = data.index(bodyEnd, offsetBy: 1, limitedBy: data.endIndex) ?? data.endIndex
        }

        return result
    }
}
