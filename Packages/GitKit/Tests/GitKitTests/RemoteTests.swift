import Foundation
import Testing

@testable import GitKit

@Suite("远程操作")
struct RemoteTests {

    /// 建一对「远程 + 克隆」的仓库。远程用 bare，才能接受推送。
    private func makePair() async throws -> (origin: URL, work: URL, client: GitClient, cleanup: () -> Void) {
        let seed = try await TemporaryRepository()
        try seed.write("初始\n", to: "a.txt")
        try await seed.commitAll("base")

        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let originPath = base.appendingPathComponent("yugit-origin-\(UUID().uuidString).git")
        let workPath = base.appendingPathComponent("yugit-work-\(UUID().uuidString)")

        try await seed.client.run(
            ["clone", "--quiet", "--bare", seed.url.path, originPath.path], in: base)
        try await seed.client.run(["clone", "--quiet", originPath.path, workPath.path], in: base)
        try await seed.client.run(["config", "user.email", "t@yugit.local"], in: workPath)
        try await seed.client.run(["config", "user.name", "测试"], in: workPath)

        let client = seed.client
        return (
            originPath, workPath, client,
            {
                try? FileManager.default.removeItem(at: originPath)
                try? FileManager.default.removeItem(at: workPath)
                // seed 由自身的 deinit 清理，这里持有它到闭包结束
                _ = seed
            }
        )
    }

    @Test("列出远程仓库")
    func listsRemotes() async throws {
        let pair = try await makePair()
        defer { pair.cleanup() }

        let remotes = try await pair.client.remotes(in: pair.work)
        let origin = try #require(remotes.first { $0.name == "origin" })

        #expect(remotes.count == 1)
        #expect(origin.fetchURL.contains("yugit-origin"))
        #expect(!origin.usesSSH, "本地路径不是 SSH")
    }

    @Test("推送本地提交并报告进度")
    func pushesWithProgress() async throws {
        let pair = try await makePair()
        defer { pair.cleanup() }

        try "新内容\n".write(
            to: pair.work.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try await pair.client.run(["commit", "--quiet", "--all", "--message", "本地改动"], in: pair.work)

        let collector = ProgressCollector()
        try await pair.client.push(in: pair.work, onProgress: { collector.append($0) })

        // 远程应当收到这条提交
        let remoteLog = try await pair.client.log(in: pair.origin)
        #expect(remoteLog.first?.subject == "本地改动")

        // 本地路径的推送很快，进度可能一条都没有，但解析器不该崩
        let progresses = collector.all()
        for progress in progresses {
            #expect((0...100).contains(progress.percentage))
        }
    }

    @Test("fetch 后能看到远程的新提交")
    func fetchesRemoteChanges() async throws {
        let pair = try await makePair()
        defer { pair.cleanup() }

        // 另建一个克隆，从它推一条提交上去，模拟别人的改动
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let otherPath = base.appendingPathComponent("yugit-other-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: otherPath) }
        try await pair.client.run(["clone", "--quiet", pair.origin.path, otherPath.path], in: base)
        try await pair.client.run(["config", "user.email", "o@yugit.local"], in: otherPath)
        try await pair.client.run(["config", "user.name", "别人"], in: otherPath)
        try "别人的改动\n".write(
            to: otherPath.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try await pair.client.run(["add", "--all"], in: otherPath)
        try await pair.client.run(["commit", "--quiet", "--message", "别人的提交"], in: otherPath)
        try await pair.client.push(in: otherPath)

        try await pair.client.fetch(in: pair.work)

        let branches = try await pair.client.branches(in: pair.work)
        let main = try #require(branches.first { $0.name == "main" && !$0.isRemote })
        #expect(main.tracking.behind == 1, "fetch 之后应当能看出落后一条")
    }

    @Test("pull 把远程改动合并进工作区")
    func pullsRemoteChanges() async throws {
        let pair = try await makePair()
        defer { pair.cleanup() }

        let base = URL(fileURLWithPath: NSTemporaryDirectory())
        let otherPath = base.appendingPathComponent("yugit-other-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: otherPath) }
        try await pair.client.run(["clone", "--quiet", pair.origin.path, otherPath.path], in: base)
        try await pair.client.run(["config", "user.email", "o@yugit.local"], in: otherPath)
        try await pair.client.run(["config", "user.name", "别人"], in: otherPath)
        try "别人的文件\n".write(
            to: otherPath.appendingPathComponent("新文件.txt"), atomically: true, encoding: .utf8)
        try await pair.client.run(["add", "--all"], in: otherPath)
        try await pair.client.run(["commit", "--quiet", "--message", "别人加的文件"], in: otherPath)
        try await pair.client.push(in: otherPath)

        try await pair.client.pull(in: pair.work)

        let exists = FileManager.default.fileExists(
            atPath: pair.work.appendingPathComponent("新文件.txt").path)
        #expect(exists, "pull 之后文件应当出现在工作区")
    }

    @Test("推送到不存在的远程时给出中文提示而不是挂起", .timeLimit(.minutes(1)))
    func reportsFailureInChinese() async throws {
        let repository = try await TemporaryRepository()
        try repository.write("a\n", to: "a.txt")
        try await repository.commitAll("base")
        try await repository.git("remote", "add", "origin", "/根本不存在的路径/repo.git")

        do {
            try await repository.client.push(in: repository.url, remote: "origin", branch: "main")
            Issue.record("推送到不存在的远程应当失败")
        } catch let failure as RemoteFailure {
            #expect(!failure.message.isEmpty)
            #expect(!failure.suggestion.isEmpty)
            #expect(!failure.rawOutput.isEmpty, "原始输出要保留，供展开详情")
        }
    }
}

/// 收集进度回调。回调来自后台线程，用锁保护。
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TransferProgress] = []

    func append(_ progress: TransferProgress) {
        lock.withLock { items.append(progress) }
    }

    func all() -> [TransferProgress] {
        lock.withLock { items }
    }
}

@Suite("传输进度解析")
struct TransferProgressParsingTests {

    @Test("解析带百分比与计数的进度行")
    func parsesProgressLine() throws {
        let progress = try #require(TransferProgressParser.parse("Writing objects:  33% (1/3)"))

        #expect(progress.phase == .writing)
        #expect(progress.phase.chineseName == "写入对象")
        #expect(progress.percentage == 33)
        #expect(progress.current == 1)
        #expect(progress.total == 3)
        #expect(!progress.isFinished)
        #expect(progress.description == "写入对象 33%（1/3）")
    }

    @Test("识别阶段完成")
    func detectsCompletion() throws {
        let progress = try #require(
            TransferProgressParser.parse("Writing objects: 100% (3/3), 285 bytes | 285.00 KiB/s, done."))

        #expect(progress.percentage == 100)
        #expect(progress.isFinished)
    }

    @Test("remote: 前缀的服务端进度同样解析")
    func parsesRemotePrefixedLine() throws {
        let progress = try #require(
            TransferProgressParser.parse("remote: Resolving deltas: 100% (1/1), completed with 1 local object."))

        #expect(progress.phase == .resolving)
        #expect(progress.phase.chineseName == "解析增量")
        #expect(progress.percentage == 100)
    }

    @Test("无关的行被忽略")
    func ignoresUnrelatedLines() {
        #expect(TransferProgressParser.parse("To https://github.com/user/repo.git") == nil)
        #expect(TransferProgressParser.parse("   abc1234..def5678  main -> main") == nil)
        #expect(TransferProgressParser.parse("") == nil)
    }

    @Test("被拆成两半的行能拼回来")
    func reassemblesSplitLines() {
        // 流式读取时一行可能横跨两次回调
        var parser = TransferProgressParser()

        let first = parser.consume(Data("Writing objects:  50".utf8))
        #expect(first.isEmpty, "半行还不能解析")

        let second = parser.consume(Data("% (2/4)\r".utf8))
        #expect(second.count == 1)
        #expect(second[0].percentage == 50)
        #expect(second[0].current == 2)
    }

    @Test("一次喂入多行时全部解析")
    func parsesMultipleLines() {
        var parser = TransferProgressParser()
        let output = """
            Enumerating objects: 5, done.
            Counting objects: 100% (5/5), done.
            Compressing objects:  50% (1/2)\r
            """

        let results = parser.consume(Data(output.utf8))

        #expect(results.count >= 2)
        #expect(results.contains { $0.phase == .counting && $0.percentage == 100 })
    }
}

@Suite("远程失败诊断")
struct RemoteFailureTests {

    @Test("识别需要凭据但无法交互")
    func detectsCredentialsRequired() {
        let failure = RemoteFailure.diagnose(
            standardError: "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
            arguments: ["push"]
        )

        #expect(failure.reason == .credentialsRequired)
        #expect(failure.suggestion.contains("钥匙串"))
    }

    @Test("识别认证失败并提示用 token")
    func detectsAuthenticationFailure() {
        let failure = RemoteFailure.diagnose(
            standardError:
                "remote: Invalid username or password.\nfatal: Authentication failed for 'https://github.com/u/r.git/'",
            arguments: ["push"]
        )

        #expect(failure.reason == .authenticationFailed)
        #expect(failure.suggestion.contains("token"), "平台早已不收账号密码，提示必须点明这一点")
    }

    @Test("识别 SSH 公钥被拒")
    func detectsSSHRejection() {
        let failure = RemoteFailure.diagnose(
            standardError:
                "git@github.com: Permission denied (publickey).\nfatal: Could not read from remote repository.",
            arguments: ["fetch"]
        )

        #expect(failure.reason == .sshKeyRejected)
        #expect(failure.suggestion.contains("ssh-add"))
    }

    @Test("识别推送被拒并明确警告不要 force")
    func detectsNonFastForward() {
        let failure = RemoteFailure.diagnose(
            standardError: "! [rejected] main -> main (non-fast-forward)\nerror: failed to push some refs",
            arguments: ["push"]
        )

        #expect(failure.reason == .nonFastForward)
        #expect(failure.suggestion.contains("不要直接用 force"), "这是会覆盖他人提交的操作，必须警告")
    }

    @Test("识别网络不通")
    func detectsNetworkFailure() {
        let failure = RemoteFailure.diagnose(
            standardError: "ssh: Could not resolve hostname github.com: nodename nor servname provided",
            arguments: ["fetch"]
        )

        #expect(failure.reason == .networkUnreachable)
    }

    @Test("未识别的错误保留原始输出与等价命令")
    func fallsBackGracefully() {
        let failure = RemoteFailure.diagnose(
            standardError: "fatal: 某种从未见过的错误",
            arguments: ["push", "origin", "main"]
        )

        #expect(failure.reason == .other)
        #expect(failure.rawOutput.contains("从未见过"))
        #expect(failure.suggestion.contains("git push origin main"))
    }
}
