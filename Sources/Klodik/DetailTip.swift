import AppKit

/// Окошко над списком сессий: что просит сессия под курсором. Появляется сразу, без системной задержки подсказок.
final class DetailTip {
    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private static let padding: CGFloat = 10

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu   // выше списка, который сам висит над окнами
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.94).cgColor
        box.layer?.cornerRadius = 8
        label.textColor = .white
        label.font = .systemFont(ofSize: 12)
        label.maximumNumberOfLines = 8
        label.lineBreakMode = .byWordWrapping
        box.addSubview(label)
        panel.contentView = box
    }

    /// Показать над окном `anchor` той же ширины (или под ним, если сверху нет места).
    func show(_ text: String, above anchor: NSRect) {
        let width = max(anchor.width - 16, 200)
        label.stringValue = text
        label.preferredMaxLayoutWidth = width - 2 * Self.padding
        let textSize = label.fittingSize
        let size = NSSize(width: width, height: textSize.height + 2 * Self.padding)
        label.frame = NSRect(x: Self.padding, y: Self.padding, width: width - 2 * Self.padding, height: textSize.height)

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? anchor
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 6)
        if origin.y + size.height > screen.maxY { origin.y = anchor.minY - size.height - 6 }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
