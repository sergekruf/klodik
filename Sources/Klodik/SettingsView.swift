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
    @Published var windowDays = 7
    @Published var portText = ""
    @Published var portError: String?
    @Published var listeningPort: UInt16?
    @Published var hooksInstalled = false

    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var setReminderScale: (ReminderScale) -> Void = { _ in }
    var setWindowDays: (Int) -> Void = { _ in }
    var applyPort: (UInt16) -> Void = { _ in }
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

                Stepper(value: Binding(get: { model.windowDays }, set: { model.setWindowDays($0) }), in: 1...30) {
                    Text("Сессии за последние \(model.windowDays) дн.")
                }
            }

            Section("Хуки Claude Code") {
                HStack {
                    Text(model.hooksInstalled ? "Установлены" : "Не установлены")
                        .foregroundStyle(model.hooksInstalled ? Color.secondary : Color.orange)
                    Spacer()
                    Button(model.hooksInstalled ? "Удалить" : "Установить") { model.toggleHooks() }
                }
                HStack {
                    TextField("Порт", text: $model.portText)
                        .frame(width: 90)
                    Button("Применить") {
                        if let port = UInt16(model.portText.trimmingCharacters(in: .whitespaces)), port >= 1024 {
                            model.portError = nil
                            model.applyPort(port)
                        } else {
                            model.portError = "Порт — число от 1024 до 65535"
                        }
                    }
                    Spacer()
                    if let port = model.listeningPort {
                        Text("слушаю \(String(port))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = model.portError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
