import XCTest
@testable import KlodikCore

final class SessionLinkTests: XCTestCase {
    func testLocalIdOpensTheSession() {
        XCTAssertEqual(SessionLink.url(localId: "local_fbc15b63-ad05-448c-9e9c-f9e2d2d364b2")?.absoluteString,
                       "claude://code/continue?session=local_fbc15b63-ad05-448c-9e9c-f9e2d2d364b2")
    }

    func testIdsTheAppWouldRejectGiveNil() {
        // Приложение Claude принимает только ^local_[A-Za-z0-9-]{1,64}$, остальное молча игнорирует.
        XCTAssertNil(SessionLink.url(localId: "528d83eb-018b-4b14-9516-8d7217939ee8"))   // номер Claude Code
        XCTAssertNil(SessionLink.url(localId: "local_"))
        XCTAssertNil(SessionLink.url(localId: "local_a&b=c"))
        XCTAssertNil(SessionLink.url(localId: "local_" + String(repeating: "a", count: 65)))
    }
}
