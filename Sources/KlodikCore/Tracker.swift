import Foundation

/// Строка списка Клодика: сессия, которой нужен пользователь.
public struct TrackedItem: Equatable {
    public enum Dot: Equatable {
        /// Нужен ответ: разрешение, вопрос, решение.
        case gray
        /// Закончила, не прочитана.
        case blue
        /// Пользователь сам попросил напомнить.
        case remind
    }

    public var localId: String
    public var cliSessionId: String?
    public var title: String
    public var projectName: String
    public var dot: Dot
    /// С какого момента сессия ждёт: для «12 мин» и порядка в списке (свежие сверху).
    public var waitingSince: Date
    /// Серую сессию уже открывали после того, как она начала ждать: Клодик из-за неё не прыгает.
    public var openedSinceWaiting: Bool
    /// Что просит или что сделала: «Bash: npm run build», текст вопроса, итог хода от приложения Claude.
    public var detail: String?
}

/// Сводит файлы сессий, события хуков и метки пользователя в список для Клодика.
/// Всё время передаётся явно, поэтому правила проверяются тестами без часов.
public final class Tracker {
    public struct Config {
        /// Сессии без активности дольше этого в список не попадают.
        public var windowDays: Double = 7
        /// «Работает» гаснет само, если `Stop` потерялся.
        public var workingTimeout: TimeInterval = 10 * 60
        public init() {}
    }

    /// Уведомления, после которых сессия ждёт ответа.
    static let questionNotifications: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    /// Окно в днях меняется из настроек на ходу.
    public var config: Config
    /// Метки «напомнить»: `localId` → когда поставлена. Снимается сама, когда сессию открыли после метки.
    public private(set) var remind: [String: Date] = [:]
    /// «Скрыть до следующей активности»: `localId` → когда скрыта.
    public private(set) var hidden: [String: Date] = [:]
    /// Метки поменялись — их пора сохранить.
    public var onMarksChanged: (() -> Void)?
    /// Серая сессия перестала ждать: пользователь ответил, разрешил или отказал. Для сводки за день.
    public var onWaitEnded: ((WaitRecord) -> Void)?

    private var sessions: [String: SessionInfo] = [:]
    private var localByCli: [String: String] = [:]
    /// Сессия, открытая сейчас в Claude: у неё самый свежий `lastFocusedAt`.
    private var onScreenId: String?

    // Всё, что пришло от хуков, по `cliSessionId`. Хранится и для сессий без файла:
    // файл новой сессии может появиться позже первого события.
    private var waitingSince: [String: Date] = [:]
    private var answeredAt: [String: Date] = [:]
    private var stoppedAt: [String: Date] = [:]
    private var workingAt: [String: Date] = [:]
    private var lastEventAt: [String: Date] = [:]
    /// Что просит серая сессия из хуков: команда, файл, текст вопроса.
    private var waitDetail: [String: String] = [:]
    /// Последний инструмент перед запросом: PreToolUse приходит раньше уведомления о вопросе или разрешении.
    private var pendingTool: [String: String] = [:]
    /// Сессия закончила ход у пользователя на глазах — прочитана до этого момента. По `localId`.
    private var readByPresence: [String: Date] = [:]

    public init(config: Config = Config()) {
        self.config = config
    }

    /// Метки из сохранённого состояния, при запуске.
    public func restore(remind: [String: Date], hidden: [String: Date]) {
        self.remind = remind
        self.hidden = hidden
    }

    public func update(sessions list: [SessionInfo]) {
        sessions = Dictionary(list.map { ($0.localId, $0) }, uniquingKeysWith: { first, _ in first })
        localByCli = Dictionary(list.compactMap { s in s.cliSessionId.map { ($0, s.localId) } },
                                uniquingKeysWith: { first, _ in first })
        onScreenId = list.filter { $0.lastFocusedAt != nil }.max { $0.lastFocusedAt! < $1.lastFocusedAt! }?.localId
        cleanUpMarks()
    }

    public func handle(_ event: HookEvent, claudeFrontmost: Bool) {
        let cli = event.sessionId
        let grayBefore = grayStart(cli, at: event.at)
        defer {
            if let start = grayBefore, grayStart(cli, at: event.at) == nil,
               let local = localByCli[cli], let s = sessions[local] {
                onWaitEnded?(WaitRecord(localId: local, title: s.title, start: start, end: event.at))
            }
        }
        lastEventAt[cli] = event.at
        switch event.kind {
        case .sessionStart:
            break
        case .promptSubmit:
            answeredAt[cli] = event.at
            waitingSince[cli] = nil
            waitDetail[cli] = nil
            workingAt[cli] = event.at
        case .preTool:
            // PreToolUse приходит и перед запросом разрешения, поэтому ожидание он не снимает.
            workingAt[cli] = event.at
            pendingTool[cli] = event.detail
        case .postTool:
            waitingSince[cli] = nil
            waitDetail[cli] = nil
            workingAt[cli] = event.at
        case .permissionRequest:
            startWaiting(cli, at: event.at)
            if let detail = event.detail { waitDetail[cli] = detail }
        case .notification(let type):
            if Self.questionNotifications.contains(type) {
                startWaiting(cli, at: event.at)
                // Текст уведомления общий («Claude needs your permission…»), инструмент из PreToolUse говорит больше.
                if waitDetail[cli] == nil { waitDetail[cli] = pendingTool[cli] ?? event.detail }
            }
        case .stop, .stopFailure:
            waitingSince[cli] = nil
            waitDetail[cli] = nil
            workingAt[cli] = nil
            stoppedAt[cli] = event.at
            if claudeFrontmost, let local = localByCli[cli], local == onScreenId {
                // Секунда запаса: приложение пишет конец хода в файл чуть раньше, чем приходит хук.
                readByPresence[local] = event.at.addingTimeInterval(1)
            }
        case .sessionEnd:
            waitingSince[cli] = nil
            waitDetail[cli] = nil
            workingAt[cli] = nil
        }
        cleanUpMarks()
    }

    /// Пользователь вернулся в Claude: сессия на экране прочитана, даже если закончила, пока он был в другом окне.
    /// Сам Claude в этом случае `lastFocusedAt` не обновляет — сессию не переключали.
    public func markOnScreenRead(at date: Date) {
        guard let id = onScreenId else { return }
        readByPresence[id] = date
    }

    public func markRemind(_ localId: String, at date: Date) {
        remind[localId] = date
        onMarksChanged?()
    }

    public func unmarkRemind(_ localId: String) {
        guard remind.removeValue(forKey: localId) != nil else { return }
        onMarksChanged?()
    }

    public func hide(_ localId: String, at date: Date) {
        hidden[localId] = date
        onMarksChanged?()
    }

    /// Сверху самые свежие: кто позже начал ждать, тот выше, независимо от цвета точки (решение пользователя).
    public func items(now: Date) -> [TrackedItem] {
        let windowStart = now.addingTimeInterval(-config.windowDays * 24 * 3600)
        var result: [TrackedItem] = []
        for s in sessions.values where !s.isArchived {
            let mark = remind[s.localId]
            let lastSeen = max(s.lastActivityAt ?? .distantPast, s.cliSessionId.flatMap { lastEventAt[$0] } ?? .distantPast)
            guard lastSeen > windowStart || mark != nil else { continue }
            if let hiddenAt = hidden[s.localId], lastSignal(s) <= hiddenAt { continue }

            var state = needState(s, now: now)
            if let mark, state?.dot != .gray { state = (.remind, mark) }
            guard let (dot, since) = state else { continue }

            result.append(TrackedItem(localId: s.localId, cliSessionId: s.cliSessionId, title: s.title,
                                      projectName: s.projectName, dot: dot, waitingSince: since,
                                      openedSinceWaiting: dot == .gray && (s.lastFocusedAt ?? .distantPast) > since,
                                      detail: detail(s, dot: dot)))
        }
        return result.sorted { $0.waitingSince > $1.waitingSince }
    }

    /// `localId` сессий, которые сейчас работают.
    public func workingSessions(now: Date) -> Set<String> {
        Set(workingAt.compactMap { cli, at in
            now.timeIntervalSince(at) < config.workingTimeout ? localByCli[cli] : nil
        })
    }

    // MARK: - Правила

    private func startWaiting(_ cli: String, at date: Date) {
        if waitingSince[cli] == nil { waitingSince[cli] = date }
        workingAt[cli] = nil
    }

    private func isWorking(_ cli: String?, now: Date) -> Bool {
        guard let cli, let at = workingAt[cli] else { return false }
        return now.timeIntervalSince(at) < config.workingTimeout
    }

    /// Серая или синяя, без учёта меток.
    private func needState(_ s: SessionInfo, now: Date) -> (dot: TrackedItem.Dot, since: Date)? {
        let cli = s.cliSessionId
        if let cli, let since = waitingSince[cli] { return (.gray, since) }

        // Итог хода «blocked» из файла, если пользователь ещё не ответил после этого хода.
        var fileBlocked = false
        if s.statusCategory == .blocked, let since = s.lastTurnEdgeAt ?? s.lastActivityAt {
            let answered = cli.flatMap { answeredAt[$0] }.map { $0 > since } ?? false
            fileBlocked = !answered
            if fileBlocked && !isWorking(cli, now: now) { return (.gray, since) }
        }

        guard !fileBlocked, !isWorking(cli, now: now) else { return nil }
        let edge = max(s.lastTurnEdgeAt ?? .distantPast, cli.flatMap { stoppedAt[$0] } ?? .distantPast)
        let read = max(s.lastFocusedAt ?? .distantPast, readByPresence[s.localId] ?? .distantPast)
        return edge > read ? (.blue, edge) : nil
    }

    /// С какого момента сессия ждёт ответа, если она сейчас серая.
    private func grayStart(_ cli: String, at date: Date) -> Date? {
        guard let local = localByCli[cli], let s = sessions[local],
              let state = needState(s, now: date), state.dot == .gray else { return nil }
        return state.since
    }

    /// Серая из хуков — что она просит сейчас (итог прошлого хода из файла тут устарел).
    /// Серая из файла и синяя — итог хода, который приложение Claude записало в файл.
    private func detail(_ s: SessionInfo, dot: TrackedItem.Dot) -> String? {
        if dot == .gray, let cli = s.cliSessionId, waitingSince[cli] != nil { return waitDetail[cli] }
        return s.statusDetail
    }

    /// Последний признак жизни сессии: конец хода или новый запрос ответа.
    private func lastSignal(_ s: SessionInfo) -> Date {
        let cli = s.cliSessionId
        return [s.lastTurnEdgeAt, cli.flatMap { stoppedAt[$0] }, cli.flatMap { waitingSince[$0] }]
            .compactMap { $0 }.max() ?? .distantPast
    }

    private func cleanUpMarks() {
        var changed = false
        for (id, markedAt) in remind {
            if let focused = sessions[id]?.lastFocusedAt, focused > markedAt {
                remind[id] = nil
                changed = true
            }
        }
        for (id, hiddenAt) in hidden {
            if let s = sessions[id], lastSignal(s) > hiddenAt {
                hidden[id] = nil
                changed = true
            }
        }
        if changed { onMarksChanged?() }
    }
}
