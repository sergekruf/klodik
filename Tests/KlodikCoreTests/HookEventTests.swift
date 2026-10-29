import XCTest
@testable import KlodikCore

final class HookEventTests: XCTestCase {
    let at = Date(timeIntervalSince1970: 1_793_125_765)

    func parse(_ json: String) -> HookEvent? {
        HookEvent.parse(Data(json.utf8), at: at)
    }

    func common(_ event: String, _ extra: String = "") -> String {
        """
        {"session_id": "53c48b4e-1111-2222-3333-444455556666",
         "transcript_path": "/Users/x/.claude/projects/p/53c48b4e.jsonl",
         "cwd": "/Users/x/Documents/claude/sandbox-hooks",
         "permission_mode": "default",
         "hook_event_name": "\(event)"\(extra)}
        """
    }

    func testCommonFields() throws {
        let event = try XCTUnwrap(parse(common("Stop")))
        XCTAssertEqual(event.sessionId, "53c48b4e-1111-2222-3333-444455556666")
        XCTAssertEqual(event.cwd, "/Users/x/Documents/claude/sandbox-hooks")
        XCTAssertEqual(event.at, at)
        XCTAssertEqual(event.kind, .stop)
    }

    func testEveryKnownEvent() {
        XCTAssertEqual(parse(common("SessionStart"))?.kind, .sessionStart)
        XCTAssertEqual(parse(common("UserPromptSubmit", #", "prompt": "выполни команду date""#))?.kind, .promptSubmit)
        XCTAssertEqual(parse(common("PreToolUse", #", "tool_name": "Bash", "tool_input": {"command": "date"}"#))?.kind,
                       .preTool("Bash"))
        XCTAssertEqual(parse(common("PostToolUse", #", "tool_name": "Bash", "tool_response": {}"#))?.kind, .postTool("Bash"))
        XCTAssertEqual(parse(common("PermissionRequest", #", "tool_name": "Bash", "tool_input": {"command": "touch test.txt"}"#))?.kind,
                       .permissionRequest("Bash"))
        XCTAssertEqual(parse(common("Notification",
                                    #", "message": "Claude needs your permission to use Bash", "notification_type": "permission_prompt""#))?.kind,
                       .notification("permission_prompt"))
        XCTAssertEqual(parse(common("StopFailure"))?.kind, .stopFailure)
        XCTAssertEqual(parse(common("SessionEnd", #", "reason": "other""#))?.kind, .sessionEnd)
    }

    func testNotificationWithoutTypeIsStillANotification() {
        XCTAssertEqual(parse(common("Notification", #", "message": "hi""#))?.kind, .notification(""))
    }

    func testUnknownEventIsIgnored() {
        XCTAssertNil(parse(common("PreCompact")))
    }

    func testMissingSessionIdIsIgnored() {
        XCTAssertNil(parse(#"{"hook_event_name": "Stop"}"#))
    }

    func testBrokenJsonIsIgnored() {
        XCTAssertNil(parse(#"{"session_id": "a", "hook_event_name": "#))
    }

    // MARK: что просит

    func testRequestDetails() {
        XCTAssertEqual(parse(common("PermissionRequest", #", "tool_name": "Bash", "tool_input": {"command": "npm run build\nnpm test"}"#))?.detail,
                       "Bash: npm run build")
        XCTAssertEqual(parse(common("PreToolUse", #", "tool_name": "Edit", "tool_input": {"file_path": "/Users/x/p/Tracker.swift"}"#))?.detail,
                       "Edit: Tracker.swift")
        XCTAssertEqual(parse(common("PreToolUse", #", "tool_name": "WebFetch", "tool_input": {"url": "https://github.com/a/b"}"#))?.detail,
                       "WebFetch: github.com")
        XCTAssertEqual(parse(common("PreToolUse", #", "tool_name": "mcp__ccd_session__start_session", "tool_input": {}"#))?.detail,
                       "start_session")
        XCTAssertEqual(parse(common("PreToolUse",
                                    #", "tool_name": "AskUserQuestion", "tool_input": {"questions": [{"question": "CSV или Google Sheets?"}]}"#))?.detail,
                       "CSV или Google Sheets?")
        XCTAssertEqual(parse(common("Notification", #", "message": "Claude needs your permission", "notification_type": "permission_prompt""#))?.detail,
                       "Claude needs your permission")
        XCTAssertNil(parse(common("Stop"))?.detail)
    }

    func testAskUserQuestionOptions() {
        let json = #", "tool_name": "AskUserQuestion", "tool_input": {"questions": [{"question": "Что генерируем?", "multiSelect": false, "options": [{"label": "Светлая версия", "description": "Пилот на одном артикуле"}, {"label": "Видео", "description": ""}, {"description": "без подписи"}]}, {"question": "", "options": []}, {"question": "Какие артикулы?", "multiSelect": true, "options": []}]}"#
        XCTAssertEqual(parse(common("PreToolUse", json))?.questions, [
            AskedQuestion(text: "Что генерируем?", options: [.init(label: "Светлая версия", description: "Пилот на одном артикуле"),
                                                            .init(label: "Видео")]),
            AskedQuestion(text: "Какие артикулы?", options: [], multiSelect: true),
        ])
        XCTAssertEqual(parse(common("PreToolUse", #", "tool_name": "Bash", "tool_input": {"command": "ls"}"#))?.questions, [])
    }

    func testLongDetailIsClipped() {
        let long = String(repeating: "a", count: 300)
        let detail = parse(common("PermissionRequest", #", "tool_name": "Bash", "tool_input": {"command": "\#(long)"}"#))?.detail
        XCTAssertEqual(detail?.count, 120)
        XCTAssertEqual(detail?.last, "…")
    }
}
