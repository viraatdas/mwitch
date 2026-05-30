import XCTest
@testable import mwitch

final class SwitcherSessionTests: XCTestCase {
    func testStartSelectsMostRecentBackgroundWindow() {
        var session = SwitcherSession()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox"),
            entry(id: 3, app: "Terminal", title: "Build")
        ]

        let result = session.start(entries: entries)

        XCTAssertEqual(result, .render(scrollTarget: 1, reposition: false))
        XCTAssertTrue(session.isVisible)
        XCTAssertEqual(session.selection, 1)
        XCTAssertEqual(session.snapshot.selectedRow, 1)
    }

    func testMoveSelectionAdvancesWithinVisibleRows() {
        var session = startedSession()

        let result = session.perform(.moveSelection(delta: 1))

        XCTAssertEqual(result, .render(scrollTarget: 2, reposition: false))
        XCTAssertEqual(session.selection, 2)
        XCTAssertEqual(session.snapshot.selectedRow, 2)
    }

    func testSearchFiltersAndSelectsFirstResult() {
        var session = startedSession()

        let result = session.perform(.appendSearchCharacter("t"))

        XCTAssertEqual(result, .render(scrollTarget: 0, reposition: true))
        XCTAssertEqual(session.snapshot.entries.map(\.cgWindowID), [3, 4])
        XCTAssertEqual(session.snapshot.searchBuffer, "t")
        XCTAssertEqual(session.selection, 2)
    }

    func testHoverSelectionUpdatesSelectionWithoutRepositioning() {
        var session = startedSession()
        _ = session.perform(.appendSearchCharacter("t"))

        let result = session.perform(.selectFilteredRow(1))

        XCTAssertEqual(result, .render(scrollTarget: nil, reposition: false))
        XCTAssertEqual(session.selection, 3)
        XCTAssertEqual(session.snapshot.selectedRow, 1)
    }

    func testSelectingAlreadySelectedRowDoesNothing() {
        var session = startedSession()

        let result = session.perform(.selectFilteredRow(1))

        XCTAssertEqual(result, .none)
        XCTAssertEqual(session.selection, 1)
    }

    func testCommitReturnsSelectedEntryAndHidesSession() {
        var session = startedSession()

        let result = session.perform(.commit)

        XCTAssertEqual(result, .dismiss(chosen: entry(id: 2, app: "Mail", title: "Inbox")))
        XCTAssertFalse(session.isVisible)
    }

    func testCommitFilteredRowIgnoresInvalidRow() {
        var session = startedSession()

        let result = session.perform(.commitFilteredRow(10))

        XCTAssertEqual(result, .none)
        XCTAssertTrue(session.isVisible)
        XCTAssertEqual(session.selection, 1)
    }

    func testCancelHidesWithoutChoosingEntry() {
        var session = startedSession()

        let result = session.perform(.cancel)

        XCTAssertEqual(result, .dismiss(chosen: nil))
        XCTAssertFalse(session.isVisible)
    }

    private func startedSession() -> SwitcherSession {
        var session = SwitcherSession()
        _ = session.start(entries: [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox"),
            entry(id: 3, app: "Terminal", title: "Build"),
            entry(id: 4, app: "TextEdit", title: "Draft")
        ])
        return session
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
