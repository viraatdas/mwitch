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

    func testRejectsOffscreenWindowsThatAXKnowsAreNotStandard() {
        // When AX can resolve the window, trust its classification: an AXDialog
        // is a sheet/popover, not a switchable window, so it must be dropped.
        let dialog = rawWindow(
            id: 31,
            pid: 300,
            owner: "Electron App",
            title: "Detached Dialog",
            isOnscreen: false
        )

        let entries = buildEntries(
            allWindows: [dialog],
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

    func testKeepsTitledOffscreenWindowsAXCannotMap() {
        // kAXWindowsAttribute only returns the current Space's windows, so a real
        // window parked on another desktop (Discord, a terminal, etc.) has no AX
        // entry to match. It must still surface as long as it carries a real
        // CGWindowList title and clears the layer/size guards.
        let offSpaceDiscord = rawWindow(
            id: 30,
            pid: 300,
            owner: "Discord",
            title: "#general | EXLA - Discord",
            isOnscreen: false
        )
        let offSpaceTerminal = rawWindow(
            id: 32,
            pid: 320,
            owner: "Ghostty",
            title: "Moobot Terminal",
            isOnscreen: false
        )

        let entries = buildEntries(allWindows: [offSpaceDiscord, offSpaceTerminal])

        XCTAssertEqual(entries.map(\.cgWindowID), [30, 32])
        XCTAssertEqual(entries.map(\.appName), ["Discord", "Ghostty"])
    }

    func testKeepsEveryRealTabbedWindowEvenWhenTheyShareAFrame() {
        // Captured from a real Ghostty session: two separate windows, both
        // zoomed to the identical frame, each fronting one tab of its own tab
        // group. Both are real windows the switcher must offer; the background
        // tabs behind them are not. Only the two real windows hold a Space.
        let frame = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        let firstWindow = rawWindow(
            id: 78, pid: 652, owner: "Ghostty", title: "rudder", isOnscreen: true, bounds: frame
        )
        let secondWindow = rawWindow(
            id: 76, pid: 652, owner: "Ghostty", title: "🔴 Rudder: aws-v2", isOnscreen: true, bounds: frame
        )
        // Background tabs report a frame nudged by a pixel or sitting exactly on
        // top of their window, which is why frame comparison cannot classify them.
        let backgroundTabs = [
            rawWindow(id: 79, pid: 652, owner: "Ghostty", title: "i2message", isOnscreen: false,
                      bounds: CGRect(x: -1, y: 33, width: 1728, height: 1084)),
            rawWindow(id: 70, pid: 652, owner: "Ghostty", title: "aws-v2", isOnscreen: false, bounds: frame),
            rawWindow(id: 2594, pid: 652, owner: "Ghostty", title: "🟢 Rudder: mwitch", isOnscreen: false,
                      bounds: CGRect(x: 1, y: 33, width: 1728, height: 1084))
        ]

        let entries = buildEntries(
            onScreenWindows: [firstWindow, secondWindow],
            allWindows: backgroundTabs + [firstWindow, secondWindow],
            spacelessWindows: [79, 70, 2594]
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [78, 76])
        XCTAssertEqual(entries.map(\.title), ["rudder", "🔴 Rudder: aws-v2"])
    }

    func testKeepsOffSpaceWindowThatSharesAFrameWithACurrentSpaceWindow() {
        // A window parked on another Space is AX-unresolvable exactly like a
        // background tab, and users routinely size windows identically, so the
        // shared frame must not hide it. It holds a Space, so it stays.
        let frame = CGRect(x: 0, y: 33, width: 1728, height: 1084)
        let onCurrentSpace = rawWindow(
            id: 78, pid: 652, owner: "Ghostty", title: "rudder", isOnscreen: true, bounds: frame
        )
        let onAnotherSpace = rawWindow(
            id: 90, pid: 652, owner: "Ghostty", title: "~/code/sleeve", isOnscreen: false, bounds: frame
        )

        let entries = buildEntries(
            onScreenWindows: [onCurrentSpace],
            allWindows: [onAnotherSpace, onCurrentSpace]
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [78, 90])
    }

    func testKeepsWindowWhenSpaceMembershipIsUnknown() {
        // A failed Space query must not hide a real window.
        let offscreen = rawWindow(
            id: 91, pid: 652, owner: "Ghostty", title: "~/code/sleeve", isOnscreen: false
        )

        let entries = buildEntries(allWindows: [offscreen], unknownSpaceWindows: [91])

        XCTAssertEqual(entries.map(\.cgWindowID), [91])
    }

    func testKeepsSpacelessMinimizedStandardWindow() {
        let minimized = rawWindow(
            id: 92, pid: 920, owner: "Preview", title: "Scan.pdf", isOnscreen: false
        )

        let entries = buildEntries(
            allWindows: [minimized],
            axWindows: [
                920: [
                    92: WindowEnumerator.AXWindowInfo(
                        title: "Scan.pdf",
                        role: "AXWindow",
                        subrole: "AXStandardWindow",
                        isMinimized: true
                    )
                ]
            ],
            spacelessWindows: [92]
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [92])
    }

    func testRejectsSpacelessNonMinimizedAXStandardWindow() {
        // Some native inactive tabs briefly remain AX-resolvable. AX standard
        // classification alone does not make a Space-less surface switchable.
        let inactiveTab = rawWindow(
            id: 93, pid: 930, owner: "Terminal", title: "Old Tab", isOnscreen: false
        )

        let entries = buildEntries(
            allWindows: [inactiveTab],
            axWindows: [
                930: [
                    93: WindowEnumerator.AXWindowInfo(
                        title: "Old Tab",
                        role: "AXWindow",
                        subrole: "AXStandardWindow",
                        isMinimized: false
                    )
                ]
            ],
            spacelessWindows: [93]
        )

        XCTAssertTrue(entries.isEmpty)
    }

    func testKeepsSpacelessWindowFromHiddenApp() {
        let hiddenWindow = rawWindow(
            id: 94, pid: 940, owner: "Notes", title: "Private note", isOnscreen: false
        )

        let entries = buildEntries(
            allWindows: [hiddenWindow],
            axWindows: [
                940: [
                    94: WindowEnumerator.AXWindowInfo(
                        title: "Private note",
                        role: "AXWindow",
                        subrole: "AXStandardWindow",
                        isMinimized: false
                    )
                ]
            ],
            spacelessWindows: [94],
            hiddenPIDs: [940]
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [94])
    }

    func testKeepsSpacelessAXWindowWhenMinimizedStateIsUnknown() {
        let uncertainWindow = rawWindow(
            id: 97, pid: 970, owner: "Legacy App", title: "Document", isOnscreen: false
        )

        let entries = buildEntries(
            allWindows: [uncertainWindow],
            axWindows: [
                970: [
                    97: WindowEnumerator.AXWindowInfo(
                        title: "Document",
                        role: "AXWindow",
                        subrole: "AXStandardWindow",
                        isMinimized: nil
                    )
                ]
            ],
            spacelessWindows: [97]
        )

        XCTAssertEqual(entries.map(\.cgWindowID), [97])
    }

    func testKeepsSameTitleSpaceAssignedOffSpaceWindows() {
        let first = rawWindow(
            id: 95, pid: 950, owner: "Editor", title: "README.md", isOnscreen: false
        )
        let second = rawWindow(
            id: 96, pid: 950, owner: "Editor", title: "README.md", isOnscreen: false
        )

        let entries = buildEntries(allWindows: [first, second])

        XCTAssertEqual(entries.map(\.cgWindowID), [95, 96])
    }

    func testRejectsUntitledOffscreenSurfacesAXCannotMap() {
        // Stale Electron helper surfaces show up in the all-windows pass with no
        // CGWindowList title and no AX entry; without a title they stay hidden.
        let helperSurface = rawWindow(
            id: 33,
            pid: 330,
            owner: "Electron App",
            title: "",
            isOnscreen: false
        )

        let entries = buildEntries(allWindows: [helperSurface])

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

    /// Windows are assigned to a Space unless listed in `spacelessWindows`
    /// (background tab surfaces) or `unknownSpaceWindows` (query failed).
    private func buildEntries(
        onScreenWindows: [WindowEnumerator.RawWindow] = [],
        allWindows: [WindowEnumerator.RawWindow] = [],
        axWindows: [pid_t: [CGWindowID: WindowEnumerator.AXWindowInfo]] = [:],
        spacelessWindows: Set<CGWindowID> = [],
        unknownSpaceWindows: Set<CGWindowID> = [],
        hiddenPIDs: Set<pid_t> = []
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
            },
            isAssignedToASpace: { windowID in
                if unknownSpaceWindows.contains(windowID) { return nil }
                return !spacelessWindows.contains(windowID)
            },
            isAppHidden: { hiddenPIDs.contains($0) }
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
