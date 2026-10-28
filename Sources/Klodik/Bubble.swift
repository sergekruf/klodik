import AppKit

/// Пузырь с короткой фразой рядом с Клодиком, на несколько секунд.
final class Bubble {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        box.layer?.cornerRadius = 8
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        box.addSubview(label)
        panel.contentView = box
    }

    /// Показать над окном `anchor` (или под ним, если сверху нет места).
    func show(_ text: String, above anchor: NSRect, for seconds: TimeInterval = 3) {
        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: min(label.frame.width, 260) + 20, height: label.frame.height + 12)
        label.frame = NSRect(x: 10, y: 6, width: size.width - 20, height: label.frame.height)

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? anchor
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 4)
        if origin.y + size.height > screen.maxY { origin.y = anchor.minY - size.height - 4 }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
