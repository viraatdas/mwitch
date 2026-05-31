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
    private var updater: SPUUpdater!
    private var updateUserDriver: MwitchUpdateUserDriver!

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
        // can target it. startUpdater() kicks off the scheduled checks.
        setupUpdater()
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
        let updateItem = NSMenuItem(title: "Check for Updates…",
                                    action: #selector(checkForUpdates),
                                    keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
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

    private func setupUpdater() {
        updateUserDriver = MwitchUpdateUserDriver(hostBundle: .main) {
            Self.currentVersionDescription
        }
        updater = SPUUpdater(hostBundle: .main,
                             applicationBundle: .main,
                             userDriver: updateUserDriver,
                             delegate: nil)
        do {
            try updater.start()
        } catch {
            MwitchLog.shared.line("updater: failed to start: \(error)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Unable to Check for Updates"
                alert.informativeText = "The updater failed to start. Please install the latest version of mwitch from mwitch.viraat.dev."
                alert.runModal()
            }
        }
    }

    private static var currentVersionDescription: String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        guard let build = (info?["CFBundleVersion"] as? String), !build.isEmpty else {
            return version
        }
        return "\(version) (build \(build))"
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

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) {
            return updater?.canCheckForUpdates ?? false
        }
        return true
    }
}

private final class MwitchUpdateUserDriver: SPUStandardUserDriver {
    private let versionProvider: () -> String

    init(hostBundle: Bundle, versionProvider: @escaping () -> String) {
        self.versionProvider = versionProvider
        super.init(hostBundle: hostBundle, delegate: nil)
    }

    override func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let nsError = error as NSError
        let userInfo = nsError.userInfo.merging([
            NSLocalizedDescriptionKey: "No New Updates",
            NSLocalizedRecoverySuggestionErrorKey: "mwitch is up to date.\nCurrent version: \(versionProvider())",
            NSLocalizedRecoveryOptionsErrorKey: ["OK"]
        ]) { _, new in new }
        let presentationError = NSError(domain: nsError.domain, code: nsError.code, userInfo: userInfo)
        super.showUpdateNotFoundWithError(presentationError, acknowledgement: acknowledgement)
    }
}
