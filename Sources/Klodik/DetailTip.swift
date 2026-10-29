import AppKit
import SwiftUI
import KlodikCore

/// Окошко сбоку от списка сессий напротив строки под курсором: что эта сессия просит, а если задала вопрос —
/// вопрос и варианты ответа. Только показывает: отвечают в Claude. Появляется сразу, без системной задержки подсказок.
final class DetailTip {
    static let width: CGFloat = 320
    private let panel: NSPanel
    private let host = NSHostingView(rootView: DetailTipView(detail: nil, questions: []))

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .popUpMenu   // выше списка, который сам висит над окнами
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = host
    }

    /// Показать слева от списка `list` вровень с верхом строки `row` (справа, если слева не помещается). Всё в координатах экрана.
    func show(detail: String?, questions: [AskedQuestion], beside row: NSRect, list: NSRect) {
        host.rootView = DetailTipView(detail: detail, questions: questions)
        let size = host.fittingSize

        let screen = NSScreen.screens.first { $0.frame.intersects(list) }?.visibleFrame ?? list
        var origin = NSPoint(x: list.minX - size.width - 6, y: row.maxY - size.height)
        if origin.x < screen.minX + 4 { origin.x = list.maxX + 6 }
        origin.y = min(max(origin.y, screen.minY + 4), screen.maxY - size.height - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// Тёмная карточка: текст «что просит» или вопросы Claude с вариантами, как в самом Claude.
private struct DetailTipView: View {
    let detail: String?
    let questions: [AskedQuestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if questions.isEmpty {
                Text(detail ?? "").font(.system(size: 12)).lineLimit(8)
            } else {
                ForEach(questions.indices, id: \.self) { index in
                    question(questions[index])
                }
                Text(tr("Ответить можно в Claude: клик по строке откроет сессию", "Answer in Claude: click the row to open the session"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(width: DetailTip.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12, opacity: 0.96)))
    }

    private func question(_ q: AskedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Вопрос от Claude", "Question from Claude"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
            Text(q.text).font(.system(size: 12, weight: .semibold)).lineLimit(4)
            ForEach(q.options.indices, id: \.self) { index in
                let option = q.options[index]
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    if let description = option.description {
                        Text(description).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(3)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1)))
            }
            if q.multiSelect {
                Text(tr("Можно выбрать несколько", "You can pick several"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}
