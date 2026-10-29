import AppKit
import SwiftUI

/// Пузырь как в комиксах над Клодиком: белое облачко с обводкой и хвостиком к нему. Висит дольше, чем длиннее текст.
final class Bubble {
    struct Content {
        /// Маленькая цветная строка сверху: «Готово», «Ждёт ответа». nil — без неё.
        var label: String?
        var labelColor: Color = .secondary
        var title: String
        /// Что сделала или что просит сессия. Может прийти позже (`update`).
        var text: String?
    }

    static let maxTextWidth: CGFloat = 260
    private let panel: NSPanel
    private let host = NSHostingView(rootView: BubbleView(content: Content(title: ""), textWidth: 0, tailX: 0, tailUp: false))
    private var hideWork: DispatchWorkItem?
    private var anchor = NSRect.zero
    private var content = Content(title: "")
    private var shownAt = Date.distantPast
    private var seconds: TimeInterval = 0

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // тень рисует сам пузырь, плотную, как в комиксе
        panel.ignoresMouseEvents = true
        panel.contentView = host
    }

    var isShown: Bool { panel.isVisible }

    /// Короткая фраза без подписи: ошибки и «Никто не ждёт».
    func show(_ text: String, above anchor: NSRect, for seconds: TimeInterval? = nil) {
        show(Content(title: text), above: anchor, for: seconds)
    }

    /// Показать над окном `anchor` (или под ним, если сверху нет места). Без `seconds` — от 6 до 15 секунд по длине текста.
    func show(_ content: Content, above anchor: NSRect, for seconds: TimeInterval? = nil) {
        self.anchor = anchor
        self.content = content
        shownAt = Date()
        self.seconds = seconds ?? Self.readingTime(content)
        let frame = layout()
        // Появляется, чуть подпрыгнув от Клодика.
        hideWork?.cancel()
        panel.alphaValue = 0
        panel.setFrame(frame.offsetBy(dx: 0, dy: frame.minY > anchor.midY ? -8 : 8), display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        scheduleHide(after: self.seconds)
    }

    /// Текст пришёл позже (приложение Claude пишет итог хода через несколько секунд): перерисовать и дать дочитать.
    func update(text: String?) {
        guard isShown, text != content.text else { return }
        content.text = text
        panel.setFrame(layout(), display: true)
        let left = seconds - Date().timeIntervalSince(shownAt)
        scheduleHide(after: max(left, Self.readingTime(content) / 2))
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    private static func readingTime(_ content: Content) -> TimeInterval {
        let characters = content.title.count + (content.text?.count ?? 0)
        return min(15, max(6, Double(characters) * 0.08))
    }

    /// Нарисовать содержимое и вернуть, где должно стоять окно.
    private func layout() -> NSRect {
        let width = textWidth()
        host.rootView = BubbleView(content: content, textWidth: width, tailX: 0, tailUp: false)
        let size = host.fittingSize

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) }?.visibleFrame ?? anchor
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY - 2)
        let tailUp = origin.y + size.height > screen.maxY
        if tailUp { origin.y = anchor.minY - size.height + 4 }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        // Хвостик смотрит на Клодика, даже если пузырь прижат к краю экрана.
        host.rootView = BubbleView(content: content, textWidth: width, tailX: anchor.midX - origin.x, tailUp: tailUp)
        return NSRect(origin: origin, size: size)
    }

    /// Ширина текста: по самой длинной строке, но не шире `maxTextWidth` — дальше перенос.
    private func textWidth() -> CGFloat {
        func width(_ text: String?, _ font: NSFont) -> CGFloat {
            guard let text else { return 0 }
            return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
        }
        let widest = max(width(content.label, BubbleView.nsFont(11, .semibold)),
                         width(content.title, BubbleView.nsFont(13, .bold)),
                         width(content.text, BubbleView.nsFont(12, .regular)))
        return min(widest, Self.maxTextWidth)
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, panel.alphaValue == 0 else { return }
                panel.orderOut(nil)
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

private struct BubbleView: View {
    static let tailHeight: CGFloat = 12
    /// Сдвиг плотной тени вправо-вниз, как у рисованного пузыря.
    static let shadowOffset: CGFloat = 3

    let content: Bubble.Content
    let textWidth: CGFloat
    let tailX: CGFloat
    let tailUp: Bool

    static func nsFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    }

    var body: some View {
        let shape = SpeechBubble(tailX: tailX - 2, tailUp: tailUp, tailHeight: Self.tailHeight)
        VStack(alignment: .leading, spacing: 2) {
            if let label = content.label {
                Text(label).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(content.labelColor)
            }
            Text(content.title).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(2)
            if let text = content.text {
                Text(text).font(.system(size: 12, design: .rounded)).lineLimit(6)
            }
        }
        .foregroundStyle(Color(white: 0.1))
        .frame(width: textWidth, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .padding(tailUp ? .top : .bottom, Self.tailHeight)
        .background(
            ZStack {
                shape.fill(Color.black.opacity(0.85)).offset(x: Self.shadowOffset, y: Self.shadowOffset)
                shape.fill(Color.white)
                shape.stroke(Color.black, lineWidth: 2)
            }
        )
        .padding(.trailing, Self.shadowOffset + 1)
        .padding(.bottom, Self.shadowOffset + 1)
        .padding([.top, .leading], 1)
    }
}

/// Облачко со скруглёнными углами и треугольным хвостиком снизу (или сверху), нарисованное одной линией.
private struct SpeechBubble: Shape {
    let tailX: CGFloat
    let tailUp: Bool
    let tailHeight: CGFloat
    let radius: CGFloat = 14
    let tailWidth: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let body = tailUp
            ? CGRect(x: rect.minX, y: rect.minY + tailHeight, width: rect.width, height: rect.height - tailHeight)
            : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
        let x = min(max(tailX, body.minX + radius + tailWidth / 2), body.maxX - radius - tailWidth / 2)
        var p = Path()
        p.move(to: CGPoint(x: body.minX + radius, y: body.minY))
        if tailUp {
            p.addLine(to: CGPoint(x: x - tailWidth / 2, y: body.minY))
            p.addLine(to: CGPoint(x: x - 3, y: rect.minY))
            p.addLine(to: CGPoint(x: x + tailWidth / 2, y: body.minY))
        }
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.maxX, y: body.minY + radius), radius: radius)
        p.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX - radius, y: body.maxY), radius: radius)
        if !tailUp {
            p.addLine(to: CGPoint(x: x + tailWidth / 2, y: body.maxY))
            p.addLine(to: CGPoint(x: x - 3, y: rect.maxY))   // чуть вбок, как у рисованного
            p.addLine(to: CGPoint(x: x - tailWidth / 2, y: body.maxY))
        }
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.minX, y: body.maxY - radius), radius: radius)
        p.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX + radius, y: body.minY), radius: radius)
        p.closeSubpath()
        return p
    }
}
