import XCTest
@testable import KlodikCore

final class ReminderScaleTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_200_000)

    func nudge(_ scale: ReminderScale, waiting minutes: Double) -> Attention.Nudge {
        var config = AttentionPolicy.Config()
        scale.apply(to: &config)
        let item = TrackedItem(localId: "a", cliSessionId: nil, title: "s", projectName: "p", dot: .gray,
                               waitingSince: now.addingTimeInterval(-minutes * 60), openedSinceWaiting: false, detail: nil)
        return AttentionPolicy(config: config).attention(items: [item], workingCount: 0, now: now, claudeFrontmost: false,
                                                         snoozedUntil: nil, lastActivityAt: now).nudge
    }

    func testNormalIsTheDesignScale() {
        XCTAssertEqual(nudge(.normal, waiting: 1), .jump(every: 60))
        XCTAssertEqual(nudge(.normal, waiting: 5), .jump(every: 30))
        XCTAssertEqual(nudge(.normal, waiting: 15), .jump(every: 30))
        XCTAssertEqual(nudge(.normal, waiting: 600), .jump(every: 30))
    }

    func testGentleNeverJumpsNonStop() {
        XCTAssertEqual(nudge(.gentle, waiting: 1), .jump(every: 120))
        XCTAssertEqual(nudge(.gentle, waiting: 60), .jump(every: 60))
    }

    func testInsistentEscalatesFaster() {
        XCTAssertEqual(nudge(.insistent, waiting: 1), .jump(every: 30))
        XCTAssertEqual(nudge(.insistent, waiting: 3), .jumpContinuously)
    }

    func testDefaultStateUsesNormalScaleAndAWeek() {
        let state = AppState()
        XCTAssertEqual(state.reminderScale, .normal)
        XCTAssertEqual(state.windowDays, 7)
    }
}
