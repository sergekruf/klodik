import XCTest
@testable import KlodikCore

/// Фикстуры повторяют настоящие файлы приложения Claude, сокращённо.
enum Fixtures {
    static let full = """
    {
      "sessionId": "local_fbc15b63-ad05-448c-9e9c-f9e2d2d364b2",
      "cliSessionId": "528d83eb-018b-4b14-9516-8d7217939ee8",
      "cwd": "/Users/sergekruf/Documents/claude/pitomec-claude",
      "originCwd": "/Users/sergekruf/Documents/claude/pitomec-claude",
      "lastFocusedAt": 1793123819795,
      "createdAt": 1793099223738,
      "lastActivityAt": 1793123956294,
      "lastTurnEdgeAt": 1793123953228,
      "model": "claude-opus-5-5",
      "isArchived": false,
      "title": "Питомец Claude поверх окон",
      "enabledMcpTools": {"x:copy_file": false},
      "postTurnSummary": {
        "status_category": "blocked",
        "status_detail": "ждёт решения по мобильной обложке",
        "needs_action": true,
        "summarizes_uuid": "1c7d8e7e"
      }
    }
    """

    static let noCliId = """
    {"sessionId": "local_25e405f4", "cwd": "/Users/sergekruf/Documents/claude/vk-constructor",
     "createdAt": 1777739006320, "lastActivityAt": 1778905121063, "isArchived": true, "title": "vk конструктор"}
    """
}

final class SessionFileTests: XCTestCase {
    func testFullFileGivesAllFields() throws {
        let info = try XCTUnwrap(SessionFile.parse(Data(Fixtures.full.utf8)))
        XCTAssertEqual(info.localId, "local_fbc15b63-ad05-448c-9e9c-f9e2d2d364b2")
        XCTAssertEqual(info.cliSessionId, "528d83eb-018b-4b14-9516-8d7217939ee8")
        XCTAssertEqual(info.title, "Питомец Claude поверх окон")
        XCTAssertEqual(info.projectName, "pitomec-claude")
        XCTAssertFalse(info.isArchived)
        XCTAssertEqual(info.lastFocusedAt, Date(timeIntervalSince1970: 1793123819.795))
        XCTAssertEqual(info.lastTurnEdgeAt, Date(timeIntervalSince1970: 1793123953.228))
        XCTAssertEqual(info.lastActivityAt, Date(timeIntervalSince1970: 1793123956.294))
        XCTAssertEqual(info.statusCategory, .blocked)
        XCTAssertEqual(info.statusDetail, "ждёт решения по мобильной обложке")
    }

    func testOldFileWithoutCliIdSummaryOrFocus() throws {
        let info = try XCTUnwrap(SessionFile.parse(Data(Fixtures.noCliId.utf8)))
        XCTAssertNil(info.cliSessionId)
        XCTAssertNil(info.lastFocusedAt)
        XCTAssertNil(info.lastTurnEdgeAt)
        XCTAssertNil(info.statusCategory)
        XCTAssertTrue(info.isArchived)
        XCTAssertEqual(info.projectName, "vk-constructor")
    }

    func testUnknownStatusCategoryIsKeptAsOther() throws {
        let json = #"{"sessionId": "local_a", "postTurnSummary": {"status_category": "something_new"}}"#
        XCTAssertEqual(try XCTUnwrap(SessionFile.parse(Data(json.utf8))).statusCategory, .other)
    }

    func testMissingTitleFallsBackToProjectName() throws {
        let json = #"{"sessionId": "local_a", "cwd": "/tmp/my-project"}"#
        XCTAssertEqual(try XCTUnwrap(SessionFile.parse(Data(json.utf8))).title, "my-project")
    }

    func testBrokenJsonGivesNil() {
        XCTAssertNil(SessionFile.parse(Data("{ \"sessionId\": ".utf8)))
    }

    func testFileWithoutSessionIdGivesNil() {
        XCTAssertNil(SessionFile.parse(Data(#"{"title": "x"}"#.utf8)))
    }

    func testOnlyLocalJsonFilesAreSessions() {
        XCTAssertTrue(SessionFile.isSessionFile("local_fbc15b63.json"))
        XCTAssertFalse(SessionFile.isSessionFile("deleted_ca62c7a2"))
        XCTAssertFalse(SessionFile.isSessionFile("deleted_ca62c7a2.json"))
        XCTAssertFalse(SessionFile.isSessionFile("local_fbc15b63.json.tmp"))
    }
}
