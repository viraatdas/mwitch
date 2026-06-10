import XCTest
@testable import mwitch

final class HotkeyManagerTests: XCTestCase {
    func testCommandReleaseCommitsAfterInterceptedHotkey() {
        var gate = SwitcherCommitGate()

        gate.arm()

        XCTAssertEqual(gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true), .commit)
        XCTAssertEqual(gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true), .keepWaiting)
    }

    func testUnrelatedModifierReleaseClearsStaleWaitWithoutCommitting() {
        var gate = SwitcherCommitGate()

        gate.arm()

        XCTAssertEqual(
            gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: false),
            .discardStaleWait
        )
        XCTAssertEqual(gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true), .keepWaiting)
    }

    func testResetClearsPendingCommit() {
        var gate = SwitcherCommitGate()

        gate.arm()
        gate.reset()

        XCTAssertEqual(gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true), .keepWaiting)
    }

    /// Cmd+Tab opens the switcher (arming the gate); Esc cancels it (the tap
    /// resets the gate); the trailing Cmd release must not commit, otherwise the
    /// cancelled switcher would still activate a window.
    func testEscapeCancelDoesNotCommitOnTrailingCommandRelease() {
        var session = SwitcherSession()
        var gate = SwitcherCommitGate()

        // Cmd+Tab intercepted: switcher shows and the commit gate arms.
        let opened = session.start(entries: [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox")
        ])
        gate.arm()
        XCTAssertEqual(opened, .render(scrollTarget: 1, reposition: false))
        XCTAssertTrue(session.isVisible)

        // Esc (still holding Cmd): switcher cancels and the tap clears the gate.
        let cancelled = session.perform(.cancel)
        gate.reset()
        XCTAssertEqual(cancelled, .dismiss(chosen: nil))
        XCTAssertFalse(session.isVisible)

        // Releasing Cmd afterwards is a no-op — no window is activated.
        XCTAssertEqual(
            gate.resolvePendingCommit(commandStillHeld: false, changedKeyIsCommand: true),
            .keepWaiting
        )
    }

    private func entry(id: CGWindowID, app: String, title: String) -> WindowEntry {
        WindowEntry(
            cgWindowID: id,
            pid: pid_t(id),
            appName: app,
            appIcon: nil,
            title: title,
            bundleID: nil
        )
    }
}
