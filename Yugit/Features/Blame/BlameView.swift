import GitKit
import Observation
import SwiftUI

/// AI 归因 blame 的状态。
@MainActor
@Observable
final class BlameViewModel: Identifiable {

    nonisolated let id = UUID()

    private let repository: RepositoryViewModel

    let path: String
    private(set) var result: BlameResult?
    private(set) var isLoading = false
    var errorMessage: String?

    /// 只看 AI 参与的行。
    var showsAIOnly = false

    init(repository: RepositoryViewModel, path: String) {
        self.repository = repository
        self.path = path
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            result = try await repository.blame(path: path)
        } catch {
            errorMessage = "blame 失败：\(error)"
        }
    }

    var visibleLines: [BlameLine] {
        guard let result else { return [] }
        guard showsAIOnly else { return result.lines }
        return result.lines.filter { result.authorship(ofLine: $0).isAI }
    }
}

/// 逐行显示这段代码是谁写的：人，还是哪个 AI 工具。
///
/// 差异化设计里的「AI 归因 blame」。AI 写的代码越来越多，而普通 blame
/// 只会显示提交者的名字——那个名字是按下回车的人，不是写下这段逻辑的东西。
struct BlameView: View {

    @Bindable var model: BlameViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 900, height: 640)
        .task { await model.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.path)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Text("每一行是谁写的")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let result = model.result, result.aiLineCount > 0 {
                    Toggle("只看 AI 参与的", isOn: $model.showsAIOnly)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

            if let result = model.result {
                summaryBar(result)
            }
        }
        .padding(12)
    }

    private func summaryBar(_ result: BlameResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // 比例条：一眼看出这个文件有多少是 AI 写的
            GeometryReader { geometry in
                HStack(spacing: 1) {
                    ForEach(result.breakdown, id: \.tool) { item in
                        Rectangle()
                            .fill(Self.tint(for: item.tool))
                            .frame(
                                width: max(
                                    2,
                                    geometry.size.width * Double(item.lineCount)
                                        / Double(max(result.lines.count, 1))))
                    }
                }
            }
            .frame(height: 6)
            .clipShape(.capsule)

            HStack(spacing: 12) {
                ForEach(result.breakdown, id: \.tool) { item in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Self.tint(for: item.tool))
                            .frame(width: 7, height: 7)
                        Text("\(item.tool) \(item.lineCount) 行")
                    }
                }
                Spacer()
                if result.aiLineCount > 0 {
                    Text("AI 参与 \(Int((result.aiRatio * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption2)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView("正在追溯每一行的出处…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage {
            ContentUnavailableView {
                Label("读不到 blame", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error).textSelection(.enabled)
            }
        } else if let result = model.result {
            if model.visibleLines.isEmpty {
                ContentUnavailableView(
                    model.showsAIOnly ? "这个文件没有 AI 参与的行" : "文件是空的",
                    systemImage: model.showsAIOnly ? "person" : "doc"
                )
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.visibleLines) { line in
                            BlameRow(
                                line: line,
                                commit: result.commits[line.commit],
                                authorship: result.authorship(ofLine: line)
                            )
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label(
                "归因依据是提交信息里的署名（Co-authored-by 等）。认不出的一律算人工。",
                systemImage: "info.circle"
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Spacer()

            Button("关闭") { onDismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    /// 工具 → 颜色。人工用中性色，各家 AI 各一个色。
    static func tint(for tool: String) -> Color {
        switch tool {
        case "人工": .secondary
        case "Claude": .orange
        case "Copilot": .green
        case "Cursor": .blue
        case "Aider": .purple
        default: .pink
        }
    }
}

// MARK: - 单行

private struct BlameRow: View {

    let line: BlameLine
    let commit: BlameCommit?
    let authorship: Authorship

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左边一道色条，扫一眼就能看出一整段是谁写的
            Rectangle()
                .fill(BlameView.tint(for: authorship.displayName))
                .frame(width: 3)

            HStack(alignment: .top, spacing: 8) {
                Text("\(line.finalLineNumber)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, alignment: .trailing)

                VStack(alignment: .leading, spacing: 0) {
                    Text(commit?.summary ?? String(line.commit.prefix(7)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(authorship.displayName)
                            .foregroundStyle(BlameView.tint(for: authorship.displayName))
                        if let commit {
                            Text("·")
                            Text(commit.authorName)
                            Text("·")
                            Text(commit.authorDate, format: .relative(presentation: .named))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                .frame(width: 260, alignment: .leading)

                Text(line.content.isEmpty ? " " : line.content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.vertical, 2)
            .padding(.leading, 6)
        }
        .background(
            authorship.isAI
                ? BlameView.tint(for: authorship.displayName).opacity(0.05) : Color.clear
        )
    }
}
