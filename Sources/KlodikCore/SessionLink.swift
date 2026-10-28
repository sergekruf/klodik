import Foundation

/// Ссылка, которая открывает сессию во вкладке Code приложения Claude.
public enum SessionLink {
    /// Приложение принимает в `?session=` только свой номер `local_…` и молча игнорирует всё остальное
    /// (тогда просто выводит окно вперёд). Номер сессии Claude Code из хуков здесь не годится.
    public static func url(localId: String) -> URL? {
        guard localId.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "claude://code/continue?session=\(localId)")
    }
}
