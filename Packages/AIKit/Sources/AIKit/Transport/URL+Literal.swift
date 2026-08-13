import Foundation

extension URL {

    /// 从源码里写死的字面量构造 URL。
    ///
    /// 参数类型是 `StaticString`，编译器保证只能传字面量、传不进运行时数据。
    /// 所以构造失败只可能是字面量本身敲错了——那是编译期就该发现的编程错误，
    /// 直接崩比返回 optional 让每个调用方各自编个兜底 URL 更诚实。
    ///
    /// 禁止强解包的规矩针对的是**运行时**数据（用户输入的接口地址走的是
    /// `URL(string:)` 加校验，见 ``AIConfiguration/makeProvider(apiKey:session:)``）。
    static func literal(_ string: StaticString) -> URL {
        guard let url = URL(string: "\(string)") else {
            preconditionFailure("URL 字面量不合法：\(string)")
        }
        return url
    }
}
