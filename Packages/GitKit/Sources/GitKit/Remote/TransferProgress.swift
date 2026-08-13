import Foundation

/// fetch / push 的传输进度。
///
/// git 把进度写在 stderr 上，用 `\r` 原地刷新同一行，所以必须流式读取才能实时显示。
public struct TransferProgress: Sendable, Equatable {

    /// 传输阶段。git 的英文阶段名在这里翻成中文，界面直接用。
    public enum Phase: String, Sendable, Equatable, CaseIterable {
        case enumerating = "Enumerating objects"
        case counting = "Counting objects"
        case compressing = "Compressing objects"
        case writing = "Writing objects"
        case receiving = "Receiving objects"
        case resolving = "Resolving deltas"
        case checkingOut = "Updating files"

        public var chineseName: String {
            switch self {
            case .enumerating: "枚举对象"
            case .counting: "统计对象"
            case .compressing: "压缩对象"
            case .writing: "写入对象"
            case .receiving: "接收对象"
            case .resolving: "解析增量"
            case .checkingOut: "检出文件"
            }
        }
    }

    public let phase: Phase
    /// 百分比（0–100）。
    public let percentage: Int
    public let current: Int?
    public let total: Int?
    /// 这一阶段已经结束。
    public let isFinished: Bool

    public var description: String {
        if let current, let total {
            "\(phase.chineseName) \(percentage)%（\(current)/\(total)）"
        } else {
            "\(phase.chineseName) \(percentage)%"
        }
    }
}

/// 从 git 的 stderr 输出里解析传输进度。
///
/// 典型输出（`\r` 表示原地刷新）：
/// ```
/// Enumerating objects: 5, done.
/// Counting objects:  20% (1/5)\rCounting objects: 100% (5/5), done.
/// Writing objects:  33% (1/3)\rWriting objects: 100% (3/3), 285 bytes | 285.00 KiB/s, done.
/// remote: Resolving deltas: 100% (1/1), completed with 1 local object.
/// ```
public struct TransferProgressParser: Sendable {

    /// 累积尚未成行的片段。流式读取时一行可能被拆在两次回调里。
    private var buffer = ""

    public init() {}

    /// 喂入一段 stderr 数据，返回其中解析出的所有进度。
    public mutating func consume(_ data: Data) -> [TransferProgress] {
        buffer += String(decoding: data, as: UTF8.self)

        // git 用 \r 刷新同一行，\n 结束一行，两者都算分隔
        var segments = buffer.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).map(String.init)

        // 最后一段可能还没收全，留到下次；除非输入本身以分隔符结尾
        if let last = buffer.last, last != "\r" && last != "\n", !segments.isEmpty {
            buffer = segments.removeLast()
        } else {
            buffer = ""
        }

        return segments.compactMap(Self.parse)
    }

    /// 解析单行，如 `Writing objects:  33% (1/3)`。
    static func parse(_ line: String) -> TransferProgress? {
        // remote: 前缀表示这是服务端的进度，内容格式相同
        let content =
            line.hasPrefix("remote: ")
            ? String(line.dropFirst("remote: ".count))
            : line

        guard let colon = content.firstIndex(of: ":") else { return nil }
        let phaseName = String(content[content.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        guard let phase = TransferProgress.Phase(rawValue: phaseName) else { return nil }

        let rest = content[content.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let percentIndex = rest.firstIndex(of: "%"),
            let percentage = Int(rest[rest.startIndex..<percentIndex].trimmingCharacters(in: .whitespaces))
        else {
            // 没有百分比的形式，如 `Enumerating objects: 5, done.`
            return rest.contains("done")
                ? TransferProgress(
                    phase: phase, percentage: 100, current: nil, total: nil, isFinished: true)
                : nil
        }

        // 括号里的 (当前/总数)
        var current: Int?
        var total: Int?
        if let open = rest.firstIndex(of: "("), let close = rest[open...].firstIndex(of: ")") {
            let pair = rest[rest.index(after: open)..<close].split(separator: "/")
            if pair.count == 2 {
                current = Int(pair[0])
                total = Int(pair[1])
            }
        }

        return TransferProgress(
            phase: phase,
            percentage: percentage,
            current: current,
            total: total,
            isFinished: rest.contains("done")
        )
    }
}
