import Foundation
import XCTest
@testable import FilePetShell

final class AnimationTests: XCTestCase {
    private let size = CoreSize(width: 1440, height: 900)
    private let origin = CorePoint(x: 100, y: 100)

    func testSourceFrameTimingAndLoop() {
        XCTAssertEqual(CharacterAnimation.frameIndex(at: -1), 0)
        XCTAssertEqual(CharacterAnimation.frameIndex(at: 0), 0)
        XCTAssertEqual(CharacterAnimation.frameIndex(at: 0.039), 0)
        XCTAssertEqual(CharacterAnimation.frameIndex(at: 0.04), 1)
        XCTAssertEqual(CharacterAnimation.frameIndex(at: 1.18), 29)
        XCTAssertEqual(CharacterAnimation.frameIndex(at: 1.2), 0)
        XCTAssertEqual(CharacterAnimation.frameIndex(at: 2.36), 29)
        XCTAssertEqual(CharacterAnimation.frameIndex(at: .infinity), 0)
        XCTAssertEqual(CharacterAnimation.frameIndex(at: .nan), 0)
        XCTAssertTrue((0..<30).contains(CharacterAnimation.frameIndex(at: .greatestFiniteMagnitude)))
    }

    func testSourceFrameBoundaryDoesNotAdvanceEarly() {
        let boundaries: [(TimeInterval, Int)] = [
            (0.04, 1), (0.08, 2), (0.12, 3), (1.16, 29), (1.2, 0), (2.36, 29)
        ]
        for (time, frame) in boundaries {
            let previous = (frame + CharacterAnimation.frameCount - 1) % CharacterAnimation.frameCount
            XCTAssertEqual(CharacterAnimation.frameIndex(at: time - 0.000000001), previous, "before \(time)")
            XCTAssertEqual(CharacterAnimation.frameIndex(at: time.nextDown), previous, "ULP before \(time)")
            XCTAssertEqual(CharacterAnimation.frameIndex(at: time), frame, "at \(time)")
            XCTAssertEqual(CharacterAnimation.frameIndex(at: time.nextUp), frame, "ULP after \(time)")
            XCTAssertEqual(CharacterAnimation.frameIndex(at: time + 0.000000001), frame, "after \(time)")
        }
    }

    func testHandPointUsesSameFrameAndMirror() {
        let right = CharacterAnimation.handPoint(at: 0, facingRight: true)
        let left = CharacterAnimation.handPoint(at: 0, facingRight: false)
        XCTAssertEqual(right.x, 104.52, accuracy: 0.000001)
        XCTAssertEqual(left.x, 35.88, accuracy: 0.000001)
        XCTAssertEqual(right.y, 41.6, accuracy: 0.000001)
        XCTAssertEqual(right.y, left.y)
        XCTAssertEqual(right.x + left.x, CharacterAnimation.mouseSize.width, accuracy: 0.000001)
        XCTAssertEqual(CharacterAnimation.handPoint(at: 0), CharacterAnimation.handPoint(at: 1.2))
    }

    func testShoulderAnchorUsesOriginalPoseAndMirror() {
        let expected = [
            CorePoint(x: 75.40, y: 61.36), CorePoint(x: 76.44, y: 56.16),
            CorePoint(x: 78.00, y: 63.44), CorePoint(x: 74.36, y: 62.40),
            CorePoint(x: 73.32, y: 55.64), CorePoint(x: 74.36, y: 58.76),
        ]
        for frame in 0..<CharacterAnimation.frameCount {
            let t = Double(frame) * CharacterAnimation.frameDuration + 0.001
            let right = CharacterAnimation.shoulderPoint(at: t)
            let left = CharacterAnimation.shoulderPoint(at: t, facingRight: false)
            XCTAssertEqual(right, expected[frame % expected.count])
            XCTAssertEqual(right.x + left.x, CharacterAnimation.mouseSize.width, accuracy: 0.000001)
            XCTAssertEqual(right.y, left.y)
        }
    }

    func testSceneKeyframesCatchAndExit() {
        let initial = TheftChoreography.state(at: 0, size: size, origin: origin)
        XCTAssertEqual(initial.grapeCenter, origin)
        XCTAssertEqual(initial.mouseOpacity, 0)
        let entry = TheftChoreography.state(at: 1.25, size: size, origin: origin)
        XCTAssertLessThan(entry.mouseOrigin.x + CharacterAnimation.mouseSize.width, 0)
        let falling = TheftChoreography.state(at: 1.8, size: size, origin: origin)
        let caught = TheftChoreography.state(at: 2.1, size: size, origin: origin)
        XCTAssertLessThan(falling.grapeCenter.y, caught.grapeCenter.y)
        XCTAssertEqual(caught.grapeCenter.x, 100, accuracy: 0.000001)
        XCTAssertGreaterThan(caught.mouseOpacity, 0.99)
        XCTAssertGreaterThan(caught.grapeCenter.y, caught.grapeBackContact.y)
        let before = TheftChoreography.state(at: 2.1 - 0.000001, size: size, origin: origin)
        XCTAssertEqual(before.grapeCenter.x, caught.grapeCenter.x, accuracy: 0.002)
        XCTAssertEqual(before.grapeCenter.y, caught.grapeCenter.y, accuracy: 0.002)
        let hold = TheftChoreography.state(at: 2.17, size: size, origin: origin)
        XCTAssertEqual(CharacterAnimation.frameIndex(at: caught.mouseElapsed),
                       CharacterAnimation.frameIndex(at: hold.mouseElapsed))
        XCTAssertGreaterThan(hold.catchImpact, 0)
        XCTAssertGreaterThan(hold.grapeScale.width, hold.grapeScale.height)
        let exit = TheftChoreography.state(at: 5.35, size: size, origin: origin)
        XCTAssertGreaterThan(exit.mouseOrigin.x, size.width)
        XCTAssertGreaterThan(exit.grapeCenter.x - 64, size.width)
        let finished = TheftChoreography.state(at: TheftChoreography.duration, size: size, origin: origin)
        XCTAssertEqual(finished.grapeOpacity, 0)
        XCTAssertEqual(finished.mouseOpacity, 0)
    }

    func testCarriedBerriesStayOnBackThroughAllRunPoses() {
        var poses = Set<Int>()
        for t in stride(from: 2.1, through: 5.35, by: 0.005) {
            let state = TheftChoreography.state(at: t, size: size, origin: origin)
            let shoulder = CharacterAnimation.shoulderPoint(at: state.mouseElapsed)
            let support = CorePoint(x: state.mouseOrigin.x + shoulder.x,
                                    y: state.mouseOrigin.y + shoulder.y)
            XCTAssertEqual(state.grapeBackContact.x, support.x, accuracy: 0.000001, "t=\(t)")
            XCTAssertEqual(state.grapeBackContact.y, support.y, accuracy: 0.000001, "t=\(t)")
            let angle = state.grapeRotation * .pi / 180
            let contactX = 22 * state.grapeScale.width
            let contactY = 6 * state.grapeScale.height
            XCTAssertEqual(state.grapeCenter.x + contactX * cos(angle) - contactY * sin(angle),
                           support.x, accuracy: 0.000001)
            XCTAssertEqual(state.grapeCenter.y + contactX * sin(angle) + contactY * cos(angle),
                           support.y, accuracy: 0.000001)
            XCTAssertGreaterThan(state.grapeCenter.y, support.y)
            XCTAssertLessThan(state.grapeCenter.x, support.x)
            XCTAssertEqual(state.ropeOpacity, 0)
            XCTAssertEqual(state.ropeSag, 0)
            poses.insert(CharacterAnimation.frameIndex(at: state.mouseElapsed) % 6)
        }
        XCTAssertEqual(poses.count, 6)
    }

    func testCarriedBerriesClearFloorThroughoutCatchAndRun() {
        // These are the visible ellipses in the 64 x 88 grape artwork. The
        // transformed ellipse bounds check the fruit itself, not its empty box.
        let berries: [(x: Double, y: Double, diameter: Double)] = [
            (32, 17, 20), (20, 25, 21), (44, 27, 20),
            (31, 37, 22), (14, 42, 20), (49, 44, 20),
            (22, 55, 21), (40, 57, 22), (31, 72, 21),
            (34, 9, 19), (17, 15, 19), (48, 17, 19),
        ]
        var poses = Set<Int>()
        for t in stride(from: 2.1, through: 5.35, by: 0.005) {
            let state = TheftChoreography.state(at: t, size: size, origin: origin)
            let angle = state.grapeRotation * .pi / 180
            let s = sin(angle), c = cos(angle)
            let lowest = berries.enumerated().map { index, berry in
                let x = (berry.x - 32) * state.grapeScale.width
                let y = (berry.y - 44) * state.grapeScale.height
                let rx = berry.diameter / 2
                let ry = berry.diameter * 0.55
                let berryAngle = Double(index % 3 - 1) * 8 * .pi / 180
                let bs = sin(berryAngle), bc = cos(berryAngle)
                let sx = state.grapeScale.width, sy = state.grapeScale.height
                let verticalRadius = hypot(rx * (sx * s * bc + sy * c * bs),
                                           ry * (-sx * s * bs + sy * c * bc))
                return state.grapeCenter.y + x * s + y * c + verticalRadius
            }.max()!
            XCTAssertLessThan(lowest, state.floorY - 1, "lowest berry at t=\(t)")
            poses.insert(CharacterAnimation.frameIndex(at: state.mouseElapsed) % 6)
        }
        XCTAssertEqual(poses.count, 6)
    }

    func testBodyMotionAndVisibilityStayContinuousAtStageBoundaries() {
        let epsilon = 0.000001
        for boundary in [0.9, 1.25, 2.1, 2.18, 2.34, 2.55, 3.0, 5.35, 5.45, 5.8] {
            let a = TheftChoreography.state(at: boundary - epsilon, size: size, origin: origin)
            let b = TheftChoreography.state(at: boundary + epsilon, size: size, origin: origin)
            // The back anchor changes on source cel boundaries. Its supported
            // fruit follows the same cel rather than interpolating off the back.
            XCTAssertEqual(a.mouseOrigin.x, b.mouseOrigin.x, accuracy: 0.01, "t=\(boundary)")
            XCTAssertEqual(a.mouseOrigin.y, b.mouseOrigin.y, accuracy: 0.01, "t=\(boundary)")
            XCTAssertEqual(a.grapeOpacity, b.grapeOpacity, accuracy: 0.001, "t=\(boundary)")
            XCTAssertEqual(a.mouseOpacity, b.mouseOpacity, accuracy: 0.001, "t=\(boundary)")
            XCTAssertEqual(a.mouseElapsed, b.mouseElapsed, accuracy: 0.00001, "t=\(boundary)")
        }
        let a = TheftChoreography.state(at: 3.5, size: size, origin: origin)
        let b = TheftChoreography.state(at: 3.54, size: size, origin: origin)
        XCTAssertEqual(b.mouseElapsed - a.mouseElapsed, 0.04, accuracy: 0.000001)
    }

    func testReducedMotionUsesStationaryCarryAndFade() {
        let a = TheftChoreography.state(at: 2, size: size, origin: origin, reducedMotion: true)
        let b = TheftChoreography.state(at: 4, size: size, origin: origin, reducedMotion: true)
        XCTAssertEqual(a.grapeCenter, b.grapeCenter)
        XCTAssertEqual(a.mouseOrigin, b.mouseOrigin)
        XCTAssertEqual(a.grapeOpacity, 1)
        XCTAssertEqual(a.mouseOpacity, 1)
        XCTAssertEqual(a.mouseElapsed, 0)
        XCTAssertEqual(a.grapeRotation, -25)
        let shoulder = CharacterAnimation.shoulderPoint(at: 0)
        XCTAssertEqual(a.grapeBackContact.x, a.mouseOrigin.x + shoulder.x, accuracy: 0.000001)
        XCTAssertEqual(a.grapeBackContact.y, a.mouseOrigin.y + shoulder.y, accuracy: 0.000001)
        XCTAssertEqual(a.ropeOpacity, 0)
        XCTAssertEqual(a.catchImpact, 0)
        let invisible = TheftChoreography.state(at: 5.1, size: size, origin: origin, reducedMotion: true)
        XCTAssertEqual(invisible.grapeOpacity, 0)
        XCTAssertEqual(invisible.mouseOpacity, 0)
    }

    func testSmallStageProducesFiniteGeometry() {
        for t in stride(from: -1.0, through: 6.0, by: 0.025) {
            let state = TheftChoreography.state(at: t, size: CoreSize(width: 0, height: 0),
                                               origin: CorePoint(x: -30, y: 500))
            XCTAssertTrue(state.grapeCenter.x.isFinite)
            XCTAssertTrue(state.grapeCenter.y.isFinite)
            XCTAssertTrue(state.mouseOrigin.x.isFinite)
            XCTAssertTrue((0...1).contains(state.grapeOpacity))
            XCTAssertTrue((0...1).contains(state.mouseOpacity))
        }
    }

    func testSharedVineLayoutMaintainsCategoryAnchors() {
        XCTAssertEqual(VineLayout.size, CoreSize(width: 520, height: 250))
        XCTAssertEqual(VineLayout.branchX(0), 464)
        XCTAssertEqual(VineLayout.branchX(8), 80)
        for index in 0..<9 {
            let x = VineLayout.branchX(index)
            for t in [0.0, 1.0, 1000.0] {
                let expected = 103 + sin(x / 79) * 9 + cos(x / 41) * 4 + sin(t * 1.05 + x * 0.012) * 1.4
                XCTAssertEqual(VineLayout.height(at: x, time: t), expected, accuracy: 0.000001)
            }
        }
    }

    func testSharedCharacterAssetsIncludeAllFrames() throws {
        XCTAssertNotNil(CharacterAssets.charactersDirectoryURL)
        let tom = try XCTUnwrap(CharacterAssets.url(for: "TomWatch.png"))
        XCTAssertEqual(Array(try Data(contentsOf: tom).prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        for index in 0..<CharacterAnimation.frameCount {
            let fileName = String(format: "frame_%04d.png", index)
            XCTAssertNotNil(CharacterAssets.url(for: fileName, subdirectory: "JerryRun"), fileName)
        }
        XCTAssertNotNil(CharacterAssets.url(for: "TomSource.md"))
        XCTAssertNil(CharacterAssets.url(for: "missing.png"))
    }

    func testSceneGeometryCanBeSerializedForOtherHosts() throws {
        let state = TheftChoreography.state(at: 3, size: size, origin: origin)
        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(TheftSceneState.self, from: data), state)
    }
}
