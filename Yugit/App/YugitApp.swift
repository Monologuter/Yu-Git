import AppKit
import SwiftUI

@main
struct YugitApp: App {

    @State private var model = AppModel()
    @State private var aiSettings = AISettingsStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                // Git 客户端的三栏布局在窄窗口下没法用，给一个够用的下限
                .frame(minWidth: 900, minHeight: 560)
                .environment(aiSettings)
                .onAppear {
                    // 从 Finder 拖到图标上、或用 open 命令传入的仓库，
                    // 可能在窗口就绪前就到达，这里补取一次
                    appDelegate.openHandler = { url in model.open(url) }
                    appDelegate.flushPendingOpen()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开仓库…") {
                    model.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .undoRedo) {
                Button("撤销上一步操作") {
                    model.undoMostRecent()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(model.repository?.mostRecentUndoableEntry == nil)
            }

            CommandGroup(after: .toolbar) {
                Button("刷新") {
                    model.refreshCurrentRepository()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.repository == nil)
            }
        }

        Settings {
            AISettingsView(store: aiSettings)
        }
    }
}
