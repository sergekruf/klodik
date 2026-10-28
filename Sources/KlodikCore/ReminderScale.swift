import Foundation

/// Насколько настойчиво Клодик напоминает о серой сессии, которую ещё не открывали.
public enum ReminderScale: String, Codable, CaseIterable {
    case gentle, normal, insistent

    public var title: String {
        switch self {
        case .gentle: tr("Спокойно", "Gentle")
        case .normal: tr("Обычно", "Normal")
        case .insistent: tr("Настойчиво", "Insistent")
        }
    }

    public var detail: String {
        switch self {
        case .gentle: tr("Прыжок раз в 2 минуты, через 10 минут — раз в минуту. Без остановки не прыгает.",
                          "Jumps every 2 minutes, after 10 minutes every minute. Never nonstop.")
        case .normal: tr("Раз в минуту, через 2 минуты — раз в 30 секунд. Без остановки не прыгает.",
                          "Every minute, after 2 minutes every 30 seconds. Never nonstop.")
        case .insistent: tr("Раз в 30 секунд, через 2 минуты — без остановки.", "Every 30 seconds, after 2 minutes nonstop.")
        }
    }

    public func apply(to config: inout AttentionPolicy.Config) {
        switch self {
        case .gentle:
            config.jumpSteps = [(10 * 60, 120)]
            config.afterLastStep = .jump(every: 60)
        case .normal:
            config.jumpSteps = [(2 * 60, 60)]
            config.afterLastStep = .jump(every: 30)
        case .insistent:
            config.jumpSteps = [(2 * 60, 30)]
            config.afterLastStep = .jumpContinuously
        }
    }
}
