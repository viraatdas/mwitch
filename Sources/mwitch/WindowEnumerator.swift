import Cocoa
import ApplicationServices

struct WindowEntry: Equatable {
    let cgWindowID: CGWindowID
    let pid: pid_t
    let appName: String
    let appIcon: NSImage?
    let title: String
    let bundleID: String?

    static func == (lhs: WindowEntry, rhs: WindowEntry) -> Bool {
        lhs.cgWindowID == rhs.cgWindowID
    }
}

enum WindowEnumerator {
    struct AppMeta {
        let name: String
        let icon: NSImage?
        let bundleID: String?
    }

    struct RawWindow {
        let cgWindowID: CGWindowID
        let pid: pid_t
        let ownerName: String
        let layer: Int
        let title: String
        let bounds: CGRect
        let isOnscreen: Bool
    }

    struct AXWindowInfo {
        let title: String
        let role: String?
        let subrole: String?
        let isMinimized: Bool?

        var isStandardWindow: Bool {
            role == (kAXWindowRole as String) &&
            subrole == (kAXStandardWindowSubrole as String)
        }
    }

    private static var metaCache: [pid_t: AppMeta] = [:]

    /// Drops cached app metadata when an app terminates so we don't hand back
    /// stale icons for recycled PIDs.
    static func invalidate(pid: pid_t) { metaCache.removeValue(forKey: pid) }

    /// All switchable, normal-layer, titled windows across applications.
    /// Current-space on-screen windows keep CGWindowList front-to-back order;
    /// real standard windows from other Spaces, hidden apps, and minimized
    /// state are appended after AX validation.
    static func enumerate() -> [WindowEntry] {
        let onScreen = rawWindows(options: [.optionOnScreenOnly, .excludeDesktopElements])
        let all = rawWindows(options: [.optionAll, .excludeDesktopElements])

        return entries(
            onScreenWindows: onScreen,
            allWindows: all,
            ownPID: ProcessInfo.processInfo.processIdentifier,
            axWindowsForPID: axWindows(pid:),
            appMetaForPID: appMeta(pid:ownerName:),
            isAssignedToASpace: WindowSpaces.isAssignedToASpace(_:),
            isAppHidden: { NSRunningApplication(processIdentifier: $0)?.isHidden == true }
        )
    }

    static func entries(
        onScreenWindows: [RawWindow],
        allWindows: [RawWindow],
        ownPID: pid_t,
        axWindowsForPID: (pid_t) -> [CGWindowID: AXWindowInfo]?,
        appMetaForPID: (pid_t, String) -> AppMeta,
        isAssignedToASpace: (CGWindowID) -> Bool?,
        isAppHidden: (pid_t) -> Bool
    ) -> [WindowEntry] {
        var seenWindowIDs = Set<CGWindowID>()
        var seenTitles: [pid_t: Set<String>] = [:]
        var results: [WindowEntry] = []
        var axCache: [pid_t: [CGWindowID: AXWindowInfo]?] = [:]

        // nil means the app's AX window query itself failed (hung app, no
        // accessibility bridge) — distinct from a window merely absent from a
        // successful query.
        func axWindows(for pid: pid_t) -> [CGWindowID: AXWindowInfo]? {
            if let cached = axCache[pid] { return cached }
            let value = axWindowsForPID(pid)
            axCache[pid] = value
            return value
        }

        func append(_ window: RawWindow, fromAllWindowsPass: Bool) {
            guard window.layer == 0 else { return }
            guard window.pid != ownPID else { return }
            guard !seenWindowIDs.contains(window.cgWindowID) else { return }
            guard window.bounds.height >= 40, window.bounds.width >= 80 else { return }

            var axInfo: AXWindowInfo?
            var spaceMembership: Bool?

            // The all-windows pass is what finds real windows from other Spaces,
            // hidden apps, and minimized state. It also includes stale helper
            // surfaces, so non-onscreen candidates need an extra gate.
            var appAXWindows: [CGWindowID: AXWindowInfo]?
            if fromAllWindowsPass, !window.isOnscreen {
                appAXWindows = axWindows(for: window.pid)
                axInfo = appAXWindows?[window.cgWindowID]
                if let axInfo {
                    // AX could resolve this window: trust its classification and
                    // keep only real standard windows (drops dialogs, sheets,
                    // popovers, and other non-switchable surfaces).
                    guard axInfo.isStandardWindow else { return }
                } else {
                    // AX cannot map windows that live on another Space:
                    // kAXWindowsAttribute only returns the current Space's (and
                    // minimized) windows, so _AXUIElementGetWindow has nothing to
                    // match. That silently dropped real windows parked on other
                    // desktops — Discord, terminal windows, etc. Fall back to the
                    // CGWindowList title: genuine windows publish a name, while
                    // the stale helper surfaces the all-pass also returns do not
                    // (and are caught by the empty-title and minimum-size guards).
                    // Combined with the per-app title de-dupe below, a titled
                    // candidate here is a real off-Space window worth switching to.
                    guard !window.title.isEmpty else { return }
                }

                // Native AppKit tabs (Ghostty, Terminal, and others) leave
                // titled layer-0 CG surfaces behind for every inactive tab.
                // Those surfaces have no WindowServer Space. Empty Space
                // membership is broader than tabs, though: minimized windows
                // and windows from hidden apps can also be Space-less, so keep
                // those explicit states. A missing/failed private API query is
                // nil and deliberately fails open.
                spaceMembership = isAssignedToASpace(window.cgWindowID)
                // Minimized windows do appear in kAXWindowsAttribute, so when
                // the app's AX query succeeded, a window absent from it is a
                // surface rather than a minimized window. When the query itself
                // failed, minimized state is unknown — fail open and keep the
                // window rather than guess.
                let isDefinitelyNotMinimized =
                    (appAXWindows != nil && axInfo == nil) || axInfo?.isMinimized == false
                if spaceMembership == false,
                   isDefinitelyNotMinimized,
                   !isAppHidden(window.pid) {
                    return
                }
            }

            // Prefer the CGWindowList name. Some apps (Contacts, System
            // Information) never publish kCGWindowName even with Screen Recording
            // granted, so fall back to the Accessibility title before dropping
            // the window. Only windows with no title from any source are skipped.
            if window.title.isEmpty, axInfo == nil {
                axInfo = axWindows(for: window.pid)?[window.cgWindowID]
            }
            let title = window.title.isEmpty ? (axInfo?.title ?? "") : window.title
            guard !title.isEmpty else { return }

            // If a candidate cannot be tied to an AX window, avoid showing the
            // common duplicate title surfaces that some apps publish. Exact AX
            // matches are de-duplicated by CGWindowID so two real windows with
            // the same title can both appear. A nonempty Space membership is
            // equally strong proof for AX-unmapped windows on other Spaces.
            if seenTitles[window.pid]?.contains(title) == true {
                if axInfo == nil {
                    axInfo = axWindows(for: window.pid)?[window.cgWindowID]
                }
                guard axInfo != nil || spaceMembership == true else { return }
            }

            let meta = appMetaForPID(window.pid, window.ownerName)
            seenWindowIDs.insert(window.cgWindowID)
            seenTitles[window.pid, default: []].insert(title)
            results.append(WindowEntry(
                cgWindowID: window.cgWindowID,
                pid: window.pid,
                appName: meta.name,
                appIcon: meta.icon,
                title: title,
                bundleID: meta.bundleID
            ))
        }

        for window in onScreenWindows {
            append(window, fromAllWindowsPass: false)
        }
        for window in allWindows {
            append(window, fromAllWindowsPass: true)
        }
        return results
    }

    private static func rawWindows(options: CGWindowListOption) -> [RawWindow] {
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.compactMap(RawWindow.init(windowInfo:))
    }

    private static func appMeta(pid: pid_t, ownerName: String) -> AppMeta {
        if let cached = metaCache[pid] { return cached }
        let app = NSRunningApplication(processIdentifier: pid)
        let meta = AppMeta(
            name: app?.localizedName ?? ownerName,
            icon: app?.icon,
            bundleID: app?.bundleIdentifier
        )
        metaCache[pid] = meta
        return meta
    }

    /// Accessibility metadata for an app's windows, keyed by CGWindowID. Matches
    /// each AX window via the same private API the activator uses, so titles and
    /// switchability checks line up with the exact CG window we enumerated.
    /// Returns nil when the query itself fails, so callers can tell "app has no
    /// resolvable windows" apart from "AX is unavailable for this app".
    private static func axWindows(pid: pid_t) -> [CGWindowID: AXWindowInfo]? {
        let axApp = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return nil
        }

        var result: [CGWindowID: AXWindowInfo] = [:]
        for window in windows {
            var winID: CGWindowID = 0
            guard _AXUIElementGetWindow(window, &winID) == .success else { continue }

            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef)
            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)

            result[winID] = AXWindowInfo(
                title: titleRef as? String ?? "",
                role: roleRef as? String,
                subrole: subroleRef as? String,
                isMinimized: minimizedRef as? Bool
            )
        }
        return result
    }
}

extension WindowEnumerator.RawWindow {
    fileprivate init?(windowInfo: [String: Any]) {
        guard let cgWindowID = windowInfo[kCGWindowNumber as String] as? CGWindowID else { return nil }
        guard let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t else { return nil }
        guard let layer = windowInfo[kCGWindowLayer as String] as? Int else { return nil }
        guard let boundsInfo = windowInfo[kCGWindowBounds as String] as? [String: Any] else { return nil }
        guard let x = Self.cgFloat(boundsInfo["X"]),
              let y = Self.cgFloat(boundsInfo["Y"]),
              let width = Self.cgFloat(boundsInfo["Width"]),
              let height = Self.cgFloat(boundsInfo["Height"]) else {
            return nil
        }

        self.cgWindowID = cgWindowID
        self.pid = pid
        self.ownerName = windowInfo[kCGWindowOwnerName as String] as? String ?? ""
        self.layer = layer
        self.title = windowInfo[kCGWindowName as String] as? String ?? ""
        self.bounds = CGRect(x: x, y: y, width: width, height: height)
        self.isOnscreen = Self.bool(windowInfo[kCGWindowIsOnscreen as String]) ?? false
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? Int { return value != 0 }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }
}
