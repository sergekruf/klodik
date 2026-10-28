import AppKit

/// Прозрачное окно без рамки поверх всех окон и на всех рабочих столах.
/// Не забирает фокус у приложения, в котором вы работаете.
final class PetPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        contentView = PetView(size: size)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Рисует Клодика и даёт его перетаскивать. Правый клик открывает `menu`.
final class PetView: NSView {
    /// Текущий кадр. Кладётся прямо в слой, вид ничего не рисует сам.
    var image: CGImage? {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)   // без плавного перехода между кадрами
            layer?.contents = image
            CATransaction.commit()
        }
    }
    /// Вызывается, когда перетаскивание закончилось.
    var onDragEnd: (() -> Void)?

    init(size: NSSize) {
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.magnificationFilter = .nearest   // крупные чёткие пиксели
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)   // возвращается, когда кнопку отпустили
        onDragEnd?()
    }
}
