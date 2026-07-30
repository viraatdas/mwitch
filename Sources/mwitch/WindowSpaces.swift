import Cocoa
import Darwin

typealias CGSConnectionID = Int32

/// Space membership for a CGWindowID.
///
/// macOS native window tabbing (`NSWindow.addTabbedWindow`, used by Ghostty,
/// Terminal, and others) backs every tab with its own CG window. Background tabs
/// linger in `CGWindowListCopyWindowInfo(.optionAll)` looking exactly like real
/// windows — layer 0, a real title, a real frame — and Accessibility often
/// cannot resolve them, which is also true for a real window on another Space.
/// Neither CG nor AX identity alone can classify every case.
///
/// Nonempty WindowServer Space membership proves a real window. Empty membership
/// is a broader invisible-window bucket, so the enumerator exempts minimized and
/// hidden-app windows before rejecting an inactive tab or phantom surface.
enum WindowSpaces {
    private typealias MainConnectionFunction = @convention(c) () -> CGSConnectionID
    private typealias CopySpacesFunction = @convention(c) (
        CGSConnectionID,
        Int32,
        CFArray
    ) -> Unmanaged<CFArray>?

    private struct API {
        // Retain the dlopen handle for as long as the function pointers live.
        let libraryHandle: UnsafeMutableRawPointer
        let connection: CGSConnectionID
        let copySpaces: CopySpacesFunction
    }

    /// Current | others | user — every Space the window server tracks.
    private static let allSpacesMask: Int32 = 0x7

    // Resolve private symbols dynamically. If Apple removes either one, mwitch
    // still launches and the caller's nil handling keeps uncertain windows.
    private static let api: API? = {
        let path = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return nil }
        guard let mainSymbol = dlsym(handle, "CGSMainConnectionID"),
              let copySymbol = dlsym(handle, "CGSCopySpacesForWindows") else {
            dlclose(handle)
            return nil
        }

        let mainConnection = unsafeBitCast(mainSymbol, to: MainConnectionFunction.self)
        let copySpaces = unsafeBitCast(copySymbol, to: CopySpacesFunction.self)
        return API(
            libraryHandle: handle,
            connection: mainConnection(),
            copySpaces: copySpaces
        )
    }()

    /// Whether the window server assigns this window to any Space.
    /// Returns `nil` when the query fails so callers can keep the window rather
    /// than hide a real one on bad data.
    static func isAssignedToASpace(_ windowID: CGWindowID) -> Bool? {
        guard let api else { return nil }
        let windowIDs = [NSNumber(value: windowID)] as CFArray
        guard let result = api.copySpaces(api.connection, allSpacesMask, windowIDs) else {
            return nil
        }
        guard let spaces = result.takeRetainedValue() as? [NSNumber] else { return nil }
        return !spaces.isEmpty
    }
}
