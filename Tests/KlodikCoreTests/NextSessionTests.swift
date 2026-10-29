import XCTest
@testable import KlodikCore

final class NextSessionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_200_000)

    func item(_ id: String, _ dot: TrackedItem.Dot, waitingMinutes: Double, opened: Bool = false) -> TrackedItem {
        TrackedItem(localId: id, cliSessionId: nil, title: id, projectName: "p", dot: dot,
                    waitingSince: now.addingTimeInterval(-waitingMinutes * 60), openedSinceWaiting: opened, detail: nil)
    }

    lazy var items = [
        item("blue-old", .blue, waitingMinutes: 90),
        item("gray-opened", .waiting, waitingMinutes: 60, opened: true),
        item("gray-new", .waiting, waitingMinutes: 2),
        item("gray-old", .waiting, waitingMinutes: 30),
        item("remind", .remind, waitingMinutes: 5),
    ]

    func testOrderIsUnopenedGrayThenOpenedGrayThenRemindThenBlue() {
        XCTAssertEqual(NextSession.order(items).map(\.localId), ["gray-old", "gray-new", "gray-opened", "remind", "blue-old"])
    }

    func testClaudeUnreadGoesWithRemindBeforeBlue() {
        let list = [item("blue", .blue, waitingMinutes: 90), item("unread", .unread, waitingMinutes: 50), item("remind", .remind, waitingMinutes: 5)]
        XCTAssertEqual(NextSession.order(list).map(\.localId), ["unread", "remind", "blue"])
    }

    func testRepeatedPressesWalkTheQueueAndWrapAround() {
        var next = NextSession()
        let picks = (0..<6).map { i in next.pick(from: items, now: now.addingTimeInterval(Double(i)))?.localId }
        XCTAssertEqual(picks, ["gray-old", "gray-new", "gray-opened", "remind", "blue-old", "gray-old"])
    }

    func testLongPauseStartsOver() {
        var next = NextSession()
        _ = next.pick(from: items, now: now)
        XCTAssertEqual(next.pick(from: items, now: now.addingTimeInterval(11 * 60))?.localId, "gray-old")
    }

    func testEmptyListGivesNil() {
        var next = NextSession()
        XCTAssertNil(next.pick(from: [], now: now))
    }
}
