import XCTest
@testable import KlodikCore

final class WaitTimeTests: XCTestCase {
    override func setUp() { Lang.current = .ru }

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

    func testDurationForDaySummary() {
        XCTAssertEqual(WaitTime.duration(20), "меньше минуты")
        XCTAssertEqual(WaitTime.duration(4 * 60 + 30), "4 мин")
        XCTAssertEqual(WaitTime.duration(3600), "1 ч")
        XCTAssertEqual(WaitTime.duration(80 * 60), "1 ч 20 мин")
        XCTAssertEqual(WaitTime.duration(50 * 3600), "2 дн")
    }

    func testEnglish() {
        Lang.current = .en
        defer { Lang.current = .ru }
        XCTAssertEqual(WaitTime.short(30), "just now")
        XCTAssertEqual(WaitTime.short(12 * 60), "12 min")
        XCTAssertEqual(WaitTime.duration(80 * 60), "1 h 20 min")
        XCTAssertEqual(ReminderScale.normal.title, "Normal")
    }

    func testAgeSteps() {
        XCTAssertEqual(WaitTime.age(23 * 3600), .fresh)
        XCTAssertEqual(WaitTime.age(25 * 3600), .day)
        XCTAssertEqual(WaitTime.age(71 * 3600), .day)
        XCTAssertEqual(WaitTime.age(73 * 3600), .days)
    }

    func testNextMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Yekaterinburg")!
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        XCTAssertEqual(WaitTime.nextMorning(after: at(30, 23), calendar: calendar), at(31, 9))
        XCTAssertEqual(WaitTime.nextMorning(after: at(30, 2), calendar: calendar), at(30, 9))     // ночью — до сегодняшнего утра
        XCTAssertEqual(WaitTime.nextMorning(after: at(30, 9), calendar: calendar), at(31, 9))
        XCTAssertEqual(WaitTime.nextMorning(after: at(30, 8, 59), calendar: calendar), at(30, 9))
    }
}
