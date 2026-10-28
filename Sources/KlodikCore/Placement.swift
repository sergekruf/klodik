import CoreGraphics

/// Где показывать Клодика на экране.
public enum Placement {
    /// Отступ от края видимой области экрана, в точках.
    public static let margin: CGFloat = 24

    /// Сохранённая позиция, если центр Клодика попадает на какой-нибудь экран,
    /// иначе правый нижний угол первого экрана (главного — так их отдаёт NSScreen.screens).
    /// Координаты как у AppKit: начало в левом нижнем углу.
    public static func resolvedOrigin(saved: CGPoint?, petSize: CGSize, visibleFrames: [CGRect]) -> CGPoint {
        if let saved {
            let center = CGPoint(x: saved.x + petSize.width / 2, y: saved.y + petSize.height / 2)
            if visibleFrames.contains(where: { $0.contains(center) }) { return saved }
        }
        guard let main = visibleFrames.first else { return .zero }
        return CGPoint(x: main.maxX - petSize.width - margin, y: main.minY + margin)
    }
}
