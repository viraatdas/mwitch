import Cocoa

typealias CGSConnectionID = Int32

// Private CGS API, like _AXUIElementGetWindow in WindowActivator. Stable for
// years and relied on by AltTab and yabai to map windows to Spaces.
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

// "Copy" means the array comes back +1 retained, so take it as Unmanaged and
// release it explicitly rather than leaking one array per query.
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(
    _ connection: CGSConnectionID,
    _ mask: Int32,
    _ windowIDs: CFArray
) -> Unmanaged<CFArray>?

/// Space membership for a CGWindowID.
///
/// macOS native window tabbing (`NSWindow.addTabbedWindow`, used by Ghostty,
/// Terminal, and others) backs every tab with its own CG window. Background tabs
/// linger in `CGWindowListCopyWindowInfo(.optionAll)` looking exactly like real
/// windows — layer 0, a real title, a real frame — and Accessibility cannot
/// resolve them, which is the same thing that happens to a real window parked on
/// another Space. So neither CG nor AX data can tell the two apart.
///
/// The window server can: it assigns every real window to a Space, including
/// windows on other Spaces and in fullscreen Spaces, while background tab
/// surfaces belong to no Space at all.
enum WindowSpaces {
    /// Current | others | user — every Space the window server tracks.
    private static let allSpacesMask: Int32 = 0x7

    private static let connection = CGSMainConnectionID()

    /// Whether the window server assigns this window to any Space.
    /// Returns `nil` when the query fails so callers can keep the window rather
    /// than hide a real one on bad data.
    static func isAssignedToASpace(_ windowID: CGWindowID) -> Bool? {
        let windowIDs = [NSNumber(value: windowID)] as CFArray
        guard let result = CGSCopySpacesForWindows(connection, allSpacesMask, windowIDs) else {
            return nil
        }
        guard let spaces = result.takeRetainedValue() as? [NSNumber] else { return nil }
        return !spaces.isEmpty
    }
}
