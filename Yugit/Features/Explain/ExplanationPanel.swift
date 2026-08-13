import AIKit
import SwiftUI

/// 「用中文讲讲这是什么」的面板。
///
/// 默认收起。展开一次才发一次请求——AI 铁律：只有用户主动要，才把内容发出去。
/// 折叠状态不缓存结果，因为改动会变；但同一次展开期间不会重复请求。
struct ExplanationPanel: View {

    /// 面板标题，例如「这次 commit 做了什么」。
    let title: String
    /// 生成解释的请求。每次展开时调用。
    ///
    /// 是 async 的：解释一次 commit 需要先把它的 diff 取出来，而那是一次 git 调用。
    let makeSubject: () async throws -> Explainer.Subject

    @Environment(AISettingsStore.self) private var aiSettings

    @State private var isExpanded = false
    @State private var text = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        // 没配 AI 就整块不出现，界面上不留任何 AI 痕迹
        if aiSettings.isAvailable {
            VStack(alignment: .leading, spacing: 8) {
                header

                if isExpanded {
                    content
                }
            }
            .padding(12)
            .background(Color(nsColor: .underPageBackgroundColor), in: .rect(cornerRadius: 8))
            .onDisappear {
                // 切走就别再烧 token 了
                task?.cancel()
            }
        }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
            if isExpanded && text.isEmpty && !isLoading { start() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                Button("重试") { start() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        } else if text.isEmpty && isLoading {
            Text("正在阅读改动…")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !isLoading {
                    // AI 会出错，这句提醒必须一直在——不是免责声明，是让用户
                    // 保持「以代码为准」的习惯
                    Label("AI 生成的解释可能有误，请以代码为准", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func start() {
        task?.cancel()
        text = ""
        errorMessage = nil
        isLoading = true

        guard let (provider, model) = aiSettings.makeProvider() else {
            errorMessage = AIError.notConfigured.localizedMessage
            isLoading = false
            return
        }

        task = Task {
            do {
                // 先取上下文（可能是一次 git 调用），再发请求
                let subject = try await makeSubject()
                let stream = Explainer(provider: provider, model: model).explain(subject).text
                for try await delta in stream {
                    text += delta
                }
            } catch let error as AIError {
                errorMessage = "\(error.localizedMessage)\n\(error.suggestion)"
            } catch is CancellationError {
                // 用户折叠或切走，不是错误
            } catch {
                errorMessage = "\(error)"
            }
            isLoading = false
        }
    }
}
