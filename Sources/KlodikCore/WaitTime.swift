import Foundation

/// «12 мин», «3 ч», «2 дн» — сколько сессия ждёт, для строки списка.
public enum WaitTime {
    public static func short(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: "только что"
        case ..<3600: "\(Int(seconds / 60)) мин"
        case ..<(24 * 3600): "\(Int(seconds / 3600)) ч"
        default: "\(Int(seconds / (24 * 3600))) дн"
        }
    }

    /// «меньше минуты», «4 мин», «1 ч 20 мин», «2 дн» — длительность для сводки за день.
    public static func duration(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return "меньше минуты"
        case ..<3600: return "\(Int(seconds / 60)) мин"
        case ..<(24 * 3600):
            let minutes = Int(seconds / 60) % 60
            return "\(Int(seconds / 3600)) ч" + (minutes > 0 ? " \(minutes) мин" : "")
        default: return "\(Int(seconds / (24 * 3600))) дн"
        }
    }
}
