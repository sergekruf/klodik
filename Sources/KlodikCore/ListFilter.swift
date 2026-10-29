import Foundation

/// Поиск и выбор проекта в списке Клодика: сессий бывает под сотню, по десятку проектов.
public enum ListFilter {
    /// С такого числа сессий над списком появляются поиск и кнопки проектов.
    public static let showFrom = 8

    /// Каждое слово запроса должно найтись в названии сессии или в имени проекта, без учёта регистра.
    /// Слово по-русски ищется ещё и латиницей: «ламода» находит Lamoda и папку RAY-lamoda-templates.
    public static func apply(_ items: [TrackedItem], query: String, project: String?) -> [TrackedItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map { [String($0), latin(String($0))] }
        return items.filter { item in
            if let project, item.projectName != project { return false }
            let haystack = item.title + " " + item.projectName
            return words.allSatisfy { variants in variants.contains { haystack.localizedStandardContains($0) } }
        }
    }

    static let cyrillic: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i", "й": "y",
        "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
        "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    ]

    static func latin(_ word: String) -> String {
        word.lowercased().map { cyrillic[$0] ?? String($0) }.joined()
    }

    /// Проекты для кнопок: где больше сессий — левее, при равенстве по алфавиту.
    public static func projects(_ items: [TrackedItem]) -> [(name: String, count: Int)] {
        Dictionary(grouping: items.filter { !$0.projectName.isEmpty }, by: \.projectName)
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
