import SwiftUI
import ServiceManagement
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
    @Published var hooksInstalled = false

    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var setReminderScale: (ReminderScale) -> Void = { _ in }
    var toggleHooks: () -> Void = {}
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.loginNeedsApproval {
                    HStack {
                        Text("Разрешите Клодика в «Объектах входа»").font(.caption).foregroundStyle(.orange)
                        Button("Открыть") { SMAppService.openSystemSettingsLoginItems() }.font(.caption)
                    }
                }
                if let error = model.loginError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Напоминания") {
                Picker("Напоминания", selection: Binding(
                    get: { model.reminderScale },
                    set: { model.setReminderScale($0) }
                )) {
                    ForEach(ReminderScale.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(model.reminderScale.detail).font(.caption).foregroundStyle(.secondary)
            }

            // Порт приёмника и глубина истории (7 дней) живут только в state.json: обычному пользователю они не нужны.
            Section("Claude Code") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.hooksInstalled ? "Подключён" : "Не подключён")
                            .foregroundStyle(model.hooksInstalled ? Color.primary : Color.orange)
                        Text("Хуки в ~/.claude/settings.json: без них Клодик не видит запросы разрешений")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.hooksInstalled ? "Отключить" : "Подключить") { model.toggleHooks() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
