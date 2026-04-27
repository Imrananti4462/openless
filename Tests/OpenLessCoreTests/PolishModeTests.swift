import XCTest
@testable import OpenLessCore

final class PolishModeTests: XCTestCase {
    func test_allCasesAndDisplayNames() {
        XCTAssertEqual(PolishMode.allCases.count, 4)
        XCTAssertEqual(PolishMode.light.displayName, "轻度润色")
        XCTAssertEqual(PolishMode.structured.displayName, "清晰结构")
    }

    func test_codableRoundTrip() throws {
        let original = PolishMode.formal
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PolishMode.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
