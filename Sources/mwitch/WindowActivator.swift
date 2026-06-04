import Cocoa
import ApplicationServices

// Maps an AXUIElement to its CGWindowID. Private API, but stable for years and
// used by every serious macOS window manager (AltTab, yabai). Needed because
// title matching is unreliable for non-native AX apps like Chrome, whose AX
// window titles don't match the CGWindowList names the enumerator captured.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

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

        // Match by CGWindowID — exact and title-independent. Fall back to title,
        // then to the first window only as a last resort.
        var match: AXUIElement?
        for window in windows {
            var winID: CGWindowID = 0
            if _AXUIElementGetWindow(window, &winID) == .success, winID == entry.cgWindowID {
                match = window
                break
            }
        }
        if match == nil {
            for window in windows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                if let t = titleRef as? String, t == entry.title {
                    match = window
                    break
                }
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
