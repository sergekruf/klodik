import XCTest
@testable import KlodikCore

final class TrackerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_200_000)
    var tracker: Tracker!

    override func setUp() {
        tracker = Tracker()
    }

    func t(_ minutesAgo: Double) -> Date { now.addingTimeInterval(-minutesAgo * 60) }

    func session(_ n: Int, focused: Double? = nil, edge: Double? = nil, activity: Double? = nil,
                 status: StatusCategory? = nil, archived: Bool = false) -> SessionInfo {
        SessionInfo(localId: "local_\(n)", cliSessionId: "cli_\(n)", title: "Сессия \(n)", projectName: "p\(n)",
                    isArchived: archived, lastFocusedAt: focused.map(t), lastTurnEdgeAt: edge.map(t),
                    lastActivityAt: (activity ?? edge ?? focused).map(t), statusCategory: status)
    }

    func event(_ n: Int, _ kind: HookKind, _ minutesAgo: Double) -> HookEvent {
        HookEvent(sessionId: "cli_\(n)", kind: kind, at: t(minutesAgo))
    }

    func items() -> [TrackedItem] { tracker.items(now: now) }
    func dot(_ n: Int) -> TrackedItem.Dot? { items().first { $0.localId == "local_\(n)" }?.dot }

    // MARK: серая

    func testPermissionRequestHookMakesGray() {
        tracker.update(sessions: [session(1, focused: 30, edge: 20, status: .completed)])
        tracker.handle(event(1, .promptSubmit, 10), claudeFrontmost: false)
        tracker.handle(event(1, .permissionRequest("Bash"), 5), claudeFrontmost: false)
        XCTAssertEqual(dot(1), .gray)
        XCTAssertEqual(items().first?.waitingSince, t(5))
    }

    func testQuestionNotificationsMakeGrayButIdlePromptDoesNot() {
        tracker.update(sessions: [session(1, focused: 30), session(2, focused: 30), session(3, focused: 30), session(4, focused: 30)])
        tracker.handle(event(1, .notification("permission_prompt"), 5), claudeFrontmost: false)
        tracker.handle(event(2, .notification("elicitation_dialog"), 5), claudeFrontmost: false)
        tracker.handle(event(3, .notification("agent_needs_input"), 5), claudeFrontmost: false)
        tracker.handle(event(4, .notification("idle_prompt"), 5), claudeFrontmost: false)
        XCTAssertEqual(dot(1), .gray)
        XCTAssertEqual(dot(2), .gray)
        XCTAssertEqual(dot(3), .gray)
        XCTAssertNil(dot(4))
    }

    func testBlockedSummaryInFileMakesGray() {
        tracker.update(sessions: [session(1, focused: 60, edge: 30, status: .blocked)])
        XCTAssertEqual(dot(1), .gray)
        XCTAssertEqual(items().first?.waitingSince, t(30))
    }

    func testGrayClearsAfterUserAnswers() {
        tracker.update(sessions: [session(1, focused: 30, edge: 20, status: .blocked)])
        tracker.handle(event(1, .promptSubmit, 2), claudeFrontmost: true)
        XCTAssertNotEqual(dot(1), .gray)
    }

    func testGrayClearsAfterPermissionGranted() {
        tracker.update(sessions: [session(1, focused: 30, edge: 20, status: .completed)])
        tracker.handle(event(1, .preTool("Bash"), 6), claudeFrontmost: false)
        tracker.handle(event(1, .permissionRequest("Bash"), 6), claudeFrontmost: false)
        tracker.handle(event(1, .notification("permission_prompt"), 5.9), claudeFrontmost: false)
        XCTAssertEqual(dot(1), .gray)
        tracker.handle(event(1, .postTool("Bash"), 4), claudeFrontmost: false)
        XCTAssertNotEqual(dot(1), .gray)
    }

    func testGrayClearsWhenNextTurnIsNotBlocked() {
        tracker.update(sessions: [session(1, focused: 30, edge: 20, status: .blocked)])
        tracker.update(sessions: [session(1, focused: 15, edge: 10, status: .completed)])
        XCTAssertEqual(dot(1), .blue)
    }

    func testOpenedGrayStaysButIsMarkedOpened() {
        tracker.update(sessions: [session(1, focused: 10, edge: 20, status: .blocked),
                                  session(2, focused: 30, edge: 20, status: .blocked)])
        XCTAssertEqual(items().first { $0.localId == "local_1" }?.openedSinceWaiting, true)
        XCTAssertEqual(items().first { $0.localId == "local_2" }?.openedSinceWaiting, false)
        XCTAssertEqual(dot(1), .gray)
    }

    // MARK: синяя

    func testFinishedAfterLastOpenIsBlue() {
        tracker.update(sessions: [session(1, focused: 30, edge: 10, status: .completed)])
        XCTAssertEqual(dot(1), .blue)
        XCTAssertEqual(items().first?.waitingSince, t(10))
    }

    func testOpeningClearsBlue() {
        tracker.update(sessions: [session(1, focused: 30, edge: 10, status: .completed)])
        tracker.update(sessions: [session(1, focused: 5, edge: 10, status: .completed)])
        XCTAssertNil(dot(1))
    }

    func testStopHookMakesBlueBeforeTheFileCatchesUp() {
        tracker.update(sessions: [session(1, focused: 30, edge: 40, status: .completed)])
        XCTAssertNil(dot(1))
        tracker.handle(event(1, .promptSubmit, 3), claudeFrontmost: false)
        tracker.handle(event(1, .stop, 1), claudeFrontmost: false)
        XCTAssertEqual(dot(1), .blue)
    }

    func testFinishingWhileOnScreenCountsAsRead() {
        // Сессия 1 открыта последней, Claude на переднем плане — пользователь видит, как она закончила.
        tracker.update(sessions: [session(1, focused: 5, edge: 40), session(2, focused: 20, edge: 40)])
        tracker.handle(event(1, .stop, 1), claudeFrontmost: true)
        XCTAssertNil(dot(1))
    }

    func testFinishingWhileClaudeInBackgroundIsBlue() {
        tracker.update(sessions: [session(1, focused: 5, edge: 40)])
        tracker.handle(event(1, .stop, 1), claudeFrontmost: false)
        XCTAssertEqual(dot(1), .blue)
    }

    func testReturningToClaudeReadsTheSessionOnScreen() {
        // Сессия 1 открыта в Claude, но закончила, пока пользователь был в другом приложении. Он вернулся в Claude.
        tracker.update(sessions: [session(1, focused: 30, edge: 3), session(2, focused: 40, edge: 3)])
        tracker.handle(event(1, .stop, 3), claudeFrontmost: false)
        XCTAssertEqual(dot(1), .blue)
        tracker.markOnScreenRead(at: t(1))
        XCTAssertNil(dot(1))
        XCTAssertEqual(dot(2), .blue)   // другую сессию он не видел
    }

    func testReturningToClaudeDoesNotClearGray() {
        tracker.update(sessions: [session(1, focused: 30, edge: 3, status: .blocked)])
        tracker.markOnScreenRead(at: t(1))
        XCTAssertEqual(dot(1), .gray)
    }

    func testFinishingWhileAnotherSessionIsOnScreenIsBlue() {
        tracker.update(sessions: [session(1, focused: 20, edge: 40), session(2, focused: 5, edge: 40)])
        tracker.handle(event(1, .stop, 1), claudeFrontmost: true)
        XCTAssertEqual(dot(1), .blue)
    }

    func testWorkingSessionIsNotBlue() {
        tracker.update(sessions: [session(1, focused: 30, edge: 10, status: .completed)])
        tracker.handle(event(1, .promptSubmit, 1), claudeFrontmost: false)
        XCTAssertNil(dot(1))
    }

    // MARK: «напомнить» и «скрыть»

    func testRemindMarkHoldsUntilOpened() {
        tracker.update(sessions: [session(1, focused: 30, edge: 40)])
        tracker.markRemind("local_1", at: t(20))
        XCTAssertEqual(dot(1), .remind)
        XCTAssertEqual(items().first?.waitingSince, t(20))
        tracker.update(sessions: [session(1, focused: 10, edge: 40)])
        XCTAssertNil(dot(1))
        XCTAssertTrue(tracker.remind.isEmpty)
    }

    func testRemindMarkCanBeRemoved() {
        tracker.update(sessions: [session(1, focused: 30, edge: 40)])
        tracker.markRemind("local_1", at: t(20))
        tracker.unmarkRemind("local_1")
        XCTAssertNil(dot(1))
    }

    func testRemindOnBlueShowsRemindAndGrayBeatsRemind() {
        tracker.update(sessions: [session(1, focused: 30, edge: 10), session(2, focused: 30, edge: 10, status: .blocked)])
        tracker.markRemind("local_1", at: t(5))
        tracker.markRemind("local_2", at: t(5))
        XCTAssertEqual(dot(1), .remind)
        XCTAssertEqual(dot(2), .gray)
    }

    func testMarksChangedCallback() {
        var calls = 0
        tracker.onMarksChanged = { calls += 1 }
        tracker.update(sessions: [session(1, focused: 30, edge: 40)])
        tracker.markRemind("local_1", at: t(20))
        tracker.update(sessions: [session(1, focused: 10, edge: 40)])   // открыли — метка снята сама
        XCTAssertEqual(calls, 2)
    }

    func testHiddenUntilNextActivity() {
        tracker.update(sessions: [session(1, focused: 60, edge: 30, status: .blocked)])
        tracker.hide("local_1", at: t(20))
        XCTAssertNil(dot(1))
        tracker.update(sessions: [session(1, focused: 60, edge: 5, status: .blocked)])
        XCTAssertEqual(dot(1), .gray)
        XCTAssertTrue(tracker.hidden.isEmpty)
    }

    func testHiddenComesBackOnNewPermissionRequest() {
        tracker.update(sessions: [session(1, focused: 60, edge: 30, status: .blocked)])
        tracker.hide("local_1", at: t(20))
        tracker.handle(event(1, .permissionRequest("Bash"), 2), claudeFrontmost: false)
        XCTAssertEqual(dot(1), .gray)
    }

    // MARK: какие сессии вообще смотрим

    func testOnlyRecentUnarchivedSessions() {
        let week = 7 * 24 * 60.0
        tracker.update(sessions: [session(1, focused: week + 100, edge: week + 10, status: .blocked),
                                  session(2, focused: 60, edge: 30, status: .blocked, archived: true),
                                  session(3, focused: 60, edge: 30, status: .blocked)])
        XCTAssertEqual(items().map(\.localId), ["local_3"])
    }

    func testRemindIgnoresTheWindowButNotArchive() {
        let week = 7 * 24 * 60.0
        tracker.update(sessions: [session(1, focused: week + 100, edge: week + 100),
                                  session(2, focused: 60, edge: 60, archived: true)])
        tracker.markRemind("local_1", at: t(5))
        tracker.markRemind("local_2", at: t(5))
        XCTAssertEqual(items().map(\.localId), ["local_1"])
    }

    func testEventsFromSessionsWithoutFileAreIgnored() {
        tracker.update(sessions: [])
        tracker.handle(HookEvent(sessionId: "terminal", kind: .permissionRequest("Bash"), at: t(1)), claudeFrontmost: false)
        tracker.handle(HookEvent(sessionId: "terminal2", kind: .promptSubmit, at: t(1)), claudeFrontmost: false)
        XCTAssertTrue(items().isEmpty)
        XCTAssertTrue(tracker.workingSessions(now: now).isEmpty)
    }

    func testEventArrivingBeforeTheFileAppliesOnceFileShowsUp() {
        tracker.handle(event(1, .permissionRequest("Bash"), 1), claudeFrontmost: false)
        tracker.update(sessions: [session(1, focused: 2, edge: 2)])
        XCTAssertEqual(dot(1), .gray)
    }

    // MARK: работает

    func testWorkingFromPromptUntilStop() {
        tracker.update(sessions: [session(1, focused: 30, edge: 40)])
        tracker.handle(event(1, .promptSubmit, 3), claudeFrontmost: false)
        tracker.handle(event(1, .preTool("Bash"), 2), claudeFrontmost: false)
        XCTAssertEqual(tracker.workingSessions(now: now), ["local_1"])
        tracker.handle(event(1, .stop, 1), claudeFrontmost: false)
        XCTAssertTrue(tracker.workingSessions(now: now).isEmpty)
    }

    func testWaitingForPermissionIsNotWorking() {
        tracker.update(sessions: [session(1, focused: 30, edge: 40)])
        tracker.handle(event(1, .preTool("Bash"), 2), claudeFrontmost: false)
        tracker.handle(event(1, .permissionRequest("Bash"), 2), claudeFrontmost: false)
        XCTAssertTrue(tracker.workingSessions(now: now).isEmpty)
    }

    func testMissedStopExpiresAfter10Minutes() {
        tracker.update(sessions: [session(1, focused: 30, edge: 40)])
        tracker.handle(event(1, .preTool("Bash"), 11), claudeFrontmost: false)
        XCTAssertTrue(tracker.workingSessions(now: now).isEmpty)
    }

    // MARK: порядок

    func testNewestFirstWhateverTheDot() {
        tracker.update(sessions: [session(1, focused: 60, edge: 5, status: .completed),
                                  session(2, focused: 60, edge: 50, status: .completed),
                                  session(3, focused: 60, edge: 10, status: .blocked),
                                  session(4, focused: 60, edge: 40, status: .blocked)])
        XCTAssertEqual(items().map(\.localId), ["local_1", "local_3", "local_4", "local_2"])
    }

    // MARK: что просит

    func detail(_ n: Int) -> String? { items().first { $0.localId == "local_\(n)" }?.detail }

    func testPermissionShowsWhatIsAsked() {
        tracker.update(sessions: [session(1, focused: 30, edge: 20)])
        tracker.handle(HookEvent(sessionId: "cli_1", kind: .permissionRequest("Bash"), detail: "Bash: npm run build", at: t(2)),
                       claudeFrontmost: false)
        XCTAssertEqual(detail(1), "Bash: npm run build")
        tracker.handle(event(1, .postTool("Bash"), 1), claudeFrontmost: false)
        XCTAssertNil(dot(1))
    }

    func testQuestionTakesTextFromThePrecedingTool() {
        tracker.update(sessions: [session(1, focused: 30, edge: 20)])
        tracker.handle(HookEvent(sessionId: "cli_1", kind: .preTool("AskUserQuestion"), detail: "CSV или Google Sheets?", at: t(3)),
                       claudeFrontmost: false)
        tracker.handle(HookEvent(sessionId: "cli_1", kind: .notification("elicitation_dialog"), detail: "Claude has a question", at: t(2)),
                       claudeFrontmost: false)
        XCTAssertEqual(detail(1), "CSV или Google Sheets?")
    }

    func testFileBlockedAndBlueShowTheTurnSummary() {
        let blocked = SessionInfo(localId: "local_1", cliSessionId: "cli_1", title: "a", projectName: "p", lastFocusedAt: t(30),
                                  lastTurnEdgeAt: t(5), lastActivityAt: t(5), statusCategory: .blocked, statusDetail: "ждёт выбора обложки")
        let done = SessionInfo(localId: "local_2", cliSessionId: "cli_2", title: "b", projectName: "p", lastFocusedAt: t(30),
                               lastTurnEdgeAt: t(5), lastActivityAt: t(5), statusCategory: .completed, statusDetail: "сайт собран")
        tracker.update(sessions: [blocked, done])
        XCTAssertEqual(detail(1), "ждёт выбора обложки")
        XCTAssertEqual(detail(2), "сайт собран")
    }

    func testHookGrayDoesNotShowStaleSummary() {
        let s = SessionInfo(localId: "local_1", cliSessionId: "cli_1", title: "a", projectName: "p", lastFocusedAt: t(30),
                            lastTurnEdgeAt: t(20), lastActivityAt: t(20), statusCategory: .completed, statusDetail: "старый итог")
        tracker.update(sessions: [s])
        tracker.handle(event(1, .notification("permission_prompt"), 2), claudeFrontmost: false)
        XCTAssertEqual(dot(1), .gray)
        XCTAssertNil(detail(1))
    }

    // MARK: сводка за день

    func testAnsweringPermissionEndsTheWait() {
        var ended: [WaitRecord] = []
        tracker.onWaitEnded = { ended.append($0) }
        tracker.update(sessions: [session(1, focused: 30, edge: 20)])
        tracker.handle(event(1, .permissionRequest("Bash"), 6), claudeFrontmost: false)
        tracker.handle(event(1, .preTool("Bash"), 5), claudeFrontmost: false)   // ещё ждёт
        XCTAssertTrue(ended.isEmpty)
        tracker.handle(event(1, .postTool("Bash"), 2), claudeFrontmost: false)
        XCTAssertEqual(ended, [WaitRecord(localId: "local_1", title: "Сессия 1", start: t(6), end: t(2))])
    }

    func testAnsweringABlockedTurnEndsTheWait() {
        var ended: [WaitRecord] = []
        tracker.onWaitEnded = { ended.append($0) }
        tracker.update(sessions: [session(1, focused: 30, edge: 20, status: .blocked)])
        tracker.handle(event(1, .promptSubmit, 4), claudeFrontmost: true)
        XCTAssertEqual(ended.map(\.start), [t(20)])
        XCTAssertEqual(ended.map(\.end), [t(4)])
    }

    func testBlueSessionDoesNotCountAsWait() {
        var ended: [WaitRecord] = []
        tracker.onWaitEnded = { ended.append($0) }
        tracker.update(sessions: [session(1, focused: 30, edge: 20, status: .completed)])
        tracker.handle(event(1, .promptSubmit, 4), claudeFrontmost: true)
        XCTAssertTrue(ended.isEmpty)
    }
}
