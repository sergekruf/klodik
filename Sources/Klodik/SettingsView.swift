import SwiftUI
import ServiceManagement
import Translation
import KlodikCore

/// Автозапуск при входе в систему через SMAppService.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

final class SettingsModel: ObservableObject {
    @Published var launchAtLogin = false
    @Published var loginNeedsApproval = false
    @Published var loginError: String?
    @Published var reminderScale = ReminderScale.normal
    @Published var hotKeyEnabled = true
    @Published var checkUpdates = true
    /// Сочетание занято другим приложением.
    @Published var hotKeyBusy = false
    @Published var hooksInstalled = false
    /// Английские итоги ходов можно переводить, но языки перевода ещё не скачаны.
    @Published var translationNeedsDownload = false
    var translationLanguages = (source: Locale.Language(identifier: "en"), target: Locale.Language(identifier: "ru"))

    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var setReminderScale: (ReminderScale) -> Void = { _ in }
    var setHotKeyEnabled: (Bool) -> Void = { _ in }
    var setCheckUpdates: (Bool) -> Void = { _ in }
    var toggleHooks: () -> Void = {}
    /// Окно скачивания языков закрылось: скачали или отказались.
    var translationPrepared: () -> Void = {}
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    /// Легенда точек: те же цвета, что в Claude (решение пользователя).
    static let legend: [(dot: TrackedItem.Dot, opened: Bool, text: String)] = [
        (.waiting, false, tr("Ждёт ответа: разрешение или вопрос", "Needs your answer: a permission or a question")),
        (.waiting, true, tr("Ждёт ответа, вы уже открывали", "Needs your answer, you already opened it")),
        (.blue, false, tr("Закончила, вы ещё не открывали", "Finished, you haven't opened it yet")),
        (.unread, false, tr("Отмечена непрочитанной в Claude", "Marked unread in Claude")),
        (.remind, false, tr("«Напомнить» в Клодике (правый клик по строке)", "“Remind me” in Klodik (right-click a row)")),
    ]

    var body: some View {
        Form {
            Section {
                Toggle(tr("Запускать при входе в систему", "Launch at login"), isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.loginNeedsApproval {
                    HStack {
                        Text(tr("Разрешите Клодика в «Объектах входа»", "Allow Klodik in Login Items")).font(.caption).foregroundStyle(.orange)
                        Button(tr("Открыть", "Open")) { SMAppService.openSystemSettingsLoginItems() }.font(.caption)
                    }
                }
                if let error = model.loginError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }

            Section(tr("Напоминания", "Reminders")) {
                Picker(tr("Напоминания", "Reminders"), selection: Binding(
                    get: { model.reminderScale },
                    set: { model.setReminderScale($0) }
                )) {
                    ForEach(ReminderScale.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.reminderScale.detail).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: Binding(get: { model.hotKeyEnabled }, set: { model.setHotKeyEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("\(HotKey.display) — к следующей сессии", "\(HotKey.display): next session"))
                        Text(tr("Открывает сессию, которая дольше всех ждёт ответа. Ещё раз — следующую",
                                 "Opens the session that has waited longest for you. Press again for the next one"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.hotKeyEnabled && model.hotKeyBusy {
                    Text(tr("Сочетание занято другим приложением", "This shortcut is taken by another app")).font(.caption).foregroundStyle(.orange)
                }
                Toggle(tr("Проверять новые версии на GitHub", "Check GitHub for new versions"),
                       isOn: Binding(get: { model.checkUpdates }, set: { model.setCheckUpdates($0) }))
                if #available(macOS 15, *), model.translationNeedsDownload {
                    TranslationDownloadRow(model: model)
                }
            }

            Section(tr("Точки в списке", "Dots in the list")) {
                ForEach(Self.legend, id: \.text) { row in
                    HStack(spacing: 10) {
                        DotView(dot: row.dot, opened: row.opened)
                        Text(row.text)
                    }
                }
            }

            // Порт приёмника и глубина истории (7 дней) живут только в state.json: обычному пользователю они не нужны.
            Section("Claude Code") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hooksInstalled ? tr("Подключён", "Connected") : tr("Не подключён", "Not connected"))
                            .foregroundStyle(model.hooksInstalled ? Color.primary : Color.orange)
                        Text(tr("Хуки в ~/.claude/settings.json: без них Клодик не видит запросы разрешений",
                                 "Hooks in ~/.claude/settings.json: without them Klodik can't see permission requests"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.hooksInstalled ? tr("Отключить", "Disconnect") : tr("Подключить", "Connect")) { model.toggleHooks() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Строка в настройках, пока языки перевода не скачаны. Скачивание спрашивает сама macOS в своём окне.
@available(macOS 15, *)
private struct TranslationDownloadRow: View {
    @ObservedObject var model: SettingsModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Переводить итоги на русский", "Translate summaries into English"))
                Text(tr("Claude иногда пишет итог хода по-английски. Перевод идёт на этом Mac, языки нужно один раз скачать",
                         "Claude sometimes writes turn summaries in Russian. Translation runs on this Mac; download the languages once"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(tr("Скачать", "Download")) {
                configuration = .init(source: model.translationLanguages.source, target: model.translationLanguages.target)
            }
        }
        .translationTask(configuration) { session in
            try? await session.prepareTranslation()
            await MainActor.run { model.translationPrepared() }
        }
    }
}
