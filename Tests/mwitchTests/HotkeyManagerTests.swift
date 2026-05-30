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
}
