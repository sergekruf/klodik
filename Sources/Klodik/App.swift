import AppKit
import KlodikCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state = AppState.load()
    private var panel: PetPanel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PetPanel(image: Sprites.image(Sprites.idle))
        let view = panel.contentView as! PetView
        view.menu = makeMenu()
        view.onDragEnd = { [weak self] in self?.savePosition() }

        placePanel()
        panel.orderFrontRegardless()

        // Подключили или отключили монитор — проверить, что Клодик не остался за экраном.
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.placePanel() }
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

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Выйти", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        return menu
    }
}
