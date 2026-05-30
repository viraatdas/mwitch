import Cocoa
import SwiftUI

/// Centered floating panel with the row layout:
///     [hint] [app name, right-aligned] [icon] [window title, left-aligned]
/// Typing filters by app + title; release Cmd commits.
final class SwitcherPanel: NSPanel {
    private weak var panelDelegate: SwitcherPanelDelegate?

    private var hostingView: NSHostingView<SwitcherPanelView>?
    private var snapshot = SwitcherPanelSnapshot.empty

    private var keyMonitor: Any?
    // Forces SwiftUI hover state to reset each time the reused panel is shown.
    private var presentationID = 0

    private let rowHeight: CGFloat = 38
    private let panelWidth: CGFloat = 620
    private let cornerRadius: CGFloat = 10
    private let selectionInsetX: CGFloat = 7
    private let selectionInsetY: CGFloat = 3
    private let selectionCornerRadius: CGFloat = 8

    init(delegate: SwitcherPanelDelegate) {
        self.panelDelegate = delegate
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

    func render(_ snapshot: SwitcherPanelSnapshot, scrollTarget: Int? = nil, reposition: Bool = false) {
        self.snapshot = snapshot
        sizeToContents()
        renderContent(scrollTarget: scrollTarget)
        if reposition {
            positionOnActiveScreen()
        }
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
        renderContent(scrollTarget: snapshot.selectedRow)
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
        let rowsHeight = CGFloat(max(1, snapshot.entries.count)) * rowHeight
        let chrome: CGFloat = 12 + (snapshot.searchBuffer.isEmpty ? 0 : 26)
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
            panelDelegate?.switcherPanel(self, didPerform: .cancel)
            return true
        case 36, 76: // Return / numpad Enter
            panelDelegate?.switcherPanel(self, didPerform: .commit)
            return true
        case 125: // Down
            panelDelegate?.switcherPanel(self, didPerform: .moveSelection(delta: 1))
            return true
        case 126: // Up
            panelDelegate?.switcherPanel(self, didPerform: .moveSelection(delta: -1))
            return true
        case 48: // Tab
            panelDelegate?.switcherPanel(
                self,
                didPerform: .moveSelection(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
            )
            return true
        case 51: // Delete
            panelDelegate?.switcherPanel(self, didPerform: .deleteLastSearchCharacter)
            return true
        default:
            if let chars = event.charactersIgnoringModifiers,
               let scalar = chars.unicodeScalars.first,
               scalar.value >= 0x20, scalar.value < 0x7F {
                panelDelegate?.switcherPanel(self, didPerform: .appendSearchCharacter(Character(scalar)))
                return true
            }
            return false
        }
    }

    private func renderContent(scrollTarget: Int? = nil) {
        hostingView?.rootView = makePanelView(scrollTarget: scrollTarget)
    }

    private func makePanelView(scrollTarget: Int? = nil) -> SwitcherPanelView {
        SwitcherPanelView(
            entries: snapshot.entries,
            searchBuffer: snapshot.searchBuffer,
            selectedRow: snapshot.selectedRow,
            scrollTarget: scrollTarget,
            presentationID: presentationID,
            rowHeight: rowHeight,
            selectionInsetX: selectionInsetX,
            selectionInsetY: selectionInsetY,
            selectionCornerRadius: selectionCornerRadius,
            onSelect: { [weak self] row in
                guard let self else { return }
                self.panelDelegate?.switcherPanel(self, didPerform: .selectFilteredRow(row))
            },
            onCommit: { [weak self] row in
                guard let self else { return }
                self.panelDelegate?.switcherPanel(self, didPerform: .commitFilteredRow(row))
            }
        )
    }

    private var panelIsActive: Bool { panelDelegate?.switcherPanelIsActive ?? false }
}
