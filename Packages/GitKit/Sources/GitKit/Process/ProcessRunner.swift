import Foundation

public enum ProcessRunnerError: Error, Sendable {
    /// 可执行文件不存在、无执行权限，或工作目录无效。
    case launchFailed(path: String, reason: String)
    /// 超过给定时限仍未退出，进程已被终止。
    case timedOut(Duration)
}

extension ProcessRunnerError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .launchFailed(path, reason):
            "无法启动 \(path)：\(reason)"
        case let .timedOut(limit):
            "进程超过 \(limit) 未退出，已被强制终止"
        }
    }
}

/// 子进程执行器——全项目的地基。
///
/// 它存在的首要理由是**避免管道死锁**：子进程写入 stdout / stderr 的数据超过内核管道
/// 缓冲区（macOS 上约 64 KB）后，写操作会阻塞，直到有人把数据读走。若调用方「先读完
/// stdout 再读 stderr」，而子进程正卡在写 stderr 上，双方就会互等——stdout 永远等不到
/// EOF，进程永不退出。git 在大仓库上轻易输出上百 KB，这个坑必踩。
///
/// 因此这里的铁律是：**读 stdout、读 stderr、写 stdin 三件事必须并发进行**。
public struct ProcessRunner: Sendable {

    /// SIGTERM 之后留给进程收尾的时间，超出则补 SIGKILL。
    private static let killGracePeriod: Duration = .seconds(2)

    public init() {}

    /// 执行一个子进程并等待其结束。
    ///
    /// - Parameters:
    ///   - environment: 传 `nil` 表示继承当前进程环境。
    ///   - standardInput: 传 `nil` 时 stdin 接到 `/dev/null`——绝不能让子进程继承父进程的
    ///     stdin，否则 git 一旦尝试交互式读取（凭据、编辑器）就会永久挂起。
    ///   - timeout: 传 `nil` 表示不限时。超时会终止进程并抛出 ``ProcessRunnerError/timedOut(_:)``。
    ///   - onStandardErrorChunk: stderr 每来一段就回调一次，用于 fetch / push 的实时进度。
    ///     回调可能来自任意线程。
    /// - Note: 非零退出码不算错误。git 用退出码表达业务语义（如 `diff --quiet` 返回 1
    ///   表示「有改动」），判断权交给调用方。
    public func run(
        executable: URL,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        timeout: Duration? = nil,
        onStandardErrorChunk: (@Sendable (Data) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let inputPipe: Pipe? = standardInput == nil ? nil : Pipe()
        process.standardInput = inputPipe ?? FileHandle.nullDevice

        // terminationHandler 必须在 run() 之前挂上，否则进程可能在挂钩前就结束了。
        let exitWaiter = ExitWaiter()
        process.terminationHandler = { _ in exitWaiter.signal() }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(
                path: executable.path,
                reason: error.localizedDescription
            )
        }

        // FileHandle 不是 Sendable，这里用一次性包装把句柄交给独占它的后台线程。
        let outHandle = UncheckedSendable(outPipe.fileHandleForReading)
        let errHandle = UncheckedSendable(errPipe.fileHandleForReading)
        let inputHandle = inputPipe.map { UncheckedSendable($0.fileHandleForWriting) }

        let control = ProcessControl(process)

        // 超时看门狗：先 SIGTERM 给进程收尾的机会，宽限期后仍在就补 SIGKILL。
        let watchdog: Task<Void, Never>? = timeout.map { limit in
            Task {
                guard (try? await Task.sleep(for: limit)) != nil else { return }
                control.markTimedOut()
                control.terminate()
                guard (try? await Task.sleep(for: Self.killGracePeriod)) != nil else { return }
                control.kill()
            }
        }
        defer { watchdog?.cancel() }

        let (out, err) = await withTaskCancellationHandler {
            // async let 让两路读取立刻并发跑起来，谁也不等谁——这就是防死锁的关键。
            async let stdoutData = Self.readToEnd(outHandle)
            async let stderrData = Self.readToEnd(errHandle, onChunk: onStandardErrorChunk)

            // 写 stdin 同样不能等：输入超过管道缓冲区时，要边写边让子进程读。
            if let inputHandle, let standardInput {
                Self.writeAndClose(standardInput, to: inputHandle)
            }

            await exitWaiter.wait()
            return await (stdoutData, stderrData)
        } onCancel: {
            control.terminate()
        }

        watchdog?.cancel()

        if let timeout, control.didTimeOut {
            throw ProcessRunnerError.timedOut(timeout)
        }
        try Task.checkCancellation()

        return ProcessResult(
            exitCode: process.terminationStatus,
            wasTerminatedBySignal: process.terminationReason == .uncaughtSignal,
            standardOutput: out,
            standardError: err
        )
    }

    // MARK: - 管道读写

    /// 把句柄读到 EOF。
    ///
    /// **事件驱动，不占线程。** 早先的写法是 `DispatchQueue.global().async` 里
    /// 循环 `availableData`——那会让一整条线程阻塞在 `read()` 上，直到子进程退出。
    /// 一个 git 调用要占两条（stdout 与 stderr），而 libdispatch 全局队列的
    /// 线程数有硬上限（默认 64）。并发跑满之后，新提交的 block 再也拿不到线程，
    /// 里面的 `continuation.resume` 就永远不会执行——**整个进程停在 0% CPU 上，
    /// 没有超时、没有报错、什么都不动**。这在并行跑测试时反复出现过，
    /// 而 app 里同样会发生：刷新一次要并发发好几条 git 命令。
    ///
    /// `readabilityHandler` 走的是 dispatch source，只在真有数据时才短暂占用线程，
    /// 等待期间一条都不占。
    ///
    /// - Parameter onChunk: 每读到一段就回调一次，用于实时进度。git 的 fetch / push
    ///   把进度写在 stderr 并用 `\r` 原地刷新，等到 EOF 再读就只剩最后一行了。
    /// - Note: 已知边界——若子进程 fork 出的孙进程继承了管道写端并长期存活，
    ///   即使父进程已退出也读不到 EOF，此时只能靠 `timeout` 兜底。git 的常见子进程
    ///   （credential helper、hook）都是短命的。
    private static func readToEnd(
        _ handle: UncheckedSendable<FileHandle>,
        onChunk: (@Sendable (Data) -> Void)? = nil
    ) async -> Data {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            let buffer = DataBuffer()
            handle.value.readabilityHandler = { fileHandle in
                let chunk = fileHandle.availableData
                guard !chunk.isEmpty else {
                    // 空数据即 EOF。先摘掉 handler 再 resume——
                    // 不摘的话它还会被调用，而 continuation 只能 resume 一次。
                    fileHandle.readabilityHandler = nil
                    try? fileHandle.close()
                    continuation.resume(returning: buffer.take())
                    return
                }
                buffer.append(chunk)
                onChunk?(chunk)
            }
        }
    }

    /// 后台写入 stdin 并关闭写端——不关就等于不发 EOF，子进程会一直等输入。
    private static func writeAndClose(_ data: Data, to handle: UncheckedSendable<FileHandle>) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 子进程提前退出后继续写会触发 SIGPIPE，默认行为是杀掉**我们自己**。
            // 用 Darwin 的 per-fd 开关关掉它，写入改为返回 EPIPE 错误——
            // 比 signal(SIGPIPE, SIG_IGN) 干净，不影响宿主 App 的全局信号处理。
            var disableSIGPIPE: Int32 = 1
            _ = fcntl(handle.value.fileDescriptor, F_SETNOSIGPIPE, &disableSIGPIPE)

            // 子进程提前退出时写入失败属预期情况，忽略。
            try? handle.value.write(contentsOf: data)
            try? handle.value.close()
        }
    }
}

// MARK: - 并发辅助

/// 分段累积管道数据。
///
/// `readabilityHandler` 会被调用很多次，而每次都在 dispatch 的私有队列上——
/// 虽然对同一个句柄是串行的，Swift 6 的并发检查仍然要求跨边界共享的状态
/// 自己保证安全。加锁的代价可以忽略：一次 git 调用的回调次数是个位数到几十次。
private final class DataBuffer: @unchecked Sendable {

    private var storage = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(chunk)
    }

    func take() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// 把非 `Sendable` 的值送过并发边界。
///
/// 仅用于「交给唯一一个后台线程独占使用」的场景（如管道的一端），不做共享。
private struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// 把 `Process.terminationHandler` 这个回调式接口转成 `await`。
///
/// 必须处理「进程先退出、调用方后等待」的顺序：此时 `wait()` 要立即返回，不能空等。
private final class ExitWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasExited = false

    func signal() {
        lock.lock()
        if let pending = continuation {
            continuation = nil
            lock.unlock()
            pending.resume()
        } else {
            hasExited = true
            lock.unlock()
        }
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if hasExited {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }
}

/// 线程安全地持有 `Process`，供看门狗与取消回调终止进程。
private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var timedOut = false

    init(_ process: Process) {
        self.process = process
    }

    var didTimeOut: Bool {
        lock.withLock { timedOut }
    }

    func markTimedOut() {
        lock.withLock { timedOut = true }
    }

    func terminate() {
        lock.withLock {
            guard process.isRunning else { return }
            process.terminate()
        }
    }

    func kill() {
        lock.withLock {
            guard process.isRunning else { return }
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }
}
