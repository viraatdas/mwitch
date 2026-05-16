import Cocoa
import ApplicationServices

enum WindowActivator {
    /// Brings the entry's app forward and raises the specific window.
    static func activate(_ entry: WindowEntry) {
        guard let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        app.activate(options: [.activateIgnoringOtherApps])

        let axApp = AXUIElementCreateApplication(entry.pid)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return
        }

        // Prefer exact title match; fall back to first window.
        var match: AXUIElement?
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if let t = titleRef as? String, t == entry.title {
                match = window
                break
            }
        }
        let target = match ?? windows.first
        guard let target else { return }

        // Un-minimize if needed.
        var minRef: CFTypeRef?
        AXUIElementCopyAttributeValue(target, kAXMinimizedAttribute as CFString, &minRef)
        if let minimized = minRef as? Bool, minimized {
            AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        AXUIElementPerformAction(target, kAXRaiseAction as CFString)

        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(target, kAXMainAttribute as CFString, &settable) == .success,
           settable.boolValue {
            AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
    }
}
