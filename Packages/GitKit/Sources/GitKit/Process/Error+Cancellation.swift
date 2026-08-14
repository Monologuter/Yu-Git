import Foundation

extension Error {

    /// 这个错误是不是「取消」而不是真的失败。
    ///
    /// 放在 GitKit 里是因为取消正是从这儿抛出来的：``ProcessRunner`` 在进程
    /// 结束后调用 `Task.checkCancellation()`，任务被取消时抛 `CancellationError`。
    /// 谁抛的谁提供判断方式，调用方不必自己去猜错误的具体类型。
    ///
    /// 这个区分很要紧：SwiftUI 的 `.task(id:)` 在 id 变化时会取消上一个任务，
    /// 用户在提交列表里连点几下，前面几条的 git 命令都会被中断。
    /// 把这些当失败报出去，界面上会蹦出一串「操作失败 CancellationError()」，
    /// 而实际上什么都没坏。
    ///
    /// 三种来源都要认：
    /// - `CancellationError`：`Task.checkCancellation()` 抛的，最常见
    /// - `URLError.cancelled`：URLSession 请求被取消（AI 调用走这条）
    /// - `NSUserCancelledError` / `NSURLErrorCancelled`：Cocoa 的等价表示，
    ///   错误跨越框架边界被转成 `NSError` 后会是这个形态
    public var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }

        let nsError = self as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        return false
    }
}
