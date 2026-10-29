import NaturalLanguage

/// На каком языке строка. Итоги ходов Claude пишет то по-русски, то по-английски, даже в одной сессии.
public enum TextLanguage {
    /// Русский или английский; nil — не разобрать (пусто, одни цифры и знаки).
    public static func detect(_ text: String) -> Lang? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.russian, .english]
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .russian?: return .ru
        case .english?: return .en
        default: return nil
        }
    }
}
