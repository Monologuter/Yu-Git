import AppKit
import GitKit
import Observation
import SwiftUI

/// 应用级状态：当前打开的仓库、最近打开记录、全局错误。
@Observable
@MainActor
final class AppModel {

    private(set) var repository: RepositoryViewModel?

    /// 最近打开过的仓库路径，按最近使用排序。
    private(set) var recentRepositories: [URL] = []

    /// 打不开仓库这类需要用户知晓的错误。
    var errorMessage: String?

    private let recentsKey = "com.chenya.yugit.recentRepositories"
    private let maximumRecents = 10

    init() {
        recentRepositories = loadRecents()
    }

    // MARK: - 打开仓库

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "打开"
        panel.message = "选择一个 Git 仓库目录"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        Task {
            do {
                let viewModel = try await RepositoryViewModel(url: url)
                repository = viewModel
                rememberRecent(url)
                await viewModel.refresh()
            } catch {
                // 选错目录是最常见的情况，错误信息要直接说清楚下一步该做什么
                errorMessage = "\(error)"
            }
        }
    }

    func closeRepository() {
        repository = nil
    }

    func refreshCurrentRepository() {
        guard let repository else { return }
        Task { await repository.refresh() }
    }

    // MARK: - 最近打开

    private func rememberRecent(_ url: URL) {
        var recents = recentRepositories.filter { $0.path != url.path }
        recents.insert(url, at: 0)
        recentRepositories = Array(recents.prefix(maximumRecents))
        UserDefaults.standard.set(recentRepositories.map(\.path), forKey: recentsKey)
    }

    func removeRecent(_ url: URL) {
        recentRepositories.removeAll { $0.path == url.path }
        UserDefaults.standard.set(recentRepositories.map(\.path), forKey: recentsKey)
    }

    private func loadRecents() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        // 仓库可能已被移动或删除，过滤掉不存在的，免得列表里全是死链接
        return
            paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
