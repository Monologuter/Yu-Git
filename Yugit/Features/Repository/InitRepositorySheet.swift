import GitKit
import SwiftUI

/// 新建仓库的确认面板。
///
/// 存在的唯一理由是**把 git 不说的话说出来**。`git init` 在两种情况下
/// 会一声不吭地做出用户没想要的事：目录已经是仓库时把它重新初始化一遍，
/// 目录在别的仓库里面时造出一个嵌套仓库。两种都以 0 退出。
struct InitRepositorySheet: View {

    let pending: AppModel.PendingInit
    let model: AppModel
    let onDismiss: () -> Void

    /// 默认分支名。
    ///
    /// 预填 `main` 而不是读用户的 `init.defaultBranch`：那个配置很多人没设，
    /// 没设时 git 用 `master` 并打一段警告。与其把这个历史包袱转嫁给用户，
    /// 不如给一个明确的默认值，同时留出改的余地。
    @State private var branch = "main"

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.loose) {
            Label("新建仓库", systemImage: "folder.badge.plus")
                .font(Theme.Font.title)

            Text(pending.directory.path)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if let obstacle = pending.obstacle {
                ObstacleNotice(obstacle: obstacle)
            }

            if pending.obstacle?.isBlocking != true {
                HStack(spacing: Theme.Spacing.regular) {
                    Text("默认分支")
                        .font(Theme.Font.body)
                    TextField("main", text: $branch)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                }

                EquivalentCommand(
                    GitOperation.initRepository(
                        initialBranch: branch.isEmpty ? "main" : branch
                    ).equivalentCommand
                )
            }

            HStack {
                Spacer()
                Button(pending.obstacle?.isBlocking == true ? "好" : "取消", role: .cancel) {
                    onDismiss()
                }
                if pending.obstacle?.isBlocking != true {
                    Button("新建") {
                        model.createRepository(
                            at: pending.directory,
                            initialBranch: branch.trimmingCharacters(in: .whitespaces).isEmpty
                                ? "main" : branch.trimmingCharacters(in: .whitespaces)
                        )
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(Theme.Spacing.section)
        .frame(width: 480)
    }
}

/// 事前检查发现的问题。
private struct ObstacleNotice: View {

    let obstacle: InitObstacle

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.regular) {
            Image(systemName: obstacle.isBlocking ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(obstacle.isBlocking ? Theme.Colors.warning : Theme.Colors.brand)

            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                Text(title)
                    .font(Theme.Font.body)
                Text(detail)
                    .font(Theme.Font.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            obstacle.isBlocking ? Theme.Colors.warningWash : Theme.Colors.brandWash,
            in: .rect(cornerRadius: Theme.Radius.medium)
        )
    }

    private var title: String {
        switch obstacle {
        case .alreadyARepository: "这个目录已经是一个 Git 仓库"
        case .insideRepository: "这个目录在另一个仓库里面"
        case .directoryNotEmpty(let count): "目录里已经有 \(count) 个文件"
        }
    }

    private var detail: String {
        switch obstacle {
        case .alreadyARepository:
            "直接打开它就行。在已有仓库上再执行 init 不会报错，"
                + "但那只是把它重新初始化一遍，不会得到一个新仓库。"
        case .insideRepository(let root):
            "外层仓库在 \(root)。在这里新建会得到一个**嵌套仓库**——"
                + "里层是独立仓库，外层只把它看成一个未跟踪的目录。"
                + "如果本意是把这部分独立出去，正确的做法是 submodule。"
        case .directoryNotEmpty:
            "这些文件不会被自动纳入版本控制，它们会以「未跟踪」的身份出现，由你决定哪些要提交。"
        }
    }
}
