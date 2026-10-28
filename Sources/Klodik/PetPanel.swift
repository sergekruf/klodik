import AppKit

/// Прозрачное окно без рамки поверх всех окон и на всех рабочих столах.
/// Не забирает фокус у приложения, в котором вы работаете.
final class PetPanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: content.frame.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Клодик и бейдж над ним. Клик — `onClick`, перетаскивание двигает окно, правый клик открывает `menu`.
final class PetContentView: NSView {
    static let size = NSSize(width: Sprites.size.width + 16, height: Sprites.size.height + 10)

    let sprite = SpriteView(frame: NSRect(origin: .zero, size: Sprites.size))
    let badge = BadgeView(frame: NSRect(x: Sprites.size.width - 10, y: Sprites.size.height - 8, width: 26, height: 18))
    var onClick: (() -> Void)?
    /// Вызывается, когда перетаскивание закончилось.
    var onDragEnd: (() -> Void)?

    private var mouseDownAt: NSPoint?
    private var windowOriginAtDown: NSPoint = .zero
    private var dragging = false

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        addSubview(sprite)
        addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// Все клики достаются этому виду, а не спрайту или бейджу.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownAt = NSEvent.mouseLocation
        windowOriginAtDown = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownAt else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !dragging && hypot(dx, dy) < 3 { return }   // дрожание руки при клике — не перетаскивание
        dragging = true
        window?.setFrameOrigin(NSPoint(x: windowOriginAtDown.x + dx, y: windowOriginAtDown.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownAt = nil }
        if dragging { onDragEnd?() } else { onClick?() }
    }
}

/// Кадр Клодика. Кладётся прямо в слой, вид ничего не рисует сам.
final class SpriteView: NSView {
    var image: CGImage? {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)   // без плавного перехода между кадрами
            layer?.contents = image
            CATransaction.commit()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest   // крупные чёткие пиксели
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }
}

/// Число сессий в списке. Красный — кто-то ждёт ответа, синий — только непрочитанные.
final class BadgeView: NSView {
    var count = 0 { didSet { if count != oldValue { isHidden = count == 0; needsDisplay = true } } }
    var urgent = false { didSet { if urgent != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override func draw(_ dirtyRect: NSRect) {
        let text = count > 99 ? "99+" : "\(count)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = text.size(withAttributes: attributes)
        let width = max(bounds.height, textSize.width + 10)
        let pill = NSRect(x: bounds.maxX - width, y: 0, width: width, height: bounds.height)
        (urgent ? NSColor.systemRed : NSColor.systemBlue).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: NSPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2), withAttributes: attributes)
    }
}
