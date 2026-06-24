import Cocoa
import ApplicationServices

/// Global most-recently-used order of windows, keyed by CGWindowID.
///
/// CGWindowList only exposes z-order, which groups every window of an app
/// together because activating an app raises all its windows as a block. macOS
/// has no API for global per-window recency, so we build it ourselves:
///   - record each window mwitch activates,
///   - watch NSWorkspace app-activations to catch switches between apps made
///     outside mwitch (native Cmd+Tab, Dock, clicking another app), and
///   - watch each app's AX focused-window changes so clicking between two
///     windows of the *same* app reorders them too.
final class WindowRecencyTracker {
    static let shared = WindowRecencyTracker()

    /// Most-recently-used first.
    private var order: [CGWindowID] = []
    private let maxEntries = 256
    private let ownPID: pid_t

    /// One AX observer per app PID, tracking its focused-window changes.
    private var observers: [pid_t: AXObserver] = [:]

    init(ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
    }

    /// Begins observing app and window focus changes. Call once at launch.
    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appActivated(_:)),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appLaunched(_:)),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            observeFocusChanges(pid: app.processIdentifier)
        }
    }

    /// Marks a window as the most recently used.
    func record(_ id: CGWindowID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        if order.count > maxEntries { order.removeLast(order.count - maxEntries) }
    }

    /// Reorders entries most-recently-used first. Windows never seen keep their
    /// original (z-order) relative position, appended after all known windows —
    /// so a freshly launched mwitch still shows a sensible list before any
    /// switches have been recorded.
    func sorted(_ entries: [WindowEntry]) -> [WindowEntry] {
        var rank: [CGWindowID: Int] = [:]
        for (index, id) in order.enumerated() { rank[id] = index }
        return entries.enumerated().sorted { lhs, rhs in
            switch (rank[lhs.element.cgWindowID], rank[rhs.element.cgWindowID]) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let pid = Self.pid(from: note) else { return }
        recordFocusedWindow(pid: pid, lookup: Self.focusedWindowID)
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let pid = Self.pid(from: note) else { return }
        observeFocusChanges(pid: pid)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let pid = Self.pid(from: note) else { return }
        stopObserving(pid: pid)
    }

    // MARK: - Per-app focused-window observers

    /// Fired by AX whenever an app's focused/main window changes, including
    /// clicking between two windows of the same app, which NSWorkspace never
    /// reports. Some apps send the changed window as `element`; others send the
    /// observed app element, so fall back to querying that app's focused window.
    private let focusChangedCallback: AXObserverCallback = { _, element, _, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<WindowRecencyTracker>.fromOpaque(refcon).takeUnretainedValue()

        var winID: CGWindowID = 0
        if _AXUIElementGetWindow(element, &winID) == .success {
            tracker.record(winID)
            return
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else {
            return
        }
        tracker.recordFocusedWindow(pid: pid, lookup: WindowRecencyTracker.focusedWindowID)
    }

    private func observeFocusChanges(pid: pid_t) {
        guard pid != ownPID, observers[pid] == nil else { return }
        var observer: AXObserver?
        guard AXObserverCreate(pid, focusChangedCallback, &observer) == .success,
              let observer else { return }

        let axApp = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let focusedResult = AXObserverAddNotification(
            observer,
            axApp,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        let mainResult = AXObserverAddNotification(
            observer,
            axApp,
            kAXMainWindowChangedNotification as CFString,
            refcon
        )
        guard focusedResult == .success || mainResult == .success else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func stopObserving(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    // MARK: - Helpers

    private static func pid(from note: Notification) -> pid_t? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
    }

    func recordFocusedWindow(pid: pid_t, lookup: (pid_t) -> CGWindowID?) {
        guard pid != ownPID, let id = lookup(pid) else { return }
        record(id)
    }

    /// The CGWindowID of an app's focused window, via the same private API the
    /// enumerator and activator use to bridge AX windows to CGWindowIDs.
    private static func focusedWindowID(pid: pid_t) -> CGWindowID? {
        let axApp = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focusedRef = focused,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let window = focusedRef as! AXUIElement
        var winID: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &winID) == .success else { return nil }
        return winID
    }
}
