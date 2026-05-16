import Cocoa

/// Centered floating panel with the row layout:
///     [hint] [app name, right-aligned] [icon] [window title, left-aligned]
/// Typing filters by app + title; release Cmd commits.
final class SwitcherPanel: NSPanel, NSTableViewDataSource, NSTableViewDelegate {
    private weak var controller: SwitcherController?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let visualEffect = NSVisualEffectView()
    private let searchLabel = NSTextField(labelWithString: "")

    private var entries: [WindowEntry] = []
    private var filtered: [WindowEntry] = []
    private var searchBuffer: String = ""
    private var keyMonitor: Any?

    private let rowHeight: CGFloat = 38
    private let panelWidth: CGFloat = 620
    private let cornerRadius: CGFloat = 10
    private let selectionInsetX: CGFloat = 7
    private let selectionInsetY: CGFloat = 3
    private let selectionCornerRadius: CGFloat = 8

    init(controller: SwitcherController) {
        self.controller = controller
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        animationBehavior = .none

        setupContent()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private func setupContent() {
        guard let content = contentView else { return }

        visualEffect.frame = content.bounds
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = cornerRadius
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        content.addSubview(visualEffect)

        searchLabel.frame = NSRect(x: 14, y: visualEffect.bounds.height - 26,
                                   width: panelWidth - 28, height: 18)
        searchLabel.autoresizingMask = [.minYMargin, .width]
        searchLabel.font = .systemFont(ofSize: 11, weight: .medium)
        searchLabel.textColor = .tertiaryLabelColor
        searchLabel.isHidden = true
        visualEffect.addSubview(searchLabel)

        scrollView.frame = visualEffect.bounds.insetBy(dx: 6, dy: 6)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.rowHeight = rowHeight
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.refusesFirstResponder = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = panelWidth - 12
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        visualEffect.addSubview(scrollView)
    }

    // MARK: - Lifecycle

    func update(entries: [WindowEntry], selection: Int) {
        self.entries = entries
        self.filtered = entries
        searchBuffer = ""
        updateSearchLabel()
        sizeToContents()
        tableView.reloadData()
        setSelection(selection)
    }

    func setSelection(_ index: Int) {
        guard !filtered.isEmpty else { return }
        let clamped = max(0, min(filtered.count - 1, index))
        tableView.selectRowIndexes(IndexSet(integer: clamped), byExtendingSelection: false)
        tableView.scrollRowToVisible(clamped)
    }

    /// Call once after init to pre-warm the WindowServer connection. Subsequent
    /// `present()` calls reuse the connection and are noticeably faster.
    func preWarm() {
        SidebarRowView.insetX = selectionInsetX
        SidebarRowView.insetY = selectionInsetY
        SidebarRowView.radius = selectionCornerRadius
        installKeyMonitor()
        // Force the window backing store to be created up front.
        _ = self.contentView
    }

    func present() {
        positionOnActiveScreen()
        orderFrontRegardless()
        makeKey()
    }

    func dismiss() {
        orderOut(nil)
    }

    // MARK: - Layout

    private func sizeToContents() {
        guard let screen = activeScreen() else { return }
        let usable = screen.visibleFrame.height - 120
        let rowsHeight = CGFloat(max(1, filtered.count)) * rowHeight
        let chrome: CGFloat = 12 + (searchBuffer.isEmpty ? 0 : 26)
        let desired = rowsHeight + chrome
        let height = min(usable, max(rowHeight + chrome, desired))
        var f = frame
        f.size = NSSize(width: panelWidth, height: height)
        setFrame(f, display: false)

        // Re-lay out the scroll area depending on whether search label is visible.
        if searchBuffer.isEmpty {
            scrollView.frame = visualEffect.bounds.insetBy(dx: 6, dy: 6)
        } else {
            scrollView.frame = NSRect(x: 6, y: 6,
                                      width: visualEffect.bounds.width - 12,
                                      height: visualEffect.bounds.height - 32)
        }
    }

    private func positionOnActiveScreen() {
        guard let screen = activeScreen() else { return }
        let visible = screen.visibleFrame
        let x = visible.midX - panelWidth / 2
        let y = visible.midY - frame.height / 2 + 40 // slight upward bias feels right
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func activeScreen() -> NSScreen? {
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return mouseScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - Key handling

    private func installKeyMonitor() {
        if keyMonitor != nil { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.panelIsActive else { return event }
            if self.handleKeyDown(event) { return nil }
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            controller?.cancel()
            return true
        case 36, 76: // Return / numpad Enter
            controller?.commitIfVisible()
            return true
        case 125: // Down
            moveSelection(by: 1); return true
        case 126: // Up
            moveSelection(by: -1); return true
        case 48: // Tab
            moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        case 51: // Delete
            if !searchBuffer.isEmpty {
                searchBuffer.removeLast()
                applyFilter()
            }
            return true
        default:
            if let chars = event.charactersIgnoringModifiers,
               let scalar = chars.unicodeScalars.first,
               scalar.value >= 0x20, scalar.value < 0x7F {
                searchBuffer.append(Character(scalar))
                applyFilter()
                return true
            }
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        let next = (current + delta + filtered.count) % filtered.count
        setSelection(next)
        if let abs = entries.firstIndex(of: filtered[next]) {
            controller?.setSelection(abs)
        }
    }

    private func applyFilter() {
        let needle = searchBuffer.lowercased()
        if needle.isEmpty {
            filtered = entries
        } else {
            filtered = entries.filter { entry in
                Self.fuzzyMatch(needle: needle, haystack: "\(entry.appName) \(entry.title)".lowercased())
            }
        }
        updateSearchLabel()
        sizeToContents()
        positionOnActiveScreen()
        tableView.reloadData()
        if let first = filtered.first, let abs = entries.firstIndex(of: first) {
            setSelection(0)
            controller?.setSelection(abs)
        }
    }

    private func updateSearchLabel() {
        if searchBuffer.isEmpty {
            searchLabel.isHidden = true
        } else {
            searchLabel.isHidden = false
            searchLabel.stringValue = "Search: \(searchBuffer)"
        }
    }

    private static func fuzzyMatch(needle: String, haystack: String) -> Bool {
        if haystack.contains(needle) { return true }
        var idx = haystack.startIndex
        for ch in needle {
            guard let found = haystack[idx...].firstIndex(of: ch) else { return false }
            idx = haystack.index(after: found)
        }
        return true
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = filtered[row]
        let identifier = NSUserInterfaceItemIdentifier("row")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? RowCellView) ?? {
            let c = RowCellView()
            c.identifier = identifier
            return c
        }()
        cell.configure(with: entry)
        return cell
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0, row < filtered.count else { return }
        if let abs = entries.firstIndex(of: filtered[row]) {
            controller?.setSelection(abs)
        }
        controller?.commitIfVisible()
    }

    private var panelIsActive: Bool { (controller?.isVisible ?? false) }
}

// MARK: - Row views

final class SidebarRowView: NSTableRowView {
    static var insetX: CGFloat = 7
    static var insetY: CGFloat = 3
    static var radius: CGFloat = 8

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: Self.insetX, dy: Self.insetY),
                                xRadius: Self.radius, yRadius: Self.radius)
        NSColor.controlAccentColor.setFill()
        path.fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected ? .emphasized : .normal
    }
}

final class RowCellView: NSTableCellView {
    private let appNameLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildLayout()
    }

    private func buildLayout() {
        appNameLabel.font = .systemFont(ofSize: 13, weight: .regular)
        appNameLabel.textColor = .secondaryLabelColor
        appNameLabel.alignment = .right
        appNameLabel.lineBreakMode = .byTruncatingHead
        appNameLabel.maximumNumberOfLines = 1

        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        for v in [appNameLabel, iconView, titleLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        let appWidth: CGFloat = 220
        let iconSize: CGFloat = 22

        NSLayoutConstraint.activate([
            appNameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            appNameLabel.widthAnchor.constraint(equalToConstant: appWidth),
            appNameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconView.leadingAnchor.constraint(equalTo: appNameLabel.trailingAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: iconSize),
            iconView.heightAnchor.constraint(equalToConstant: iconSize),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func configure(with entry: WindowEntry) {
        appNameLabel.stringValue = entry.appName
        iconView.image = entry.appIcon
        titleLabel.stringValue = entry.title
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let emph = (backgroundStyle == .emphasized)
            titleLabel.textColor = emph ? .white : .labelColor
            appNameLabel.textColor = emph ? NSColor.white.withAlphaComponent(0.85)
                                          : .secondaryLabelColor
        }
    }
}
