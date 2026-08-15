import GitKit
import Observation
import SwiftUI

/// 全仓库即时搜索的状态。
///
/// 每敲一个字就重搜一次，所以必须能取消上一次还没跑完的查询——
/// 否则在大仓库上会堆起一串过期的 git 进程，且结果可能乱序返回。
@Observable
@MainActor
final class SearchModel {

    enum Scope: String, CaseIterable, Identifiable {
        case contents = "内容"
        case paths = "文件名"
        case commits = "提交"

        var id: String { rawValue }
    }

    var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    var scope = Scope.contents {
        didSet {
            guard scope != oldValue else { return }
            scheduleSearch()
        }
    }

    private(set) var contentMatches: [ContentMatch] = []
    private(set) var pathMatches: [String] = []
    private(set) var commitMatches: [Commit] = []
    private(set) var isSearching = false

    /// 输入停顿多久才真正发起搜索。太短会在快速输入时空跑，太长会显得迟钝。
    private let debounce = Duration.milliseconds(180)

    private let client: GitClient
    private let root: URL
    private var pendingSearch: Task<Void, Never>?

    init(client: GitClient, root: URL) {
        self.client = client
        self.root = root
    }

    var hasResults: Bool {
        !contentMatches.isEmpty || !pathMatches.isEmpty || !commitMatches.isEmpty
    }

    func clear() {
        pendingSearch?.cancel()
        query = ""
        contentMatches = []
        pathMatches = []
        commitMatches = []
        isSearching = false
    }

    private func scheduleSearch() {
        // 上一次查询还没跑完就已经过期了，直接取消
        pendingSearch?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            contentMatches = []
            pathMatches = []
            commitMatches = []
            isSearching = false
            return
        }

        isSearching = true
        pendingSearch = Task { [debounce] in
            guard (try? await Task.sleep(for: debounce)) != nil else { return }
            await run(query: trimmed)
        }
    }

    private func run(query: String) async {
        defer { isSearching = false }

        do {
            switch scope {
            case .contents:
                contentMatches = try await client.searchFileContents(query, in: root)
            case .paths:
                pathMatches = try await client.searchFilePaths(query, in: root)
            case .commits:
                commitMatches = try await client.searchCommits(query, in: root)
            }
        } catch {
            // 搜索失败不值得打断用户，清空结果即可
            contentMatches = []
            pathMatches = []
            commitMatches = []
        }
    }
}

/// 搜索面板。
struct SearchView: View {

    @Bindable var model: SearchModel
    let onSelectFile: (String) -> Void
    let onSelectCommit: (Commit) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            results
        }
        .frame(width: 520, height: 420)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.secondaryText)

                TextField("搜索仓库", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.sheetTitle)

                if model.isSearching {
                    ProgressView().controlSize(.small)
                } else if !model.query.isEmpty {
                    Button {
                        model.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Picker("", selection: $model.scope) {
                ForEach(SearchModel.Scope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(12)
    }

    @ViewBuilder
    private var results: some View {
        if model.query.isEmpty {
            EmptyStateView(
                "搜索仓库",
                systemImage: "magnifyingglass",
                description: "在被跟踪的文件里搜内容与文件名，或按说明、作者、hash 搜提交"
            )
        } else if !model.hasResults && !model.isSearching {
            EmptyStateView(
                "没有匹配的结果",
                systemImage: "magnifyingglass",
                description: "「\(model.query)」在当前搜索范围里没有命中"
            )
        } else {
            List {
                switch model.scope {
                case .contents:
                    ForEach(model.contentMatches) { match in
                        Button {
                            onSelectFile(match.path)
                        } label: {
                            ContentMatchRow(match: match, query: model.query)
                        }
                        .buttonStyle(.plain)
                    }
                case .paths:
                    ForEach(model.pathMatches, id: \.self) { path in
                        Button {
                            onSelectFile(path)
                        } label: {
                            Label(path, systemImage: "doc.text")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                    }
                case .commits:
                    ForEach(model.commitMatches) { commit in
                        Button {
                            onSelectCommit(commit)
                        } label: {
                            CommitRow(commit: commit)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
        }
    }
}

/// 内容匹配的一行：路径 + 行号 + 命中行，命中的片段高亮。
struct ContentMatchRow: View {

    let match: ContentMatch
    let query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(match.path)
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.head)

                Text("第 \(match.lineNumber) 行")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }

            Text(highlighted)
                .font(Theme.Font.mono)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    /// 把命中的片段标出来。搜索是忽略大小写的，高亮也要跟着忽略。
    private var highlighted: AttributedString {
        var text = AttributedString(match.line.trimmingCharacters(in: .whitespaces))
        guard !query.isEmpty else { return text }

        var searchRange = text.startIndex..<text.endIndex
        while let found = text[searchRange].range(of: query, options: .caseInsensitive) {
            text[found].backgroundColor = .yellow.opacity(0.35)
            text[found].inlinePresentationIntent = .stronglyEmphasized
            guard found.upperBound < text.endIndex else { break }
            searchRange = found.upperBound..<text.endIndex
        }
        return text
    }
}
