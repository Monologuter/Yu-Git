import Foundation
import Testing

@testable import AIKit

/// diff fixture 全部取自真实 `git diff --cached` 输出，不是手写的近似格式。
@Suite("上下文脱敏")
struct ContextRedactorTests {

    /// 含 .env、私钥、明文 token、带空格文件名的真实 diff。
    static let mixedDiff = """
        diff --git a/.env b/.env
        index 80e8e70..bc8fc9e 100644
        --- a/.env
        +++ b/.env
        @@ -1,2 +1 @@
        -API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz123456
        -DB_PASS=hunter2
        +API_KEY=sk-proj-CHANGEDzzzzzzzzzzzzzzzzzzzzzz
        diff --git a/config/server.pem b/config/server.pem
        index ee6dc97..af8b295 100644
        --- a/config/server.pem
        +++ b/config/server.pem
        @@ -1,3 +1,3 @@
         -----BEGIN RSA PRIVATE KEY-----
        -MIIEowIBAAKCAQEA
        +CHANGEDKEYDATA
         -----END RSA PRIVATE KEY-----
        diff --git a/src/auth.swift b/src/auth.swift
        index ef02c77..d69668b 100644
        --- a/src/auth.swift
        +++ b/src/auth.swift
        @@ -1,3 +1,4 @@
         func login() {
        -  let token = "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        +  let token = "ghp_ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"
        +  retry()
         }
        diff --git a/src/with space.txt b/src/with space.txt
        index e75c2c6..1178a1e 100644
        --- a/src/with space.txt\t
        +++ b/src/with space.txt\t
        @@ -1 +1 @@
        -plain content
        +changed content
        """

    // MARK: - 切分

    @Test("按文件切分")
    func splitsIntoFiles() {
        let files = ContextRedactor.splitByFile(Self.mixedDiff)
        #expect(files.map(\.path) == [".env", "config/server.pem", "src/auth.swift", "src/with space.txt"])
    }

    @Test("含空格的路径不丢字也不带尾随制表符")
    func handlesPathWithSpace() throws {
        let files = ContextRedactor.splitByFile(Self.mixedDiff)
        let file = try #require(files.last)
        #expect(file.path == "src/with space.txt")
    }

    @Test("路径里出现 b/ 时仍能取全")
    func handlesPathContainingBSlash() throws {
        // diff --git 行在这种路径下真有歧义：`a/foo b/bar.txt b/foo b/bar.txt`
        // 光看这一行无法确定哪个 " b/" 是分界，所以要从 +++ 行取
        let diff = """
            diff --git a/foo b/bar.txt b/foo b/bar.txt
            index 5626abf..f719efd 100644
            --- a/foo b/bar.txt\t
            +++ b/foo b/bar.txt\t
            @@ -1 +1 @@
            -one
            +two
            """

        let files = ContextRedactor.splitByFile(diff)
        let file = try #require(files.first)
        #expect(file.path == "foo b/bar.txt")
    }

    @Test("正文里形似文件头的行不会被误认")
    func ignoresHeaderLikeContentInsideHunk() throws {
        // 新增一行内容为 `++ b/伪造.txt`，加上 + 前缀后正好长得像 +++ 行
        let diff = """
            diff --git a/notes.md b/notes.md
            index 111..222 100644
            --- a/notes.md
            +++ b/notes.md
            @@ -1 +1,2 @@
             既有内容
            +++ b/伪造.txt
            """

        let files = ContextRedactor.splitByFile(diff)
        #expect(files.count == 1)
        #expect(files.first?.path == "notes.md")
    }

    @Test("新增文件的路径取自 +++ 侧")
    func usesPlusSideForNewFile() throws {
        let diff = """
            diff --git a/新文件.swift b/新文件.swift
            new file mode 100644
            index 0000000..abc1234
            --- /dev/null
            +++ b/新文件.swift
            @@ -0,0 +1 @@
            +内容
            """

        let files = ContextRedactor.splitByFile(diff)
        #expect(files.first?.path == "新文件.swift")
    }

    @Test("删除文件的路径取自 --- 侧")
    func usesMinusSideForDeletedFile() throws {
        let diff = """
            diff --git a/删掉的.swift b/删掉的.swift
            deleted file mode 100644
            index abc1234..0000000
            --- a/删掉的.swift
            +++ /dev/null
            @@ -1 +0,0 @@
            -内容
            """

        let files = ContextRedactor.splitByFile(diff)
        #expect(files.first?.path == "删掉的.swift")
    }

    @Test("二进制文件没有 ---/+++ 行，退回文件头解析")
    func fallsBackToHeaderForBinary() throws {
        let diff = """
            diff --git a/图标.png b/图标.png
            index 111..222 100644
            Binary files a/图标.png and b/图标.png differ
            """

        let files = ContextRedactor.splitByFile(diff)
        #expect(files.first?.path == "图标.png")
    }

    @Test("空 diff 不产生文件")
    func emptyDiffYieldsNothing() {
        #expect(ContextRedactor.splitByFile("").isEmpty)
    }

    // MARK: - 敏感文件

    @Test(
        "敏感文件整份排除",
        arguments: [
            ".env", ".env.production", "config/.env.local",
            "server.pem", "config/server.pem", "keys/id_rsa", "app.p12", "release.keystore",
            "~/.aws/credentials", "credentials.json", ".netrc", "terraform.tfstate",
            "App.mobileprovision",
        ])
    func detectsSensitivePaths(path: String) {
        #expect(ContextRedactor.isSensitive(path: path))
    }

    @Test(
        "正常文件不误伤",
        arguments: [
            "src/auth.swift", "README.md", "Package.swift",
            // 这几个如果用 *secret* / *key* 之类的模糊匹配就会被误杀
            "Tests/SecretsManagerTests.swift", "src/keyboard.ts", "docs/环境变量.md",
            "src/EnvironmentView.swift", "certificates.crt",
        ])
    func doesNotOverMatch(path: String) {
        #expect(!ContextRedactor.isSensitive(path: path))
    }

    @Test("敏感文件的内容一个字都不出现在结果里")
    func excludesSensitiveContentEntirely() {
        let result = ContextRedactor().redact(diff: Self.mixedDiff)

        #expect(result.excludedPaths.sorted() == [".env", "config/server.pem"])
        // 值本身、变量名、私钥标记，全都不能漏
        #expect(!result.text.contains("hunter2"))
        #expect(!result.text.contains("DB_PASS"))
        #expect(!result.text.contains("PRIVATE KEY"))
        #expect(!result.text.contains("sk-proj-"))
        // 非敏感文件要留下
        #expect(result.text.contains("func login()"))
        #expect(result.text.contains("changed content"))
    }

    // MARK: - 打码

    @Test("正常文件里的明文 token 被打码")
    func masksTokensInRegularFiles() {
        let result = ContextRedactor().redact(diff: Self.mixedDiff)

        #expect(!result.text.contains("ghp_ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ"))
        #expect(!result.text.contains("ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
        #expect(result.text.contains("«已打码»"))
        #expect(result.maskedSecretCount == 2)
        // 打码只换掉密钥本身，代码结构要留着，否则模型读不懂改了什么
        #expect(result.text.contains("let token ="))
        #expect(result.text.contains("+  retry()"))
    }

    @Test(
        "认得出常见密钥格式",
        arguments: [
            "sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
            "ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
            "github_pat_11ABCDEFG0abcdefghijklmnop",
            "glpat-abcdefghijklmnopqrst",
            "AKIAIOSFODNN7EXAMPLE",
            "xoxb-1234567890-abcdefghij",
            "AIzaSyD-abcdefghijklmnopqrstuvwxyz1234567",
        ])
    func masksKnownSecretShapes(secret: String) {
        let (masked, count) = ContextRedactor.maskSecrets(in: "let k = \"\(secret)\"")
        #expect(count == 1)
        #expect(!masked.contains(secret))
    }

    @Test(
        "不误伤长得像密钥但不是的字符串",
        arguments: [
            // commit hash、UUID、base64 资源如果靠长度或熵去猜就全中招了
            "e48c16b8f2a91d3c4e5f6a7b8c9d0e1f2a3b4c5d",
            "550e8400-e29b-41d4-a716-446655440000",
            "aGVsbG8gd29ybGQgdGhpcyBpcyBiYXNlNjQgY29udGVudA==",
            "npm install --save-dev typescript",
        ])
    func doesNotMaskInnocentStrings(text: String) {
        let (_, count) = ContextRedactor.maskSecrets(in: text)
        #expect(count == 0)
    }

    // MARK: - 体积

    @Test("超预算时按文件截断，不腰斩")
    func truncatesByWholeFile() throws {
        let big = String(repeating: "+这是一行很长的改动内容\n", count: 200)
        let diff = """
            diff --git a/small.txt b/small.txt
            index 1..2 100644
            --- a/small.txt
            +++ b/small.txt
            @@ -1 +1 @@
            +小改动
            diff --git a/big.txt b/big.txt
            index 3..4 100644
            --- a/big.txt
            +++ b/big.txt
            @@ -1 +200 @@
            \(big)
            """

        let result = ContextRedactor().redact(diff: diff, budget: 200)

        #expect(result.truncatedPaths == ["big.txt"])
        #expect(result.text.contains("小改动"))
        // 被截断的文件是整份不进，不能留半截 hunk 让模型看不懂
        #expect(!result.text.contains("这是一行很长的改动内容"))
    }

    @Test("没有任何删改时不显示提示")
    func noSummaryWhenNothingChanged() {
        let clean = """
            diff --git a/README.md b/README.md
            index 1..2 100644
            --- a/README.md
            +++ b/README.md
            @@ -1 +1 @@
            -旧标题
            +新标题
            """

        let result = ContextRedactor().redact(diff: clean)
        #expect(result.summary == nil)
        #expect(result.text.contains("新标题"))
    }

    @Test("有删改时提示说得清")
    func summaryDescribesWhatHappened() throws {
        let result = ContextRedactor().redact(diff: Self.mixedDiff)
        let summary = try #require(result.summary)

        #expect(summary.contains("2 个敏感文件"))
        #expect(summary.contains("2 处疑似密钥"))
    }
}
