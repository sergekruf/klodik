import Foundation

/// Что Клодику делать сейчас: фоновая анимация, как часто дёргать пользователя и число над головой.
public struct Attention: Equatable {
    public enum Nudge: Equatable {
        case none
        case wave(every: TimeInterval)
        case jump(every: TimeInterval)
        case jumpContinuously
    }

    /// `.idle`, `.working` или `.sleep`.
    public var base: PetAnimation
    public var nudge: Nudge
    /// Сколько сессий в списке.
    public var badge: Int

    public init(base: PetAnimation, nudge: Nudge, badge: Int) {
        self.base = base; self.nudge = nudge; self.badge = badge
    }
}

public struct AttentionPolicy {
    public struct Config {
        /// Шкала напоминаний для серой сессии, которую ещё не открывали: пока ждёт меньше `upTo` — прыжок раз в `every`.
        public var jumpSteps: [(upTo: TimeInterval, every: TimeInterval)] = [(2 * 60, 60), (10 * 60, 30)]
        /// Серая, которая ждёт дольше этого, не заставляет прыгать (решение пользователя).
        public var grayStaleAfter: TimeInterval = 24 * 3600
        /// Синие, «напомнить», уже открытые и давние серые — изредка помахать.
        public var waveEvery: TimeInterval = 5 * 60
        /// Список пуст и ничего не происходит — уснуть.
        public var sleepAfter: TimeInterval = 15 * 60
        public init() {}
    }

    public var config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    /// - Parameter lastActivityAt: последнее событие хука или изменение файла сессии.
    public func attention(items: [TrackedItem], workingCount: Int, now: Date, claudeFrontmost: Bool,
                          snoozedUntil: Date?, lastActivityAt: Date) -> Attention {
        let base: PetAnimation
        if workingCount > 0 {
            base = .working
        } else if items.isEmpty && now.timeIntervalSince(lastActivityAt) >= config.sleepAfter {
            base = .sleep
        } else {
            base = .idle
        }

        let silenced = claudeFrontmost || (snoozedUntil.map { $0 > now } ?? false)
        guard !items.isEmpty, !silenced else { return Attention(base: base, nudge: .none, badge: items.count) }

        let freshUnopenedGray = items.filter {
            $0.dot == .gray && !$0.openedSinceWaiting && now.timeIntervalSince($0.waitingSince) < config.grayStaleAfter
        }
        guard let oldest = freshUnopenedGray.map(\.waitingSince).min() else {
            return Attention(base: base, nudge: .wave(every: config.waveEvery), badge: items.count)
        }
        let waited = now.timeIntervalSince(oldest)
        let nudge = config.jumpSteps.first { waited < $0.upTo }.map { Attention.Nudge.jump(every: $0.every) } ?? .jumpContinuously
        return Attention(base: base, nudge: nudge, badge: items.count)
    }
}
