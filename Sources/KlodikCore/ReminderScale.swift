import Foundation

/// Насколько настойчиво Клодик напоминает о серой сессии, которую ещё не открывали.
public enum ReminderScale: String, Codable, CaseIterable {
    case gentle, normal, insistent

    public var title: String {
        switch self {
        case .gentle: "Спокойно"
        case .normal: "Обычно"
        case .insistent: "Настойчиво"
        }
    }

    public var detail: String {
        switch self {
        case .gentle: "Прыжок раз в 2 минуты, через 10 минут — раз в минуту. Без остановки не прыгает."
        case .normal: "Раз в минуту, через 2 минуты — раз в 30 секунд, через 10 минут — без остановки."
        case .insistent: "Раз в 30 секунд, через 2 минуты — без остановки."
        }
    }

    public func apply(to config: inout AttentionPolicy.Config) {
        switch self {
        case .gentle:
            config.jumpSteps = [(10 * 60, 120)]
            config.afterLastStep = .jump(every: 60)
        case .normal:
            config.jumpSteps = [(2 * 60, 60), (10 * 60, 30)]
            config.afterLastStep = .jumpContinuously
        case .insistent:
            config.jumpSteps = [(2 * 60, 30)]
            config.afterLastStep = .jumpContinuously
        }
    }
}
