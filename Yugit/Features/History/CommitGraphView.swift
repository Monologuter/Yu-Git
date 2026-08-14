import AppKit
import GitKit
import SwiftUI

/// 提交历史列表，用 AppKit 实现。
///
/// 这是全项目仅有的两处 AppKit 之一（另一处是 diff 查看器）。SwiftUI 的 List 在
/// 5 万行量级下达不到 PRD 要求的 60fps 滚动，而 `NSTableView` 的行复用机制天生
/// 为此而生：无论历史多长，同一时刻只存在一屏的视图。
struct CommitHistoryView: NSViewRepresentable {

    let commits: [Commit]
    let graph: CommitGraph
    @Binding var selection: Commit.ID?
    /// 滚动接近底部时触发，用于增量加载更多历史。
    let onReachEnd: () -> Void
    /// 右键某一行时选了 Quick Action。
    let onQuickAction: (QuickAction, Commit) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = CommitTableView()
        table.style = .inset
        table.headerView = nil
        table.rowHeight = Coordinator.rowHeight
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.intercellSpacing = NSSize(width: 0, height: 0)

        let column = NSTableColumn(identifier: Coordinator.columnID)
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        table.dataSource = context.coordinator
        table.delegate = context.coordinator

        // 右键菜单。NSTableView 会把 clickedRow 设成右键那一行，
        // 所以菜单项不需要自己记住是谁被点了。
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu

        // ⌘C 复制选中提交的完整 hash。这是从历史里取一个 hash 拿去
        // cherry-pick、revert、粘给同事时最常做的一步，
        // 让人先点开右边的详情面板再找复制按钮实在绕。
        table.onCopySelection = { [weak coordinator = context.coordinator] in
            guard let coordinator, let table = coordinator.table else { return }
            let row = table.selectedRow
            guard coordinator.parent.commits.indices.contains(row) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(
                coordinator.parent.commits[row].hash, forType: .string)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        context.coordinator.table = table
        context.coordinator.observeScrolling(in: scrollView)
        context.coordinator.observeThemeChanges()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let previousCount = coordinator.parent.commits.count
        coordinator.parent = self

        // 只在内容真的变了时才 reload：滚动过程中无谓的 reload 会掉帧
        if previousCount != commits.count || coordinator.needsReload {
            coordinator.needsReload = false
            coordinator.table?.reloadData()
        }

        coordinator.syncSelection(selection)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {

        static let rowHeight: CGFloat = 44
        static let columnID = NSUserInterfaceItemIdentifier("commit")

        var parent: CommitHistoryView
        weak var table: NSTableView?
        var needsReload = false

        /// 避免「程序设置选中」反过来又触发一次选中回调。
        private var isSyncingSelection = false

        init(_ parent: CommitHistoryView) {
            self.parent = parent
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.commits.count
        }

        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard parent.commits.indices.contains(row) else { return nil }

            // 复用：NSTableView 只为可见行创建视图，这是 5 万行仍能流畅滚动的关键
            let cell =
                tableView.makeView(withIdentifier: Self.columnID, owner: self) as? CommitCellView
                ?? CommitCellView(identifier: Self.columnID)

            cell.configure(
                commit: parent.commits[row],
                graphRow: parent.graph.rows.indices.contains(row) ? parent.graph.rows[row] : nil,
                laneCount: parent.graph.maximumLaneCount
            )
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let table else { return }
            let row = table.selectedRow
            parent.selection = parent.commits.indices.contains(row) ? parent.commits[row].id : nil
        }

        func syncSelection(_ id: Commit.ID?) {
            guard let table else { return }
            let targetRow = id.flatMap { identifier in
                parent.commits.firstIndex { $0.id == identifier }
            }

            isSyncingSelection = true
            defer { isSyncingSelection = false }

            if let targetRow {
                if table.selectedRow != targetRow {
                    table.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
                    table.scrollRowToVisible(targetRow)
                }
            } else if table.selectedRow != -1 {
                table.deselectAll(nil)
            }
        }

        // MARK: - 右键菜单

        /// 每次弹出时重建菜单：可用的动作取决于点的是哪一行
        /// （最新那条没法并进父提交，最旧那条要留作落脚点），
        /// 建一次然后一直用会把上一行的可用性带到这一行。
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()

            let row = table?.clickedRow ?? -1
            guard parent.commits.indices.contains(row) else { return }

            let header = NSMenuItem(
                title: parent.commits[row].subject, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())

            for action in QuickAction.allCases {
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(runQuickAction(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = action
                item.image = NSImage(
                    systemSymbolName: action.systemImage, accessibilityDescription: nil)
                item.isEnabled = action.isAvailable(at: row, loadedCount: parent.commits.count)
                item.toolTip = action.explanation
                menu.addItem(item)
            }

            // 复制 hash 也放进菜单，不只是给一个藏起来的 ⌘C。
            // 键盘快捷键不写在任何地方的话没人会知道它存在，
            // 而菜单项自带的快捷键标注正好把它教出来。
            menu.addItem(.separator())
            let copyItem = NSMenuItem(
                title: "复制完整 hash",
                action: #selector(copyHash(_:)),
                keyEquivalent: "c"
            )
            copyItem.keyEquivalentModifierMask = .command
            copyItem.target = self
            copyItem.toolTip = parent.commits[row].hash
            menu.addItem(copyItem)
        }

        @objc private func copyHash(_ sender: NSMenuItem) {
            guard let row = table?.clickedRow,
                parent.commits.indices.contains(row)
            else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(parent.commits[row].hash, forType: .string)
        }

        @objc private func runQuickAction(_ sender: NSMenuItem) {
            guard
                let action = sender.representedObject as? QuickAction,
                let row = table?.clickedRow,
                parent.commits.indices.contains(row)
            else { return }

            parent.onQuickAction(action, parent.commits[row])
        }

        // MARK: - 主题

        /// 换主题时重绘整张表。
        ///
        /// AppKit 不在 SwiftUI 的依赖追踪里：`Theme.Colors` 的值变了，
        /// 已经画在屏幕上的行不会自己知道。SwiftUI 那边靠 @Observable 自动重绘，
        /// 这边只能收到通知后自己 reload。
        func observeThemeChanges() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(themeDidChange),
                name: ThemeManager.themeDidChange,
                object: nil
            )
        }

        @objc private func themeDidChange() {
            table?.reloadData()
        }

        // MARK: - 增量加载

        func observeScrolling(in scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                let documentHeight = clipView.documentView?.bounds.height
            else { return }

            // 距底部不到两屏就预加载，等滚到底再加载会看到明显的空白
            let visibleBottom = clipView.bounds.maxY
            let threshold = documentHeight - clipView.bounds.height * 2
            guard visibleBottom >= threshold else { return }

            parent.onReachEnd()
        }
    }
}

/// 单行：分支图 + 提交信息。
///
/// 元信息拆成三个独立 label 而不是拼成一个字符串。拼字符串省事，
/// 但那样三样东西必然同字号同颜色——想让 hash 更淡、时间右对齐都做不到，
/// 眼睛扫下来也就分不出哪个重要。
final class CommitCellView: NSTableCellView {

    private let graphView = LaneGraphView()
    private let subjectLabel = NSTextField(labelWithString: "")
    private let hashLabel = NSTextField(labelWithString: "")
    private let authorLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")

    /// 每条轨道的水平间距（轨道不多时用这个值）。
    static let laneWidth: CGFloat = 14
    /// 图形区最窄宽度，避免线性历史时信息贴着左边缘。
    static let minimumGraphWidth: CGFloat = 24

    /// 图形区最宽多少。
    ///
    /// **必须有上限**，否则提交标题会被挤没。轨道数取的是整个已加载历史的
    /// 最大并行数，不是当前这一屏的——一个有几十个分支的仓库里，只要历史中
    /// 某处并行过八条轨道，每一行都会留出 112pt 图形区，哪怕眼前这一屏
    /// 全是单线提交。中间栏总共才 260pt 上下，扣掉之后标题只剩几十 pt，
    /// 整列就会变成「fix(proj...」「Merge...」这种读不出内容的样子。
    ///
    /// 84pt 是权衡的结果：够画 6 条等宽轨道，覆盖绝大多数仓库的日常形态；
    /// 再多就靠压缩轨道间距容纳，宁可线挤一点，也不能让标题看不见——
    /// 分支图是辅助信息，提交标题才是这个列表存在的理由。
    static let maximumGraphWidth: CGFloat = 84
    /// 轨道再挤也不能细过这个值，否则相邻两条线会糊成一条。
    static let minimumLaneWidth: CGFloat = 5

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        subjectLabel.lineBreakMode = .byTruncatingTail
        subjectLabel.font = Theme.NSFonts.body
        // 标题该截断就截断，不许它反过来把图形区挤窄。
        //
        // 默认的压缩阻力是 750，和图形区宽度约束打平——打平时 Auto Layout
        // 的取舍就取决于标题长短，结果是标题长的行把图形区挤扁、短的不挤，
        // 整列的左边界会一行一个样，在滚动时看着像在左右抖。
        // 图形区宽度必须是全列一致的，那是"同一条轨道在相邻行要能连上"的前提。
        subjectLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        authorLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // hash 用等宽，**只有它用**。等宽字体渲染中文（人名、提交标题）
        // 字距会很难看：中文字形本身就是等宽的，再套一层西文等宽只会破坏节奏。
        hashLabel.font = Theme.NSFonts.mono
        hashLabel.textColor = .tertiaryLabelColor

        authorLabel.lineBreakMode = .byTruncatingTail
        authorLabel.font = Theme.NSFonts.secondary
        authorLabel.textColor = .secondaryLabelColor

        // 时间右对齐：不这么做的话，每行的视觉右边界随作者名长度参差不齐，
        // 快速扫读时间线时眼睛得来回找。
        dateLabel.font = Theme.NSFonts.secondary
        dateLabel.textColor = .tertiaryLabelColor
        dateLabel.alignment = .right
        // 时间是固定要显示完整的，作者名可以被挤掉
        dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        dateLabel.setContentHuggingPriority(.required, for: .horizontal)
        hashLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        hashLabel.setContentHuggingPriority(.required, for: .horizontal)

        for view in [graphView, subjectLabel, hashLabel, authorLabel, dateLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        graphWidthConstraint = graphView.widthAnchor.constraint(
            equalToConstant: Self.minimumGraphWidth)
        // 比标题的压缩阻力高，比下面那条「不超过三分之一行宽」的硬上限低。
        // 夹在中间：正常情况下宽度说一不二，只有窄到超过三分之一时才让步。
        graphWidthConstraint.priority = NSLayoutConstraint.Priority(900)

        let inset = Theme.Spacing.regular

        NSLayoutConstraint.activate([
            // 无论轨道多少，图形区都不许吃掉超过三分之一的行宽。
            // 用约束而不是在 configure 里按宽度算：栏宽是可以被用户随手拖的，
            // 靠计算的话每拖一次都得 reloadData 才能生效，而这条约束
            // 是 Auto Layout 自己实时算的，拖动过程中就跟着让位。
            graphView.widthAnchor.constraint(
                lessThanOrEqualTo: widthAnchor, multiplier: 0.34)
        ])

        NSLayoutConstraint.activate([
            graphView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.tight),
            graphView.topAnchor.constraint(equalTo: topAnchor),
            graphView.bottomAnchor.constraint(equalTo: bottomAnchor),
            graphWidthConstraint,

            subjectLabel.leadingAnchor.constraint(equalTo: graphView.trailingAnchor, constant: inset),
            subjectLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
            subjectLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.tight + 1),

            hashLabel.leadingAnchor.constraint(equalTo: subjectLabel.leadingAnchor),
            hashLabel.topAnchor.constraint(
                equalTo: subjectLabel.bottomAnchor, constant: Theme.Spacing.hairline),

            authorLabel.leadingAnchor.constraint(
                equalTo: hashLabel.trailingAnchor, constant: Theme.Spacing.regular),
            authorLabel.firstBaselineAnchor.constraint(equalTo: hashLabel.firstBaselineAnchor),

            // 作者和时间之间留一个最小间距，作者名过长时先截断作者
            dateLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: authorLabel.trailingAnchor, constant: Theme.Spacing.regular),
            dateLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            dateLabel.firstBaselineAnchor.constraint(equalTo: hashLabel.firstBaselineAnchor),
        ])
    }

    private var graphWidthConstraint = NSLayoutConstraint()

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 加载")
    }

    /// 行被选中时 AppKit 会把这个属性切到 `.emphasized`。
    ///
    /// 必须跟着改前景色：`secondaryLabelColor` / `tertiaryLabelColor` 这类
    /// 语义色是为**浅色背景**调的灰阶，直接画在强调色选中背景上对比度不够，
    /// 看起来像是"变灰了"。分支图同理，交给它自己处理。
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let emphasized = backgroundStyle == .emphasized
            subjectLabel.textColor = emphasized ? Theme.Colors.onEmphasized : .labelColor
            authorLabel.textColor =
                emphasized
                ? Theme.Colors.onEmphasized.withAlphaComponent(0.85) : .secondaryLabelColor
            let faded: NSColor =
                emphasized
                ? Theme.Colors.onEmphasized.withAlphaComponent(0.7) : .tertiaryLabelColor
            hashLabel.textColor = faded
            dateLabel.textColor = faded

            graphView.isEmphasized = emphasized
            graphView.needsDisplay = true
        }
    }

    func configure(commit: Commit, graphRow: CommitGraph.Row?, laneCount: Int) {
        graphView.row = graphRow

        // 轨道多到放不下时压缩间距，而不是把图形区一路撑宽去挤占标题。
        // 间距对所有行必须一致，否则同一条轨道在相邻两行会错位、连不上线。
        let lanes = max(laneCount, 1)
        let laneWidth = max(
            Self.minimumLaneWidth,
            min(Self.laneWidth, Self.maximumGraphWidth / CGFloat(lanes))
        )
        graphView.laneWidth = laneWidth
        graphView.needsDisplay = true

        graphWidthConstraint.constant = min(
            max(Self.minimumGraphWidth, CGFloat(lanes) * laneWidth),
            Self.maximumGraphWidth
        )

        subjectLabel.stringValue = commit.subject
        hashLabel.stringValue = commit.abbreviatedHash
        authorLabel.stringValue = commit.author.name
        dateLabel.stringValue = Self.relativeFormatter.localizedString(
            for: commit.author.date, relativeTo: Date())
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}

/// 画一行的轨道与连线。
final class LaneGraphView: NSView {

    var row: CommitGraph.Row?

    /// 这一行是否处于「选中且窗口活跃」状态。
    ///
    /// 影响很大：选中行的背景是系统强调色（默认蓝），
    /// 而轨道配色的第一个颜色恰好也是 `.systemBlue`——
    /// 不做处理的话蓝线画在蓝底上等于消失，只剩节点中间那个掏空的洞，
    /// 看起来像界面出了 bug。
    var isEmphasized = false

    /// 轨道间距。由 cell 按当前轨道总数算好后传进来——
    /// 轨道多时会被压缩，所以不能在这里读那个常量。
    var laneWidth: CGFloat = CommitCellView.laneWidth

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let row else { return }

        // 轨道数超出上限时，多出来的部分会落在 bounds 之外。
        // 显式裁剪，免得线画到标题上去。
        NSBezierPath(rect: bounds).setClip()

        let height = bounds.height
        let middle = height / 2

        func centerX(of lane: Int) -> CGFloat {
            CGFloat(lane) * laneWidth + laneWidth / 2
        }

        // 选中态下放弃区分轨道颜色，全部用能压住强调色背景的前景色。
        // 丢掉的颜色信息只影响当前这一行，而这一行本来就靠背景高亮
        // 就能一眼定位；相比之下"看不见"是更严重的问题。
        func color(at index: Int) -> NSColor {
            isEmphasized
                ? Theme.Colors.onEmphasized
                : Theme.Colors.lanes[index % Theme.Colors.lanes.count]
        }

        // 先画线，节点压在线上面
        for link in row.links {
            color(at: link.colorIndex).setStroke()

            let path = NSBezierPath()
            path.lineWidth = Theme.Colors.laneLineWidth
            path.lineCapStyle = .round

            let fromX = centerX(of: link.fromLane)
            let toX = centerX(of: link.toLane)

            if link.fromLane == link.toLane {
                path.move(to: CGPoint(x: fromX, y: 0))
                path.line(to: CGPoint(x: fromX, y: height))
            } else {
                // 用曲线而非折线：分叉处更顺眼，也更接近 Fork 那种观感
                path.move(to: CGPoint(x: fromX, y: 0))
                path.curve(
                    to: CGPoint(x: toX, y: height),
                    controlPoint1: CGPoint(x: fromX, y: middle),
                    controlPoint2: CGPoint(x: toX, y: middle)
                )
            }
            path.stroke()
        }

        // 提交节点
        let radius = Theme.Colors.laneNodeRadius
        let nodeRect = NSRect(
            x: centerX(of: row.nodeLane) - radius,
            y: middle - radius,
            width: radius * 2,
            height: radius * 2
        )
        color(at: row.colorIndex).setFill()
        NSBezierPath(ovalIn: nodeRect).fill()

        // 中间掏空，让节点在密集的线里也能辨认。
        // 选中态下要掏成背景的强调色而不是 textBackgroundColor（白），
        // 否则蓝底上会出现一个刺眼的白点——正是改之前那个样子。
        if isEmphasized {
            Theme.Colors.laneNodeCoreOnSelection.setFill()
        } else {
            Theme.Colors.laneNodeCore.setFill()
        }
        NSBezierPath(ovalIn: nodeRect.insetBy(dx: 1.6, dy: 1.6)).fill()
    }
}

/// 带键盘操作的提交表格。
///
/// `NSTableView` 本身就认 ↑↓、Page Up/Down、Home/End，这些不用管也不该改——
/// 覆盖系统已有的键只会让人重新学。这里只补两样它没有的：
/// vim 风格的 j/k，以及 ⌘C 复制 hash。
final class CommitTableView: NSTableView {

    /// ⌘C 时调用。
    var onCopySelection: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // 只认不带任何修饰键的 j/k。带上修饰键的组合都是别人的地盘：
        // ⌘J、⌥K 之类可能是菜单快捷键，抢过来会让那些菜单项失灵。
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.isEmpty {
            switch event.charactersIgnoringModifiers {
            case "j":
                moveSelection(by: 1)
                return
            case "k":
                moveSelection(by: -1)
                return
            default:
                break
            }
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "c",
            selectedRow >= 0
        {
            onCopySelection?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// 上下移动选中行。
    ///
    /// 还没有任何选中时，无论按 j 还是 k 都落到第一行——
    /// 此时列表顶端就在眼前，从那里开始最符合预期。
    private func moveSelection(by delta: Int) {
        guard numberOfRows > 0 else { return }

        let target: Int
        if selectedRow < 0 {
            target = 0
        } else {
            target = selectedRow + delta
        }

        guard target >= 0, target < numberOfRows else { return }
        selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        scrollRowToVisible(target)
    }
}
