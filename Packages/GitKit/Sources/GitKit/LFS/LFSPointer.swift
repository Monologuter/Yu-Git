import Foundation

/// 一个 Git LFS 指针。
///
/// LFS 把大文件换成一个三行的纯文本占位符存进仓库，真正的内容放在别处。
/// **不认出来的话，界面会把它当成普通文本显示**——用户看到的是「改了三行字」，
/// 而实际发生的是一个几百 MB 的二进制文件被整个换掉了。
///
/// 格式由 LFS 规范固定：
/// ```
/// version https://git-lfs.github.com/spec/v1
/// oid sha256:4d7a214614ab2935c943f9e0ff69d22eadbb8f32b1258daaa5e2ca24d17e2393
/// size 12345
/// ```
public struct LFSPointer: Sendable, Equatable {

    /// 内容的哈希，形如 `sha256:4d7a…`。
    public let oid: String
    /// 真实文件的字节数。
    public let size: Int

    public init(oid: String, size: Int) {
        self.oid = oid
        self.size = size
    }

    /// 人能读的大小，如「117.4 MB」。
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    /// oid 的短形式，用于展示。
    public var abbreviatedOID: String {
        guard let separator = oid.firstIndex(of: ":") else { return String(oid.prefix(12)) }
        return String(oid[oid.index(after: separator)...].prefix(12))
    }

    private static let versionPrefix = "version https://git-lfs.github.com/spec/"

    /// 从文件内容里认出指针。不是指针就返回 nil。
    ///
    /// 先按大小挡一道：真正的指针只有一百多字节，而一个恰好以 `version https://…`
    /// 开头的大文本文件不该被逐行扫一遍。**这个上限也是安全边界**——
    /// 没有它，一个几百 MB 的文本文件会被整个读进来做前缀匹配。
    public static func parse(_ data: Data) -> LFSPointer? {
        guard data.count <= maximumPointerSize else { return nil }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// 指针文件的大小上限。规范没有硬性规定，取 1 KB 足够宽松——
    /// 实际的指针在 130 字节上下。
    public static let maximumPointerSize = 1024

    public static func parse(_ text: String) -> LFSPointer? {
        // 第一行必须是 version，这是规范要求的顺序
        guard text.hasPrefix(versionPrefix) else { return nil }

        var oid: String?
        var size: Int?

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "oid": oid = String(parts[1])
            case "size": size = Int(parts[1])
            default: break
            }
        }

        guard let oid, let size else { return nil }
        return LFSPointer(oid: oid, size: size)
    }
}

extension GitClient {

    /// 这个仓库有没有在用 LFS。
    ///
    /// 看 `.gitattributes` 里有没有 `filter=lfs`，而不是看 git-lfs 装没装：
    /// 一个用 LFS 的仓库在没装 git-lfs 的机器上照样是用 LFS 的仓库，
    /// 而那正是最需要提示用户的时候。
    public func usesLFS(in repository: URL) async -> Bool {
        let attributes = repository.appendingPathComponent(".gitattributes")
        guard let contents = try? String(contentsOf: attributes, encoding: .utf8) else {
            return false
        }
        return contents.contains("filter=lfs")
    }

    /// 某个路径是不是走 LFS。
    ///
    /// 用 `git check-attr` 问 git 而不是自己解析 `.gitattributes`：
    /// 属性规则可以出现在任意层级的 `.gitattributes` 里，还能被 `.git/info/attributes`
    /// 和全局配置覆盖，自己算迟早算错。
    public func isLFSTracked(_ path: String, in repository: URL) async -> Bool {
        // `-z` 形式输出 `路径\0filter\0lfs\0`，路径含空格时这是唯一可靠的形式
        guard
            let result = try? await runReturningResult(
                ["check-attr", "-z", "filter", "--", path], in: repository,
                allowsOptionalLocks: false),
            result.isSuccess
        else { return false }

        let fields = result.standardOutput.split(separator: 0x00).map {
            String(decoding: $0, as: UTF8.self)
        }
        // 三个一组：路径、属性名、值
        return fields.count >= 3 && fields[2] == "lfs"
    }

    /// 本机装没装 git-lfs。
    ///
    /// 用来区分两种情况：仓库不用 LFS，和仓库用 LFS 但这台机器拉不下来实际内容。
    /// 后者的表现是工作区里躺着一堆指针文件而不是真文件，而用户往往完全不知道
    /// 发生了什么——文件明明在，打开却是三行乱码。
    public func isLFSAvailable() async -> Bool {
        let result = try? await ProcessRunner().run(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git-lfs", "version"],
            workingDirectory: URL(fileURLWithPath: "/"),
            environment: environment,
            timeout: .seconds(5)
        )
        return result?.isSuccess == true
    }
}
