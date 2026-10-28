import XCTest
@testable import KlodikCore

final class AttentionPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_200_000)
    let policy = AttentionPolicy()

    func item(_ dot: TrackedItem.Dot, waiting minutes: Double, opened: Bool = false) -> TrackedItem {
        TrackedItem(localId: UUID().uuidString, cliSessionId: nil, title: "s", projectName: "p", dot: dot,
                    waitingSince: now.addingTimeInterval(-minutes * 60), openedSinceWaiting: opened, detail: nil)
    }

    func attention(_ items: [TrackedItem], working: Int = 0, frontmost: Bool = false,
                   snoozedUntil: Date? = nil, quietFor minutes: Double = 1) -> Attention {
        policy.attention(items: items, workingCount: working, now: now, claudeFrontmost: frontmost,
                         snoozedUntil: snoozedUntil, lastActivityAt: now.addingTimeInterval(-minutes * 60))
    }

    // MARK: эскалация

    func testFreshUnopenedGrayJumpsOncePerMinute() {
        XCTAssertEqual(attention([item(.gray, waiting: 1)]).nudge, .jump(every: 60))
    }

    func testGrayWaiting2To10MinutesJumpsEvery30Seconds() {
        XCTAssertEqual(attention([item(.gray, waiting: 2)]).nudge, .jump(every: 30))
        XCTAssertEqual(attention([item(.gray, waiting: 9.9)]).nudge, .jump(every: 30))
    }

    func testGrayWaitingOver10MinutesJumpsContinuously() {
        XCTAssertEqual(attention([item(.gray, waiting: 10)]).nudge, .jumpContinuously)
    }

    func testOldestUnopenedGrayDecides() {
        let items = [item(.gray, waiting: 1), item(.gray, waiting: 12), item(.gray, waiting: 60, opened: true)]
        XCTAssertEqual(attention(items).nudge, .jumpContinuously)
    }

    func testOpenedGraysAreNotAReasonToJump() {
        XCTAssertEqual(attention([item(.gray, waiting: 60, opened: true)]).nudge, .wave(every: 300))
    }

    // MARK: синие и «напомнить»

    func testBlueAndRemindWaveSometimes() {
        XCTAssertEqual(attention([item(.blue, waiting: 30)]).nudge, .wave(every: 300))
        XCTAssertEqual(attention([item(.remind, waiting: 30)]).nudge, .wave(every: 300))
    }

    func testBadgeCountsEverything() {
        let items = [item(.gray, waiting: 1), item(.gray, waiting: 5, opened: true), item(.blue, waiting: 3)]
        XCTAssertEqual(attention(items).badge, 3)
    }

    // MARK: тишина

    func testClaudeInFrontMeansBadgeOnly() {
        let a = attention([item(.gray, waiting: 30)], frontmost: true)
        XCTAssertEqual(a.nudge, .none)
        XCTAssertEqual(a.badge, 1)
    }

    func testSnoozeSilencesUntilItEnds() {
        let items = [item(.gray, waiting: 30)]
        XCTAssertEqual(attention(items, snoozedUntil: now.addingTimeInterval(60)).nudge, .none)
        XCTAssertEqual(attention(items, snoozedUntil: now.addingTimeInterval(-1)).nudge, .jumpContinuously)
    }

    // MARK: фон

    func testEmptyListWhileWorking() {
        let a = attention([], working: 2)
        XCTAssertEqual(a, Attention(base: .working, nudge: .none, badge: 0))
    }

    func testEmptyListAndQuietFor15MinutesSleeps() {
        XCTAssertEqual(attention([], quietFor: 15).base, .sleep)
        XCTAssertEqual(attention([], quietFor: 5).base, .idle)
    }

    func testNeverSleepsWhileSomethingWaits() {
        XCTAssertEqual(attention([item(.blue, waiting: 120)], quietFor: 120).base, .idle)
    }

    func testWorkingStaysTheBaseUnderNudges() {
        let a = attention([item(.gray, waiting: 1)], working: 1)
        XCTAssertEqual(a.base, .working)
        XCTAssertEqual(a.nudge, .jump(every: 60))
    }
}
