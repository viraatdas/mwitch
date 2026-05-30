import Cocoa

/// Owns the panel + currently-shown window list. Handles Cmd+Tab semantics:
/// first press = show panel with most-recent window selected; subsequent presses
/// advance selection; Cmd-up commits and activates.
final class SwitcherController {
    private var panel: SwitcherPanel?
    private var session = SwitcherSession()

    var entries: [WindowEntry] { session.entries }
    var selection: Int { session.selection }
    var isVisible: Bool { session.isVisible }

    /// Pre-create the panel + warm the WindowServer connection so the first
    /// Cmd+Tab doesn't pay allocation cost.
    func preWarm() {
        if panel == nil {
            panel = SwitcherPanel(delegate: self)
            panel?.preWarm()
        }
        // Touch the window list once so AppKit caches its bookkeeping.
        _ = WindowEnumerator.enumerate()
    }

    func advance(reverse: Bool = false) {
        if !isVisible {
            let entries = WindowEnumerator.enumerate()
            handle(session.start(entries: entries), presenting: true)
        } else {
            handle(session.perform(.moveSelection(delta: reverse ? -1 : 1)))
        }
    }

    func setSelection(_ index: Int, updatePanel: Bool = true) {
        let result = session.setSelection(index)
        if updatePanel { handle(result) }
    }

    func clearSelection(updatePanel: Bool = true) {
        let result = session.clearSelection()
        if updatePanel { handle(result) }
    }

    func commitIfVisible() {
        handle(session.perform(.commit))
    }

    func cancel() {
        handle(session.perform(.cancel))
    }

    private func show() {
        if panel == nil {
            panel = SwitcherPanel(delegate: self)
            panel?.preWarm()
        }
        renderPanel(scrollTarget: session.snapshot.selectedRow)
        panel?.present()
    }

    private func hide() {
        panel?.dismiss()
    }

    private func renderPanel(scrollTarget: Int? = nil, reposition: Bool = false) {
        panel?.render(session.snapshot, scrollTarget: scrollTarget, reposition: reposition)
    }

    private func handle(_ result: SwitcherSessionResult, presenting: Bool = false) {
        switch result {
        case .none:
            return
        case .render(let scrollTarget, let reposition):
            if presenting {
                show()
            } else {
                renderPanel(scrollTarget: scrollTarget, reposition: reposition)
            }
        case .dismiss(let chosen):
            hide()
            if let chosen {
                WindowActivator.activate(chosen)
            }
        }
    }
}

extension SwitcherController: SwitcherPanelDelegate {
    var switcherPanelIsActive: Bool { isVisible }

    func switcherPanel(_ panel: SwitcherPanel, didPerform action: SwitcherPanelAction) {
        handle(session.perform(action))
    }
}
