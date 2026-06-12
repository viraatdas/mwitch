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
            appMetaForPID: appMeta(pid:ownerName:)
        )
    }

    static func entries(
        onScreenWindows: [RawWindow],
        allWindows: [RawWindow],
        ownPID: pid_t,
        axWindowsForPID: (pid_t) -> [CGWindowID: AXWindowInfo],
        appMetaForPID: (pid_t, String) -> AppMeta
    ) -> [WindowEntry] {
        var seenWindowIDs = Set<CGWindowID>()
        var seenTitles: [pid_t: Set<String>] = [:]
        var results: [WindowEntry] = []
        var axCache: [pid_t: [CGWindowID: AXWindowInfo]] = [:]

        func axWindows(for pid: pid_t) -> [CGWindowID: AXWindowInfo] {
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

            // The all-windows pass is what finds real windows from other Spaces,
            // hidden apps, and minimized state. It also includes stale helper
            // surfaces; require an exact AX standard-window match before adding
            // any non-onscreen candidate.
            if fromAllWindowsPass, !window.isOnscreen {
                axInfo = axWindows(for: window.pid)[window.cgWindowID]
                guard axInfo?.isStandardWindow == true else { return }
            }

            // Prefer the CGWindowList name. Some apps (Contacts, System
            // Information) never publish kCGWindowName even with Screen Recording
            // granted, so fall back to the Accessibility title before dropping
            // the window. Only windows with no title from any source are skipped.
            if window.title.isEmpty, axInfo == nil {
                axInfo = axWindows(for: window.pid)[window.cgWindowID]
            }
            let title = window.title.isEmpty ? (axInfo?.title ?? "") : window.title
            guard !title.isEmpty else { return }

            // If a candidate cannot be tied to an AX window, avoid showing the
            // common duplicate title surfaces that some apps publish. Exact AX
            // matches are de-duplicated by CGWindowID so two real windows with
            // the same title can both appear.
            if seenTitles[window.pid]?.contains(title) == true {
                if axInfo == nil {
                    axInfo = axWindows(for: window.pid)[window.cgWindowID]
                }
                guard axInfo != nil else { return }
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
    private static func axWindows(pid: pid_t) -> [CGWindowID: AXWindowInfo] {
        let axApp = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return [:]
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
