import Cocoa

/// Owns the panel + currently-shown window list. Handles Cmd+Tab semantics:
/// first press = show panel with most-recent window selected; subsequent presses
/// advance selection; Cmd-up commits and activates.
final class SwitcherController {
    private var panel: SwitcherPanel?
    private(set) var entries: [WindowEntry] = []
    private(set) var selection: Int = 0
    private(set) var isVisible: Bool = false

    /// Pre-create the panel + warm the WindowServer connection so the first
    /// Cmd+Tab doesn't pay allocation cost.
    func preWarm() {
        if panel == nil {
            panel = SwitcherPanel(controller: self)
            panel?.preWarm()
        }
        // Touch the window list once so AppKit caches its bookkeeping.
        _ = WindowEnumerator.enumerate()
    }

    func advance(reverse: Bool = false) {
        if !isVisible {
            entries = WindowEnumerator.enumerate()
            guard entries.count > 0 else { return }
            // Default selection: the second window (most-recent non-front),
            // matching the muscle memory of Cmd+Tab.
            selection = entries.count > 1 ? 1 : 0
            show()
        } else {
            guard entries.count > 0 else { return }
            if let selected = panel?.advanceVisibleSelection(reverse: reverse) {
                selection = selected
            } else {
                clearSelection(updatePanel: false)
            }
        }
    }

    func setSelection(_ index: Int, updatePanel: Bool = true) {
        guard index >= 0, index < entries.count else { return }
        selection = index
        if updatePanel {
            panel?.setSelection(index)
        }
    }

    func clearSelection(updatePanel: Bool = true) {
        selection = -1
        if updatePanel {
            panel?.clearSelection()
        }
    }

    func commitIfVisible() {
        guard isVisible else { return }
        let chosen = entries.indices.contains(selection) ? entries[selection] : nil
        hide()
        if let chosen { WindowActivator.activate(chosen) }
    }

    func cancel() {
        guard isVisible else { return }
        hide()
    }

    private func show() {
        if panel == nil {
            panel = SwitcherPanel(controller: self)
            panel?.preWarm()
        }
        isVisible = true
        panel?.update(entries: entries, selection: selection)
        panel?.present()
    }

    private func hide() {
        panel?.dismiss()
        isVisible = false
    }
}
