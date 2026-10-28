import AppKit
import KlodikCore

/// Крутит кадры на одноразовых таймерах: каждый кадр держится столько, сколько ему положено.
/// Статичный кадр (сон) таймер не заводит вовсе, поэтому Клодик в покое ничего не тратит.
final class Animator {
    private let show: (CGImage) -> Void
    /// Фоновая анимация, к которой Клодик возвращается после разовых.
    private(set) var base: PetAnimation = .idle
    private var frames: [(image: CGImage, duration: TimeInterval)] = []
    private var index = 0
    private var playingOnce = false
    private var timer: Timer?

    init(show: @escaping (CGImage) -> Void) {
        self.show = show
        start(.idle)
    }

    func setBase(_ animation: PetAnimation) {
        guard animation != base else { return }
        base = animation
        if !playingOnce { start(animation) }
    }

    /// Разовая анимация поверх фоновой: прыжок, взмах, радость.
    func playOnce(_ animation: PetAnimation) {
        playingOnce = true
        start(animation)
    }

    private func start(_ animation: PetAnimation) {
        frames = Sprites.frames[animation] ?? []
        index = 0
        showCurrent()
    }

    private func showCurrent() {
        timer?.invalidate()
        timer = nil
        guard index < frames.count else { return }
        let frame = frames[index]
        show(frame.image)
        guard frame.duration.isFinite else { return }
        let next = Timer(timeInterval: frame.duration, repeats: false) { [weak self] _ in self?.advance() }
        next.tolerance = frame.duration * 0.1   // система может объединять пробуждения — меньше расход батареи
        RunLoop.main.add(next, forMode: .common)   // .common: не замирать, пока открыто меню или тащат окно
        timer = next
    }

    private func advance() {
        index += 1
        if index < frames.count { showCurrent(); return }
        if playingOnce {
            playingOnce = false
            start(base)
        } else {
            index = 0
            showCurrent()
        }
    }
}
