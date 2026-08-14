import Foundation
import Testing

@testable import GitKit

@Suite("历史过滤")
struct HistoryFilterTests {

    private func seeded() async throws -> TemporaryRepository {
        let repository = try await TemporaryRepository()

        try repository.write("1\n", to: "a.txt")
        try await repository.git("add", "--all")
        try await repository.git(
            "-c", "user.name=张三", "-c", "user.email=zhang.san@example.com",
            "commit", "--quiet", "--message", "feat(ui): 加一个 [WIP] 按钮")

        try repository.write("2\n", to: "b.txt")
        try await repository.git("add", "--all")
        try await repository.git(
            "-c", "user.name=李四", "-c", "user.email=li@example.com",
            "commit", "--quiet", "--message", "fix: 修一个 v1.0 的问题")

        return repository
    }

    @Test("按提交信息筛，特殊字符按字面处理")
    func filtersByMessageLiterally() async throws {
        let repository = try await seeded()

        // 不加 --fixed-strings 的话 [WIP] 会被当成字符集，匹配任意一个 W/I/P，
        // 于是两条提交都会中——那不是用户想要的
        let wip = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(message: "[WIP]"))
        #expect(wip.count == 1)
        #expect(wip.first?.subject.contains("[WIP]") == true)

        // v1.0 里的点同理，不转义会匹配到 v1X0
        let version = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(message: "v1.0"))
        #expect(version.count == 1)
    }

    @Test("按提交信息筛不区分大小写")
    func messageFilterIsCaseInsensitive() async throws {
        let repository = try await seeded()
        let found = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(message: "FEAT"))
        #expect(found.count == 1)
    }

    @Test("按作者筛，子串就够")
    func filtersByAuthorSubstring() async throws {
        let repository = try await seeded()

        let byName = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(author: "张三"))
        #expect(byName.count == 1)

        // 邮箱的一部分也能筛
        let byEmail = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(author: "li@example"))
        #expect(byEmail.count == 1)
        #expect(byEmail.first?.author.name == "李四")
    }

    @Test("作者名里的正则元字符被转义")
    func escapesRegexInAuthor() async throws {
        let repository = try await seeded()

        // --author 始终按正则解释，--fixed-strings 管不到它（实测）。
        // 不转义的话 zhang.san 里的点会匹配任意字符，
        // 于是 "zhangXsan" 这类不相干的作者也会被筛出来。
        // 这里反过来验证：转义后，把点当通配符的写法应该**筛不到**任何东西。
        let wildcard = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(author: "zhang.san"))
        #expect(wildcard.count == 1, "字面的 zhang.san 应该匹配到")

        let shouldNotMatch = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(author: "zhangXsan"))
        #expect(shouldNotMatch.isEmpty, "转义之后 X 不该匹配到点")
    }

    @Test("按时间筛，用完整时间戳而不是裸日期")
    func filtersByDate() async throws {
        let repository = try await seeded()

        let all = try await repository.client.log(in: repository.url)
        #expect(all.count == 2)

        // 裸日期（2026-08-14 这种）会漏掉当天的提交——git 对它的解释
        // 和本地时区不一致。所以 HistoryFilter 一律输出带时区的完整时间戳。
        let future = Date().addingTimeInterval(3600)
        #expect(HistoryFilter.timestamp(future).contains("T"))

        let sinceFuture = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(since: future))
        #expect(sinceFuture.isEmpty)

        let sincePast = try await repository.client.log(
            in: repository.url,
            filter: HistoryFilter(since: Date().addingTimeInterval(-86400)))
        #expect(sincePast.count == 2)
    }

    @Test("多个条件是 AND 关系")
    func combinesConditions() async throws {
        let repository = try await seeded()

        // 作者对但信息不对，应该一条都没有
        let none = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(message: "feat", author: "李四"))
        #expect(none.isEmpty)

        let one = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(message: "feat", author: "张三"))
        #expect(one.count == 1)
    }

    @Test("空过滤器不改变结果")
    func emptyFilterIsNoOp() async throws {
        let repository = try await seeded()
        #expect(HistoryFilter().isEmpty)
        #expect(HistoryFilter(message: "   ").isEmpty, "只有空白应该视为没填")

        let all = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(message: "  "))
        #expect(all.count == 2)
    }

    @Test("按路径筛")
    func filtersByPath() async throws {
        let repository = try await seeded()
        let onlyB = try await repository.client.log(
            in: repository.url, filter: HistoryFilter(paths: ["b.txt"]))
        #expect(onlyB.count == 1)
        #expect(onlyB.first?.subject.contains("fix") == true)
    }
}
