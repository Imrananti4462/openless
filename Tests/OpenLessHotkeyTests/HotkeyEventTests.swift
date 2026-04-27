import XCTest
@testable import OpenLessHotkey

final class HotkeyEventTests: XCTestCase {
    func test_eventsAreDistinct() {
        XCTAssertNotEqual(HotkeyEvent.pressed, .released)
        XCTAssertNotEqual(HotkeyEvent.pressed, .cancelled)
        XCTAssertNotEqual(HotkeyEvent.released, .cancelled)
    }
}
