import XCTest
@testable import KlodikCore

final class PlacementTests: XCTestCase {
    let size = CGSize(width: 48, height: 48)
    let main = CGRect(x: 0, y: 80, width: 1440, height: 820)    // видимая область без Dock и меню
    let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func testNoSavedPositionGoesToBottomRightCorner() {
        let origin = Placement.resolvedOrigin(saved: nil, petSize: size, visibleFrames: [main, second])
        XCTAssertEqual(origin, CGPoint(x: 1440 - 48 - Placement.margin, y: 80 + Placement.margin))
    }

    func testSavedPositionOnScreenIsKept() {
        let saved = CGPoint(x: 1800, y: 500)
        XCTAssertEqual(Placement.resolvedOrigin(saved: saved, petSize: size, visibleFrames: [main, second]), saved)
    }

    func testSavedPositionOnDisconnectedMonitorFallsBackToCorner() {
        let saved = CGPoint(x: 1800, y: 500)   // был на втором мониторе, его отключили
        let origin = Placement.resolvedOrigin(saved: saved, petSize: size, visibleFrames: [main])
        XCTAssertEqual(origin, CGPoint(x: 1440 - 48 - Placement.margin, y: 80 + Placement.margin))
    }

    func testPetMostlyOffScreenFallsBackToCorner() {
        let saved = CGPoint(x: 1430, y: 500)   // центр за правым краем единственного экрана
        let origin = Placement.resolvedOrigin(saved: saved, petSize: size, visibleFrames: [main])
        XCTAssertEqual(origin, CGPoint(x: 1440 - 48 - Placement.margin, y: 80 + Placement.margin))
    }

    func testNoScreensReturnsZero() {
        XCTAssertEqual(Placement.resolvedOrigin(saved: nil, petSize: size, visibleFrames: []), .zero)
    }
}
