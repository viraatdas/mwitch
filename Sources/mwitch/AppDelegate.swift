import Cocoa
import ApplicationServices
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var switcher: SwitcherController!
    private var hotkey: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        MwitchLog.shared.line("--- launched pid=\(getpid()) bundle=\(Bundle.main.bundlePath) ---")
        MwitchLog.shared.line("AXIsProcessTrusted=\(AXIsProcessTrusted())")
        ensureAccessibility()
        MwitchLog.shared.line("after prompt: AXIsProcessTrusted=\(AXIsProcessTrusted())")
        setupStatusItem()

        switcher = SwitcherController()
        switcher.preWarm()

        hotkey = HotkeyManager()
        hotkey.onPress = { [weak self] in
            MwitchLog.shared.line("hotkey: Cmd+Tab")
            self?.switcher.advance()
        }
        hotkey.onShiftPress = { [weak self] in
            MwitchLog.shared.line("hotkey: Cmd+Shift+Tab")
            self?.switcher.advance(reverse: true)
        }
        hotkey.onModifiersReleased = { [weak self] in
            MwitchLog.shared.line("hotkey: Cmd released → commit")
            self?.switcher.commitIfVisible()
        }
        hotkey.register()
    }

    private func ensureAccessibility() {
        if !AXIsProcessTrusted() {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "rectangle.stack.fill", accessibilityDescription: "mwitch")
            btn.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Switcher", action: #selector(showSwitcher), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        let accItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "")
        accItem.target = self
        menu.addItem(accItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit mwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showSwitcher() {
        switcher.advance()
        switcher.commitIfVisible()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

