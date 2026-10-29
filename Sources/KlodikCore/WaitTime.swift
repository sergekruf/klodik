import Foundation

/// «12 мин», «3 ч», «2 дн» — сколько сессия ждёт, для строки списка.
public enum WaitTime {
    public static func short(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: tr("только что", "just now")
        case ..<3600: "\(Int(seconds / 60)) " + tr("мин", "min")
        case ..<(24 * 3600): "\(Int(seconds / 3600)) " + tr("ч", "h")
        default: "\(Int(seconds / (24 * 3600))) " + tr("дн", "d")
        }
    }

    /// Насколько застряла сессия, которая ждёт ответа: время в списке красится, чтобы долгие решения было видно сразу.
    public enum Age: Equatable {
        case fresh
        /// Ждёт дольше суток — оранжевое.
        case day
        /// Дольше трёх дней — красное.
        case days
    }

    public static func age(_ seconds: TimeInterval) -> Age {
        switch seconds {
        case ..<(24 * 3600): .fresh
        case ..<(3 * 24 * 3600): .day
        default: .days
        }
    }

    /// «Отложить до утра»: до ближайших 9:00. Ночью после полуночи — до сегодняшних, вечером — до завтрашних.
    public static let morningHour = 9

    public static func nextMorning(after now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: now)!
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)!
    }

    /// «меньше минуты», «4 мин», «1 ч 20 мин», «2 дн» — длительность для сводки за день.
    public static func duration(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return tr("меньше минуты", "under a minute")
        case ..<3600: return "\(Int(seconds / 60)) " + tr("мин", "min")
        case ..<(24 * 3600):
            let minutes = Int(seconds / 60) % 60
            return "\(Int(seconds / 3600)) " + tr("ч", "h") + (minutes > 0 ? " \(minutes) " + tr("мин", "min") : "")
        default: return "\(Int(seconds / (24 * 3600))) " + tr("дн", "d")
        }
    }
}
