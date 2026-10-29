import Foundation

/// Какую сессию открыть по горячей клавише. Сначала неоткрытые ждущие ответа, потом открытые, отмеченные («напомнить» и непрочитанные в Claude) и синие;
/// внутри группы — кто дольше ждёт. Повторное нажатие идёт к следующей, пока очередь не кончится.
public struct NextSession {
    /// Пауза между нажатиями, после которой очередь начинается заново.
    public static let cycleResetAfter: TimeInterval = 10 * 60

    private var visited: [String] = []
    private var lastPress: Date?

    public init() {}

    public mutating func pick(from items: [TrackedItem], now: Date) -> TrackedItem? {
        if let last = lastPress, now.timeIntervalSince(last) > Self.cycleResetAfter { visited = [] }
        lastPress = now
        let queue = Self.order(items)
        var next = queue.first { !visited.contains($0.localId) }
        if next == nil {
            // Всё обошли — по кругу с начала.
            visited = []
            next = queue.first
        }
        if let next { visited.append(next.localId) }
        return next
    }

    static func order(_ items: [TrackedItem]) -> [TrackedItem] {
        func rank(_ item: TrackedItem) -> Int {
            switch item.dot {
            case .waiting: item.openedSinceWaiting ? 1 : 0
            case .remind, .unread: 2
            case .blue: 3
            }
        }
        return items.sorted { (rank($0), $0.waitingSince) < (rank($1), $1.waitingSince) }
    }
}
