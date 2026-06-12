import XCTest
@testable import mwitch

final class WindowEnumeratorTests: XCTestCase {
    func testAppendsOffscreenStandardAXWindowsAfterVisibleWindows() {
        let visible = rawWindow(id: 10, pid: 100, owner: "Safari", title: "Docs", isOnscreen: true)
        let notionCalendar = rawWindow(
            id: 20,
            pid: 200,
            owner: "Notion Calendar",
            title: "Jul 2026 - Notion Calendar",
            isOnscreen: false
        )

        let entries = buildEntries(
            onScreenWindows: [visible],
            allWindows: [notionCalendar, visible],
            axWindows: [
                200: [
                    20: WindowEnumerator.AXWindowInfo(
                        title: "Jul 2026 - Notion Calendar",
                        role: "AXWindow",
                        subrole: "AXStandardWindow",
                        isMinimized: false
                    )
                ]
            ]
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [10, 20])
        XCTAssertEqual(entries.map(\.appName), ["Safari", "Notion Calendar"])
    }

    func testRejectsOffscreenWindowsWithoutExactStandardAXMatch() {
        let helperSurface = rawWindow(
            id: 30,
            pid: 300,
            owner: "Electron App",
            title: "Background Surface",
            isOnscreen: false
        )
        let dialog = rawWindow(
            id: 31,
            pid: 300,
            owner: "Electron App",
            title: "Detached Dialog",
            isOnscreen: false
        )

        let entries = buildEntries(
            allWindows: [helperSurface, dialog],
            axWindows: [
                300: [
                    31: WindowEnumerator.AXWindowInfo(
                        title: "Detached Dialog",
                        role: "AXWindow",
                        subrole: "AXDialog",
                        isMinimized: false
                    )
                ]
            ]
        )

        XCTAssertTrue(entries.isEmpty)
    }

    func testFallsBackToAXTitleForUntitledCGWindow() {
        let untitled = rawWindow(id: 40, pid: 400, owner: "Contacts", title: "", isOnscreen: true)

        let entries = buildEntries(
            onScreenWindows: [untitled],
            axWindows: [
                400: [
                    40: WindowEnumerator.AXWindowInfo(
                        title: "All Contacts",
                        role: "AXWindow",
                        subrole: "AXStandardWindow",
                        isMinimized: false
                    )
                ]
            ]
        )

        XCTAssertEqual(entries.map(\.title), ["All Contacts"])
    }

    func testKeepsDistinctAXWindowsWithTheSameTitle() {
        let first = rawWindow(id: 50, pid: 500, owner: "Chrome", title: "New Tab", isOnscreen: true)
        let second = rawWindow(id: 51, pid: 500, owner: "Chrome", title: "New Tab", isOnscreen: true)

        let entries = buildEntries(
            onScreenWindows: [first, second],
            axWindows: [
                500: [
                    50: WindowEnumerator.AXWindowInfo(
                        title: "New Tab",
                        role: "AXWindow",
                        subrole: "AXStandardWindow",
                        isMinimized: false
                    ),
                    51: WindowEnumerator.AXWindowInfo(
                        title: "New Tab",
                        role: "AXWindow",
                        subrole: "AXStandardWindow",
                        isMinimized: false
                    )
                ]
            ]
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [50, 51])
    }

    func testDeduplicatesUntetheredDuplicateTitleSurfaces() {
        let first = rawWindow(id: 60, pid: 600, owner: "Legacy App", title: "Report", isOnscreen: true)
        let duplicate = rawWindow(id: 61, pid: 600, owner: "Legacy App", title: "Report", isOnscreen: true)

        let entries = buildEntries(onScreenWindows: [first, duplicate])

        XCTAssertEqual(entries.map(\.cgWindowID), [60])
    }

    private func buildEntries(
        onScreenWindows: [WindowEnumerator.RawWindow] = [],
        allWindows: [WindowEnumerator.RawWindow] = [],
        axWindows: [pid_t: [CGWindowID: WindowEnumerator.AXWindowInfo]] = [:]
    ) -> [WindowEntry] {
        WindowEnumerator.entries(
            onScreenWindows: onScreenWindows,
            allWindows: allWindows,
            ownPID: 9999,
            axWindowsForPID: { axWindows[$0] ?? [:] },
            appMetaForPID: { pid, ownerName in
                WindowEnumerator.AppMeta(
                    name: ownerName.isEmpty ? "App \(pid)" : ownerName,
                    icon: nil,
                    bundleID: "test.\(pid)"
                )
            }
        )
    }

    private func rawWindow(
        id: CGWindowID,
        pid: pid_t,
        owner: String,
        title: String,
        isOnscreen: Bool,
        layer: Int = 0,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 800, height: 600)
    ) -> WindowEnumerator.RawWindow {
        WindowEnumerator.RawWindow(
            cgWindowID: id,
            pid: pid,
            ownerName: owner,
            layer: layer,
            title: title,
            bounds: bounds,
            isOnscreen: isOnscreen
        )
    }
}
