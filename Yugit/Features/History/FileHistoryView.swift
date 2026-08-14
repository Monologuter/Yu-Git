import GitKit
import Observation
import SwiftUI

/// 单文件历史面板的状态。
@MainActor
@Observable
final class FileHistoryViewModel: Identifiable {

    nonisolated let id = UUID()

    let repository: RepositoryViewModel
    let path: String

    private(set) var commits: [Commit] = []
    private(set) var isLoading = false
    var errorMessage: String?

    /// 跨过改名去看更早的历史。
    ///
    /// 默认开着：一个中途换过名字的文件，不跟随的话历史会在改名那一刻戛然而止，
    /// 看起来像是上个月才被创建的。关掉的意义是「这个位置上曾经有过哪些文件」，
    /// 那是另一个问题。
    var followsRenames = true {
        didSet {
            guard followsRenames != oldValue else { return }
            Task { await reload() }
        }
    }

    init(repository: RepositoryViewModel, path: String) {
        self.repository = repository
        self.path = path
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            commits = try await repository.fileHistory(of: path, follow: followsRenames)
        } catch {
            errorMessage = "读取历史失败：\(error)"
        }
    }
}

/// 某个文件的所有改动记录。
struct FileHistoryView: View {

    @Bindable var model: FileHistoryViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 640, height: 460)
        .task { await model.reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
            HStack {
                Label("文件历史", systemImage: "clock.arrow.circlepath")
                    .font(Theme.Font.title)
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            Text(model.path)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(Theme.Spacing.loose)
    }

    @ViewBuilder
    private var content: some View {
        if model.commits.isEmpty && !model.isLoading {
            EmptyStateView(
                "这个文件还没有历史",
                systemImage: "doc",
                description: "它可能是新加的，还没有被任何一次提交记录过。"
            )
        } else {
            List(model.commits) { commit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.subject)
                        .font(Theme.Font.body)
                        .lineLimit(2)
                    HStack(spacing: Theme.Spacing.regular) {
                        Text(commit.abbreviatedHash)
                            .font(Theme.Font.mono)
                        Text(commit.author.name)
                        Text(Self.formatter.localizedString(for: commit.author.date, relativeTo: Date()))
                    }
                    .font(Theme.Font.secondary)
                    .foregroundStyle(Theme.Colors.tertiaryText)
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("复制完整 hash") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(commit.hash, forType: .string)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("跨过改名", isOn: $model.followsRenames)
                .toggleStyle(.checkbox)
                .help("关掉之后只看这个路径本身的历史，不追溯它改名之前叫什么")
            Text("共 \(model.commits.count) 条")
                .font(Theme.Font.secondary)
                .foregroundStyle(Theme.Colors.tertiaryText)
            Spacer()
            Button("完成") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(Theme.Spacing.loose)
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
