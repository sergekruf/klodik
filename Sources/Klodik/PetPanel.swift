import AppKit

/// Прозрачное окно без рамки поверх всех окон и на всех рабочих столах.
/// Не забирает фокус у приложения, в котором вы работаете.
final class PetPanel: NSPanel {
    init(image: NSImage) {
        super.init(contentRect: NSRect(origin: .zero, size: image.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        contentView = PetView(image: image)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Рисует Клодика и даёт его перетаскивать. Правый клик открывает `menu`.
final class PetView: NSView {
    var image: NSImage { didSet { needsDisplay = true } }
    /// Вызывается, когда перетаскивание закончилось.
    var onDragEnd: (() -> Void)?

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: bounds)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)   // возвращается, когда кнопку отпустили
        onDragEnd?()
    }
}
