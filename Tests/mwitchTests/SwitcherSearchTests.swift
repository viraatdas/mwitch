import XCTest
@testable import mwitch

final class SwitcherSearchTests: XCTestCase {
    func testPrefixMatchesRankAheadOfFuzzyMatches() {
        let entries = [
            entry(id: 1, app: "Safari", title: "Terminal Notes"),
            entry(id: 2, app: "Terminal", title: "Build"),
            entry(id: 3, app: "Mail", title: "Team Report")
        ]

        let results = SwitcherSearch.rankedResults(for: entries, query: "ter")

        XCTAssertEqual(results.map(\.cgWindowID), [2, 1, 3])
    }

    func testPrefixRankPreservesOriginalOrderWithinRank() {
        let entries = [
            entry(id: 1, app: "Terminal", title: "Build"),
            entry(id: 2, app: "TextEdit", title: "Draft"),
            entry(id: 3, app: "TeamViewer", title: "Remote")
        ]

        let results = SwitcherSearch.rankedResults(for: entries, query: "te")

        XCTAssertEqual(results.map(\.cgWindowID), [1, 2, 3])
    }

    func testSubstringMatchesRankAheadOfLooseFuzzyMatches() {
        let entries = [
            entry(id: 1, app: "Notes", title: "Trace Log"),
            entry(id: 2, app: "Calendar", title: "Team Review")
        ]

        let results = SwitcherSearch.rankedResults(for: entries, query: "ea")

        XCTAssertEqual(results.map(\.cgWindowID), [2, 1])
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
