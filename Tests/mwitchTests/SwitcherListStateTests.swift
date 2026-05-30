import XCTest
@testable import mwitch

final class SwitcherListStateTests: XCTestCase {
    func testFilteringSelectsFirstVisibleEntryByAbsoluteIndex() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox"),
            entry(id: 3, app: "Terminal", title: "Build")
        ]

        XCTAssertEqual(state.update(entries: entries, selection: 1), 1)

        XCTAssertEqual(state.appendSearchCharacter("t"), 2)
        XCTAssertEqual(state.filtered.map(\.cgWindowID), [3])
        XCTAssertEqual(state.selectedRow, 0)
        XCTAssertEqual(state.selectedAbsoluteIndex, 2)
    }

    func testAbsoluteSelectionMapsToFilteredRow() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Mail", title: "Inbox"),
            entry(id: 3, app: "Terminal", title: "Build"),
            entry(id: 4, app: "TextEdit", title: "Draft")
        ]

        _ = state.update(entries: entries, selection: 0)
        _ = state.appendSearchCharacter("t")

        XCTAssertEqual(state.filtered.map(\.cgWindowID), [3, 4])
        XCTAssertEqual(state.setSelection(absoluteIndex: 3), 1)
        XCTAssertEqual(state.selectedRow, 1)
        XCTAssertEqual(state.selectedAbsoluteIndex, 3)
    }

    func testMoveSelectionReturnsAbsoluteIndexFromFilteredRows() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Terminal", title: "Build"),
            entry(id: 3, app: "TextEdit", title: "Draft")
        ]

        _ = state.update(entries: entries, selection: 0)
        _ = state.appendSearchCharacter("t")

        XCTAssertEqual(state.moveSelection(by: 1), 2)
        XCTAssertEqual(state.selectedRow, 1)
        XCTAssertEqual(state.selectedAbsoluteIndex, 2)
    }

    func testFilteredAdvanceKeepsSelectedAbsoluteIndexVisible() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Terminal", title: "Build"),
            entry(id: 3, app: "TextEdit", title: "Draft")
        ]

        _ = state.update(entries: entries, selection: 0)
        _ = state.appendSearchCharacter("t")

        let selectedAbsoluteIndex = state.moveSelection(by: 1)

        XCTAssertEqual(selectedAbsoluteIndex, 2)
        XCTAssertEqual(state.filtered.map(\.cgWindowID), [2, 3])
        XCTAssertEqual(
            selectedAbsoluteIndex.map { entries[$0] },
            state.selectedRow.map { state.filtered[$0] }
        )
    }

    func testSelectingHiddenAbsoluteIndexClearsSelection() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Terminal", title: "Build")
        ]

        _ = state.update(entries: entries, selection: 0)
        _ = state.appendSearchCharacter("t")

        XCTAssertNil(state.setSelection(absoluteIndex: 0))
        XCTAssertNil(state.selectedRow)
        XCTAssertNil(state.selectedAbsoluteIndex)
    }

    func testSelectingFilteredRowReturnsAbsoluteIndexAndUpdatesSelection() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Terminal", title: "Build"),
            entry(id: 3, app: "TextEdit", title: "Draft")
        ]

        _ = state.update(entries: entries, selection: 0)
        _ = state.appendSearchCharacter("t")

        XCTAssertEqual(state.selectFilteredRow(1), 2)
        XCTAssertEqual(state.selectedRow, 1)
        XCTAssertEqual(state.selectedAbsoluteIndex, 2)
    }

    func testSelectingInvalidFilteredRowLeavesSelectionUnchanged() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Terminal", title: "Build")
        ]

        _ = state.update(entries: entries, selection: 0)

        XCTAssertNil(state.selectFilteredRow(10))
        XCTAssertEqual(state.selectedRow, 0)
        XCTAssertEqual(state.selectedAbsoluteIndex, 0)
    }

    func testSnapshotExposesPanelRenderingState() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Terminal", title: "Build"),
            entry(id: 3, app: "TextEdit", title: "Draft")
        ]

        _ = state.update(entries: entries, selection: 0)
        _ = state.appendSearchCharacter("t")
        _ = state.selectFilteredRow(1)

        let snapshot = state.snapshot

        XCTAssertEqual(snapshot.entries.map(\.cgWindowID), [2, 3])
        XCTAssertEqual(snapshot.searchBuffer, "t")
        XCTAssertEqual(snapshot.selectedRow, 1)
    }

    func testFilteringToNoMatchesClearsSelection() {
        var state = SwitcherListState()
        let entries = [
            entry(id: 1, app: "Safari", title: "Docs"),
            entry(id: 2, app: "Notes", title: "Roadmap")
        ]

        _ = state.update(entries: entries, selection: 0)

        XCTAssertNil(state.appendSearchCharacter("z"))
        XCTAssertTrue(state.filtered.isEmpty)
        XCTAssertNil(state.selectedRow)
        XCTAssertNil(state.selectedAbsoluteIndex)
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
