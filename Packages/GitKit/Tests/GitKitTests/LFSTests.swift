import Foundation
import Testing

@testable import GitKit

@Suite("Git LFS")
struct LFSTests {

    private let pointerText = """
        version https://git-lfs.github.com/spec/v1
        oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
        size 123456789

        """

    // MARK: - 指针识别

    /// 不认出来的话，界面会把它当成普通文本——用户看到「改了三行字」，
    /// 而实际是一个上百 MB 的二进制文件被整个换掉了。
    @Test("认得出标准指针，读得出 oid 与大小")
    func parsesAPointer() throws {
        let pointer = try #require(LFSPointer.parse(pointerText))

        #expect(pointer.size == 123_456_789)
        #expect(pointer.oid.hasPrefix("sha256:"))
        #expect(pointer.abbreviatedOID == "4d7a214614ab")
        // 给人看的大小，不是一串数字
        #expect(pointer.formattedSize.contains("MB"))
    }

    @Test("普通文本不会被误认成指针")
    func rejectsOrdinaryText() {
        #expect(LFSPointer.parse("") == nil)
        #expect(LFSPointer.parse("这是一个普通文件\n第二行\n") == nil)
        #expect(LFSPointer.parse("version 1.0\noid x\nsize 3\n") == nil)
    }

    @Test("缺字段的指针按不是指针处理，不给一个半截的结果")
    func rejectsIncompletePointers() {
        let noSize = """
            version https://git-lfs.github.com/spec/v1
            oid sha256:abc

            """
        let noOID = """
            version https://git-lfs.github.com/spec/v1
            size 100

            """
        #expect(LFSPointer.parse(noSize) == nil)
        #expect(LFSPointer.parse(noOID) == nil)
    }

    @Test("size 不是数字时不当作指针")
    func rejectsNonNumericSize() {
        let broken = """
            version https://git-lfs.github.com/spec/v1
            oid sha256:abc
            size 很大

            """
        #expect(LFSPointer.parse(broken) == nil)
    }

    /// 大小上限既是省事也是安全边界：没有它，一个恰好以 `version https://…`
    /// 开头的几百 MB 文本文件会被整个读进来做匹配。
    @Test("超过上限的内容直接判定不是指针，不整个读进来")
    func rejectsOversizedInput() {
        var data = Data(pointerText.utf8)
        data.append(Data(repeating: 0x20, count: LFSPointer.maximumPointerSize))

        #expect(data.count > LFSPointer.maximumPointerSize)
        #expect(LFSPointer.parse(data) == nil)
        // 同样的内容不超限时是认得出来的
        #expect(LFSPointer.parse(Data(pointerText.utf8)) != nil)
    }

    @Test("认后续版本的 spec")
    func acceptsFutureSpecVersions() {
        let v2 = pointerText.replacingOccurrences(of: "spec/v1", with: "spec/v2")
        #expect(LFSPointer.parse(v2) != nil)
    }

    // MARK: - 真实仓库

    /// 手工造指针文件而不是真装 LFS 去 track：指针格式由规范固定，
    /// 而测试不该依赖机器上装没装 git-lfs。
    private func makeRepositoryWithPointer() async throws -> TemporaryRepository {
        let repo = try await TemporaryRepository()
        try repo.write("*.bin filter=lfs diff=lfs merge=lfs -text\n", to: ".gitattributes")
        try repo.write(pointerText, to: "big.bin")
        try repo.write("普通内容\n", to: "normal.txt")
        try await repo.commitAll("带 LFS 指针")
        return repo
    }

    @Test("认得出仓库在用 LFS")
    func detectsLFSRepositories() async throws {
        let repo = try await makeRepositoryWithPointer()
        #expect(await repo.client.usesLFS(in: repo.url))

        let plain = try await TemporaryRepository()
        try plain.write("x\n", to: "f.txt")
        try await plain.commitAll("base")
        #expect(await plain.client.usesLFS(in: plain.url) == false)
    }

    /// 看 `.gitattributes` 而不是看 git-lfs 装没装：一个用 LFS 的仓库
    /// 在没装 git-lfs 的机器上照样是用 LFS 的仓库，而那正是最该提示的时候。
    @Test("哪些路径走 LFS 由 git 说了算，不自己解析 .gitattributes")
    func asksGitWhichPathsAreTracked() async throws {
        let repo = try await makeRepositoryWithPointer()

        #expect(await repo.client.isLFSTracked("big.bin", in: repo.url))
        #expect(await repo.client.isLFSTracked("normal.txt", in: repo.url) == false)
    }

    @Test("路径里有空格也问得对")
    func handlesSpacesInPaths() async throws {
        let repo = try await TemporaryRepository()
        try repo.write("*.bin filter=lfs -text\n", to: ".gitattributes")
        try repo.write(pointerText, to: "my big file.bin")
        try await repo.commitAll("带空格的路径")

        #expect(await repo.client.isLFSTracked("my big file.bin", in: repo.url))
    }

    @Test("提交进去的确实是指针文本而不是文件内容")
    func storesThePointerInTheRepository() async throws {
        let repo = try await makeRepositoryWithPointer()

        let stored = try await repo.client.run(["cat-file", "-p", "HEAD:big.bin"], in: repo.url)
        let pointer = try #require(LFSPointer.parse(stored.standardOutput))
        #expect(pointer.size == 123_456_789)
    }
}
