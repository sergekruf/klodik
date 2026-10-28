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
}
