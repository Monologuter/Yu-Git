import Foundation
import Testing

@testable import GitKit

@Suite("取消不是失败")
struct CancellationTests {

    @Test("认得出标准的 CancellationError")
    func recognizesCancellationError() {
        #expect(CancellationError().isCancellation)
    }

    @Test("认得出被取消的 URLSession 请求")
    func recognizesCancelledURLError() {
        #expect(URLError(.cancelled).isCancellation)
        #expect(!URLError(.timedOut).isCancellation)
    }

    @Test("认得出跨框架边界后的 NSError 形态")
    func recognizesBridgedNSError() {
        // 错误在框架之间传递时会被转成 NSError，类型判断就失效了，
        // 只剩 domain + code 可认
        #expect(
            (NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled) as Error)
                .isCancellation)
        #expect(
            (NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError) as Error)
                .isCancellation)
    }

    @Test("真正的失败不会被误判成取消")
    func doesNotSwallowRealFailures() {
        // 这条最要紧：判反了会让真实错误静默消失，用户点了没反应也不知道为什么
        let gitError = GitError.commandFailed(
            arguments: ["status"], exitCode: 128, standardError: "not a git repository")
        #expect(!gitError.isCancellation)
        #expect(!URLError(.notConnectedToInternet).isCancellation)
        #expect(!(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut) as Error).isCancellation)
        // 碰巧同号但不同 domain 的错误不能算取消
        #expect(
            !(NSError(domain: "com.example.custom", code: NSUserCancelledError) as Error)
                .isCancellation)
    }

    @Test("被取消的任务里跑 git，抛的是取消而不是命令失败")
    func cancelledGitCommandThrowsCancellation() async throws {
        let sandbox = try await TemporaryRepository()
        try sandbox.write("内容\n", to: "a.txt")
        try await sandbox.commitAll("base")

        let task = Task {
            // 先让出一次，给下面的 cancel() 机会在命令跑起来后生效
            await Task.yield()
            return try await sandbox.client.run(["log", "--oneline"], in: sandbox.url)
        }
        task.cancel()

        do {
            _ = try await task.value
            // 命令太快跑完也可能不抛，那不算失败
        } catch {
            #expect(error.isCancellation, "被取消时应抛取消，实际是 \(error)")
        }
    }
}
