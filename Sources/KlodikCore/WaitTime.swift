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
