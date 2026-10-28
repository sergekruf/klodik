import XCTest
@testable import KlodikCore

final class WaitTimeTests: XCTestCase {
    func testShortForms() {
        XCTAssertEqual(WaitTime.short(20), "только что")
        XCTAssertEqual(WaitTime.short(60), "1 мин")
        XCTAssertEqual(WaitTime.short(12 * 60 + 40), "12 мин")
        XCTAssertEqual(WaitTime.short(59 * 60), "59 мин")
        XCTAssertEqual(WaitTime.short(3600), "1 ч")
        XCTAssertEqual(WaitTime.short(20 * 3600 + 1800), "20 ч")
        XCTAssertEqual(WaitTime.short(24 * 3600), "1 дн")
        XCTAssertEqual(WaitTime.short(4 * 24 * 3600), "4 дн")
    }

    func testNegativeIsJustNow() {
        XCTAssertEqual(WaitTime.short(-5), "только что")
    }
}
