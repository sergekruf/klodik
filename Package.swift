// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Klodik",
    platforms: [.macOS(.v14)],
    targets: [
        // Логика без UI: файлы сессий, события хуков, правила, состояние.
        .target(name: "KlodikCore"),
        // Само приложение: окно питомца, спрайты, меню.
        .executableTarget(name: "Klodik", dependencies: ["KlodikCore"]),
        .testTarget(name: "KlodikCoreTests", dependencies: ["KlodikCore"]),
    ]
)
