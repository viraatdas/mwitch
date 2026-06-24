import XCTest
@testable import mwitch

final class WindowRecencyTrackerTests: XCTestCase {
    func testSortsMostRecentlyUsedFirstAndUngroupsApps() {
        // z-order groups an app's windows together: [a1, a2, b1].
        let zOrder = [
            entry(id: 1, app: "AppA", title: "a1"),
            entry(id: 2, app: "AppA", title: "a2"),
            entry(id: 3, app: "AppB", title: "b1"),
        ]
        let tracker = WindowRecencyTracker()

        // Usage: focus a1, then b1, then a2 — a2 is now most recent.
        tracker.record(1)
        tracker.record(3)
        tracker.record(2)

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [2, 3, 1])
    }

    func testUnseenWindowsKeepZOrderAfterKnownOnes() {
        let zOrder = [
            entry(id: 1, app: "AppA", title: "a1"),
            entry(id: 2, app: "AppB", title: "b1"),
            entry(id: 3, app: "AppC", title: "c1"),
        ]
        let tracker = WindowRecencyTracker()
        tracker.record(3) // only AppC's window has been used

        // Used window leads; the rest keep their original relative order.
        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [3, 1, 2])
    }

    func testRecordingExistingWindowMovesItToFront() {
        let zOrder = [
            entry(id: 1, app: "AppA", title: "a1"),
            entry(id: 2, app: "AppB", title: "b1"),
        ]
        let tracker = WindowRecencyTracker()
        tracker.record(1)
        tracker.record(2)
        tracker.record(1) // re-using a1 promotes it without duplicating

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [1, 2])
    }

    func testRecordsFocusedWindowByPIDForAppLevelAXNotifications() {
        let zOrder = [
            entry(id: 1, app: "Arc", title: "Project"),
            entry(id: 2, app: "Arc", title: "Docs"),
            entry(id: 3, app: "Terminal", title: "Build"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 999)

        tracker.recordFocusedWindow(pid: 100) { pid in
            pid == 100 ? 2 : nil
        }

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [2, 1, 3])
    }

    func testDoesNotRecordOwnFocusedWindow() {
        let zOrder = [
            entry(id: 2, app: "Arc", title: "Docs"),
            entry(id: 1, app: "mwitch", title: "Panel"),
        ]
        let tracker = WindowRecencyTracker(ownPID: 100)

        tracker.recordFocusedWindow(pid: 100) { _ in 1 }

        XCTAssertEqual(tracker.sorted(zOrder).map(\.cgWindowID), [2, 1])
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
