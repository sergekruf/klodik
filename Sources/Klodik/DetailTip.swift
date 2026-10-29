import AppKit

/// Окошко сбоку от списка сессий напротив строки под курсором: что эта сессия просит. Появляется сразу, без системной задержки подсказок.
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

    /// Показать слева от списка `list` напротив строки `row` (справа, если слева не помещается). Всё в координатах экрана.
    func show(_ text: String, beside row: NSRect, list: NSRect) {
        let width: CGFloat = 280
        label.stringValue = text
        label.preferredMaxLayoutWidth = width - 2 * Self.padding
        let textSize = label.fittingSize
        let size = NSSize(width: width, height: textSize.height + 2 * Self.padding)
        label.frame = NSRect(x: Self.padding, y: Self.padding, width: width - 2 * Self.padding, height: textSize.height)

        let screen = NSScreen.screens.first { $0.frame.intersects(list) }?.visibleFrame ?? list
        var origin = NSPoint(x: list.minX - size.width - 6, y: row.midY - size.height / 2)
        if origin.x < screen.minX + 4 { origin.x = list.maxX + 6 }
        origin.y = min(max(origin.y, screen.minY + 4), screen.maxY - size.height - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
