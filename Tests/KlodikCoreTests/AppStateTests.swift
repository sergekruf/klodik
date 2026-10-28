import XCTest
@testable import KlodikCore

final class AppStateTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("klodik-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRoundTripKeepsPetOrigin() throws {
        let url = dir.appendingPathComponent("state.json")
        var state = AppState()
        state.petOrigin = CGPoint(x: 120, y: 340)
        try state.save(to: url)   // папки ещё нет — save создаёт её сам
        XCTAssertEqual(AppState.load(from: url).petOrigin, CGPoint(x: 120, y: 340))
    }

    func testRoundTripKeepsMarks() throws {
        let url = dir.appendingPathComponent("state.json")
        var state = AppState()
        state.remind = ["local_a": Date(timeIntervalSince1970: 1000)]
        state.hidden = ["local_b": Date(timeIntervalSince1970: 2000)]
        try state.save(to: url)
        XCTAssertEqual(AppState.load(from: url), state)
    }

    func testFileFromStep1StillLoads() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.json")
        try Data(#"{"petOrigin": [400, 300]}"#.utf8).write(to: url)
        let state = AppState.load(from: url)
        XCTAssertEqual(state.petOrigin, CGPoint(x: 400, y: 300))
        XCTAssertTrue(state.remind.isEmpty)
    }

    func testMissingFileGivesDefaults() {
        XCTAssertNil(AppState.load(from: dir.appendingPathComponent("nope.json")).petOrigin)
    }

    func testBrokenFileGivesDefaults() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.json")
        try Data("{ не json".utf8).write(to: url)
        XCTAssertNil(AppState.load(from: url).petOrigin)
    }
}
