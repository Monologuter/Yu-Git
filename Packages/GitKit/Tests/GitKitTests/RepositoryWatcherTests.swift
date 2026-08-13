import Foundation
import Testing

@testable import GitKit

@Suite("仓库监听")
struct RepositoryWatcherTests {

    /// 记录回调次数，并支持等到「至少 n 次」为止。
    private actor ChangeRecorder {
        private(set) var count = 0
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func record() {
            count += 1
            let waiting = continuations
            continuations = []
            waiting.forEach { $0.resume() }
        }

        /// 等到收到通知或超时。返回是否收到。
        func waitForChange(timeout: Duration) async -> Bool {
            let before = count
            let waiter = Task {
                await withCheckedContinuation { continuation in
                    continuations.append(continuation)
                }
            }
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                waiter.cancel()
            }
            _ = await waiter.result
            timeoutTask.cancel()
            return count > before
        }
    }

    @Test("工作区文件变化会触发通知", .timeLimit(.minutes(1)))
    func notifiesOnWorkTreeChange() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("原始\n", to: "f.txt")
        try await repository.commitAll("base")

        let recorder = ChangeRecorder()
        let watcher = RepositoryWatcher(root: repository.url, debounce: .milliseconds(100)) {
            Task { await recorder.record() }
        }
        watcher.start()
        defer { watcher.stop() }

        // FSEvents 建流需要一点时间才开始送事件
        try await Task.sleep(for: .milliseconds(300))
        try repository.write("被外部改动了\n", to: "f.txt")

        let notified = await recorder.waitForChange(timeout: .seconds(5))
        #expect(notified, "外部改动必须能被感知到")
    }

    @Test("批量改动被合并成一次通知", .timeLimit(.minutes(1)))
    func debouncesBurstOfChanges() async throws {
        // git checkout 会一次性改动成百上千个文件，逐个刷新会把界面拖垮。
        let repository = try await TemporaryRepository()
        try repository.write("seed\n", to: "seed.txt")
        try await repository.commitAll("base")

        let recorder = ChangeRecorder()
        let watcher = RepositoryWatcher(root: repository.url, debounce: .milliseconds(300)) {
            Task { await recorder.record() }
        }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(300))
        for index in 0..<50 {
            try repository.write("内容 \(index)\n", to: "批量\(index).txt")
        }

        _ = await recorder.waitForChange(timeout: .seconds(5))
        // 等防抖窗口彻底过去，确认没有后续的重复通知
        try await Task.sleep(for: .milliseconds(800))

        let count = await recorder.count
        #expect(count >= 1, "改动必须被感知")
        #expect(count <= 3, "50 个文件的批量改动不该产生 \(count) 次刷新")
    }

    @Test("挂起期间不通知，恢复后继续工作", .timeLimit(.minutes(1)))
    func staysQuietWhileSuspended() async throws {
        // 驭Git 自己执行 git 命令时也会触发事件，那属于自己刷自己。
        let repository = try await TemporaryRepository()
        try repository.write("seed\n", to: "seed.txt")
        try await repository.commitAll("base")

        let recorder = ChangeRecorder()
        let watcher = RepositoryWatcher(root: repository.url, debounce: .milliseconds(100)) {
            Task { await recorder.record() }
        }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))

        watcher.suspend()
        try repository.write("挂起期间的改动\n", to: "suspended.txt")
        try await Task.sleep(for: .milliseconds(600))
        let duringSuspension = await recorder.count
        #expect(duringSuspension == 0, "挂起期间不该有通知")

        watcher.resume()
        try repository.write("恢复之后的改动\n", to: "resumed.txt")
        let notified = await recorder.waitForChange(timeout: .seconds(5))
        #expect(notified, "恢复后应当继续工作")
    }

    // MARK: - 路径过滤

    @Test("忽略 git 内部的高频无关路径")
    func filtersIrrelevantPaths() {
        let base = "/repo"

        #expect(RepositoryWatcher.isRelevant("\(base)/src/main.swift"))
        #expect(RepositoryWatcher.isRelevant("\(base)/中 文.txt"))

        // 这些变化说明别的 git 进程正在改动仓库，必须响应
        #expect(RepositoryWatcher.isRelevant("\(base)/.git/index"))
        #expect(RepositoryWatcher.isRelevant("\(base)/.git/HEAD"))
        #expect(RepositoryWatcher.isRelevant("\(base)/.git/refs/heads/main"))

        // git gc / fetch 会在这些目录里产生海量事件，却不改变可见状态
        #expect(!RepositoryWatcher.isRelevant("\(base)/.git/objects/ab/cdef"))
        #expect(!RepositoryWatcher.isRelevant("\(base)/.git/logs/HEAD"))
        #expect(!RepositoryWatcher.isRelevant("\(base)/.git/index.lock"))

        // 我们自己的操作日志：监听它会造成写日志→触发刷新→再写日志的回环
        #expect(!RepositoryWatcher.isRelevant("\(base)/.git/yugit/operations.jsonl"))
    }

    @Test("终端里执行 git 命令能被感知", .timeLimit(.minutes(1)))
    func detectsExternalGitCommands() async throws {
        // 这是 PRD 里点名的场景：用户在终端 checkout 分支，GUI 必须跟上。
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")

        let recorder = ChangeRecorder()
        let watcher = RepositoryWatcher(root: repository.url, debounce: .milliseconds(100)) {
            Task { await recorder.record() }
        }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))

        try await repository.git("checkout", "--quiet", "-b", "新分支")

        let notified = await recorder.waitForChange(timeout: .seconds(5))
        #expect(notified, "外部 git 操作必须能被感知")
    }
}
