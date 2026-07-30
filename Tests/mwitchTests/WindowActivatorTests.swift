import AppKit
import XCTest
@testable import mwitch

final class WindowActivatorTests: XCTestCase {
    func testActivationDoesNotBringAllApplicationWindowsForward() {
        XCTAssertFalse(
            WindowActivator.applicationActivationOptions.contains(.activateAllWindows)
        )
    }
}
