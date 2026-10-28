import AppKit
import SwiftUI
import KlodikCore

/// Связывает всё вместе: файлы сессий и хуки → трекер → политика внимания → анимация, бейдж, пузыри, список.
final class PetController: NSObject, NSMenuDelegate {
    /// Пауза между прыжками в режиме «прыгает непрерывно» (сам прыжок ~0,7 с).
    static let continuousJumpEvery: TimeInterval = 1.2
    static let snoozeFor: TimeInterval = 30 * 60
    /// Раз в столько пересчитать всё: эскалация по времени, «работает» и сон гаснут сами.
    static let tickEvery: TimeInterval = 30

    private var state = AppState.load()
    private let content = PetContentView()
    private lazy var panel = PetPanel(content: content)
    private var animator: Animator!

    private let store = SessionStore()
    private let server = EventServer()
    private let tracker = Tracker()
    private let policy = AttentionPolicy()
    private let front = FrontAppWatcher()
    private let bubble = Bubble()
    private let listModel = SessionListModel()
    private lazy var popover = makePopover()

    private var snoozedUntil: Date?
    private var lastActivityAt = Date()
    /// Точки на прошлом пересчёте — чтобы заметить новое событие. nil до первого пересчёта:
    /// при запуске Клодик не объявляет о том, что и так уже было.
    private var previousDots: [String: TrackedItem.Dot]?
    private var nudge: Attention.Nudge = .none
    private var nudgeTimer: Timer?
    private var tickTimer: Timer?
    private var refreshScheduled = false
    /// KLODIK_DEMO: анимация задана руками, логика её не трогает.
    private var demo: PetAnimation?
    private var demoTimer: Timer?

    func start() {
        animator = Animator { [content] in content.sprite.image = $0 }
        content.menu = makeMenu()
        content.onClick = { [weak self] in self?.toggleList() }
        content.onDragEnd = { [weak self] in self?.savePosition() }
        placePanel()
        panel.orderFrontRegardless()
        // Подключили или отключили монитор — проверить, что Клодик не остался за экраном.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.placePanel() }

        tracker.restore(remind: state.remind, hidden: state.hidden)
        tracker.onMarksChanged = { [weak self] in self?.saveMarks() }

        store.onChange = { [weak self] in
            guard let self else { return }
            tracker.update(sessions: Array(store.sessions.values))
            lastActivityAt = Date()
            scheduleRefresh()
        }
        store.loadAll()
        store.startWatching()

        server.onState = { NSLog("Klodik: приёмник событий: \(String(describing: $0))") }
        server.onEvent = { [weak self] event in
            guard let self else { return }
            tracker.handle(event, claudeFrontmost: front.isClaudeFrontmost)
            lastActivityAt = event.at
            scheduleRefresh()
        }
        server.start()

        front.onChange = { [weak self] in self?.scheduleRefresh() }

        let tick = Timer(timeInterval: Self.tickEvery, repeats: true) { [weak self] _ in self?.refresh() }
        tick.tolerance = 5
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick

        setUpListActions()
        startDemoIfAsked()
        refresh()

        // KLODIK_SHOW_LIST=1 — сразу открыть список (для проверки вёрстки без клика). Без клика система
        // не даёт Клодику стать активным, и обычный список закрылся бы сам, поэтому здесь он не закрывается.
        if ProcessInfo.processInfo.environment["KLODIK_SHOW_LIST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.popover.behavior = .applicationDefined
                self?.toggleList()
            }
        }
    }

    // MARK: - Пересчёт

    /// Сотни событий подряд (Claude быстро гоняет инструменты) сливаются в один пересчёт.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshScheduled = false
            self?.refresh()
        }
    }

    private func refresh() {
        let now = Date()
        if let until = snoozedUntil, until <= now { snoozedUntil = nil }
        let items = tracker.items(now: now)
        let attention = policy.attention(items: items, workingCount: tracker.workingSessions(now: now).count, now: now,
                                         claudeFrontmost: front.isClaudeFrontmost, snoozedUntil: snoozedUntil,
                                         lastActivityAt: lastActivityAt)

        content.badge.count = attention.badge
        content.badge.urgent = items.contains { $0.dot == .gray }
        if demo == nil {
            animator.setBase(attention.base)
            apply(attention.nudge)
        }
        announce(items)

        listModel.items = items
        listModel.remindIds = Set(tracker.remind.keys)
        listModel.now = now
        listModel.snoozed = snoozedUntil != nil
        listModel.formatBroken = store.formatBroken
    }

    /// Новая серая — пузырь «ждёт ответа» и взмах, новая синяя — «готово» и радость.
    private func announce(_ items: [TrackedItem]) {
        let dots = Dictionary(items.map { ($0.localId, $0.dot) }, uniquingKeysWith: { first, _ in first })
        defer { previousDots = dots }
        guard let previous = previousDots, demo == nil,
              !front.isClaudeFrontmost, snoozedUntil == nil else { return }

        if let item = items.first(where: { $0.dot == .gray && previous[$0.localId] != .gray }) {
            bubble.show("Ждёт ответа: \(item.title)", above: panel.frame)
            animator.playOnce(.wave)
        } else if let item = items.first(where: { $0.dot == .blue && previous[$0.localId] == nil }) {
            bubble.show("Готово: \(item.title)", above: panel.frame)
            animator.playOnce(.happy)
        }
    }

    private func apply(_ newNudge: Attention.Nudge) {
        guard newNudge != nudge else { return }
        nudge = newNudge
        nudgeTimer?.invalidate()
        nudgeTimer = nil
        switch newNudge {
        case .none:
            break
        case .wave(let every):
            schedule(every: every, .wave)
        case .jump(let every):
            animator.playOnce(.jump)
            schedule(every: every, .jump)
        case .jumpContinuously:
            animator.playOnce(.jump)
            schedule(every: Self.continuousJumpEvery, .jump)
        }
    }

    private func schedule(every interval: TimeInterval, _ animation: PetAnimation) {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.animator.playOnce(animation) }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        nudgeTimer = timer
    }

    // MARK: - Список

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient   // закрывается кликом мимо и по Esc
        let host = NSHostingController(rootView: SessionListView(model: listModel))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        return popover
    }

    private func toggleList() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        refresh()
        NSApp.activate(ignoringOtherApps: true)   // иначе список не получит Esc и клики мимо
        popover.show(relativeTo: content.sprite.bounds, of: content.sprite, preferredEdge: .maxY)
    }

    private func setUpListActions() {
        listModel.open = { [weak self] item in
            self?.popover.performClose(nil)
            Self.openInClaude(item)
        }
        listModel.toggleRemind = { [weak self] item in
            guard let self else { return }
            if tracker.remind[item.localId] != nil {
                tracker.unmarkRemind(item.localId)
            } else {
                tracker.markRemind(item.localId, at: Date())
            }
            refresh()
        }
        listModel.hide = { [weak self] item in
            self?.tracker.hide(item.localId, at: Date())
            self?.refresh()
        }
        listModel.toggleSnooze = { [weak self] in self?.toggleSnooze() }
        listModel.quit = { NSApp.terminate(nil) }
    }

    static func openInClaude(_ item: TrackedItem) {
        if let cli = item.cliSessionId, let url = URL(string: "claude://code/continue?session=\(cli)") {
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: FrontAppWatcher.claudeBundleId) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func toggleSnooze() {
        snoozedUntil = snoozedUntil == nil ? Date().addingTimeInterval(Self.snoozeFor) : nil
        refresh()
    }

    // MARK: - Меню по правому клику

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let snooze = menu.addItem(withTitle: "", action: #selector(toggleSnooze), keyEquivalent: "")
        snooze.target = self
        snooze.tag = 1

        // Временное: включить любую анимацию руками.
        let debug = NSMenu()
        for anim in PetAnimation.allCases {
            let item = debug.addItem(withTitle: anim.rawValue, action: #selector(debugPlay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = anim.rawValue
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Отладка: анимация", action: nil, keyEquivalent: "").submenu = debug
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 1)?.title = snoozedUntil == nil ? "Отложить на 30 минут" : "Не откладывать"
    }

    @objc private func debugPlay(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let anim = PetAnimation(rawValue: name) else { return }
        if anim.loops { animator.setBase(anim) } else { animator.playOnce(anim) }
    }

    /// KLODIK_DEMO=<анимация> крутит её без остановки — для замеров нагрузки.
    private func startDemoIfAsked() {
        guard let name = ProcessInfo.processInfo.environment["KLODIK_DEMO"], let anim = PetAnimation(rawValue: name) else { return }
        demo = anim
        if anim.loops {
            animator.setBase(anim)
        } else {
            demoTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.animator.playOnce(anim) }
            animator.playOnce(anim)
        }
    }

    // MARK: - Состояние

    private func placePanel() {
        let origin = Placement.resolvedOrigin(saved: state.petOrigin, petSize: panel.frame.size,
                                              visibleFrames: NSScreen.screens.map(\.visibleFrame))
        panel.setFrameOrigin(origin)
    }

    private func savePosition() {
        state.petOrigin = panel.frame.origin
        save()
    }

    private func saveMarks() {
        state.remind = tracker.remind
        state.hidden = tracker.hidden
        save()
    }

    private func save() {
        do { try state.save() } catch { NSLog("Klodik: не удалось сохранить состояние: \(error)") }
    }
}
