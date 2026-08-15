import Foundation
import Testing

@testable import GitKit

@Suite("提交签名")
struct SigningTests {

    private func actor(for repo: TemporaryRepository) async throws -> RepoActor {
        try await RepoActor(root: repo.url, client: repo.client, operationLog: InMemoryOperationLog())
    }

    // MARK: - 状态解读

    /// 没有签名的提交是 `N`，绝大多数提交都是这个。
    @Test("普通提交读出来是未签名")
    func readsUnsignedCommits() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("没签名的提交")

        let signature = try await repo.client.signature(of: "HEAD", in: repo.url)

        #expect(signature.status == .none)
        #expect(!signature.status.isVerified)
        #expect(!signature.status.needsAttention)
    }

    @Test("认不出的提交返回未签名而不是崩")
    func handlesMissingCommits() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("x\n", to: "f.txt")
        try await repo.commitAll("base")

        let signature = try await repo.client.signature(
            of: "0000000000000000000000000000000000000000", in: repo.url)
        #expect(signature == .unsigned)
    }

    /// 「签名有效但 key 未标记可信」极其常见——对方确实签了、也对得上，
    /// 只是你没把他的 key 加进信任列表。把它跟「签名是坏的」混为一谈，
    /// 这个功能就成了噪音。
    @Test("只有 G 算验证通过，U 不算问题")
    func onlyGoodCountsAsVerified() {
        #expect(SignatureStatus.good.isVerified)
        #expect(!SignatureStatus.unknownTrust.isVerified)
        #expect(!SignatureStatus.unknownTrust.needsAttention)
        #expect(!SignatureStatus.cannotCheck.needsAttention)
    }

    /// 「没有签名」不该报警：绝大多数仓库的绝大多数提交都没签名，
    /// 给每一条都挂个警告等于没有警告。
    @Test("未签名不报警，坏签名与吊销报警")
    func flagsOnlyRealProblems() {
        #expect(!SignatureStatus.none.needsAttention)
        #expect(SignatureStatus.bad.needsAttention)
        #expect(SignatureStatus.revokedKey.needsAttention)
        #expect(SignatureStatus.expiredKey.needsAttention)
    }

    @Test("每种状态都有中文说法和解释")
    func everyStatusIsExplained() {
        for status in SignatureStatus.allCases {
            #expect(!status.displayName.isEmpty)
            #expect(!status.explanation.isEmpty)
        }
    }

    // MARK: - 配置

    @Test("没配过时读出的是关闭状态")
    func readsDefaultSettings() async throws {
        let repo = try await TemporaryRepository()

        let settings = await repo.client.signingSettings(in: repo.url)

        #expect(!settings.signsCommits)
        #expect(settings.signingKey.isEmpty)
        // 没设 gpg.format 时 git 用 openpgp
        #expect(settings.format == .openpgp)
    }

    @Test("写进去的配置读得回来")
    func roundTripsSettings() async throws {
        let repo = try await TemporaryRepository()
        let repoActor = try await actor(for: repo)

        try await repoActor.perform(.setConfiguration(key: "commit.gpgsign", value: "true"))
        try await repoActor.perform(.setConfiguration(key: "gpg.format", value: "ssh"))
        try await repoActor.perform(
            .setConfiguration(key: "user.signingkey", value: "~/.ssh/id_ed25519.pub"))

        let settings = await repo.client.signingSettings(in: repo.url)
        #expect(settings.signsCommits)
        #expect(settings.format == .ssh)
        #expect(settings.signingKey == "~/.ssh/id_ed25519.pub")
        #expect(settings.blocker(hasGPG: false) == nil)
    }

    /// 空值要 `--unset` 而不是写一个空字符串：空字符串和「没设置」在 git 里
    /// 是两回事，前者会让 `gpg.format=` 成为一个无效值而不是回落到默认。
    @Test("清空一项配置是删掉它，不是写空字符串")
    func clearingUnsets() async throws {
        let repo = try await TemporaryRepository()
        let repoActor = try await actor(for: repo)
        try await repoActor.perform(.setConfiguration(key: "gpg.format", value: "ssh"))

        try await repoActor.perform(.setConfiguration(key: "gpg.format", value: ""))

        let result = try await repo.client.runReturningResult(
            ["config", "--get", "gpg.format"], in: repo.url)
        // 读不到才对：读到空字符串说明写成了 `gpg.format=`
        #expect(!result.isSuccess)
        #expect(await repo.client.signingSettings(in: repo.url).format == .openpgp)
    }

    /// **开了签名却缺东西，每一次提交都会失败。** 界面必须在打开开关之前
    /// 就拦住，否则用户只会看到「提交失败」，而原因是他刚在另一个页面做的事。
    @Test("开了签名却没有 key 时判定为不可用")
    func detectsMissingKey() {
        let broken = SigningSettings(signsCommits: true, format: .ssh, signingKey: "")
        #expect(broken.blocker(hasGPG: true) == .missingKey)

        let workable = SigningSettings(signsCommits: true, format: .ssh, signingKey: "key")
        #expect(workable.blocker(hasGPG: false) == nil)

        // 关着的时候缺什么都无所谓
        let off = SigningSettings(signsCommits: false, format: .openpgp, signingKey: "")
        #expect(off.blocker(hasGPG: false) == nil)
    }

    /// 第二种失败方式，容易漏：key 配得好好的，签名照样失败，
    /// 因为选的是 GPG 格式而本机根本没有 gpg 可跑。
    @Test("选了 GPG 格式但本机没装 gpg，同样判定为不可用")
    func detectsMissingGPG() {
        let settings = SigningSettings(signsCommits: true, format: .openpgp, signingKey: "ABC123")

        #expect(settings.blocker(hasGPG: false) == .gpgNotInstalled)
        #expect(settings.blocker(hasGPG: true) == nil)

        // SSH 签名不需要 gpg
        let ssh = SigningSettings(signsCommits: true, format: .ssh, signingKey: "ABC123")
        #expect(ssh.blocker(hasGPG: false) == nil)
    }

    @Test("每种阻碍都说清了怎么解决")
    func everyBlockerHasASuggestion() {
        for blocker in [SigningSettings.Blocker.missingKey, .gpgNotInstalled] {
            #expect(!blocker.displayName.isEmpty)
            #expect(!blocker.suggestion.isEmpty)
        }
    }

    /// 这条锁的是那个真实后果：配置一半就提交，git 直接失败。
    ///
    /// 不断言具体措辞——报错取决于缺的是 key 还是 gpg，两种说法完全不同
    /// （`cannot run gpg` vs `either user.signingkey ... needs to be configured`），
    /// 而且都会随 git 版本变。要锁的是「提交失败了，且跟签名有关」。
    @Test("签名配置不全时提交确实会失败")
    func brokenConfigurationBreaksCommits() async throws {
        let repo = try await TemporaryRepository()
        try await repo.git("config", "commit.gpgsign", "true")
        try repo.write("x\n", to: "f.txt")
        try await repo.git("add", "--all")

        let result = try await repo.client.runReturningResult(
            ["commit", "--message", "该失败"], in: repo.url)

        #expect(!result.isSuccess)
        let stderr = result.standardErrorText.lowercased()
        #expect(stderr.contains("sign") || stderr.contains("gpg"))
    }

    @Test("每种签名格式都说清了要什么")
    func everyFormatStatesItsRequirement() {
        for format in SigningSettings.Format.allCases {
            #expect(!format.displayName.isEmpty)
            #expect(!format.requirement.isEmpty)
        }
    }

    // MARK: - 补签

    /// 补签会改写历史：内容一样，但多了签名，hash 因此变了。
    @Test("给已有提交补签算改写历史")
    func signingAnExistingCommitRewritesHistory() throws {
        let operation = GitOperation.signLastCommit()

        #expect(operation.hazard == .rewritesHistory)
        #expect(operation.arguments.contains("--gpg-sign"))
        #expect(operation.arguments.contains("--no-edit"))
        let warning = try #require(operation.warning(hasSnapshot: true))
        #expect(warning.consequence.contains("推送"))
    }

    @Test("改配置不算危险操作")
    func configurationChangesAreSafe() {
        #expect(GitOperation.setConfiguration(key: "a.b", value: "c").hazard == .none)
    }
}
