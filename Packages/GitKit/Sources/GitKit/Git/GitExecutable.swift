import Foundation

/// 定位系统上的 git 可执行文件。
public enum GitExecutable {

    /// GUI App 不经过 login shell 启动，继承到的 PATH 往往只有系统目录，
    /// 找不到 Homebrew 装的 git。这里先按常见位置兜底；
    /// 接入 App 时会补上「从 login shell 解析真实 PATH」的逻辑（届时 credential
    /// helper 的查找也依赖它）。
    private static let fallbackDirectories = [
        "/opt/homebrew/bin",  // Apple Silicon Homebrew
        "/usr/local/bin",  // Intel Homebrew
        "/usr/bin",  // Xcode 命令行工具
    ]

    /// 按 PATH → 常见安装位置的顺序查找 git。
    public static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for directory in pathDirectories + fallbackDirectories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("git")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
