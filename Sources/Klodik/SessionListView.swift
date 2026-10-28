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

    var open: (TrackedItem) -> Void = { _ in }
    var toggleRemind: (TrackedItem) -> Void = { _ in }
    var hide: (TrackedItem) -> Void = { _ in }
    var installHooks: () -> Void = {}
    var toggleSnooze: () -> Void = {}
    var quit: () -> Void = {}
}

struct SessionListView: View {
    @ObservedObject var model: SessionListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.items.isEmpty {
                Text("Никто не ждёт")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.items, id: \.localId) { item in
                            SessionRow(item: item, reminded: model.remindIds.contains(item.localId), now: model.now)
                                .onTapGesture { model.open(item) }
                                .contextMenu {
                                    Button(model.remindIds.contains(item.localId) ? "Не напоминать" : "Напомнить") {
                                        model.toggleRemind(item)
                                    }
                                    Button("Скрыть до следующей активности") { model.hide(item) }
                                }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }

            if model.formatBroken {
                Warning(text: "Не читаются файлы сессий Claude — слежу только по хукам")
            }
            if let problem = model.serverProblem {
                Warning(text: problem)
            }
            if !model.hooksInstalled {
                Divider()
                HStack {
                    Text("Хуки Claude Code не установлены: не вижу запросов разрешений")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Установить") { model.installHooks() }
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()
            HStack {
                Button(model.snoozed ? "Не откладывать" : "Отложить на 30 минут") { model.toggleSnooze() }
                Spacer()
                Button("Выйти") { model.quit() }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
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
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Dot(dot: item.dot, opened: item.openedSinceWaiting)
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
        .onHover { hovered = $0 }
        .help(item.detail ?? item.title)
    }
}

/// Серая — нужен ответ (кольцо, если уже открывали), синяя — не прочитана, синяя с колокольчиком — «напомнить».
private struct Dot: View {
    let dot: TrackedItem.Dot
    let opened: Bool

    var body: some View {
        Group {
            switch dot {
            case .gray where opened:
                Circle().strokeBorder(Color.gray, lineWidth: 2)
            case .gray:
                Circle().fill(Color.gray)
            case .blue:
                Circle().fill(Color.blue)
            case .remind:
                ZStack {
                    Circle().fill(Color.blue)
                    Image(systemName: "bell.fill").font(.system(size: 6)).foregroundStyle(.white)
                }
            }
        }
        .frame(width: 10, height: 10)
    }
}
