import Cocoa
import ApplicationServices

// Maps an AXUIElement to its CGWindowID. Private API, but stable for years and
// used by every serious macOS window manager (AltTab, yabai). Needed because
// title matching is unreliable for non-native AX apps like Chrome, whose AX
// window titles don't match the CGWindowList names the enumerator captured.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: inout CGWindowID) -> AXError

enum WindowActivator {
    // Bringing every window forward destroys the WindowServer's cross-app
    // ordering by turning each application's windows into a contiguous block.
    // Raise and focus only the requested AX window instead.
    static let applicationActivationOptions: NSApplication.ActivationOptions = [
        .activateIgnoringOtherApps
    ]

    /// Brings the entry's app forward and raises the specific window.
    ///
    /// Order matters: activating the app before the target window is the app's
    /// front window makes macOS raise the app's *previous* key window, which can
    /// be on another display — covering whatever the user had there. So when AX
    /// can resolve the target, all AX work (raise, main, focus) happens while
    /// the app is still inactive, and the app is activated last.
    ///
    /// The exception is a window on another Space: kAXWindowsAttribute omits
    /// off-Space windows, so the target is unresolvable until the app is
    /// activated and macOS switches Spaces. That path activates first and then
    /// retries the lookup while the Space switch completes.
    static func activate(_ entry: WindowEntry) {
        guard let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
        app.unhide()

        let axApp = AXUIElementCreateApplication(entry.pid)

        if let target = resolveTarget(axApp, entry: entry) {
            raiseAndFocus(target, axApp: axApp)
            app.activate(options: applicationActivationOptions)
            // Some apps ignore AX raise/main/focus while inactive. Repeating
            // the same calls now that the app is active is idempotent when the
            // first pass worked and recovers the target when it didn't.
            raiseAndFocus(target, axApp: axApp)
            return
        }

        // Unresolvable from the current Space (or AX can't list windows at
        // all). Activating the app is what triggers macOS's switch to the
        // window's Space; retry the lookup while that completes so multi-window
        // apps still land on the exact window that was chosen.
        app.activate(options: applicationActivationOptions)
        raiseWhenResolvable(entry, axApp: axApp, attemptsLeft: 5)
    }

    /// The AX window matching the entry — by CGWindowID (exact), else by title.
    private static func resolveTarget(_ axApp: AXUIElement, entry: WindowEntry) -> AXUIElement? {
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            var winID: CGWindowID = 0
            if _AXUIElementGetWindow(window, &winID) == .success, winID == entry.cgWindowID {
                return window
            }
        }
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if let t = titleRef as? String, t == entry.title {
                return window
            }
        }
        return nil
    }

    private static func raiseWhenResolvable(_ entry: WindowEntry, axApp: AXUIElement, attemptsLeft: Int) {
        if let target = resolveTarget(axApp, entry: entry) {
            raiseAndFocus(target, axApp: axApp)
            return
        }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            raiseWhenResolvable(entry, axApp: axApp, attemptsLeft: attemptsLeft - 1)
        }
    }

    private static func raiseAndFocus(_ target: AXUIElement, axApp: AXUIElement) {
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
        if AXUIElementIsAttributeSettable(target, kAXFocusedAttribute as CFString, &settable) == .success,
           settable.boolValue {
            AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        if AXUIElementIsAttributeSettable(axApp, kAXFocusedWindowAttribute as CFString, &settable) == .success,
           settable.boolValue {
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, target)
        }
    }
}
