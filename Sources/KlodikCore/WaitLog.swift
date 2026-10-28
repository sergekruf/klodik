import Foundation

/// Сессия ждала ответа пользователя с `start` до `end`.
public struct WaitRecord: Codable, Equatable {
    public var localId: String
    public var title: String
    public var start: Date
    public var end: Date

    public init(localId: String, title: String, start: Date, end: Date) {
        self.localId = localId; self.title = title; self.start = start; self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Итог дня: на сколько запросов ответил, как быстро, какая сессия ждала дольше всех.
public struct DaySummary: Equatable {
    public var answered: Int
    public var average: TimeInterval
    public var longest: WaitRecord
}

/// Журнал ожиданий за последние 30 дней: ~/Library/Application Support/Klodik/waits.json.
public struct WaitLog: Codable, Equatable {
    public static let keepDays: Double = 30

    public private(set) var records: [WaitRecord] = []

    public init(records: [WaitRecord] = []) {
        self.records = records
    }

    public mutating func add(_ record: WaitRecord) {
        records.append(record)
        let cutoff = record.end.addingTimeInterval(-Self.keepDays * 24 * 3600)
        records.removeAll { $0.end < cutoff }
    }

    /// Ожидания, которые закончились в тот же календарный день, что и `now`. Нет ни одного — nil.
    public func summary(on now: Date, calendar: Calendar = .current) -> DaySummary? {
        let today = records.filter { calendar.isDate($0.end, inSameDayAs: now) }
        guard let longest = today.max(by: { $0.duration < $1.duration }) else { return nil }
        let average = today.map(\.duration).reduce(0, +) / Double(today.count)
        return DaySummary(answered: today.count, average: average, longest: longest)
    }

    public static var defaultURL: URL {
        AppState.defaultURL.deletingLastPathComponent().appendingPathComponent("waits.json")
    }

    /// Нет файла или он битый — пустой журнал.
    public static func load(from url: URL = defaultURL) -> WaitLog {
        guard let data = try? Data(contentsOf: url),
              let log = try? JSONDecoder().decode(WaitLog.self, from: data) else { return WaitLog() }
        return log
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
