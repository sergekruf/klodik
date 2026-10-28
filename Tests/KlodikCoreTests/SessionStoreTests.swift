import XCTest
@testable import KlodikCore

final class SessionStoreTests: XCTestCase {
    var root: URL!
    var folder: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("klodik-sessions-\(UUID().uuidString)")
        folder = root.appendingPathComponent("acc/org")   // как у приложения: <аккаунт>/<организация>/local_*.json
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ name: String, _ json: String) throws {
        try Data(json.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    func session(_ id: String, title: String) -> String {
        #"{"sessionId": "\#(id)", "cwd": "/tmp/p", "title": "\#(title)"}"#
    }

    func testLoadAllReadsSessionsAndSkipsJunk() throws {
        try write("local_a.json", session("local_a", title: "A"))
        try write("local_b.json", session("local_b", title: "B"))
        try write("local_broken.json", "{ не json")
        try write("deleted_c", session("local_c", title: "C"))

        let store = SessionStore(root: root)
        store.loadAll()
        XCTAssertEqual(Set(store.sessions.keys), ["local_a", "local_b"])
        XCTAssertFalse(store.formatBroken)
    }

    func testMissingFolderMeansBrokenFormat() {
        let store = SessionStore(root: root.appendingPathComponent("nope"))
        store.loadAll()
        XCTAssertTrue(store.formatBroken)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testAllFilesUnreadableMeansBrokenFormat() throws {
        try write("local_a.json", #"{"id": "формат поменялся"}"#)
        let store = SessionStore(root: root)
        store.loadAll()
        XCTAssertTrue(store.formatBroken)
    }

    func testReloadPicksUpChangesAndDeletions() throws {
        try write("local_a.json", session("local_a", title: "A"))
        try write("local_b.json", session("local_b", title: "B"))
        let store = SessionStore(root: root)
        store.loadAll()

        try write("local_a.json", session("local_a", title: "A2"))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("local_b.json"))
        store.reload(paths: [folder.appendingPathComponent("local_a.json").path,
                             folder.appendingPathComponent("local_b.json").path])

        XCTAssertEqual(store.sessions["local_a"]?.title, "A2")
        XCTAssertNil(store.sessions["local_b"])
    }

    func testHalfWrittenFileKeepsPreviousValue() throws {
        try write("local_a.json", session("local_a", title: "A"))
        let store = SessionStore(root: root)
        store.loadAll()
        try write("local_a.json", #"{"sessionId": "local_a", "ti"#)
        store.reload(paths: [folder.appendingPathComponent("local_a.json").path])
        XCTAssertEqual(store.sessions["local_a"]?.title, "A")
    }

    func testCopyInAnotherAccountFolderLosesToTheFresherOne() throws {
        // Приложение хранит копии сессий в папках разных аккаунтов; живая — с самой поздней активностью.
        let other = root.appendingPathComponent("old-acc/old-org")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let stale = #"{"sessionId": "local_a", "title": "Старая", "lastActivityAt": 1000}"#
        let fresh = #"{"sessionId": "local_a", "title": "Свежая", "lastActivityAt": 2000}"#
        try Data(stale.utf8).write(to: other.appendingPathComponent("local_a.json"))
        try write("local_a.json", fresh)

        let store = SessionStore(root: root)
        store.loadAll()
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions["local_a"]?.title, "Свежая")

        // Старую копию трогают — свежая остаётся.
        store.reload(paths: [other.appendingPathComponent("local_a.json").path])
        XCTAssertEqual(store.sessions["local_a"]?.title, "Свежая")

        // Свежую удалили — показываем оставшуюся копию.
        try FileManager.default.removeItem(at: folder.appendingPathComponent("local_a.json"))
        store.reload(paths: [folder.appendingPathComponent("local_a.json").path])
        XCTAssertEqual(store.sessions["local_a"]?.title, "Старая")
    }

    func testWatchingNoticesNewFile() throws {
        let store = SessionStore(root: root)
        store.loadAll()
        let changed = expectation(description: "FSEvents сообщил о новом файле")
        store.onChange = { if store.sessions["local_new"] != nil { changed.fulfill() } }
        store.startWatching(latency: 0.1)
        defer { store.stopWatching() }

        try write("local_new.json", session("local_new", title: "Новая"))
        wait(for: [changed], timeout: 5)
    }
}
