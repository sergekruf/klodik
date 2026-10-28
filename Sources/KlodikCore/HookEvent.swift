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
    /// Что именно просит или спрашивает Claude, коротко: «Bash: npm run build», «Edit: Tracker.swift», текст вопроса.
    public var detail: String?
    /// Когда событие пришло к Клодику.
    public var at: Date

    public init(sessionId: String, kind: HookKind, cwd: String? = nil, detail: String? = nil, at: Date) {
        self.sessionId = sessionId; self.kind = kind; self.cwd = cwd; self.detail = detail; self.at = at
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
        var detail: String?
        switch kind {
        case .preTool, .permissionRequest:
            let input = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tool_input"] as? [String: Any]
            detail = toolSummary(raw.tool_name, input ?? [:])
        case .notification:
            detail = raw.message
        default:
            break
        }
        return HookEvent(sessionId: raw.session_id, kind: kind, cwd: raw.cwd, detail: detail.flatMap(clipped), at: at)
    }

    /// Самое говорящее поле инструмента. Вопрос AskUserQuestion — без имени инструмента, остальное — «Инструмент: что».
    static func toolSummary(_ tool: String?, _ input: [String: Any]) -> String? {
        guard let tool else { return nil }
        if tool == "AskUserQuestion" {
            return ((input["questions"] as? [[String: Any]])?.first?["question"] as? String)
        }
        // mcp__server__tool → tool
        let name = tool.hasPrefix("mcp__") ? (tool.components(separatedBy: "__").last ?? tool) : tool
        let what: String?
        if let command = input["command"] as? String {
            what = command
        } else if let path = (input["file_path"] ?? input["notebook_path"] ?? input["path"]) as? String {
            what = (path as NSString).lastPathComponent
        } else if let url = input["url"] as? String {
            what = URL(string: url)?.host ?? url
        } else if let query = (input["query"] ?? input["pattern"] ?? input["description"]) as? String {
            what = query
        } else {
            what = nil
        }
        return what.map { "\(name): \($0)" } ?? name
    }

    /// Первая строка, пробелы схлопнуты, не длиннее 120 символов.
    static func clipped(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let compact = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !compact.isEmpty else { return nil }
        return compact.count > 120 ? String(compact.prefix(119)) + "…" : compact
    }

    private struct Raw: Decodable {
        var session_id: String
        var hook_event_name: String
        var cwd: String?
        var tool_name: String?
        var notification_type: String?
        var message: String?
    }
}
