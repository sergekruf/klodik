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
}
