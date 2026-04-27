import XCTest
@testable import OpenLessHotkey

final class HotkeyBindingTests: XCTestCase {
    func test_defaultIsRightOption() {
        XCTAssertEqual(HotkeyBinding.default.trigger, .rightOption)
    }

    func test_codableRoundTrip() throws {
        let original = HotkeyBinding(trigger: .fn)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_allTriggersAreCovered() {
        XCTAssertEqual(HotkeyBinding.Trigger.allCases.count, 6)
    }

    func test_triggerRawValuesAreStable() {
        XCTAssertEqual(HotkeyBinding.Trigger.rightOption.rawValue, "rightOption")
        XCTAssertEqual(HotkeyBinding.Trigger.fn.rawValue, "fn")
    }
}
