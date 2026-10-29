import XCTest
@testable import KlodikCore

final class MorningDigestTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Yekaterinburg")!
        return c
    }()

    func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testOncePerDayAfterSix() {
        XCTAssertTrue(MorningDigest.isDue(lastShown: nil, now: at(30, 9), calendar: calendar))
        XCTAssertFalse(MorningDigest.isDue(lastShown: nil, now: at(30, 2), calendar: calendar))       // ночь — ещё вчера
        XCTAssertFalse(MorningDigest.isDue(lastShown: at(30, 9), now: at(30, 18), calendar: calendar))
        XCTAssertTrue(MorningDigest.isDue(lastShown: at(29, 9), now: at(30, 6), calendar: calendar))
        XCTAssertFalse(MorningDigest.isDue(lastShown: at(29, 9), now: at(30, 1), calendar: calendar))
    }

    func testCountsWaitingAndFindsOldest() {
        func item(_ id: String, _ dot: TrackedItem.Dot, _ hoursAgo: Double, opened: Bool = false) -> TrackedItem {
            TrackedItem(localId: id, cliSessionId: nil, title: id, projectName: "p", dot: dot,
                        waitingSince: Date().addingTimeInterval(-hoursAgo * 3600), openedSinceWaiting: opened, detail: nil)
        }
        let digest = MorningDigest.make(items: [item("a", .waiting, 2), item("b", .waiting, 70, opened: true),
                                                item("c", .blue, 100), item("d", .remind, 90)])
        XCTAssertEqual(digest?.waiting, 2)
        XCTAssertEqual(digest?.oldest.localId, "b")
        XCTAssertNil(MorningDigest.make(items: [item("c", .blue, 1)]))
    }
}
