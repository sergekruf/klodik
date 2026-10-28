import Foundation
import CoreGraphics

/// Состояние Клодика между запусками: ~/Library/Application Support/Klodik/state.json.
/// Метки «напомнить», скрытые сессии и настройки добавятся на следующих шагах.
public struct AppState: Codable, Equatable {
    public var petOrigin: CGPoint?

    public init() {}

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
