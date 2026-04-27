import XCTest
@testable import OpenLessHotkey

final class HotkeyEventTests: XCTestCase {
    func test_eventsAreDistinct() {
        XCTAssertNotEqual(HotkeyEvent.toggled, .cancelled)
    }
}
