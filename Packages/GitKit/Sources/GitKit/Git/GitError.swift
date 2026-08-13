import Foundation

public enum GitError: Error, Sendable, Equatable {
    /// git 命令以非零状态退出。
    case commandFailed(arguments: [String], exitCode: Int32, standardError: String)
    /// 目标路径不在任何 git 仓库内。
    case notARepository(path: String)
    /// 在 PATH 与常见安装位置都没找到 git。
    case executableNotFound
    /// git 输出不符合预期格式。
    case parseFailure(reason: String, context: String)
}

extension GitError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .commandFailed(arguments, exitCode, standardError):
            let command = "git " + arguments.joined(separator: " ")
            let detail = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "命令失败（退出码 \(exitCode)）：\(command)"
                : "命令失败（退出码 \(exitCode)）：\(command)\n\(detail)"
        case let .notARepository(path):
            return "\(path) 不是 git 仓库"
        case .executableNotFound:
            return "找不到 git，请确认已安装 Xcode 命令行工具或 Homebrew 版 git"
        case let .parseFailure(reason, context):
            return "解析 git 输出失败：\(reason)\n原文：\(context)"
        }
    }
}
