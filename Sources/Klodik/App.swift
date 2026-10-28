import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = PetController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }
}
