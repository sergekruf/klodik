import XCTest
@testable import KlodikCore

final class PetArtTests: XCTestCase {
    func testEveryFrameFillsTheCanvas() {
        for anim in PetAnimation.allCases {
            for frame in PetArt.frames(for: anim) {
                XCTAssertEqual(frame.pixels.count, PetArt.height, "\(anim)")
                XCTAssertTrue(frame.pixels.allSatisfy { $0.count == PetArt.width }, "\(anim)")
                XCTAssertGreaterThan(frame.duration, 0, "\(anim)")
            }
        }
    }

    func testMovingAnimationsRunAt8To12Fps() {
        for anim in [PetAnimation.working, .wave, .jump, .happy] {
            for frame in PetArt.frames(for: anim) {
                XCTAssertTrue((1.0 / 12 - 0.001 ... 1.0 / 8 + 0.001).contains(frame.duration), "\(anim): \(frame.duration)")
            }
        }
    }

    func testOneShotAnimationsHave6To8Frames() {
        for anim in [PetAnimation.wave, .jump, .happy] {
            XCTAssertTrue((6...8).contains(PetArt.frames(for: anim).count), "\(anim)")
            XCTAssertFalse(anim.loops)
        }
    }

    func testSleepIsOneStaticFrameSoTheTimerCanStop() {
        let frames = PetArt.frames(for: .sleep)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].duration, .infinity)
    }

    func testIdleRedrawsRarely() {
        // Дыхание и моргание — не чаще пары кадров в секунду в среднем.
        let frames = PetArt.frames(for: .idle)
        let total = frames.map(\.duration).reduce(0, +)
        XCTAssertGreaterThan(total / Double(frames.count), 0.5)
    }

    func testBlinkChangesOnlyTheEyes() {
        let open = PetArt.render(Pose())
        let closed = PetArt.render(Pose(eyes: .closed))
        for (a, b) in zip(open, closed) where a != b {
            for (ca, cb) in zip(a, b) where ca != cb {
                XCTAssertTrue(ca == "E" || cb == "E", "отличие не в глазах")
            }
        }
        XCTAssertNotEqual(open, closed)
    }

    func testFeetStayOnTheGroundWhenStandingOrSquashed() {
        XCTAssertNotEqual(PetArt.render(Pose()).last, String(repeating: ".", count: PetArt.width))
        XCTAssertNotEqual(PetArt.render(Pose(squash: true)).last, String(repeating: ".", count: PetArt.width))
    }

    func testJumpPeakLiftsTheWholeBody() {
        let ground = PetArt.render(Pose())
        let air = PetArt.render(Pose(lift: 5))
        let empty = String(repeating: ".", count: PetArt.width)
        XCTAssertEqual(Array(air[0..<(PetArt.height - 5)]), Array(ground[5...]))
        XCTAssertEqual(Array(air[(PetArt.height - 5)...]), Array(repeating: empty, count: 5))
    }
}
