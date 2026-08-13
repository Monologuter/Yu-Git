import AppKit

/// 承接 AppKit 层的事件：从 Finder 打开、`open` 命令传入的路径、退出行为。
///
/// SwiftUI 的 `onOpenURL` 只处理自定义 URL scheme，接不到文件打开，
/// 所以这部分仍需要一个 delegate。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 由窗口在就绪后注入。
    var openHandler: ((URL) -> Void)?

    /// App 冷启动时，打开请求会早于窗口出现，先存下来。
    private var pendingURL: URL?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let openHandler {
            openHandler(url)
        } else {
            pendingURL = url
        }
    }

    func flushPendingOpen() {
        guard let pendingURL, let openHandler else { return }
        self.pendingURL = nil
        openHandler(pendingURL)
    }

    /// 关掉最后一个窗口就退出——单窗口工具没有留在后台的理由。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
