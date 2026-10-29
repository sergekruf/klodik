import Foundation

/// Утренняя сводка решений: раз в день, при первой активности после шести утра, — сколько сессий ждут ответа
/// и какая дольше всех. Чтобы решения не копились днями.
public enum MorningDigest {
    /// Раньше этого часа не считается утром: работа после полуночи — ещё вчерашний день.
    public static let startHour = 6

    public struct Digest: Equatable {
        public var waiting: Int
        public var oldest: TrackedItem
    }

    public static func isDue(lastShown: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.component(.hour, from: now) >= startHour else { return false }
        guard let lastShown else { return true }
        return !calendar.isDate(lastShown, inSameDayAs: now)
    }

    /// nil — никто не ждёт ответа, сводка не нужна.
    public static func make(items: [TrackedItem]) -> Digest? {
        let waiting = items.filter { $0.dot == .waiting }
        guard let oldest = waiting.min(by: { $0.waitingSince < $1.waitingSince }) else { return nil }
        return Digest(waiting: waiting.count, oldest: oldest)
    }
}
