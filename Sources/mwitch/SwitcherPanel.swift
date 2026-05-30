import Cocoa
import SwiftUI

/// Centered floating panel with the row layout:
///     [hint] [app name, right-aligned] [icon] [window title, left-aligned]
/// Typing filters by app + title; release Cmd commits.
final class SwitcherPanel: NSPanel {
    private weak var controller: SwitcherController?

    private var hostingView: NSHostingView<SwitcherPanelView>?

    private var listState = SwitcherListState()
    private var keyMonitor: Any?
    // Forces SwiftUI hover state to reset each time the reused panel is shown.
    private var presentationID = 0

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
        let host = NSHostingView(rootView: makePanelView())
        host.frame = content.bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.cornerRadius = cornerRadius
        host.layer?.masksToBounds = true
        content.addSubview(host)
        hostingView = host
    }

    // MARK: - Lifecycle

    func update(entries: [WindowEntry], selection: Int) {
        let selectedRow = listState.update(entries: entries, selection: selection)
        sizeToContents()
        renderContent(scrollTarget: selectedRow)
    }

    func setSelection(_ index: Int) {
        let selectedRow = listState.setSelection(absoluteIndex: index)
        renderContent(scrollTarget: selectedRow)
    }

    func clearSelection() {
        listState.clearSelection()
        renderContent()
    }

    /// Advances through the rows that are currently visible in the panel and
    /// returns the corresponding absolute entry index for the controller.
    func advanceVisibleSelection(reverse: Bool = false) -> Int? {
        let selectedAbsoluteIndex = listState.moveSelection(by: reverse ? -1 : 1)
        guard let selectedAbsoluteIndex, let selectedRow = listState.selectedRow else {
            clearSelection()
            return nil
        }
        renderContent(scrollTarget: selectedRow)
        return selectedAbsoluteIndex
    }

    /// Call once after init to pre-warm the WindowServer connection. Subsequent
    /// `present()` calls reuse the connection and are noticeably faster.
    func preWarm() {
        installKeyMonitor()
        // Force the window backing store to be created up front.
        _ = self.contentView
    }

    func present() {
        presentationID += 1
        renderContent()
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
        let rowsHeight = CGFloat(max(1, listState.filtered.count)) * rowHeight
        let chrome: CGFloat = 12 + (listState.searchBuffer.isEmpty ? 0 : 26)
        let desired = rowsHeight + chrome
        let height = min(usable, max(rowHeight + chrome, desired))
        var f = frame
        f.size = NSSize(width: panelWidth, height: height)
        setFrame(f, display: false)
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
            applyFilter(selectedAbsoluteIndex: listState.deleteLastSearchCharacter())
            return true
        default:
            if let chars = event.charactersIgnoringModifiers,
               let scalar = chars.unicodeScalars.first,
               scalar.value >= 0x20, scalar.value < 0x7F {
                applyFilter(selectedAbsoluteIndex: listState.appendSearchCharacter(Character(scalar)))
                return true
            }
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard let selectedAbsoluteIndex = advanceVisibleSelection(reverse: delta < 0) else {
            controller?.clearSelection(updatePanel: false)
            return
        }
        controller?.setSelection(selectedAbsoluteIndex, updatePanel: false)
    }

    private func applyFilter(selectedAbsoluteIndex: Int?) {
        sizeToContents()
        positionOnActiveScreen()
        if let selectedAbsoluteIndex, let selectedRow = listState.selectedRow {
            renderContent(scrollTarget: selectedRow)
            controller?.setSelection(selectedAbsoluteIndex, updatePanel: false)
        } else {
            clearSelection()
            controller?.clearSelection(updatePanel: false)
        }
    }

    private func renderContent(scrollTarget: Int? = nil) {
        hostingView?.rootView = makePanelView(scrollTarget: scrollTarget)
    }

    private func selectFilteredRow(_ row: Int) {
        guard let abs = listState.absoluteIndex(forFilteredRow: row) else { return }
        guard listState.selectedRow != row else { return }
        _ = listState.setSelection(absoluteIndex: abs)
        renderContent()
        controller?.setSelection(abs, updatePanel: false)
    }

    private func makePanelView(scrollTarget: Int? = nil) -> SwitcherPanelView {
        SwitcherPanelView(
            entries: listState.filtered,
            searchBuffer: listState.searchBuffer,
            selectedRow: listState.selectedRow,
            scrollTarget: scrollTarget,
            presentationID: presentationID,
            rowHeight: rowHeight,
            selectionInsetX: selectionInsetX,
            selectionInsetY: selectionInsetY,
            selectionCornerRadius: selectionCornerRadius,
            onSelect: { [weak self] row in
                self?.selectFilteredRow(row)
            },
            onCommit: { [weak self] row in
                guard let self, let abs = self.listState.absoluteIndex(forFilteredRow: row) else { return }
                self.controller?.setSelection(abs, updatePanel: false)
                self.controller?.commitIfVisible()
            }
        )
    }

    private var panelIsActive: Bool { (controller?.isVisible ?? false) }
}

// MARK: - SwiftUI content

struct SwitcherPanelView: View {
    let entries: [WindowEntry]
    let searchBuffer: String
    let selectedRow: Int?
    let scrollTarget: Int?
    let presentationID: Int
    let rowHeight: CGFloat
    let selectionInsetX: CGFloat
    let selectionInsetY: CGFloat
    let selectionCornerRadius: CGFloat
    let onSelect: (Int) -> Void
    let onCommit: (Int) -> Void

    @State private var initialPointerLocation: CGPoint?
    @State private var isHoverSelectionEnabled = false

    private let hoverActivationDistance: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            if !searchBuffer.isEmpty {
                Text("Search: \(searchBuffer)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 26)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { row, entry in
                            SwitcherRowView(
                                entry: entry,
                                isSelected: row == selectedRow,
                                rowHeight: rowHeight,
                                selectionInsetX: selectionInsetX,
                                selectionInsetY: selectionInsetY,
                                selectionCornerRadius: selectionCornerRadius
                            )
                            .id(row)
                            .contentShape(Rectangle())
                            .onContinuousHover(coordinateSpace: .global) { phase in
                                handleRowHover(phase, row: row)
                            }
                            .onTapGesture {
                                onSelect(row)
                                onCommit(row)
                            }
                        }
                    }
                    .padding(6)
                    .contentShape(Rectangle())
                    .onContinuousHover(coordinateSpace: .global) { phase in
                        updateHoverGate(phase)
                    }
                }
                .onAppear {
                    resetHoverGate()
                    scrollToTarget(proxy)
                }
                .onChange(of: scrollTarget) { _ in
                    scrollToTarget(proxy)
                }
                .onChange(of: presentationID) { _ in
                    resetHoverGate()
                }
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    private func handleRowHover(_ phase: HoverPhase, row: Int) {
        guard isHoverSelectionEnabled else { return }

        switch phase {
        case .active:
            guard entries.indices.contains(row) else { return }
            guard selectedRow != row else { return }

            onSelect(row)

        case .ended:
            break
        }
    }

    private func updateHoverGate(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            if initialPointerLocation == nil {
                initialPointerLocation = location
                return
            }

            guard !isHoverSelectionEnabled else { return }
            guard let initialPointerLocation else { return }

            let distanceFromInitial = hypot(
                location.x - initialPointerLocation.x,
                location.y - initialPointerLocation.y
            )

            if distanceFromInitial >= hoverActivationDistance {
                isHoverSelectionEnabled = true
            }

        case .ended:
            resetHoverGate()
        }
    }

    private func resetHoverGate() {
        initialPointerLocation = nil
        isHoverSelectionEnabled = false
    }

    private func scrollToTarget(_ proxy: ScrollViewProxy) {
        guard let scrollTarget, entries.indices.contains(scrollTarget) else { return }
        proxy.scrollTo(scrollTarget)
    }
}

private struct SwitcherRowView: View {
    let entry: WindowEntry
    let isSelected: Bool
    let rowHeight: CGFloat
    let selectionInsetX: CGFloat
    let selectionInsetY: CGFloat
    let selectionCornerRadius: CGFloat

    private let appWidth: CGFloat = 220
    private let iconSize: CGFloat = 22

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.appName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color(nsColor: .secondaryLabelColor))
                .lineLimit(1)
                .truncationMode(.head)
                .frame(width: appWidth, alignment: .trailing)

            Group {
                if let appIcon = entry.appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: iconSize, height: iconSize)

            Text(entry.title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? Color.white : Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: rowHeight)
        .background(alignment: .center) {
            if isSelected {
                RoundedRectangle(cornerRadius: selectionCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlAccentColor))
                    .padding(.horizontal, selectionInsetX)
                    .padding(.vertical, selectionInsetY)
            }
        }
    }
}
