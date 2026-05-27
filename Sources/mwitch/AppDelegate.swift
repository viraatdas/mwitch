import Cocoa
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var switcher: SwitcherController!
    private var hotkey: HotkeyManager!
    private var launchAtLoginMenuItem: NSMenuItem?
    private var updaterController: SPUStandardUpdaterController!

    private static let launchAtLoginFirstRunKey = "mwitch.launchAtLogin.firstRunHandled"

    func applicationDidFinishLaunching(_ notification: Notification) {
        MwitchLog.shared.line("--- launched pid=\(getpid()) bundle=\(Bundle.main.bundlePath) ---")
        MwitchLog.shared.line("AXIsProcessTrusted=\(AXIsProcessTrusted())")
        ensureAccessibility()
        MwitchLog.shared.line("after prompt: AXIsProcessTrusted=\(AXIsProcessTrusted())")
        // Window titles from other apps require Screen Recording on macOS
        // 10.15+ — without it, the enumerator returns 0 windows and Cmd+Tab
        // silently does nothing.
        let scOK = CGPreflightScreenCaptureAccess()
        MwitchLog.shared.line("CGPreflightScreenCaptureAccess=\(scOK)")
        if !scOK { _ = CGRequestScreenCaptureAccess() }
        enableLaunchAtLoginIfFirstRun()
        // Sparkle: silent background auto-update (SUAutomaticallyUpdate in
        // Info.plist). Created before the status menu so "Check for Updates…"
        // can target it. startingUpdater: true kicks off the scheduled checks.
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: nil,
                                                         userDriverDelegate: nil)
        setupStatusItem()
        // Show the in-app onboarding window when either permission is missing.
        // Auto-dismissable once both are granted — won't pop up on subsequent
        // launches if everything's fine.
        DispatchQueue.main.async {
            OnboardingWindow.shared.presentIfNeeded()
        }

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
        let updateItem = NSMenuItem(title: "Check for Updates…",
                                    action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                    keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)
        let setupItem = NSMenuItem(title: "Setup & Permissions…", action: #selector(showOnboarding), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        menu.addItem(NSMenuItem.separator())
        let accItem = NSMenuItem(title: "Open Accessibility Settings…", action: #selector(openAccessibility), keyEquivalent: "")
        accItem.target = self
        menu.addItem(accItem)
        let scItem = NSMenuItem(title: "Open Screen Recording Settings…", action: #selector(openScreenRecording), keyEquivalent: "")
        scItem.target = self
        menu.addItem(scItem)
        menu.addItem(NSMenuItem.separator())
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)
        self.launchAtLoginMenuItem = loginItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit mwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func showSwitcher() {
        switcher.advance()
        switcher.commitIfVisible()
    }

    @objc private func showOnboarding() {
        OnboardingWindow.shared.present()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openScreenRecording() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func enableLaunchAtLoginIfFirstRun() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.launchAtLoginFirstRunKey) else { return }
        defaults.set(true, forKey: Self.launchAtLoginFirstRunKey)
        do {
            try SMAppService.mainApp.register()
            MwitchLog.shared.line("launch-at-login: enabled by default on first run")
        } catch {
            MwitchLog.shared.line("launch-at-login: register failed: \(error)")
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                launchAtLoginMenuItem?.state = .off
                MwitchLog.shared.line("launch-at-login: disabled")
            } else {
                try service.register()
                launchAtLoginMenuItem?.state = .on
                MwitchLog.shared.line("launch-at-login: enabled")
            }
        } catch {
            MwitchLog.shared.line("launch-at-login: toggle failed: \(error)")
        }
    }
}

