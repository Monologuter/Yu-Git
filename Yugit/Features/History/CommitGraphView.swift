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
    /// 右键某一行时选了挑取 / 撤销 / 重置 / 打标签。
    let onCommitAction: (CommitAction, Commit) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = CommitTableView()
        table.style = .inset
        table.headerView = nil
        table.rowHeight = Coordinator.commitRowHeight
        table.usesAlternatingRowBackgroundColors = false
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.intercellSpacing = NSSize(width: 0, height: 0)
        // 日期分组行滚到顶部时钉住。AppKit 的 group row 自带这个行为，
        // 自己实现要监听滚动再手动摆一个浮层，没必要。
        table.floatsGroupRows = true

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
            guard let coordinator, let table = coordinator.table,
                let commit = coordinator.commit(atRow: table.selectedRow)
            else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.hash, forType: .string)
        }

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        context.coordinator.table = table
        // 先切好行再交出去。`updateNSView` 只在内容变化时 reload，
        // 而首次进来时内容并没有"变过"——不在这里建好，第一屏会是空的。
        context.coordinator.rebuildRows()
        context.coordinator.observeScrolling(in: scrollView)
        context.coordinator.observeThemeChanges()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // 只在内容真的变了时才 reload：滚动过程中无谓的 reload 会掉帧。
        //
        // 判据交给 `rebuildRows()`，它本来就要判断「这是追加了一页
        // 还是整批换了」。之前这里比的是提交条数，那漏掉一种情况：
        // 换到一个恰好加载了同样条数的分支时，列表不会刷新。
        if coordinator.rebuildRows() || coordinator.needsReload {
            coordinator.needsReload = false
            coordinator.table?.reloadData()
        }

        coordinator.syncSelection(selection)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {

        static let commitRowHeight: CGFloat = 44
        static let dayGroupRowHeight: CGFloat = 24
        static let columnID = NSUserInterfaceItemIdentifier("commit")
        static let dayGroupID = NSUserInterfaceItemIdentifier("dayGroup")

        var parent: CommitHistoryView
        weak var table: NSTableView?
        var needsReload = false

        /// 提交列表原本是清一色 44pt 等高，那是 `NSTableView` 跑满 60fps 最省事的形态。
        /// 加入日期分组行意味着放弃固定行高——换来的是整列终于有了落点：
        /// 几百条长得一模一样的提交里，眼睛此前无处停留。
        ///
        /// 分组本身（下标算术）在 GitKit 里，那边有测试；这里只管画。
        private var history = DayGroupedHistory()

        /// 避免「程序设置选中」反过来又触发一次选中回调。
        private var isSyncingSelection = false

        init(_ parent: CommitHistoryView) {
            self.parent = parent
        }

        // MARK: - 行的构建

        /// - Returns: 行有没有变。调用方拿它决定要不要 `reloadData()`。
        @discardableResult
        func rebuildRows() -> Bool {
            history.update(with: parent.commits)
        }

        /// 分组行上写什么。
        ///
        /// 今天和昨天用词说，比「8月14日」认得快。跨年了带上年份，
        /// 否则「3月11日」会和去年的同一天混淆。
        private static func dayLabel(for date: Date) -> String {
            let calendar = Calendar.current
            if calendar.isDateInToday(date) { return "今天" }
            if calendar.isDateInYesterday(date) { return "昨天" }
            let sameYear = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
            return (sameYear ? CommitCellView.dayFormatter : CommitCellView.fullDateFormatter)
                .string(from: date)
        }

        /// 某一行对应哪条提交。分组行返回 nil。
        func commit(atRow row: Int) -> Commit? {
            commitIndex(atRow: row).map { parent.commits[$0] }
        }

        func commitIndex(atRow row: Int) -> Int? {
            guard let index = history.commitIndex(atRow: row),
                parent.commits.indices.contains(index)
            else { return nil }
            return index
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            history.rows.count
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard history.rows.indices.contains(row) else { return Self.commitRowHeight }
            switch history.rows[row] {
            case .dayGroup: return Self.dayGroupRowHeight
            case .commit: return Self.commitRowHeight
            }
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            guard history.rows.indices.contains(row) else { return false }
            if case .dayGroup = history.rows[row] { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            commitIndex(atRow: row) != nil
        }

        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard history.rows.indices.contains(row) else { return nil }

            switch history.rows[row] {
            case .dayGroup(let blockIndex):
                guard history.blocks.indices.contains(blockIndex) else { return nil }
                let cell =
                    tableView.makeView(withIdentifier: Self.dayGroupID, owner: self)
                    as? DayGroupCellView ?? DayGroupCellView(identifier: Self.dayGroupID)
                let block = history.blocks[blockIndex]
                cell.configure(
                    label: Self.dayLabel(for: block.date),
                    count: block.count,
                    // 轨道要穿过分组行，否则同一条分支在日期边界上看着像断了、
                    // 像是有个分支尖端——那是分支图里最不能出的误报。
                    // 穿过去的是上一行「向下走」的那些线。
                    passages: passages(above: block.firstCommitIndex),
                    laneCount: parent.graph.maximumLaneCount
                )
                return cell

            case .commit(let index):
                guard parent.commits.indices.contains(index) else { return nil }
                // 复用：NSTableView 只为可见行创建视图，这是 5 万行仍能流畅滚动的关键
                let cell =
                    tableView.makeView(withIdentifier: Self.columnID, owner: self) as? CommitCellView
                    ?? CommitCellView(identifier: Self.columnID)

                cell.configure(
                    commit: parent.commits[index],
                    graphRow: parent.graph.rows.indices.contains(index)
                        ? parent.graph.rows[index] : nil,
                    laneCount: parent.graph.maximumLaneCount
                )
                return cell
            }
        }

        /// 第 `index` 条提交上方那道边界上，有哪些轨道在往下走。
        ///
        /// 取的是上一行的**出线**（`toLane`）而不是本行的入线：本行新开一条轨道时，
        /// 它的第一父连线同样是 `fromLane == nodeLane`，照那个画会在分组行里
        /// 多出一段无中生有的线。
        private func passages(above index: Int) -> [LanePassage] {
            guard index > 0, parent.graph.rows.indices.contains(index - 1) else { return [] }
            var seen = Set<Int>()
            var result: [LanePassage] = []
            for link in parent.graph.rows[index - 1].links where seen.insert(link.toLane).inserted {
                result.append(LanePassage(lane: link.toLane, colorIndex: link.colorIndex))
            }
            return result
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let table else { return }
            parent.selection = commit(atRow: table.selectedRow)?.id
        }

        func syncSelection(_ id: Commit.ID?) {
            guard let table else { return }
            let targetRow =
                id
                .flatMap { identifier in parent.commits.firstIndex { $0.id == identifier } }
                .flatMap { history.row(forCommitIndex: $0) }

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

            // 右键点在日期分组行上没有任何动作可给，直接给个空菜单
            guard let index = commitIndex(atRow: table?.clickedRow ?? -1) else { return }

            let header = NSMenuItem(
                title: parent.commits[index].subject, action: nil, keyEquivalent: "")
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
                // 传提交下标而不是表格行号：分组行插进来之后两者已经不是一回事，
                // 而这里判断的是「它是不是最新/最旧的那条提交」
                item.isEnabled = action.isAvailable(at: index, loadedCount: parent.commits.count)
                item.toolTip = action.explanation
                menu.addItem(item)
            }

            // 挑取 / 撤销 / 重置 / 打标签。按 group 分段——
            // 「往历史上加东西」和「把指针往回挪」的后果完全不是一回事，
            // 排在一起会让人以为它们是同一类操作。
            var previousGroup = -1
            for action in CommitAction.allCases {
                if action.group != previousGroup {
                    menu.addItem(.separator())
                    previousGroup = action.group
                }
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(runCommitAction(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = action
                item.image = NSImage(
                    systemSymbolName: action.systemImage, accessibilityDescription: nil)
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
            copyItem.toolTip = parent.commits[index].hash
            menu.addItem(copyItem)
        }

        @objc private func copyHash(_ sender: NSMenuItem) {
            guard let commit = commit(atRow: table?.clickedRow ?? -1) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.hash, forType: .string)
        }

        @objc private func runQuickAction(_ sender: NSMenuItem) {
            guard
                let action = sender.representedObject as? QuickAction,
                let commit = commit(atRow: table?.clickedRow ?? -1)
            else { return }

            parent.onQuickAction(action, commit)
        }

        @objc private func runCommitAction(_ sender: NSMenuItem) {
            guard
                let action = sender.representedObject as? CommitAction,
                let commit = commit(atRow: table?.clickedRow ?? -1)
            else { return }

            parent.onCommitAction(action, commit)
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
    /// 这一行是不是 merge 提交。影响标题的颜色，见 ``applyTextColors()``。
    private var isMergeCommit = false

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            applyTextColors()
            graphView.isEmphasized = backgroundStyle == .emphasized
            graphView.needsDisplay = true
        }
    }

    /// 按「选中与否 + 是不是 merge」决定各标签的颜色。
    ///
    /// 集中在一处而不是分散在 backgroundStyle 和 configure 里：
    /// 两处各写一遍的话，cell 复用时很容易出现「选中态的颜色配上了
    /// 新一行的内容」这种串味，而那种 bug 只在快速滚动时才偶尔现形。
    private func applyTextColors() {
        let emphasized = backgroundStyle == .emphasized

        if emphasized {
            let accent = Theme.Colors.onEmphasized
            // 选中行不再区分 merge：此刻用户明确在看这一行，
            // 把它压暗反而是帮倒忙
            subjectLabel.textColor = accent
            authorLabel.textColor = accent.withAlphaComponent(0.85)
            let faded = accent.withAlphaComponent(0.7)
            hashLabel.textColor = faded
            dateLabel.textColor = faded
        } else {
            subjectLabel.textColor = isMergeCommit ? .secondaryLabelColor : .labelColor
            authorLabel.textColor = .secondaryLabelColor
            hashLabel.textColor = .tertiaryLabelColor
            dateLabel.textColor = .tertiaryLabelColor
        }
    }

    /// 图形区的两个尺寸：轨道间距与整块的宽度。
    ///
    /// 分组行也要按同一套算，否则轨道穿过去时会跟上下两行对不齐。
    /// 轨道多到放不下时压缩间距，而不是把图形区一路撑宽去挤占标题；
    /// 间距对所有行必须一致，否则同一条轨道在相邻两行会错位、连不上线。
    static func graphMetrics(laneCount: Int) -> (laneWidth: CGFloat, width: CGFloat) {
        let lanes = max(laneCount, 1)
        let laneWidth = max(
            minimumLaneWidth,
            min(Self.laneWidth, maximumGraphWidth / CGFloat(lanes))
        )
        let width = min(max(minimumGraphWidth, CGFloat(lanes) * laneWidth), maximumGraphWidth)
        return (laneWidth, width)
    }

    func configure(
        commit: Commit,
        graphRow: CommitGraph.Row?,
        laneCount: Int
    ) {
        graphView.row = graphRow

        let metrics = Self.graphMetrics(laneCount: laneCount)
        graphView.laneWidth = metrics.laneWidth
        graphView.needsDisplay = true
        graphWidthConstraint.constant = metrics.width

        subjectLabel.stringValue = commit.subject
        hashLabel.stringValue = commit.abbreviatedHash
        authorLabel.stringValue = commit.author.name
        dateLabel.stringValue = Self.timeFormatter.string(from: commit.author.date)

        // merge 提交的标题几乎都是 git 自动生成的「Merge branch 'x' into y」，
        // 信息量接近零，却和真正干了活的提交长得一模一样。
        // 降一档颜色让它退到背景里去，眼睛扫过时自动跳过——
        // 但不隐藏：合并点是历史结构的一部分，藏起来图就读不懂了。
        isMergeCommit = commit.isMerge
        applyTextColors()
    }

    /// 时间列只写时刻。
    ///
    /// 上一版把日期塞进这一列——跨天的那行显示日期、其余显示时刻——是为了
    /// 在不破坏固定行高的前提下造出分界。有了真正的分组行之后这个折中就没必要了，
    /// 而且留着反倒有害：同一列里一会儿是「今天」一会儿是「14:32」，
    /// 右对齐的宽度对不齐，快速扫读时间时眼睛还得辨认这一格装的是哪种东西。
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }()
}

/// 日期分组行。
///
/// 24pt 一条，用一行的高度换整列的节奏，比给每一行加装饰便宜得多，
/// 也不动信息密度——这是设计稿里唯一为「列表没有落点」新加的东西。
///
/// 轨道从它中间穿过去。设计稿画的是一整条不透明色带，那样分支线会在
/// 每个日期边界断一次，看着像一堆分支尖端——分支图里最不该出的误报。
final class DayGroupCellView: NSTableCellView {

    private let passageView = LanePassageView()
    private let label = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var passageWidthConstraint = NSLayoutConstraint()

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)

        countLabel.font = Theme.NSFonts.secondary
        // 数字等宽，否则同一列的计数在不同位数之间跳
        countLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        for view in [passageView, label, countLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        passageWidthConstraint = passageView.widthAnchor.constraint(
            equalToConstant: CommitCellView.minimumGraphWidth)

        NSLayoutConstraint.activate([
            passageView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Theme.Spacing.tight),
            passageView.topAnchor.constraint(equalTo: topAnchor),
            passageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            passageWidthConstraint,

            label.leadingAnchor.constraint(
                equalTo: passageView.trailingAnchor, constant: Theme.Spacing.regular),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            countLabel.leadingAnchor.constraint(
                equalTo: label.trailingAnchor, constant: Theme.Spacing.tight),
            countLabel.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            countLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -Theme.Spacing.regular),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从 nib 加载")
    }

    func configure(label text: String, count: Int, passages: [LanePassage], laneCount: Int) {
        label.stringValue = text
        label.textColor = NSColor(Theme.Colors.secondaryText)
        countLabel.stringValue = "\(count)"
        countLabel.textColor = NSColor(Theme.Colors.decorativeText)

        let metrics = CommitCellView.graphMetrics(laneCount: laneCount)
        passageView.laneWidth = metrics.laneWidth
        passageView.passages = passages
        passageView.needsDisplay = true
        passageWidthConstraint.constant = metrics.width

        needsDisplay = true
    }

    /// 自己画底，不用系统的 group row 样式。
    ///
    /// AppKit 给 group row 的默认外观是为「来源列表」调的：加粗全大写的标题、
    /// 跟着侧栏走的背景。这里要的是设计稿那条下沉色带，两者对不上。
    /// 用 `isGroupRow` 只是为了白拿钉在顶部的行为。
    override func draw(_ dirtyRect: NSRect) {
        NSColor(Theme.Colors.sunkenBackground).setFill()
        bounds.fill()

        NSColor(Theme.Colors.separator).setFill()
        let hairline = 1 / (window?.backingScaleFactor ?? 2)
        NSRect(x: 0, y: 0, width: bounds.width, height: hairline).fill()
        NSRect(x: 0, y: bounds.maxY - hairline, width: bounds.width, height: hairline).fill()
    }
}

/// 一条轨道穿过某个位置。
struct LanePassage {
    let lane: Int
    let colorIndex: Int
}

/// 把若干条轨道竖直画过整个高度。
///
/// 和 ``LaneGraphView`` 分开而不是复用：那个要处理节点、分叉曲线、选中态，
/// 而这里只有「几条竖线穿过去」。把分组行的情况塞进去只会让那段绘制
/// 多几个分支判断，而它是每帧都在跑的代码。
final class LanePassageView: NSView {

    var passages: [LanePassage] = []
    var laneWidth: CGFloat = CommitCellView.laneWidth

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !passages.isEmpty else { return }
        NSBezierPath(rect: bounds).setClip()

        let lanes = Theme.Colors.lanes
        for passage in passages {
            lanes[passage.colorIndex % lanes.count].setStroke()
            let path = NSBezierPath()
            path.lineWidth = Theme.Colors.laneLineWidth
            let x = CGFloat(passage.lane) * laneWidth + laneWidth / 2
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: bounds.height))
            path.stroke()
        }
    }
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
        // 挖空的深度跟着线宽走，而不是写死。
        // 写死的话，线加粗之后环壁相对变薄，节点看起来像线上打了个结；
        // 反过来线变细时环壁又会显得笨重。让它随线宽缩放，
        // 换主题调线宽时节点自动保持协调。
        let wall = Theme.Colors.laneLineWidth * 0.55
        NSBezierPath(ovalIn: nodeRect.insetBy(dx: wall, dy: wall)).fill()
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
    /// 还没有任何选中时，无论按 j 还是 k 都落到第一条可选的行——
    /// 此时列表顶端就在眼前，从那里开始最符合预期。
    ///
    /// 日期分组行要跳过去。不跳的话按一次 j 会「停在」一条选不中的行上，
    /// 表现成这一下按键没反应——而实际上它已经把选中丢了。
    private func moveSelection(by delta: Int) {
        guard numberOfRows > 0 else { return }

        var target = selectedRow < 0 ? 0 : selectedRow + delta
        let step = selectedRow < 0 ? 1 : delta

        while target >= 0, target < numberOfRows {
            if canSelect(row: target) {
                selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
                scrollRowToVisible(target)
                return
            }
            target += step
        }
    }

    private func canSelect(row: Int) -> Bool {
        delegate?.tableView?(self, shouldSelectRow: row) ?? true
    }
}
