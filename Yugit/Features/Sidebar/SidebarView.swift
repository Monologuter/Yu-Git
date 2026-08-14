import GitKit
import SwiftUI

/// 左栏：本地分支、远程分支、tag。
struct SidebarView: View {

    @Bindable var repository: RepositoryViewModel

    @State private var newBranchName = ""
    @State private var isCreatingBranch = false
    @State private var renaming: Branch?
    @State private var renamedName = ""
    @State private var pendingDelete: Branch?
    @State private var pendingTagDelete: Tag?

    @State private var filter = ""
    @AppStorage("com.chenya.yugit.sidebar.remoteExpanded") private var isRemoteExpanded = false
    @AppStorage("com.chenya.yugit.sidebar.tagsExpanded") private var isTagsExpanded = false

    // MARK: - 过滤

    /// 本地分支：当前分支永远置顶，其余保持仓库给的顺序（按最后提交时间倒序）。
    ///
    /// 置顶是因为「我现在在哪个分支上」是侧栏里最高频要确认的一件事。
    /// 光靠时间排序不够：切到一个很久没动的分支后，它会沉到几十个分支的末尾，
    /// 而那恰恰是你此刻正站着的地方。
    private var filteredLocalBranches: [Branch] {
        let matched = repository.localBranches.filter { matches($0.name) }
        guard let currentIndex = matched.firstIndex(where: \.isCurrent) else { return matched }
        var reordered = matched
        reordered.insert(reordered.remove(at: currentIndex), at: 0)
        return reordered
    }

    private var filteredRemoteBranches: [Branch] {
        repository.remoteBranches.filter { matches($0.name) }
    }

    private var filteredTags: [Tag] {
        repository.tags.filter { matches($0.name) }
    }

    /// 子串匹配，忽略大小写与变音符号。
    ///
    /// 不做模糊匹配（fuzzy）：分支名里的 `-` `/` 本身有结构含义，
    /// 模糊匹配会让 `dev` 命中 `d-e-v` 这类无关的名字，反而更难找。
    private func matches(_ name: String) -> Bool {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterField(text: $filter, placeholder: "过滤分支与标签")
                .padding(.horizontal, Theme.Spacing.regular)
                .padding(.vertical, Theme.Spacing.tight + 2)

            Divider()

            list
        }
        // 侧栏是整个窗口唯一半透明的一栏。
        //
        // 材质要盖住**整栏**，包括顶部的过滤框——只给列表加的话，
        // 过滤框那一条会落在不透明的窗口底色上，接缝一眼就看得出来。
        .background(VisualEffectBackground())
    }

    private var list: some View {
        List {
            Section {
                if filteredLocalBranches.isEmpty {
                    EmptyHint(repository.localBranches.isEmpty ? "尚无分支" : "没有匹配的分支")
                } else {
                    ForEach(filteredLocalBranches) { branch in
                        BranchRow(branch: branch)
                            .contextMenu { localBranchMenu(for: branch) }
                    }
                }
            } header: {
                HStack {
                    Text("本地分支")
                    Spacer()
                    Button {
                        newBranchName = ""
                        isCreatingBranch = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("新建分支")
                }
            }

            if !filteredRemoteBranches.isEmpty {
                // 远程分支常有几十个，默认折叠起来。
                // 展开状态记在 @AppStorage 里——每次打开仓库都要重新收一次，
                // 那种小烦躁累积起来很伤。
                Section(isExpanded: $isRemoteExpanded) {
                    ForEach(filteredRemoteBranches) { branch in
                        BranchRow(branch: branch)
                            .contextMenu { remoteBranchMenu(for: branch) }
                    }
                } header: {
                    HStack {
                        Text("远程分支")
                        Text("\(filteredRemoteBranches.count)")
                            .font(Theme.Font.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !filteredTags.isEmpty {
                Section(isExpanded: $isTagsExpanded) {
                    ForEach(filteredTags) { tag in
                        TagRow(tag: tag)
                            .contextMenu { tagMenu(for: tag) }
                    }
                } header: {
                    HStack {
                        Text("标签")
                        Text("\(filteredTags.count)")
                            .font(Theme.Font.secondary)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // 列表自己那层底要撤掉，否则它会盖在材质上，半透明就白做了
        .scrollContentBackground(.hidden)
        .alert("新建分支", isPresented: $isCreatingBranch) {
            TextField("分支名", text: $newBranchName)
            Button("创建并切换") {
                let name = newBranchName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await repository.createBranch(named: name) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("从当前 HEAD 新建分支。")
        }
        .alert(
            "重命名分支",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )
        ) {
            TextField("新名字", text: $renamedName)
            Button("重命名") {
                guard let branch = renaming else { return }
                let name = renamedName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name != branch.name else { return }
                Task { await repository.renameBranch(from: branch.name, to: name) }
                renaming = nil
            }
            Button("取消", role: .cancel) { renaming = nil }
        } message: {
            // 远程分支不会跟着改名，这一点必须说清楚
            Text("只改本地分支名。若它已推送到远程，远程那边的名字不会跟着变。")
        }
        .confirmationDialog(
            "确定删除分支？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { branch in
            Button("删除 \(branch.name)", role: .destructive) {
                Task { await repository.deleteBranch(named: branch.name) }
                pendingDelete = nil
            }
            Button("强制删除（含未合并的提交）", role: .destructive) {
                Task { await repository.deleteBranch(named: branch.name, force: true) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("普通删除会在分支还有未合并提交时被 git 拒绝；强制删除后那些提交只能靠 reflog 找回。")
        }
        .confirmationDialog(
            "确定删除标签？",
            isPresented: Binding(
                get: { pendingTagDelete != nil },
                set: { if !$0 { pendingTagDelete = nil } }
            ),
            presenting: pendingTagDelete
        ) { tag in
            Button("删除 \(tag.name)", role: .destructive) {
                Task { await repository.deleteTag(named: tag.name) }
                pendingTagDelete = nil
            }
            Button("取消", role: .cancel) { pendingTagDelete = nil }
        } message: { _ in
            Text(
                "只删掉本地这个标签名，它指向的提交不受影响。如果这个标签已经推送过，"
                    + "远程那边还留着，下次 fetch 会把它拉回来。")
        }
    }

    // MARK: - 菜单

    @ViewBuilder
    private func localBranchMenu(for branch: Branch) -> some View {
        if !branch.isCurrent {
            Button("切换到 \(branch.name)") {
                Task { await repository.switchBranch(to: branch.name) }
            }
            Button("合并 \(branch.name) 到当前分支") {
                Task { await repository.merge(branch.name) }
            }
            Divider()
        }

        Button("重命名…") {
            renamedName = branch.name
            renaming = branch
        }

        if !branch.isCurrent {
            Button("删除…", role: .destructive) { pendingDelete = branch }
        }
    }

    @ViewBuilder
    private func tagMenu(for tag: Tag) -> some View {
        Button("推送 \(tag.name) 到 origin") {
            Task { await repository.pushTag(named: tag.name) }
        }
        Divider()
        // 只删本地。删远程 tag 影响的是别人——已经拉过的人本地那份不会消失，
        // 之后同名 tag 就会在不同人手上指向不同的东西。那一步不放在这个
        // 顺手就能点到的菜单里。
        Button("删除本地的 \(tag.name)", role: .destructive) {
            pendingTagDelete = tag
        }
    }

    @ViewBuilder
    private func remoteBranchMenu(for branch: Branch) -> some View {
        // origin/main → main
        let localName = branch.name.split(separator: "/").dropFirst().joined(separator: "/")

        Button("基于它新建本地分支") {
            guard !localName.isEmpty else { return }
            Task { await repository.createBranch(named: localName, from: branch.name) }
        }
        Button("合并到当前分支") {
            Task { await repository.merge(branch.name) }
        }
    }
}

struct BranchRow: View {

    let branch: Branch

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: branch.isRemote ? "cloud" : "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(branch.isCurrent ? Theme.Colors.brand : Theme.Colors.secondaryText)
                .frame(width: 14)

            Text(branch.name)
                .fontWeight(branch.isCurrent ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            trackingBadge
        }
        // 当前分支：图标换品牌靛 + 左侧一根竖标。
        //
        // 「我现在在哪个分支上」是侧栏里最高频要确认的一件事，光靠加粗不够快——
        // 几十个分支排在一起时，字重差别要盯着看才分辨得出来。竖标是唯一
        // 在余光里也能定位的信号。用品牌色而不是强调色：强调色归选中态，
        // 两者同屏时必须能区分「我站在这」和「我点了这」。
        .overlay(alignment: .leading) {
            if branch.isCurrent {
                Capsule()
                    .fill(Theme.Colors.brand)
                    .frame(width: 2)
                    .padding(.vertical, 1)
                    .offset(x: -6)
            }
        }
        .help(tooltip)
    }

    @ViewBuilder
    private var trackingBadge: some View {
        let tracking = branch.tracking
        if tracking.isGone {
            // upstream 被删了还留着配置，push 会失败，值得显眼提示
            Image(systemName: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if tracking.ahead > 0 || tracking.behind > 0 {
            HStack(spacing: 3) {
                if tracking.ahead > 0 {
                    Label("\(tracking.ahead)", systemImage: "arrow.up")
                }
                if tracking.behind > 0 {
                    Label("\(tracking.behind)", systemImage: "arrow.down")
                }
            }
            .labelStyle(.compact)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var tooltip: String {
        var lines = [branch.name]
        if let upstream = branch.upstream {
            lines.append("upstream：\(upstream)")
        }
        if branch.tracking.isGone {
            lines.append("upstream 已在远程被删除")
        } else if branch.tracking.hasDiverged {
            lines.append("已分叉：领先 \(branch.tracking.ahead)，落后 \(branch.tracking.behind)")
        }
        if !branch.lastCommitSubject.isEmpty {
            lines.append("最新提交：\(branch.lastCommitSubject)")
        }
        return lines.joined(separator: "\n")
    }
}

struct TagRow: View {

    let tag: Tag

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(tag.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if !tag.isAnnotated {
                // 工程规范要求发布用附注 tag，轻量 tag 标出来便于发现
                Text("轻量")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .help(tag.message ?? tag.name)
    }
}

/// 列表分组为空时的占位。
struct EmptyHint: View {

    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
    }
}

/// 图标与文字紧凑排列，用于角标这类窄空间。
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon
            configuration.title
        }
    }
}

extension LabelStyle where Self == CompactLabelStyle {
    static var compact: CompactLabelStyle { CompactLabelStyle() }
}

// MARK: - 过滤框

/// 侧栏顶部的过滤输入框。
///
/// 用自绘的输入框而不是 `.searchable`：后者在 macOS 上会把搜索框放进工具栏，
/// 而工具栏是全窗口共用的——过滤的明明只是侧栏这一列，控件却跑到了顶上，
/// 作用范围看不出来。放在它所影响的列的顶部，位置本身就说明了它管什么。
struct FilterField: View {

    @Binding var text: String
    let placeholder: String

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.tight + 2) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Font.secondary)
                .focused($isFocused)
                // 回车不该做任何事，但也不该让系统"咚"一声——
                // 输入框里没有默认动作可以触发
                .onSubmit {}

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("清空")
            }
        }
        .padding(.horizontal, Theme.Spacing.regular)
        .padding(.vertical, Theme.Spacing.tight + 1)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Theme.Radius.medium))
        .overlay {
            // 聚焦时描一圈强调色。系统的 .roundedBorder 在侧栏背景上太重，
            // 但完全没有焦点提示又会让人不确定键盘输入去了哪里。
            RoundedRectangle(cornerRadius: Theme.Radius.medium)
                .strokeBorder(isFocused ? Color.accentColor : .clear, lineWidth: 2)
        }
        .animation(.easeInOut(duration: 0.12), value: isFocused)
    }
}
