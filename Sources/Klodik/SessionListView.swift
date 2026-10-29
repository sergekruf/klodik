import SwiftUI
import KlodikCore

/// Данные и действия для всплывающего списка.
final class SessionListModel: ObservableObject {
    @Published var items: [TrackedItem] = []
    @Published var remindIds: Set<String> = []
    @Published var now = Date()
    @Published var snoozed = false
    @Published var formatBroken = false
    @Published var hooksInstalled = true
    /// Приёмник событий не запустился — текст для пользователя.
    @Published var serverProblem: String?
    /// Как быстро сегодня отвечал на запросы. nil — сегодня ответов ещё не было.
    @Published var daySummary: DaySummary?
    /// На GitHub вышла версия новее установленной.
    @Published var update: UpdateCheck.Release?

    var open: (TrackedItem) -> Void = { _ in }
    var toggleRemind: (TrackedItem) -> Void = { _ in }
    var hide: (TrackedItem) -> Void = { _ in }
    var installHooks: () -> Void = {}
    var toggleSnooze: () -> Void = {}
    var openSettings: () -> Void = {}
    var quit: () -> Void = {}
    var openUpdate: (URL) -> Void = { _ in }
    /// Курсор вошёл в строку (`true`) или вышел из неё: показать или убрать окошко «что просит».
    /// Рамка строки — в координатах окна списка (SwiftUI `.global`, начало сверху слева).
    var hover: (TrackedItem, Bool, CGRect) -> Void = { _, _, _ in }
}

struct SessionListView: View {
    @ObservedObject var model: SessionListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.items.isEmpty {
                Text(tr("Никто не ждёт", "Nobody is waiting"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.items, id: \.localId) { item in
                            SessionRow(item: item, reminded: model.remindIds.contains(item.localId), now: model.now,
                                       onHover: { model.hover(item, $0, $1) })
                                .onTapGesture { model.open(item) }
                                .contextMenu {
                                    Button(model.remindIds.contains(item.localId) ? tr("Не напоминать", "Don't remind me") : tr("Напомнить", "Remind me")) {
                                        model.toggleRemind(item)
                                    }
                                    Button(tr("Скрыть до следующей активности", "Hide until next activity")) { model.hide(item) }
                                }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }

            if model.formatBroken {
                Warning(text: tr("Не читаются файлы сессий Claude — слежу только по хукам", "Can't read Claude session files: tracking via hooks only"))
            }
            if let problem = model.serverProblem {
                Warning(text: problem)
            }
            if !model.hooksInstalled {
                Divider()
                HStack {
                    Text(tr("Claude Code не подключён: не вижу запросов разрешений", "Claude Code isn't connected: can't see permission requests"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button(tr("Подключить", "Connect")) { model.installHooks() }
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            if let update = model.update {
                Divider()
                HStack {
                    Text(tr("Вышла версия \(update.version)", "Version \(update.version) is out")).font(.caption)
                    Spacer()
                    Button(tr("Скачать", "Download")) { model.openUpdate(update.url) }.font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            if let summary = model.daySummary {
                Divider()
                Text(tr("Сегодня ответов: \(summary.answered), в среднем через \(WaitTime.duration(summary.average)). "
                        + "Дольше всех ждала «\(summary.longest.title)»: \(WaitTime.duration(summary.longest.duration))",
                        "Today: \(summary.answered) answered, \(WaitTime.duration(summary.average)) on average. "
                        + "Longest wait: “\(summary.longest.title)”, \(WaitTime.duration(summary.longest.duration))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            Divider()
            HStack {
                Button(model.snoozed ? tr("Не откладывать", "Resume reminders") : tr("Отложить на 30 минут", "Snooze for 30 minutes")) { model.toggleSnooze() }
                Spacer()
                Button(tr("Настройки", "Settings")) { model.openSettings() }
                Button(tr("Выйти", "Quit")) { model.quit() }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }
}

private struct Warning: View {
    let text: String

    var body: some View {
        Divider()
        Text(text)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

private struct SessionRow: View {
    let item: TrackedItem
    let reminded: Bool
    let now: Date
    let onHover: (Bool, CGRect) -> Void
    @State private var hovered = false
    @State private var frame = CGRect.zero

    var body: some View {
        HStack(spacing: 10) {
            DotView(dot: item.dot, opened: item.openedSinceWaiting)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                Text(item.projectName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if reminded && item.dot != .remind {
                Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.secondary)
            }
            Text(WaitTime.short(now.timeIntervalSince(item.waitingSince)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? Color.primary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { frame = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { frame = $1 }
        })
        .onHover { inside in
            hovered = inside
            onHover(inside, frame)
        }
    }
}

/// Как в Claude: оранжевая — нужен ответ (кольцо, если уже открывали), синяя — закончила и не прочитана,
/// серая — отмечена непрочитанной в Claude, серая с колокольчиком — «Напомнить» в Клодике.
struct DotView: View {
    let dot: TrackedItem.Dot
    let opened: Bool

    var body: some View {
        Group {
            switch dot {
            case .waiting where opened:
                Circle().strokeBorder(Color.orange, lineWidth: 2)
            case .waiting:
                Circle().fill(Color.orange)
            case .blue:
                Circle().fill(Color.blue)
            case .unread:
                Circle().fill(Color.gray)
            case .remind:
                ZStack {
                    Circle().fill(Color.gray)
                    Image(systemName: "bell.fill").font(.system(size: 6)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 10, height: 10)
    }
}
