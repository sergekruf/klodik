import AppKit

/// Пиксельный Клодик. Каждая строка — ряд пикселей: `#` тело, `E` глаз, `.` прозрачно.
/// Анимации появятся на шаге 2, пока один статичный кадр.
enum Sprites {
    /// Сторона одного «пикселя» на экране, в точках.
    static let pixel: CGFloat = 3

    static let palette: [Character: NSColor] = [
        "#": NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1),   // оранжевый Claude, #D97757
        "E": .black,
    ]

    static let idle = [
        "..############..",
        "..############..",
        "..##E######E##..",
        "..##E######E##..",
        "################",
        "################",
        "..############..",
        "..############..",
        "..#.#......#.#..",
        "..#.#......#.#..",
    ]

    static func image(_ rows: [String]) -> NSImage {
        let width = CGFloat(rows.map(\.count).max() ?? 0) * pixel
        let height = CGFloat(rows.count) * pixel
        return NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() {
                    guard let color = palette[char] else { continue }
                    color.setFill()
                    NSRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel).fill()
                }
            }
            return true
        }
    }
}
