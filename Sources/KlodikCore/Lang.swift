import Foundation

/// Язык интерфейса: русский, если он первый в языках системы, иначе английский.
public enum Lang {
    case ru, en

    /// Меняется только в тестах.
    public static var current: Lang = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .ru : .en
}

/// Строка на языке интерфейса. Переводы лежат рядом с местом использования, без отдельных файлов.
public func tr(_ ru: String, _ en: String) -> String {
    Lang.current == .ru ? ru : en
}
