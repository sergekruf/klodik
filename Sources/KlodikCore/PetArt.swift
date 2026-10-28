import Foundation

/// Что делает Клодик.
public enum PetAnimation: String, CaseIterable {
    case idle, working, wave, jump, happy, sleep

    /// Фоновые анимации крутятся по кругу, остальные играют один раз.
    public var loops: Bool { self == .idle || self == .working || self == .sleep }
}

/// Один кадр: ряды пикселей (`#` тело, `E` глаз, `z` сон, `.` прозрачно) и сколько его показывать.
public struct PetFrame: Equatable {
    public let pixels: [String]
    public let duration: TimeInterval
}

public enum Eyes { case open, closed, happy }
public enum Arm { case down, mid, up }
public enum Legs { case stand, leftUp, rightUp }

/// Поза, из которой собирается кадр.
public struct Pose: Equatable {
    /// На сколько рядов Клодик оторвался от земли.
    public var lift = 0
    /// Присел: тело на ряд ниже, ноги короче, ступни остаются на земле.
    public var squash = false
    public var eyes = Eyes.open
    public var leftArm = Arm.down
    public var rightArm = Arm.down
    public var legs = Legs.stand
    public var zzz = false

    public init(lift: Int = 0, squash: Bool = false, eyes: Eyes = .open,
                leftArm: Arm = .down, rightArm: Arm = .down, legs: Legs = .stand, zzz: Bool = false) {
        self.lift = lift; self.squash = squash; self.eyes = eyes
        self.leftArm = leftArm; self.rightArm = rightArm; self.legs = legs; self.zzz = zzz
    }
}

/// Пиксельный Клодик на холсте 16×16. Верхние 6 рядов — запас под прыжок и «Zzz».
public enum PetArt {
    public static let width = 16
    public static let height = 16

    public static func render(_ pose: Pose) -> [String] {
        var grid = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        func put(_ x: Int, _ y: Int, _ c: Character) {
            if (0..<width).contains(x), (0..<height).contains(y) { grid[y][x] = c }
        }

        let bodyRows = pose.squash ? 7 : 8
        let legRows = pose.squash ? 1 : 2
        let top = height - legRows - bodyRows - pose.lift

        for r in 0..<bodyRows { for x in 2...13 { put(x, top + r, "#") } }

        switch pose.eyes {
        case .open:
            for x in [4, 11] { put(x, top + 2, "E"); put(x, top + 3, "E") }
        case .closed:
            for x in [3, 4, 5, 10, 11, 12] { put(x, top + 3, "E") }
        case .happy:   // «^ ^»
            for x in [4, 11] { put(x, top + 2, "E") }
            for x in [3, 5, 10, 12] { put(x, top + 3, "E") }
        }

        // Опущенная и приподнятая рука — блок 2×2 сбоку, поднятая — столбик 2×4 выше макушки.
        func arm(_ arm: Arm, x: Int) {
            let rows: ClosedRange<Int>
            switch arm {
            case .down: rows = 4...5
            case .mid: rows = 3...4
            case .up: rows = -1...2
            }
            for dx in 0...1 { for r in rows { put(x + dx, top + r, "#") } }
        }
        arm(pose.leftArm, x: 0)
        arm(pose.rightArm, x: 14)

        let legTop = top + bodyRows
        for x in [2, 4, 11, 13] {
            let lifted = x < 8 ? pose.legs == .leftUp : pose.legs == .rightUp
            for r in 0..<(lifted ? 1 : legRows) { put(x, legTop + r, "#") }
        }

        if pose.zzz {
            for (y, row) in ["zzzz", "..z.", ".z..", "zzzz"].enumerated() {
                for (x, c) in row.enumerated() where c == "z" { put(11 + x, 1 + y, "z") }
            }
        }
        return grid.map { String($0) }
    }

    public static func frames(for animation: PetAnimation) -> [PetFrame] {
        func f(_ pose: Pose, _ duration: TimeInterval) -> PetFrame { PetFrame(pixels: render(pose), duration: duration) }
        let fast = 1.0 / 10, wave = 1.0 / 8, jump = 1.0 / 12

        switch animation {
        case .idle:   // стоит и иногда моргает, иногда дважды
            return [f(Pose(), 3.2), f(Pose(eyes: .closed), 0.13),
                    f(Pose(), 2.4), f(Pose(eyes: .closed), 0.13),
                    f(Pose(), 0.2), f(Pose(eyes: .closed), 0.13)]
        case .working:   // стучит лапками по клавиатуре
            return [f(Pose(leftArm: .mid, legs: .leftUp), fast), f(Pose(), fast),
                    f(Pose(rightArm: .mid, legs: .rightUp), fast), f(Pose(), fast)]
        case .wave:
            return (0..<6).map { f(Pose(eyes: .happy, rightArm: $0.isMultiple(of: 2) ? .up : .mid), wave) }
        case .jump:
            return [f(Pose(squash: true), jump),
                    f(Pose(lift: 2, leftArm: .mid, rightArm: .mid), jump),
                    f(Pose(lift: 4, leftArm: .up, rightArm: .up), jump),
                    f(Pose(lift: 5, leftArm: .up, rightArm: .up), jump),
                    f(Pose(lift: 4, leftArm: .up, rightArm: .up), jump),
                    f(Pose(lift: 2, leftArm: .mid, rightArm: .mid), jump),
                    f(Pose(squash: true), jump),
                    f(Pose(), jump)]
        case .happy:   // подпрыгивает на месте и машет обеими руками
            return [0, 1, 2, 1, 0, 1, 2, 1].enumerated().map { i, lift in
                let arm: Arm = i.isMultiple(of: 2) ? .up : .mid
                return f(Pose(lift: lift, eyes: .happy, leftArm: arm, rightArm: arm), fast)
            }
        case .sleep:
            return [f(Pose(squash: true, eyes: .closed, zzz: true), .infinity)]
        }
    }
}
