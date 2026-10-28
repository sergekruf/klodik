import Foundation

/// Дописывает и убирает хуки Клодика в `~/.claude/settings.json`.
/// Хуки Клодика — HTTP-хуки на `127.0.0.1:<порт>/klodik/event`; всё остальное в файле не трогается.
public enum HookInstaller {
    public enum Failure: Error {
        /// Файл есть, но это не JSON-объект: ничего не пишем, чтобы не сломать настройки.
        case invalidSettings
    }

    /// События, нужные трекеру.
    public static let events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest",
                                "Notification", "Stop", "StopFailure", "SessionEnd"]
    /// HTTP-хук синхронный: если Клодик завис, Claude ждёт не дольше этого.
    public static let timeoutSeconds = 2

    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    public static func hookURL(port: UInt16) -> String {
        "http://127.0.0.1:\(port)\(EventServer.path)"
    }

    /// Копия файла до первой установки Клодика.
    public static func backupURL(for settingsURL: URL) -> URL {
        settingsURL.appendingPathExtension("klodik-backup")
    }

    public static func isInstalled(settingsURL: URL = defaultSettingsURL, port: UInt16) -> Bool {
        guard let settings = try? load(settingsURL), let hooks = settings["hooks"] as? [String: Any] else { return false }
        let url = hookURL(port: port)
        return events.allSatisfy { event in
            groups(hooks[event]).contains { group in entries(group).contains { $0["url"] as? String == url } }
        }
    }

    /// Ставит хуки на `port`. Старые хуки Клодика (в том числе на другом порту) сначала убираются.
    public static func install(settingsURL: URL = defaultSettingsURL, port: UInt16) throws {
        var settings = try load(settingsURL)
        if FileManager.default.fileExists(atPath: settingsURL.path),
           !FileManager.default.fileExists(atPath: backupURL(for: settingsURL).path) {
            try FileManager.default.copyItem(at: settingsURL, to: backupURL(for: settingsURL))
        }
        var hooks = removingKlodik(from: settings["hooks"] as? [String: Any] ?? [:])
        let entry: [String: Any] = ["type": "http", "url": hookURL(port: port), "timeout": timeoutSeconds]
        for event in events {
            hooks[event] = groups(hooks[event]) + [["hooks": [entry]]]
        }
        settings["hooks"] = hooks
        try write(settings, to: settingsURL)
    }

    public static func uninstall(settingsURL: URL = defaultSettingsURL) throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        var settings = try load(settingsURL)
        let hooks = removingKlodik(from: settings["hooks"] as? [String: Any] ?? [:])
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        try write(settings, to: settingsURL)
    }

    // MARK: - Внутреннее

    static func isKlodikHook(_ entry: [String: Any]) -> Bool {
        entry["type"] as? String == "http" && (entry["url"] as? String)?.hasSuffix(EventServer.path) == true
    }

    private static func groups(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
    private static func entries(_ group: [String: Any]) -> [[String: Any]] { group["hooks"] as? [[String: Any]] ?? [] }

    /// Убирает хуки Клодика, а опустевшие группы и события — целиком.
    private static func removingKlodik(from hooks: [String: Any]) -> [String: Any] {
        var result = hooks
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else { continue }   // незнакомый формат — не трогаем
            let cleaned: [[String: Any]] = list.compactMap { group in
                let kept = entries(group).filter { !isKlodikHook($0) }
                if kept.count == entries(group).count { return group }
                guard !kept.isEmpty else { return nil }
                var copy = group
                copy["hooks"] = kept
                return copy
            }
            result[event] = cleaned.isEmpty ? nil : cleaned
        }
        return result
    }

    private static func load(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.invalidSettings }
        return object
    }

    /// Атомарная запись с сохранением прав файла (settings.json обычно 0600).
    private static func write(_ settings: [String: Any], to url: URL) throws {
        let fm = FileManager.default
        let permissions = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions]) as? Int
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        if let permissions { try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path) }
    }
}
