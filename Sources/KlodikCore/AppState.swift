import Foundation
import CoreGraphics

/// Состояние Клодика между запусками: ~/Library/Application Support/Klodik/state.json.
/// Настройки добавятся на шаге 9.
public struct AppState: Codable, Equatable {
    public var petOrigin: CGPoint?
    /// Метки «напомнить»: `localId` → когда поставлена.
    public var remind: [String: Date] = [:]
    /// «Скрыть до следующей активности»: `localId` → когда скрыта.
    public var hidden: [String: Date] = [:]
    /// Порт приёмника событий. Меняется сам, если прежний занят другим приложением.
    public var port: UInt16 = EventServer.defaultPort

    public init() {}

    /// Каждое поле необязательно: файл от старой версии Клодика читается без потерь.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        petOrigin = try c.decodeIfPresent(CGPoint.self, forKey: .petOrigin)
        remind = try c.decodeIfPresent([String: Date].self, forKey: .remind) ?? [:]
        hidden = try c.decodeIfPresent([String: Date].self, forKey: .hidden) ?? [:]
        port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? EventServer.defaultPort
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Klodik/state.json")
    }

    /// Нет файла или он битый — значения по умолчанию, без ошибки.
    public static func load(from url: URL = defaultURL) -> AppState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else { return AppState() }
        return state
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
