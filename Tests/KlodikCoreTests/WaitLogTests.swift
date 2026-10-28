import XCTest
@testable import KlodikCore

final class WaitLogTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Yekaterinburg")!
        return c
    }()
    /// 2026-10-28 15:00 по Екатеринбургу.
    lazy var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 15))!

    func record(_ title: String, minutes: Double, endedHoursAgo: Double) -> WaitRecord {
        let end = now.addingTimeInterval(-endedHoursAgo * 3600)
        return WaitRecord(localId: "local_\(title)", title: title, start: end.addingTimeInterval(-minutes * 60), end: end)
    }

    func testSummaryCountsOnlyToday() throws {
        var log = WaitLog()
        log.add(record("a", minutes: 2, endedHoursAgo: 1))
        log.add(record("b", minutes: 10, endedHoursAgo: 3))
        log.add(record("вчера", minutes: 90, endedHoursAgo: 20))   // 19:00 вчера
        let summary = try XCTUnwrap(log.summary(on: now, calendar: calendar))
        XCTAssertEqual(summary.answered, 2)
        XCTAssertEqual(summary.average, 6 * 60, accuracy: 0.001)
        XCTAssertEqual(summary.longest.title, "b")
    }

    func testNoAnswersTodayGivesNil() {
        var log = WaitLog()
        log.add(record("вчера", minutes: 5, endedHoursAgo: 20))
        XCTAssertNil(log.summary(on: now, calendar: calendar))
    }

    func testOldRecordsAreDropped() {
        var log = WaitLog()
        log.add(record("старое", minutes: 5, endedHoursAgo: 31 * 24))
        log.add(record("новое", minutes: 5, endedHoursAgo: 1))
        XCTAssertEqual(log.records.map(\.title), ["новое"])
    }

    func testSaveAndLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("klodik-waits-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var log = WaitLog()
        log.add(record("a", minutes: 3, endedHoursAgo: 1))
        try log.save(to: url)
        XCTAssertEqual(WaitLog.load(from: url), log)
        try Data("мусор".utf8).write(to: url)
        XCTAssertEqual(WaitLog.load(from: url), WaitLog())
    }
}
