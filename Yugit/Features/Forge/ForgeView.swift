import AppKit
import ForgeKit
import GitKit
import Observation
import SwiftUI

/// 平台集成面板的状态。
@MainActor
@Observable
final class ForgeViewModel: Identifiable {

    nonisolated let id = UUID()

    private let repository: RepositoryViewModel
    private let tokens = ForgeTokenStore()

    private(set) var locator: RemoteLocator?
    private(set) var requests: [PullRequest] = []
    private(set) var isLoading = false
    var errorMessage: String?

    /// 令牌是否已配。界面上据此决定显示列表还是配置引导。
    private(set) var hasToken = false

    var filter: PullRequest.State? = .open

    init(repository: RepositoryViewModel) {
        self.repository = repository
    }

    var noun: String { locator?.kind.shortNoun ?? "PR" }

    // MARK: - 载入

    func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        guard let url = await repository.originURL() else {
            errorMessage = "这个仓库没有配置 origin 远程"
            return
        }
        guard let found = RemoteLocator.parse(remoteURL: url) else {
            errorMessage = "认不出 \(url) 属于哪个平台。目前支持 GitHub、GitLab（含自建）、Gitee。"
            return
        }
        locator = found

        guard let token = try? tokens.token(forHost: found.host), !token.isEmpty else {
            hasToken = false
            requests = []
            return
        }
        hasToken = true

        do {
            let client = ForgeClient(locator: found, token: token)
            requests = try await client.pullRequests(state: filter)
        } catch let error as ForgeError {
            errorMessage = "\(error.localizedMessage)\n\(error.suggestion)"
        } catch {
            errorMessage = "\(error)"
        }
    }

    func saveToken(_ token: String) async {
        guard let locator else { return }
        do {
            try tokens.store(token, forHost: locator.host)
            await load()
        } catch let error as ForgeTokenError {
            errorMessage = error.localizedMessage
        } catch {
            errorMessage = "\(error)"
        }
    }

    func removeToken() async {
        guard let locator else { return }
        try? tokens.remove(forHost: locator.host)
        hasToken = false
        requests = []
    }

    // MARK: - 创建

    func create(title: String, body: String, target: String, isDraft: Bool) async -> Bool {
        guard
            let locator,
            let token = try? tokens.token(forHost: locator.host),
            let source = repository.currentBranch?.name
        else {
            errorMessage = ForgeError.notConfigured.localizedMessage
            return false
        }

        do {
            let client = ForgeClient(locator: locator, token: token)
            let created = try await client.createPullRequest(
                NewPullRequest(
                    title: title, body: body,
                    sourceBranch: source, targetBranch: target, isDraft: isDraft))
            // 建完直接打开网页：后续的评审、讨论都在浏览器里进行，
            // 没必要在客户端里重造一遍
            if let url = created.webURL { NSWorkspace.shared.open(url) }
            await load()
            return true
        } catch let error as ForgeError {
            errorMessage = "\(error.localizedMessage)\n\(error.suggestion)"
            return false
        } catch {
            errorMessage = "\(error)"
            return false
        }
    }

    func open(_ request: PullRequest) {
        guard let url = request.webURL else { return }
        NSWorkspace.shared.open(url)
    }

    var currentBranchName: String? { repository.currentBranch?.name }
}

/// GitHub / GitLab / Gitee 的 PR / MR 管理。
///
/// 刻意**只做列表和创建**：评审、讨论、合并这些在网页上做得比客户端好得多，
/// 硬搬进来只会做出一个更差的浏览器。客户端要解决的是「我刚推完，
/// 现在要开一个 PR」这个具体的断点。
struct ForgeView: View {

    @Bindable var model: ForgeViewModel
    let onDismiss: () -> Void

    @State private var isCreating = false
    @State private var tokenDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 560)
        .task { await model.load() }
        .sheet(isPresented: $isCreating) {
            CreateRequestSheet(model: model) { isCreating = false }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.locator?.kind.displayName ?? "代码托管平台")
                        .font(.headline)
                    if let locator = model.locator {
                        Text(locator.fullPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let locator = model.locator, locator.host != "github.com", locator.host != "gitee.com" {
                    // 自建实例的域名值得显示出来，方便用户确认连的是哪一台
                    Text(locator.host)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if model.hasToken {
                Picker("", selection: $model.filter) {
                    Text("进行中").tag(PullRequest.State?.some(.open))
                    Text("已合并").tag(PullRequest.State?.some(.merged))
                    Text("全部").tag(PullRequest.State?.none)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                .onChange(of: model.filter) { _, _ in Task { await model.load() } }

                Button {
                    isCreating = true
                } label: {
                    Label("新建 \(model.noun)", systemImage: "plus")
                }
                .disabled(model.currentBranchName == nil)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.locator == nil {
            EmptyStateView(
                "认不出这个仓库的托管平台",
                systemImage: "questionmark.circle",
                description: model.errorMessage ?? "目前支持 GitHub、GitLab（含自建）、Gitee。",
                tone: .warning
            )
        } else if !model.hasToken {
            tokenSetup
        } else if model.requests.isEmpty {
            EmptyStateView(
                "没有\(model.filter == .open ? "进行中的" : "")\(model.noun)",
                systemImage: "tray",
                description: "在当前分支上推送后可以新建一个"
            )
        } else {
            List(model.requests) { request in
                RequestRow(request: request, noun: model.noun) { model.open(request) }
            }
            .listStyle(.inset)
        }
    }

    private var tokenSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("需要一个访问令牌")
                .font(.headline)

            Text(tokenHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("访问令牌", text: $tokenDraft)
                .textFieldStyle(.roundedBorder)

            Label("令牌存放在系统钥匙串，按主机名保存，不会写进配置文件。", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("保存") {
                    Task {
                        await model.saveToken(tokenDraft)
                        tokenDraft = ""
                    }
                }
                .disabled(tokenDraft.isEmpty)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 各家令牌的权限要求不同，直接写清楚，省得用户建了个没权限的。
    private var tokenHint: String {
        switch model.locator?.kind {
        case .github:
            "在 GitHub 的 Settings → Developer settings → Personal access tokens 生成，权限勾选 repo。"
        case .gitlab:
            "在 GitLab 的 用户设置 → 访问令牌 生成，作用域勾选 api。自建实例在自己的域名下操作。"
        case .gitee:
            "在 Gitee 的 设置 → 私人令牌 生成，权限勾选 projects 和 pull_requests。"
        case nil:
            ""
        }
    }

    private var footer: some View {
        HStack {
            if let error = model.errorMessage, model.locator != nil {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            Spacer()

            if model.hasToken {
                Button("移除令牌") { Task { await model.removeToken() } }
                Button("刷新") { Task { await model.load() } }
            }

            Button("关闭") { onDismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }
}

// MARK: - 一条 PR / MR

private struct RequestRow: View {

    let request: PullRequest
    let noun: String
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if request.isDraft {
                        Text("草稿")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: .capsule)
                    }
                    Text(request.title)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text("\(noun) #\(request.number)")
                    Text("·")
                    Text(request.authorName)
                    Text("·")
                    Text("\(request.sourceBranch) → \(request.targetBranch)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let createdAt = request.createdAt {
                Text(createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .help("在浏览器中打开")
    }

    private var icon: String {
        switch request.state {
        case .open: request.isDraft ? "circle.dashed" : "arrow.triangle.pull"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle"
        }
    }

    private var tint: Color {
        switch request.state {
        case .open: request.isDraft ? .secondary : .green
        case .merged: .purple
        case .closed: .red
        }
    }
}

// MARK: - 新建

private struct CreateRequestSheet: View {

    @Bindable var model: ForgeViewModel
    let onDismiss: () -> Void

    @State private var title = ""
    /// PR 正文。不叫 body 是因为会和 SwiftUI 的 `body` 撞名；
    /// description 也正是 GitLab 对这个字段的叫法。
    @State private var description = ""
    @State private var target = "main"
    @State private var isDraft = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建 \(model.locator?.kind.requestNoun ?? "Pull Request")")
                .font(.headline)

            Form {
                LabeledContent("来源分支") {
                    Text(model.currentBranchName ?? "（无）")
                        .foregroundStyle(.secondary)
                }
                TextField("目标分支", text: $target)
                TextField("标题", text: $title)
                Toggle("作为草稿创建", isOn: $isDraft)
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 4) {
                Text("说明（可选）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $description)
                    .font(.callout)
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.separator) }
            }

            Label("创建后会在浏览器里打开", systemImage: "safari")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("创建") {
                    Task {
                        isWorking = true
                        let ok = await model.create(
                            title: title, body: description, target: target, isDraft: isDraft)
                        isWorking = false
                        if ok { onDismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.isEmpty || target.isEmpty || isWorking)
            }
        }
        .padding(16)
        .frame(width: 520)
    }
}
