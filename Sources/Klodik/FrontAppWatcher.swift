import AppKit

/// Знает, на переднем ли плане приложение Claude. Без опросов — по уведомлениям NSWorkspace.
final class FrontAppWatcher {
    static let claudeBundleId = "com.anthropic.claudefordesktop"

    private(set) var isClaudeFrontmost: Bool
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        isClaudeFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.claudeBundleId
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // Сам Клодик (список открыт) не считается: важно, что было впереди до него.
            if app?.bundleIdentifier == Bundle.main.bundleIdentifier { return }
            let front = app?.bundleIdentifier == Self.claudeBundleId
            guard front != self.isClaudeFrontmost else { return }
            self.isClaudeFrontmost = front
            self.onChange?()
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
