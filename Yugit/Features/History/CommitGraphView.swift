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
        let table = NSTableView()
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

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        context.coordinator.table = table
        context.coordinator.observeScrolling(in: scrollView)
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
        }

        @objc private func runQuickAction(_ sender: NSMenuItem) {
            guard
                let action = sender.representedObject as? QuickAction,
                let row = table?.clickedRow,
                parent.commits.indices.contains(row)
            else { return }

            parent.onQuickAction(action, parent.commits[row])
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

    /// 每条轨道的水平间距。
    static let laneWidth: CGFloat = 14
    /// 图形区最窄宽度，避免线性历史时信息贴着左边缘。
    static let minimumGraphWidth: CGFloat = 24

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        subjectLabel.lineBreakMode = .byTruncatingTail
        subjectLabel.font = Theme.NSFonts.body

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

        graphWidthConstraint = graphView.widthAnchor.constraint(equalToConstant: Self.minimumGraphWidth)

        let inset = Theme.Spacing.regular

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
        graphView.needsDisplay = true
        graphWidthConstraint.constant = max(
            Self.minimumGraphWidth, CGFloat(laneCount) * Self.laneWidth)

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

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let row else { return }

        let laneWidth = CommitCellView.laneWidth
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
            path.lineWidth = 1.8
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
        let radius: CGFloat = 4
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
            NSColor.selectedContentBackgroundColor.setFill()
        } else {
            NSColor.textBackgroundColor.setFill()
        }
        NSBezierPath(ovalIn: nodeRect.insetBy(dx: 1.6, dy: 1.6)).fill()
    }
}
