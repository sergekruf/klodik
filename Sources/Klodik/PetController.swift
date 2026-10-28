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
    /// KLODIK_DEBUG=1 — писать каждое событие хука в журнал.
    static let debug = ProcessInfo.processInfo.environment["KLODIK_DEBUG"] != nil

    private var state = AppState.load()
    private let content = PetContentView()
    private lazy var panel = PetPanel(content: content)
    private var animator: Animator!

    private let store = SessionStore()
    private var server: EventServer?
    /// Сколько соседних портов уже перепробовали, если основной занят.
    private var portAttempts = 0
    static let maxPortAttempts = 10
    private let tracker = Tracker()
    private var policy = AttentionPolicy()
    private let settingsModel = SettingsModel()
    private lazy var settingsWindow = makeSettingsWindow()
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
        applySettings()
        tracker.onMarksChanged = { [weak self] in self?.saveMarks() }

        store.onChange = { [weak self] in
            guard let self else { return }
            tracker.update(sessions: Array(store.sessions.values))
            lastActivityAt = Date()
            scheduleRefresh()
        }
        store.loadAll()
        store.startWatching()

        startServer(port: state.port)
        refreshHooksState()

        front.onChange = { [weak self] in self?.scheduleRefresh() }

        let tick = Timer(timeInterval: Self.tickEvery, repeats: true) { [weak self] _ in self?.refresh() }
        tick.tolerance = 5
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick

        setUpListActions()
        startDemoIfAsked()
        refresh()

        if ProcessInfo.processInfo.environment["KLODIK_SHOW_SETTINGS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openSettings() }
        }
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

    // MARK: - Приёмник и хуки

    private func startServer(port: UInt16) {
        server?.stop()
        let server = EventServer(port: port)
        server.onEvent = { [weak self] event in
            guard let self else { return }
            if Self.debug { NSLog("Klodik: событие \(String(describing: event.kind)) от сессии \(event.sessionId)") }
            tracker.handle(event, claudeFrontmost: front.isClaudeFrontmost)
            lastActivityAt = event.at
            scheduleRefresh()
        }
        server.onState = { [weak self] in self?.serverStateChanged($0, port: port) }
        server.start()
        self.server = server
    }

    /// Порт занят — пробуем соседний. Занялся другой порт — переставляем на него свои хуки.
    private func serverStateChanged(_ serverState: EventServer.State, port: UInt16) {
        switch serverState {
        case .ready:
            listModel.serverProblem = nil
            settingsModel.listeningPort = port
            if port != state.port {
                let hooksWereInstalled = HookInstaller.isInstalled(port: state.port)
                NSLog("Klodik: порт \(state.port) занят, слушаю \(port)")
                state.port = port
                save()
                if hooksWereInstalled { installHooks() }
            }
        case .failed(let reason):
            NSLog("Klodik: приёмник на порту \(port) не запустился: \(reason)")
            if portAttempts < Self.maxPortAttempts {
                portAttempts += 1
                startServer(port: port + 1)
            } else {
                listModel.serverProblem = "Порты \(state.port)–\(port) заняты: Клодик не слышит хуки"
            }
        }
        refreshHooksState()
    }

    private func refreshHooksState() {
        listModel.hooksInstalled = HookInstaller.isInstalled(port: state.port)
        settingsModel.hooksInstalled = listModel.hooksInstalled
    }

    @objc private func toggleHooks() {
        if listModel.hooksInstalled { uninstallHooks() } else { installHooks() }
    }

    private func installHooks() {
        do {
            try HookInstaller.install(port: state.port)
        } catch {
            NSLog("Klodik: не удалось поставить хуки: \(error)")
            bubble.show("Не получилось: ~/.claude/settings.json не читается", above: panel.frame, for: 5)
        }
        refreshHooksState()
    }

    private func uninstallHooks() {
        do {
            try HookInstaller.uninstall()
        } catch {
            NSLog("Klodik: не удалось убрать хуки: \(error)")
            bubble.show("Не получилось: ~/.claude/settings.json не читается", above: panel.frame, for: 5)
        }
        refreshHooksState()
    }

    // MARK: - Настройки

    /// Окно в днях и шкала напоминаний из state.json — в трекер и политику.
    private func applySettings() {
        tracker.config.windowDays = state.windowDays
        state.reminderScale.apply(to: &policy.config)
    }

    private func makeSettingsWindow() -> NSWindow {
        settingsModel.setLaunchAtLogin = { [weak self] enabled in
            do {
                try LoginItem.set(enabled)
                self?.settingsModel.loginError = nil
            } catch {
                self?.settingsModel.loginError = "Не получилось: \(error.localizedDescription)"
            }
            self?.refreshSettingsModel()
        }
        settingsModel.setReminderScale = { [weak self] scale in
            self?.state.reminderScale = scale
            self?.settingsChanged()
        }
        settingsModel.setWindowDays = { [weak self] days in
            self?.state.windowDays = Double(days)
            self?.settingsChanged()
        }
        settingsModel.applyPort = { [weak self] port in self?.changePort(port) }
        settingsModel.toggleHooks = { [weak self] in self?.toggleHooks() }

        let host = NSHostingController(rootView: SettingsView(model: settingsModel))
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = "Клодик — настройки"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    @objc private func openSettings() {
        refreshSettingsModel()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func refreshSettingsModel() {
        let status = LoginItem.status
        settingsModel.launchAtLogin = status == .enabled
        settingsModel.loginNeedsApproval = status == .requiresApproval
        settingsModel.reminderScale = state.reminderScale
        settingsModel.windowDays = Int(state.windowDays)
        settingsModel.portText = String(state.port)
        refreshHooksState()
    }

    private func settingsChanged() {
        save()
        applySettings()
        refreshSettingsModel()
        refresh()
    }

    /// Новый порт: перезапустить приёмник и переставить хуки, если они стояли.
    private func changePort(_ port: UInt16) {
        guard port != state.port else { return }
        let hooksWereInstalled = HookInstaller.isInstalled(port: state.port)
        state.port = port
        save()
        portAttempts = 0
        startServer(port: port)
        if hooksWereInstalled { installHooks() }
        refreshSettingsModel()
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
        refreshHooksState()
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
        listModel.installHooks = { [weak self] in self?.installHooks() }
        listModel.toggleSnooze = { [weak self] in self?.toggleSnooze() }
        listModel.openSettings = { [weak self] in
            self?.popover.performClose(nil)
            self?.openSettings()
        }
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
        let hooks = menu.addItem(withTitle: "", action: #selector(toggleHooks), keyEquivalent: "")
        hooks.target = self
        hooks.tag = 2

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
        menu.addItem(withTitle: "Настройки…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: 1)?.title = snoozedUntil == nil ? "Отложить на 30 минут" : "Не откладывать"
        refreshHooksState()
        menu.item(withTag: 2)?.title = listModel.hooksInstalled ? "Удалить хуки Claude Code" : "Установить хуки Claude Code"
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
