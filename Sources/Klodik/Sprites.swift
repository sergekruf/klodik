import AppKit
import KlodikCore

/// Превращает кадры из `PetArt` в картинки. Все кадры рисуются один раз при запуске.
enum Sprites {
    /// Сторона одного «пикселя» на экране, в точках.
    static let pixel: CGFloat = 3

    static let palette: [Character: NSColor] = [
        "#": NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1),   // оранжевый Claude, #D97757
        "E": .black,
        "z": NSColor(white: 0.55, alpha: 1),
    ]

    static let size = NSSize(width: CGFloat(PetArt.width) * pixel, height: CGFloat(PetArt.height) * pixel)

    static let frames: [PetAnimation: [(image: CGImage, duration: TimeInterval)]] =
        Dictionary(uniqueKeysWithValues: PetAnimation.allCases.map { anim in
            (anim, PetArt.frames(for: anim).compactMap { frame in bitmap(frame.pixels).map { ($0, frame.duration) } })
        })

    /// Картинка один пиксель на клетку. Увеличивает её слой окна без сглаживания,
    /// поэтому смена кадра — просто подмена картинки, без перерисовки.
    static func bitmap(_ rows: [String]) -> CGImage? {
        let width = rows.map(\.count).max() ?? 0
        guard let ctx = CGContext(data: nil, width: width, height: rows.count, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for (y, row) in rows.enumerated() {
            for (x, char) in row.enumerated() {
                guard let color = palette[char] else { continue }
                ctx.setFillColor(color.cgColor)
                ctx.fill(CGRect(x: x, y: rows.count - 1 - y, width: 1, height: 1))   // у CGContext начало внизу
            }
        }
        return ctx.makeImage()
    }

    static func image(_ rows: [String], pixel: CGFloat = pixel) -> NSImage {
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

    /// Все анимации на одном листе для просмотра: строка — анимация, столбец — кадр.
    static func writeContactSheet(to url: URL) throws {
        let cell = 16 * 6, gap = 12
        let anims = PetAnimation.allCases
        let cols = anims.map { PetArt.frames(for: $0).count }.max() ?? 1
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: cols * (cell + gap) + gap, pixelsHigh: anims.count * (cell + gap) + gap,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh).fill()
        for (row, anim) in anims.enumerated() {
            for (col, frame) in PetArt.frames(for: anim).enumerated() {
                let x = gap + col * (cell + gap)
                let y = rep.pixelsHigh - (row + 1) * (cell + gap)
                NSColor.white.setFill()
                NSRect(x: x, y: y, width: cell, height: cell).fill()
                image(frame.pixels, pixel: 6).draw(in: NSRect(x: x, y: y, width: cell, height: cell))
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// `<анимация>-<n>.png` (16×16 → 160×160) и `<анимация>.ffconcat` с длительностями кадров.
    static func writeFrames(to dir: URL, pixel: Int = 10) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for anim in PetAnimation.allCases {
            var concat = "ffconcat version 1.0\n"
            let frames = PetArt.frames(for: anim)
            for (n, frame) in frames.enumerated() {
                let name = "\(anim.rawValue)-\(n).png"
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16 * pixel, pixelsHigh: 16 * pixel,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                image(frame.pixels, pixel: CGFloat(pixel)).draw(in: NSRect(x: 0, y: 0, width: 16 * pixel, height: 16 * pixel))
                NSGraphicsContext.restoreGraphicsState()
                try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
                let duration = frame.duration.isFinite ? frame.duration : 1
                concat += "file '\(name)'\nduration \(duration)\n"
            }
            // ffmpeg берёт длительность последнего кадра, только если файл повторён ещё раз.
            if let last = frames.indices.last { concat += "file '\(anim.rawValue)-\(last).png'\n" }
            try concat.write(to: dir.appendingPathComponent("\(anim.rawValue).ffconcat"), atomically: true, encoding: .utf8)
        }
    }
}
