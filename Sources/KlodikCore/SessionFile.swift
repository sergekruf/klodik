import Foundation

/// Итог хода, как его оценило само приложение Claude (`postTurnSummary.status_category`).
public enum StatusCategory: Equatable {
    case completed, blocked, reviewReady
    /// Значение, которого не было, когда писался Клодик.
    case other
}

/// Сессия вкладки Code — то, что Клодику нужно из файла приложения.
public struct SessionInfo: Equatable {
    public var localId: String
    /// Номер сессии Claude Code: он приходит в хуках и открывает сессию по ссылке.
    public var cliSessionId: String?
    public var title: String
    public var projectName: String
    public var isArchived: Bool
    public var lastFocusedAt: Date?
    public var lastTurnEdgeAt: Date?
    public var lastActivityAt: Date?
    public var statusCategory: StatusCategory?
    public var statusDetail: String?

    public init(localId: String, cliSessionId: String? = nil, title: String, projectName: String,
                isArchived: Bool = false, lastFocusedAt: Date? = nil, lastTurnEdgeAt: Date? = nil,
                lastActivityAt: Date? = nil, statusCategory: StatusCategory? = nil, statusDetail: String? = nil) {
        self.localId = localId; self.cliSessionId = cliSessionId; self.title = title; self.projectName = projectName
        self.isArchived = isArchived; self.lastFocusedAt = lastFocusedAt; self.lastTurnEdgeAt = lastTurnEdgeAt
        self.lastActivityAt = lastActivityAt; self.statusCategory = statusCategory; self.statusDetail = statusDetail
    }
}

/// Разбор файла `~/Library/Application Support/Claude/claude-code-sessions/*/*/local_*.json`.
/// Это внутренний формат приложения Claude, поэтому всё, кроме `sessionId`, необязательно.
public enum SessionFile {
    public static func isSessionFile(_ name: String) -> Bool {
        name.hasPrefix("local_") && name.hasSuffix(".json")
    }

    public static func parse(_ data: Data) -> SessionInfo? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        let folder = raw.cwd ?? raw.originCwd
        let projectName = folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        let title = raw.title.flatMap { $0.isEmpty ? nil : $0 } ?? projectName
        return SessionInfo(localId: raw.sessionId,
                           cliSessionId: raw.cliSessionId,
                           title: title,
                           projectName: projectName,
                           isArchived: raw.isArchived ?? false,
                           lastFocusedAt: date(raw.lastFocusedAt),
                           lastTurnEdgeAt: date(raw.lastTurnEdgeAt),
                           lastActivityAt: date(raw.lastActivityAt),
                           statusCategory: raw.postTurnSummary?.status_category.map(category),
                           statusDetail: raw.postTurnSummary?.status_detail)
    }

    private static func date(_ ms: Double?) -> Date? {
        ms.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    private static func category(_ value: String) -> StatusCategory {
        switch value {
        case "completed": .completed
        case "blocked": .blocked
        case "review_ready": .reviewReady
        default: .other
        }
    }

    private struct Raw: Decodable {
        var sessionId: String
        var cliSessionId: String?
        var cwd: String?
        var originCwd: String?
        var title: String?
        var isArchived: Bool?
        var lastFocusedAt: Double?
        var lastTurnEdgeAt: Double?
        var lastActivityAt: Double?
        var postTurnSummary: Summary?

        struct Summary: Decodable {
            var status_category: String?
            var status_detail: String?
        }
    }
}
