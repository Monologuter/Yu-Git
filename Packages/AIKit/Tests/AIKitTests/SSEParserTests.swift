import Foundation
import Testing

@testable import AIKit

@Suite("SSE 解析")
struct SSEParserTests {

    private func events(from text: String) -> [SSEEvent] {
        var parser = SSEParser()
        var result = parser.consume(Data(text.utf8))
        result += parser.finish()
        return result
    }

    @Test("按空行切分事件")
    func splitsOnBlankLine() {
        let result = events(
            from: """
                event: message_start
                data: {"a":1}

                event: message_stop
                data: {"b":2}

                """)

        #expect(result.count == 2)
        #expect(result[0].name == "message_start")
        #expect(result[0].data == #"{"a":1}"#)
        #expect(result[1].name == "message_stop")
        #expect(result[1].data == #"{"b":2}"#)
    }

    @Test("只去掉一个前导空格")
    func stripsExactlyOneLeadingSpace() {
        let result = events(from: "data:  两个空格\n\n")
        #expect(result.first?.data == " 两个空格")
    }

    @Test("没有空格的冒号也能解析")
    func handlesNoSpaceAfterColon() {
        let result = events(from: "data:{\"x\":1}\n\n")
        #expect(result.first?.data == #"{"x":1}"#)
    }

    @Test("多条 data 行拼成一条")
    func joinsMultipleDataLines() {
        let result = events(from: "data: 第一行\ndata: 第二行\n\n")
        #expect(result.first?.data == "第一行\n第二行")
    }

    @Test("忽略注释行")
    func ignoresComments() {
        // 有些服务端用注释行做心跳，不能被当成数据
        let result = events(from: ": 心跳\ndata: 真数据\n\n")
        #expect(result.count == 1)
        #expect(result.first?.data == "真数据")
    }

    @Test("忽略 id 和 retry 字段")
    func ignoresUnusedFields() {
        let result = events(from: "id: 42\nretry: 3000\ndata: 正文\n\n")
        #expect(result.count == 1)
        #expect(result.first?.data == "正文")
    }

    // MARK: - 行结束符

    @Test("CRLF 行结束符")
    func handlesCRLF() {
        // Swift 把 "\r\n" 当作一个 Character，String.split(separator:"\n") 切不开，
        // 所以解析必须在字节层面做
        let result = events(from: "event: ping\r\ndata: x\r\n\r\ndata: y\r\n\r\n")
        #expect(result.count == 2)
        #expect(result[0].data == "x")
        #expect(result[1].data == "y")
    }

    @Test("单独的 CR 也算行结束符")
    func handlesLoneCR() {
        let result = events(from: "data: x\r\rdata: y\r\r")
        #expect(result.count == 2)
        #expect(result[0].data == "x")
        #expect(result[1].data == "y")
    }

    @Test("CRLF 被劈在两块之间")
    func handlesCRLFSplitAcrossChunks() {
        // 这是最阴的一个 case：缓冲刚好停在 CR 后面。如果此时就把 CR 当行结束符，
        // 下一块开头的 LF 会被当成第二个空行，凭空多切出一个事件。
        var parser = SSEParser()
        var result = parser.consume(Data("data: x\r".utf8))
        result += parser.consume(Data("\n\r\n".utf8))
        result += parser.finish()

        #expect(result.count == 1)
        #expect(result.first?.data == "x")
    }

    // MARK: - 分块

    @Test("事件被劈成任意块都能还原")
    func reassemblesAcrossArbitraryChunks() {
        let text = "event: content_block_delta\ndata: {\"text\":\"你好世界\"}\n\n"
        let bytes = Array(text.utf8)

        // 逐字节喂——最极端的分块，连汉字的 UTF-8 字节都被拆开了
        var parser = SSEParser()
        var result: [SSEEvent] = []
        for byte in bytes { result += parser.consume([byte]) }
        result += parser.finish()

        #expect(result.count == 1)
        #expect(result.first?.data == #"{"text":"你好世界"}"#)
    }

    @Test("多字节字符跨块不会乱码")
    func multibyteCharacterAcrossChunks() {
        let text = "data: 提交信息\n\n"
        let bytes = Array(text.utf8)
        let cut = bytes.count / 2

        var parser = SSEParser()
        var result = parser.consume(bytes[..<cut])
        result += parser.consume(bytes[cut...])
        result += parser.finish()

        #expect(result.first?.data == "提交信息")
    }

    // MARK: - 收尾

    @Test("缺少收尾空行时仍交出最后一个事件")
    func flushesTrailingEventWithoutBlankLine() {
        // 规范说该丢弃，但静默丢掉最后一段正文比报错更糟
        let result = events(from: "data: 最后一段")
        #expect(result.count == 1)
        #expect(result.first?.data == "最后一段")
    }

    @Test("空输入不产生事件")
    func emptyInputYieldsNothing() {
        #expect(events(from: "").isEmpty)
    }

    @Test("只有空行不产生事件")
    func blankLinesOnlyYieldNothing() {
        #expect(events(from: "\n\n\n").isEmpty)
    }

    @Test("OpenAI 的 [DONE] 哨兵")
    func passesThroughDoneSentinel() {
        let result = events(from: "data: {\"x\":1}\n\ndata: [DONE]\n\n")
        #expect(result.count == 2)
        #expect(result[1].data == "[DONE]")
        #expect(result[1].name == nil)
    }
}
