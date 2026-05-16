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
    private struct AppMeta {
        let name: String
        let icon: NSImage?
        let bundleID: String?
    }
    private static var metaCache: [pid_t: AppMeta] = [:]

    /// Drops cached app metadata when an app terminates so we don't hand back
    /// stale icons for recycled PIDs.
    static func invalidate(pid: pid_t) { metaCache.removeValue(forKey: pid) }

    /// All on-screen, normal-layer, titled windows across applications,
    /// ordered front-to-back by CGWindowList z-order.
    static func enumerate() -> [WindowEntry] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var seenPerApp: [pid_t: Set<String>] = [:]
        var results: [WindowEntry] = []

        for w in raw {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID else { continue }
            guard let wid = w[kCGWindowNumber as String] as? CGWindowID else { continue }

            let title = (w[kCGWindowName as String] as? String) ?? ""
            if title.isEmpty { continue }

            // Skip degenerate sizes (menu shadows, status indicators, etc.).
            if let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] {
                let h = bounds["Height"] ?? 0
                let wd = bounds["Width"] ?? 0
                if h < 40 || wd < 80 { continue }
            }

            // De-dupe identical titles per app (some apps report tab + window).
            let key = title
            if seenPerApp[pid]?.contains(key) == true { continue }
            seenPerApp[pid, default: []].insert(key)

            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""

            let meta: AppMeta
            if let cached = metaCache[pid] {
                meta = cached
            } else {
                let app = NSRunningApplication(processIdentifier: pid)
                meta = AppMeta(
                    name: app?.localizedName ?? owner,
                    icon: app?.icon,
                    bundleID: app?.bundleIdentifier
                )
                metaCache[pid] = meta
            }

            results.append(WindowEntry(
                cgWindowID: wid,
                pid: pid,
                appName: meta.name,
                appIcon: meta.icon,
                title: title,
                bundleID: meta.bundleID
            ))
        }
        return results
    }
}
