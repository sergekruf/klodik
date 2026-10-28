import AppKit
import KlodikCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state = AppState.load()
    private var panel: PetPanel!
    private var animator: Animator!
    private var demoTimer: Timer?
    private let server = EventServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PetPanel(size: Sprites.size)
        let view = panel.contentView as! PetView
        view.menu = makeMenu()
        view.onDragEnd = { [weak self] in self?.savePosition() }
        animator = Animator { view.image = $0 }

        placePanel()
        panel.orderFrontRegardless()

        // Подключили или отключили монитор — проверить, что Клодик не остался за экраном.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.placePanel() }

        // Пока нет трекера (шаг 5), события хуков только пишутся в системный журнал.
        server.onState = { NSLog("Klodik: приёмник событий: \(String(describing: $0))") }
        server.onEvent = { NSLog("Klodik: событие \(String(describing: $0.kind)) от сессии \($0.sessionId)") }
        server.start()

        // Для замеров нагрузки: KLODIK_DEMO=<анимация> крутит её без остановки.
        if let name = ProcessInfo.processInfo.environment["KLODIK_DEMO"], let anim = PetAnimation(rawValue: name) {
            play(anim)
            if !anim.loops {
                demoTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.play(anim) }
            }
        }
    }

    private func placePanel() {
        let origin = Placement.resolvedOrigin(saved: state.petOrigin,
                                              petSize: panel.frame.size,
                                              visibleFrames: NSScreen.screens.map(\.visibleFrame))
        panel.setFrameOrigin(origin)
    }

    private func savePosition() {
        state.petOrigin = panel.frame.origin
        do { try state.save() } catch { NSLog("Klodik: не удалось сохранить состояние: \(error)") }
    }

    private func play(_ animation: PetAnimation) {
        if animation.loops { animator.setBase(animation) } else { animator.playOnce(animation) }
    }

    @objc private func debugPlay(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let anim = PetAnimation(rawValue: name) else { return }
        play(anim)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        // Временное: пока нет логики сессий, анимации переключаются руками.
        let debug = NSMenu()
        for anim in PetAnimation.allCases {
            let item = debug.addItem(withTitle: anim.rawValue, action: #selector(debugPlay(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = anim.rawValue
        }
        menu.addItem(withTitle: "Отладка: анимация", action: nil, keyEquivalent: "").submenu = debug
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }
}
