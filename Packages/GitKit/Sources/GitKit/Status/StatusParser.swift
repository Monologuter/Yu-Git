import Foundation

/// `git status --porcelain=v2 --branch -z` 的解析器。
///
/// 只解析 porcelain v2（不解析 v1）：v2 额外给出 HEAD、upstream、ahead/behind、
/// 文件模式、oid 与重命名相似度，是 GUI 需要的全部信息。
///
/// `-z` 模式下每条记录以 NUL 结尾、路径不做任何转义——这是正确处理中文与含空格
/// 文件名的前提。代价是重命名记录会跨越两个 NUL 段，见 ``parse(_:)`` 中的处理。
public enum StatusParser {

    public static func parse(_ data: Data) throws -> RepositoryStatus {
        var commit: String?
        var name: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var entries: [StatusEntry] = []

        let records = data.split(separator: 0x00, omittingEmptySubsequences: true)
        var index = 0

        while index < records.count {
            let line = String(decoding: records[index], as: UTF8.self)
            index += 1

            guard let marker = line.first else { continue }
            switch marker {
            case "#":
                let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count >= 3 else { break }
                let value = String(parts[2])
                switch parts[1] {
                case "branch.oid":
                    commit = value == "(initial)" ? nil : value
                case "branch.head":
                    name = value == "(detached)" ? nil : value
                case "branch.upstream":
                    upstream = value
                case "branch.ab":
                    (ahead, behind) = try parseAheadBehind(value)
                default:
                    break  // 未来 git 版本新增的 header 直接忽略，不要因此报错
                }

            case "1":
                entries.append(try parseOrdinary(line))

            case "2":
                // -z 模式下重命名/复制的**来源路径单独占据下一个 NUL 段**，
                // 因此这里必须多吃一段。按 NUL 简单切分再逐条解析会在这里错位。
                guard index < records.count else {
                    throw GitError.parseFailure(reason: "重命名记录缺少来源路径", context: line)
                }
                let originalPath = String(decoding: records[index], as: UTF8.self)
                index += 1
                entries.append(try parseRenamed(line, originalPath: originalPath))

            case "u":
                entries.append(try parseUnmerged(line))

            case "?":
                entries.append(try parseUnversioned(line, kind: .untracked))

            case "!":
                entries.append(try parseUnversioned(line, kind: .ignored))

            default:
                throw GitError.parseFailure(reason: "无法识别的记录类型「\(marker)」", context: line)
            }
        }

        return RepositoryStatus(
            branch: BranchStatus(
                commit: commit,
                name: name,
                upstream: upstream,
                ahead: ahead,
                behind: behind
            ),
            entries: entries
        )
    }

    // MARK: - 各类记录

    /// `1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>`
    private static func parseOrdinary(_ line: String) throws -> StatusEntry {
        // maxSplits 精确到路径之前，路径中的空格才不会被切碎。
        let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
        guard fields.count == 9 else {
            throw GitError.parseFailure(reason: "普通条目应有 9 个字段，实得 \(fields.count)", context: line)
        }

        let (indexStatus, workTreeStatus) = try parseStatusPair(fields[1], context: line)
        return StatusEntry(
            kind: .ordinary,
            path: String(fields[8]),
            indexStatus: indexStatus,
            workTreeStatus: workTreeStatus,
            submodule: parseSubmodule(fields[2])
        )
    }

    /// `2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>`
    private static func parseRenamed(_ line: String, originalPath: String) throws -> StatusEntry {
        let fields = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
        guard fields.count == 10 else {
            throw GitError.parseFailure(reason: "重命名条目应有 10 个字段，实得 \(fields.count)", context: line)
        }

        let (indexStatus, workTreeStatus) = try parseStatusPair(fields[1], context: line)

        // 形如 `R100` / `C75`：首字符区分重命名与复制，其余是相似度。
        let scoreField = fields[8]
        guard let marker = scoreField.first, let similarity = Int(scoreField.dropFirst()) else {
            throw GitError.parseFailure(reason: "无法解析相似度「\(scoreField)」", context: line)
        }

        return StatusEntry(
            kind: marker == "C" ? .copied : .renamed,
            path: String(fields[9]),
            originalPath: originalPath,
            indexStatus: indexStatus,
            workTreeStatus: workTreeStatus,
            similarity: similarity,
            submodule: parseSubmodule(fields[2])
        )
    }

    /// `u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>`
    private static func parseUnmerged(_ line: String) throws -> StatusEntry {
        let fields = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
        guard fields.count == 11 else {
            throw GitError.parseFailure(reason: "冲突条目应有 11 个字段，实得 \(fields.count)", context: line)
        }

        let (indexStatus, workTreeStatus) = try parseStatusPair(fields[1], context: line)
        return StatusEntry(
            kind: .unmerged,
            path: String(fields[10]),
            indexStatus: indexStatus,
            workTreeStatus: workTreeStatus,
            submodule: parseSubmodule(fields[2])
        )
    }

    /// `? <path>` 与 `! <path>`
    private static func parseUnversioned(_ line: String, kind: StatusEntry.Kind) throws -> StatusEntry {
        let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard fields.count == 2, !fields[1].isEmpty else {
            throw GitError.parseFailure(reason: "条目缺少路径", context: line)
        }
        return StatusEntry(kind: kind, path: String(fields[1]))
    }

    // MARK: - 字段

    /// 解析 `+1 -2` 形式的 ahead/behind。
    private static func parseAheadBehind(_ value: String) throws -> (ahead: Int, behind: Int) {
        let parts = value.split(separator: " ")
        guard parts.count == 2,
            parts[0].first == "+", parts[1].first == "-",
            let ahead = Int(parts[0].dropFirst()),
            let behind = Int(parts[1].dropFirst())
        else {
            throw GitError.parseFailure(reason: "无法解析 ahead/behind", context: value)
        }
        return (ahead, behind)
    }

    private static func parseStatusPair(
        _ field: Substring,
        context: String
    ) throws -> (index: FileStatus, workTree: FileStatus) {
        let characters = Array(field)
        guard characters.count == 2,
            let indexStatus = FileStatus(rawValue: characters[0]),
            let workTreeStatus = FileStatus(rawValue: characters[1])
        else {
            throw GitError.parseFailure(reason: "无法解析状态位「\(field)」", context: context)
        }
        return (indexStatus, workTreeStatus)
    }

    /// `N...` 表示这不是 submodule；`S<c><m><u>` 描述 submodule 的子状态。
    private static func parseSubmodule(_ field: Substring) -> SubmoduleState? {
        let characters = Array(field)
        guard characters.count == 4, characters[0] == "S" else { return nil }
        return SubmoduleState(
            commitChanged: characters[1] == "C",
            hasModifiedContent: characters[2] == "M",
            hasUntrackedContent: characters[3] == "U"
        )
    }
}
