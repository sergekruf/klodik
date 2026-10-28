import Foundation

/// Событие Claude Code, которое пришло от хука. Нужны только события, по которым меняется состояние сессии.
public enum HookKind: Equatable {
    case sessionStart
    case promptSubmit
    case preTool(String?)
    case postTool(String?)
    case permissionRequest(String?)
    /// `notification_type`: `permission_prompt`, `idle_prompt`, `elicitation_dialog`, `agent_needs_input`…
    case notification(String)
    case stop
    case stopFailure
    case sessionEnd
}

public struct HookEvent: Equatable {
    /// Совпадает с `cliSessionId` в файле сессии приложения.
    public var sessionId: String
    public var kind: HookKind
    public var cwd: String?
    /// Когда событие пришло к Клодику.
    public var at: Date

    public init(sessionId: String, kind: HookKind, cwd: String? = nil, at: Date) {
        self.sessionId = sessionId; self.kind = kind; self.cwd = cwd; self.at = at
    }

    /// Неизвестные события, битый JSON и события без `session_id` — nil.
    public static func parse(_ data: Data, at: Date = Date()) -> HookEvent? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data), !raw.session_id.isEmpty else { return nil }
        let kind: HookKind
        switch raw.hook_event_name {
        case "SessionStart": kind = .sessionStart
        case "UserPromptSubmit": kind = .promptSubmit
        case "PreToolUse": kind = .preTool(raw.tool_name)
        case "PostToolUse": kind = .postTool(raw.tool_name)
        case "PermissionRequest": kind = .permissionRequest(raw.tool_name)
        case "Notification": kind = .notification(raw.notification_type ?? "")
        case "Stop": kind = .stop
        case "StopFailure": kind = .stopFailure
        case "SessionEnd": kind = .sessionEnd
        default: return nil
        }
        return HookEvent(sessionId: raw.session_id, kind: kind, cwd: raw.cwd, at: at)
    }

    private struct Raw: Decodable {
        var session_id: String
        var hook_event_name: String
        var cwd: String?
        var tool_name: String?
        var notification_type: String?
    }
}
