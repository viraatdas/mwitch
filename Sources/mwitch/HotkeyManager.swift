import Cocoa
import CoreGraphics
import Carbon.HIToolbox

/// Intercepts Cmd+Tab (and Cmd+Shift+Tab) at the session event-tap level so
/// the system app switcher never sees the keystroke. Also watches Cmd
/// release to commit the panel's current selection, and Esc to cancel it —
/// cancelling through the tap (instead of the panel's local key monitor) keeps
/// dismissal working regardless of how the app was installed or activated.
///
/// Requires Accessibility permission (granted via AppDelegate prompt).
/// `RegisterEventHotKey` can't steal Cmd+Tab — only a session tap can.
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onShiftPress: (() -> Void)?
    var onModifiersReleased: (() -> Void)?
    /// Returns `true` when the switcher was visible and is now cancelled, so
    /// the tap knows to swallow the Escape keystroke.
    var onCancel: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var switcherCommitGate = SwitcherCommitGate()

    func register() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            return mgr.handle(type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: opaqueSelf
        )

        guard let tap = eventTap else {
            MwitchLog.shared.line("ERROR: CGEvent.tapCreate returned nil — Accessibility not granted (or revoked due to signature change)")
            FileHandle.standardError.write(Data(
                "mwitch: could not create event tap — Accessibility permission required\n".utf8
            ))
            return
        }
        MwitchLog.shared.line("event tap created and enabled")

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS occasionally disables the tap (timeout, very high event load).
        // Re-enable and let the event through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            switcherCommitGate.reset()
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let cmdHeld = flags.contains(.maskCommand)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyDown {
            if cmdHeld && keyCode == Int64(kVK_Tab) {
                // The tap callback runs on the main runloop, so we can call
                // straight through without a dispatch_async hop. Trims the
                // perceptible Cmd+Tab→panel latency.
                if flags.contains(.maskShift) {
                    onShiftPress?()
                } else {
                    onPress?()
                }
                switcherCommitGate.arm()
                return nil // swallow before WindowServer sees it
            }

            // Cancel via Escape through the global tap rather than the panel's
            // local key monitor: the tap sees the keystroke regardless of which
            // app is active or whether the panel became key window, so dismissal
            // works the same no matter how the app was installed or launched.
            if keyCode == Int64(kVK_Escape), onCancel?() == true {
                // Clear the pending Cmd-release commit so the upcoming Cmd-up
                // (Esc is usually pressed while Cmd is still held) doesn't
                // re-activate a window after the user asked to cancel.
                switcherCommitGate.reset()
                return nil // swallow before the focused app sees it
            }
        }

        let changedCommandKey = keyCode == Int64(kVK_Command) || keyCode == Int64(kVK_RightCommand)
        if type == .flagsChanged {
            switch switcherCommitGate.resolvePendingCommit(
                commandStillHeld: cmdHeld,
                changedKeyIsCommand: changedCommandKey
            ) {
            case .commit:
                onModifiersReleased?()
            case .discardStaleWait, .keepWaiting:
                break
            }
        }

        return Unmanaged.passUnretained(event)
    }

    deinit {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }
}

/// Tracks whether mwitch has intercepted Cmd+Tab/Cmd+Shift+Tab and should
/// commit the switcher when the matching Command-key release arrives.
struct SwitcherCommitGate {
    private var waitingForCommandRelease = false

    /// Called after the event tap swallows Cmd+Tab or Cmd+Shift+Tab.
    mutating func arm() {
        waitingForCommandRelease = true
    }

    mutating func reset() {
        waitingForCommandRelease = false
    }

    /// Resolves the pending Cmd+Tab commit when all modifiers are released.
    /// A Command-key release commits; any other release clears stale state.
    mutating func resolvePendingCommit(
        commandStillHeld: Bool,
        changedKeyIsCommand: Bool
    ) -> CommandReleaseGateResult {
        guard waitingForCommandRelease else { return .keepWaiting }
        guard !commandStillHeld else { return .keepWaiting }

        waitingForCommandRelease = false
        return changedKeyIsCommand ? .commit : .discardStaleWait
    }
}

enum CommandReleaseGateResult {
    case keepWaiting
    case discardStaleWait
    case commit
}
