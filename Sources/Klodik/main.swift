import AppKit

// `Klodik --sheet путь.png` — нарисовать все анимации на одном листе и выйти.
if let i = CommandLine.arguments.firstIndex(of: "--sheet"), i + 1 < CommandLine.arguments.count {
    do {
        try Sprites.writeContactSheet(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Не удалось сохранить лист: \(error)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // без иконки в Dock, даже при запуске не из .app
app.run()
