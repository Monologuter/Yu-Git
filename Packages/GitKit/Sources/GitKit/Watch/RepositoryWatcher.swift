import CoreServices
import Foundation

/// 监听仓库目录的文件变化，外部改动能在半秒内反映到界面上。
///
/// PRD 第 5 节把这条列为硬指标：Sourcetree 被弃用的头号原因就是「在终端改了文件，
/// GUI 半天没反应」。终端里的 git、编辑器的保存、AI agent 写的代码，都要能立刻看到。
///
/// 两个必须处理的细节（见实现计划的风险清单）：
/// - **防抖**：一次 `git checkout` 会产生成百上千个事件，逐个刷新会把界面拖垮
/// - **可挂起**：驭Git 自己执行 git 命令时也会触发事件，那属于自己刷自己
public final class RepositoryWatcher: @unchecked Sendable {

    /// 事件合并窗口。太短会在批量操作时刷新过频，太长则违反 500ms 的响应指标。
    public static let defaultDebounce = Duration.milliseconds(300)

    private let root: URL
    private let debounce: Duration
    private let handler: @Sendable () -> Void

    /// FSEvents 自身的合并延迟。与防抖叠加后仍要留在 500ms 预算内。
    private let latency: CFTimeInterval = 0.05

    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var pendingNotification: Task<Void, Never>?
    private var suspensionDepth = 0

    private let queue = DispatchQueue(label: "com.chenya.yugit.repository-watcher")

    /// - Parameter onChange: 在防抖窗口结束后调用，可能来自任意线程。
    public init(
        root: URL,
        debounce: Duration = RepositoryWatcher.defaultDebounce,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.root = root
        self.debounce = debounce
        self.handler = onChange
    }

    deinit {
        stopStream()
    }

    // MARK: - 生命周期

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags =
            UInt32(kFSEventStreamCreateFlagUseCFTypes)
            | UInt32(kFSEventStreamCreateFlagFileEvents)
            // NoDefer：第一个事件立即送达，后续才走合并窗口。
            // 用户改一个文件就该马上看到，而不是等满一个 latency。
            | UInt32(kFSEventStreamCreateFlagNoDefer)

        guard
            let created = FSEventStreamCreate(
                kCFAllocatorDefault,
                eventCallback,
                &context,
                [root.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                flags
            )
        else {
            return
        }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    public func stop() {
        stopStream()
    }

    private func stopStream() {
        lock.lock()
        let current = stream
        stream = nil
        pendingNotification?.cancel()
        pendingNotification = nil
        lock.unlock()

        guard let current else { return }
        FSEventStreamStop(current)
        FSEventStreamInvalidate(current)
        FSEventStreamRelease(current)
    }

    // MARK: - 挂起

    /// 在驭Git 自己执行 git 命令期间挂起，避免自己触发自己。
    ///
    /// 支持嵌套：挂起次数与恢复次数配对即可。
    public func suspend() {
        lock.withLock { suspensionDepth += 1 }
    }

    public func resume() {
        lock.withLock { suspensionDepth = max(0, suspensionDepth - 1) }
    }

    /// 在挂起状态下执行一段工作，结束后自动恢复。
    public func whileSuspended<T>(_ work: () async throws -> T) async rethrows -> T {
        suspend()
        defer { resume() }
        return try await work()
    }

    // MARK: - 事件

    fileprivate func handleEvents(paths: [String]) {
        guard paths.contains(where: Self.isRelevant) else { return }

        let interval = debounce
        let callback = handler

        lock.withLock {
            guard suspensionDepth == 0 else { return }

            // 防抖：窗口内又来了事件就重新计时，只在安静下来之后通知一次
            pendingNotification?.cancel()
            pendingNotification = Task { [weak self] in
                guard (try? await Task.sleep(for: interval)) != nil else { return }
                // 等待期间可能刚好进入挂起状态，再确认一次
                guard let self, !self.isSuspended else { return }
                callback()
            }
        }
    }

    private var isSuspended: Bool {
        lock.withLock { suspensionDepth > 0 }
    }

    /// 过滤掉与仓库状态无关的高频路径。
    ///
    /// `git gc`、`git fetch` 会在 objects 目录里产生海量事件，而它们不改变工作区状态；
    /// 反过来 `.git/index`、`.git/HEAD`、`.git/refs` 的变化必须响应——那是别的 git
    /// 进程在改动仓库。
    static func isRelevant(_ path: String) -> Bool {
        guard let gitRange = path.range(of: "/.git/") else {
            // 工作区里的普通文件
            return true
        }

        let insideGit = path[gitRange.upperBound...]
        let ignoredPrefixes = [
            "objects/",  // 对象写入，量大且不改变可见状态
            "logs/",  // reflog
            "lfs/",
            "modules/",
            "yugit/",  // 我们自己的操作日志，写它反而会引发回环
        ]
        if ignoredPrefixes.contains(where: { insideGit.hasPrefix($0) }) {
            return false
        }

        // 锁文件本身没有意义，真正的变化会在锁释放后由目标文件的事件带出来
        return !insideGit.hasSuffix(".lock")
    }
}

/// FSEvents 的 C 回调。通过 context 里的裸指针拿回 watcher 实例。
private let eventCallback: FSEventStreamCallback = { _, contextInfo, eventCount, eventPaths, _, _ in
    guard let contextInfo else { return }
    let watcher = Unmanaged<RepositoryWatcher>.fromOpaque(contextInfo).takeUnretainedValue()

    // 建流时指定了 kFSEventStreamCreateFlagUseCFTypes，路径是 CFArray of CFString
    guard let paths = unsafeBitCast(eventPaths, to: CFArray.self) as? [String] else { return }
    _ = eventCount
    watcher.handleEvents(paths: paths)
}
