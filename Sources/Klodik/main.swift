import AppKit
import KlodikCore

// `Klodik --sheet путь.png` — нарисовать все анимации на одном листе и выйти.
if let i = CommandLine.arguments.firstIndex(of: "--sheet"), i + 1 < CommandLine.arguments.count {
    do {
        try Sprites.writeContactSheet(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Не удалось сохранить лист: \(error)\n".utf8))
        exit(1)
    }
}

// `Klodik --sessions` — прочитать сессии приложения Claude, напечатать сводку и выйти.
if CommandLine.arguments.contains("--sessions") {
    let started = Date()
    let store = SessionStore()
    store.loadAll()
    let elapsed = Date().timeIntervalSince(started)
    let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
    let recent = store.sessions.values.filter { !$0.isArchived && ($0.lastActivityAt ?? .distantPast) > weekAgo }
    print("Папка: \(store.root.path)")
    print("Сессий: \(store.sessions.count), формат сломан: \(store.formatBroken), чтение: \(Int(elapsed * 1000)) мс")
    print("Неархивных с активностью за 7 дней: \(recent.count), из них с итогом blocked: \(recent.filter { $0.statusCategory == .blocked }.count)")
    let tracker = Tracker()
    tracker.update(sessions: Array(store.sessions.values))
    let items = tracker.items(now: Date())
    let gray = items.filter { $0.dot == .gray }
    print("Список Клодика: серых \(gray.count) (из них открывали \(gray.filter(\.openedSinceWaiting).count)), синих \(items.filter { $0.dot == .blue }.count)")
    for item in items {
        let minutes = Int(Date().timeIntervalSince(item.waitingSince) / 60)
        let dot = item.dot == .gray ? (item.openedSinceWaiting ? "◌" : "●") : "◆"
        print("  \(dot) \(item.title) [\(item.projectName)] — ждёт \(minutes) мин")
    }
    let attention = AttentionPolicy().attention(items: items, workingCount: 0, now: Date(), claudeFrontmost: false,
                                                snoozedUntil: nil, lastActivityAt: Date())
    print("Клодик сейчас: \(attention)")
    exit(0)
}

// `Klodik --install-hooks` / `--uninstall-hooks` — то же, что пункт меню, из терминала.
for (flag, install) in [("--install-hooks", true), ("--uninstall-hooks", false)] where CommandLine.arguments.contains(flag) {
    let port = AppState.load().port
    do {
        if install { try HookInstaller.install(port: port) } else { try HookInstaller.uninstall() }
        print(install ? "Хуки поставлены на порт \(port): \(HookInstaller.defaultSettingsURL.path)" : "Хуки Клодика убраны")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Не получилось: \(error)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // без иконки в Dock, даже при запуске не из .app
app.run()
