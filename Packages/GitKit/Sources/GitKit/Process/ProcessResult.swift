import Foundation

/// 一次子进程执行的完整结果。
///
/// stdout / stderr 保留为 `Data` 而不是 `String`：git 会输出任意二进制内容
/// （`git cat-file` 取二进制文件、`git diff` 里的非 UTF-8 片段），
/// 在这一层强转字符串会丢数据。文本化交给调用方按需进行。
public struct ProcessResult: Sendable {
    /// 正常退出时的 exit status；被信号终止时为信号编号（配合 `wasTerminatedBySignal` 判断）。
    public let exitCode: Int32

    /// 进程是否因收到信号而终止，而非自行退出。
    public let wasTerminatedBySignal: Bool

    public let standardOutput: Data
    public let standardError: Data

    public var isSuccess: Bool { exitCode == 0 && !wasTerminatedBySignal }

    /// 按 UTF-8 解码 stdout，非法字节替换为 U+FFFD 而非返回 nil。
    public var standardOutputText: String { String(decoding: standardOutput, as: UTF8.self) }

    /// 按 UTF-8 解码 stderr，非法字节替换为 U+FFFD 而非返回 nil。
    public var standardErrorText: String { String(decoding: standardError, as: UTF8.self) }

    public init(exitCode: Int32, wasTerminatedBySignal: Bool, standardOutput: Data, standardError: Data) {
        self.exitCode = exitCode
        self.wasTerminatedBySignal = wasTerminatedBySignal
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
