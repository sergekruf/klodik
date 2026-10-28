import XCTest
@testable import KlodikCore

final class HookInstallerTests: XCTestCase {
    var dir: URL!
    var settings: URL { dir.appendingPathComponent("settings.json") }

    /// Как сейчас выглядит ~/.claude/settings.json пользователя, сокращённо.
    let userSettings = """
    {
      "cleanupPeriodDays": 99999,
      "enabledPlugins": {"superpowers@claude-plugins-official": true},
      "hooks": {
        "SessionStart": [
          {"hooks": [{"type": "command", "command": "/Users/sergekruf/scripts/hub-context.sh", "timeout": 10,
                      "statusMessage": "ProjectHub: проверяю задачи проекта"}]}
        ]
      }
    }
    """

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("klodik-hooks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func read() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
    }

    func hooks(_ event: String) throws -> [[String: Any]] {
        let all = try XCTUnwrap(read()["hooks"] as? [String: Any])
        let groups = (all[event] as? [[String: Any]]) ?? []
        return groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
    }

    func testInstallIntoMissingFileAddsEveryEvent() throws {
        try HookInstaller.install(settingsURL: settings, port: 47821)
        for event in HookInstaller.events {
            let list = try hooks(event)
            XCTAssertEqual(list.count, 1, event)
            XCTAssertEqual(list.first?["type"] as? String, "http")
            XCTAssertEqual(list.first?["url"] as? String, "http://127.0.0.1:47821/klodik/event")
            XCTAssertEqual(list.first?["timeout"] as? Int, HookInstaller.timeoutSeconds)
        }
        XCTAssertTrue(HookInstaller.isInstalled(settingsURL: settings, port: 47821))
    }

    func testUserHooksAndOtherSettingsSurvive() throws {
        try Data(userSettings.utf8).write(to: settings)
        try HookInstaller.install(settingsURL: settings, port: 47821)
        let start = try hooks("SessionStart")
        XCTAssertEqual(start.count, 1)
        XCTAssertEqual(start.first?["command"] as? String, "/Users/sergekruf/scripts/hub-context.sh")
        XCTAssertEqual(try read()["cleanupPeriodDays"] as? Int, 99999)
        XCTAssertNotNil(try read()["enabledPlugins"])
    }

    func testReinstallDoesNotDuplicateAndFollowsThePort() throws {
        try HookInstaller.install(settingsURL: settings, port: 47821)
        try HookInstaller.install(settingsURL: settings, port: 47822)
        let stop = try hooks("Stop")
        XCTAssertEqual(stop.count, 1)
        XCTAssertEqual(stop.first?["url"] as? String, "http://127.0.0.1:47822/klodik/event")
        XCTAssertFalse(HookInstaller.isInstalled(settingsURL: settings, port: 47821))
        XCTAssertTrue(HookInstaller.isInstalled(settingsURL: settings, port: 47822))
    }

    func testUninstallRemovesOnlyKlodik() throws {
        try Data(userSettings.utf8).write(to: settings)
        try HookInstaller.install(settingsURL: settings, port: 47821)
        try HookInstaller.uninstall(settingsURL: settings)
        let all = try XCTUnwrap(read()["hooks"] as? [String: Any])
        XCTAssertEqual(Array(all.keys), ["SessionStart"])
        XCTAssertEqual(try hooks("SessionStart").count, 1)
        XCTAssertFalse(HookInstaller.isInstalled(settingsURL: settings, port: 47821))
    }

    func testUninstallDropsEmptyHooksSection() throws {
        try Data(#"{"effortLevel": "high"}"#.utf8).write(to: settings)
        try HookInstaller.install(settingsURL: settings, port: 47821)
        try HookInstaller.uninstall(settingsURL: settings)
        XCTAssertNil(try read()["hooks"])
        XCTAssertEqual(try read()["effortLevel"] as? String, "high")
    }

    func testBrokenJsonIsLeftUntouched() throws {
        let broken = Data("{ \"hooks\": ".utf8)
        try broken.write(to: settings)
        XCTAssertThrowsError(try HookInstaller.install(settingsURL: settings, port: 47821))
        XCTAssertEqual(try Data(contentsOf: settings), broken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: HookInstaller.backupURL(for: settings).path))
    }

    func testBackupKeepsTheFileAsItWasBeforeKlodik() throws {
        try Data(userSettings.utf8).write(to: settings)
        try HookInstaller.install(settingsURL: settings, port: 47821)
        try HookInstaller.install(settingsURL: settings, port: 47822)   // вторая установка не затирает копию
        XCTAssertEqual(try String(contentsOf: HookInstaller.backupURL(for: settings)), userSettings)
    }

    func testFilePermissionsArePreserved() throws {
        try Data(userSettings.utf8).write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
        try HookInstaller.install(settingsURL: settings, port: 47821)
        let mode = try FileManager.default.attributesOfItem(atPath: settings.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }
}
