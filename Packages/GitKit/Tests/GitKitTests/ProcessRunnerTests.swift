import Foundation
import Testing

@testable import GitKit

@Suite("ProcessRunner")
struct ProcessRunnerTests {

    private let runner = ProcessRunner()
    private let shell = URL(fileURLWithPath: "/bin/sh")

    // MARK: - 管道死锁（本文件存在的首要理由）

    /// 全项目最关键的一条回归测试。
    ///
    /// 子进程向 stdout 和 stderr 各写 512 KB，远超内核管道缓冲区（macOS 上约 64 KB）。
    /// 若实现是「先把 stdout 读完，再读 stderr」这种直觉写法，子进程会卡在写 stderr 上
    /// 不再产出 stdout，读取方于是永远等不到 stdout 的 EOF——双方互等，进程永不退出。
    /// git 在大仓库上轻易输出上百 KB，这是 Git GUI 的经典必踩坑。
    @Test("stdout 与 stderr 同时写满管道缓冲区时不死锁", .timeLimit(.minutes(1)))
    func doesNotDeadlockWhenBothPipesFill() async throws {
        let bytes = 512 * 1024
        let script = """
            head -c \(bytes) /dev/zero | tr '\\0' 'o' &
            head -c \(bytes) /dev/zero | tr '\\0' 'e' >&2
            wait
            """

        let result = try await runner.run(executable: shell, arguments: ["-c", script])

        #expect(result.standardOutput.count == bytes)
        #expect(result.standardError.count == bytes)
        #expect(result.standardOutput.allSatisfy { $0 == UInt8(ascii: "o") })
        #expect(result.standardError.allSatisfy { $0 == UInt8(ascii: "e") })
        #expect(result.isSuccess)
    }

    // MARK: - 基本行为

    @Test("捕获 stdout 与退出码 0")
    func capturesStandardOutput() async throws {
        let result = try await runner.run(executable: shell, arguments: ["-c", "printf '你好 驭Git'"])

        #expect(result.standardOutputText == "你好 驭Git")
        #expect(result.exitCode == 0)
        #expect(result.isSuccess)
    }

    @Test("stdout 与 stderr 分开捕获不混淆")
    func separatesStandardError() async throws {
        let result = try await runner.run(
            executable: shell,
            arguments: ["-c", "printf 'out'; printf 'err' >&2"]
        )

        #expect(result.standardOutputText == "out")
        #expect(result.standardErrorText == "err")
    }

    @Test("非零退出码原样返回而不抛错")
    func reportsNonZeroExitCode() async throws {
        // git 用退出码表达业务语义（如 diff --quiet 的 1 表示有改动），
        // 因此非零退出不是错误，必须原样交给调用方判断。
        let result = try await runner.run(executable: shell, arguments: ["-c", "exit 3"])

        #expect(result.exitCode == 3)
        #expect(!result.isSuccess)
        #expect(!result.wasTerminatedBySignal)
    }

    @Test("二进制输出不被字符串解码破坏")
    func preservesNonUTF8Output() async throws {
        let result = try await runner.run(executable: shell, arguments: ["-c", "printf '\\377\\376'"])

        #expect(result.standardOutput == Data([0xFF, 0xFE]))
    }

    // MARK: - 执行环境

    @Test("在指定工作目录中执行")
    func honoursWorkingDirectory() async throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()

        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/pwd"),
            arguments: ["-P"],
            workingDirectory: temp
        )

        // pwd -P 给出物理路径（/private/var/...），而 resolvingSymlinksInPath 会去掉
        // /private 前缀（/var/...）。两边走同一套规范化才具可比性。
        let reported = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(URL(fileURLWithPath: reported).resolvingSymlinksInPath().path == temp.path)
    }

    @Test("传入的环境变量对子进程可见")
    func passesEnvironment() async throws {
        let result = try await runner.run(
            executable: shell,
            arguments: ["-c", "printf '%s' \"$YUGIT_TEST\""],
            environment: ["YUGIT_TEST": "驭Git", "PATH": "/bin:/usr/bin"]
        )

        #expect(result.standardOutputText == "驭Git")
    }

    @Test("大输入经 stdin 写入不阻塞")
    func writesLargeStandardInput() async throws {
        // 反向的死锁场景：输入超过管道缓冲区时，必须边写边让子进程读。
        let input = Data(repeating: UInt8(ascii: "x"), count: 1_048_576)

        let result = try await runner.run(
            executable: URL(fileURLWithPath: "/bin/cat"),
            standardInput: input
        )

        #expect(result.standardOutput == input)
    }

    @Test("未提供 stdin 时子进程读到 EOF 而非挂起")
    func closesStandardInputByDefault() async throws {
        // git 在缺少凭据时会尝试读 stdin，若继承了终端就会永久挂起。
        let result = try await runner.run(executable: URL(fileURLWithPath: "/bin/cat"))

        #expect(result.standardOutput.isEmpty)
        #expect(result.isSuccess)
    }

    // MARK: - 超时与取消

    @Test("超时后终止进程并抛出 timedOut")
    func timesOutAndTerminates() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: ProcessRunnerError.self) {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["30"],
                timeout: .milliseconds(200)
            )
        }

        #expect(clock.now - start < .seconds(10), "应在超时后立即返回，而不是等子进程自然结束")
    }

    @Test("任务取消后立即终止子进程")
    func cancellationTerminatesProcess() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        let task = Task { [runner] in
            try await runner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(clock.now - start < .seconds(10), "取消应当立刻生效")
    }

    // MARK: - 启动失败

    @Test("可执行文件不存在时抛出 launchFailed")
    func reportsLaunchFailure() async throws {
        await #expect(throws: ProcessRunnerError.self) {
            _ = try await runner.run(executable: URL(fileURLWithPath: "/nonexistent/yugit-not-here"))
        }
    }

    /// 大量并发调用不能把线程池耗干。
    ///
    /// 早先每路管道读取都用 `DispatchQueue.global().async` 循环阻塞在
    /// `availableData` 上——一条 git 调用占两条线程，而全局队列的线程数有硬上限。
    /// 并发一多，新提交的 block 拿不到线程，里面的 `continuation.resume`
    /// 就永远不执行：**整个进程停在 0% CPU，没有超时也没有报错**。
    ///
    /// 这条测试并发发起远超线程上限的调用。挂死的话它会卡在时间限制上，
    /// 而不是失败得莫名其妙。
    @Test("并发上百个进程不会耗尽线程池而挂死", .timeLimit(.minutes(1)))
    func survivesHighConcurrency() async throws {
        let runner = ProcessRunner()
        let count = 120

        let results = await withTaskGroup(of: Int32?.self) { group in
            for index in 0..<count {
                group.addTask {
                    let result = try? await runner.run(
                        executable: URL(fileURLWithPath: "/bin/echo"),
                        arguments: ["第 \(index) 个"],
                        timeout: .seconds(30)
                    )
                    return result?.exitCode
                }
            }
            var collected: [Int32?] = []
            for await value in group { collected.append(value) }
            return collected
        }

        #expect(results.count == count)
        #expect(results.allSatisfy { $0 == 0 })
    }

    /// 同上，但每个子进程都往两路管道写不少内容——读取路径承压时更容易暴露问题。
    @Test("并发进程同时写满两路管道也不挂死", .timeLimit(.minutes(1)))
    func survivesConcurrentPipePressure() async throws {
        let runner = ProcessRunner()
        let script = """
            for i in $(seq 1 200); do
              echo "标准输出第 $i 行"
              echo "标准错误第 $i 行" >&2
            done
            """

        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<40 {
                group.addTask {
                    guard
                        let result = try? await runner.run(
                            executable: URL(fileURLWithPath: "/bin/sh"),
                            arguments: ["-c", script],
                            timeout: .seconds(30)
                        )
                    else { return false }
                    return result.exitCode == 0
                        && result.standardOutputText.contains("标准输出第 200 行")
                        && result.standardErrorText.contains("标准错误第 200 行")
                }
            }
            var collected: [Bool] = []
            for await value in group { collected.append(value) }
            return collected
        }

        #expect(results.count == 40)
        #expect(results.allSatisfy { $0 })
    }
}
