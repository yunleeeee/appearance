import Foundation

/// Coordinates use the visible screen's top-left origin. Jerry keeps the
/// original run cels; the fruit is supported by a measured point on his back.
public struct TheftSceneState: Codable, Equatable, Sendable {
    public var grapeCenter: CorePoint
    public var grapeRotation: Double = 0
    public var grapeScale = CoreSize(width: 1, height: 1)
    public var grapeOpacity: Double = 1
    public var mouseOrigin: CorePoint
    public var mouseElapsed: TimeInterval = 0
    public var mouseOpacity: Double = 0
    // Retained for existing host renderers. Carrying uses no rope.
    public var ropeOpacity: Double = 0
    public var ropeSag: Double = 0
    public var dust: Double = 0
    public var catchImpact: Double = 0
    public var floorY: Double

    public init(grapeCenter: CorePoint, mouseOrigin: CorePoint, floorY: Double) {
        self.grapeCenter = grapeCenter
        self.mouseOrigin = mouseOrigin
        self.floorY = floorY
    }

    public var grapeStem: CorePoint {
        let angle = grapeRotation * .pi / 180
        let length = 51 * grapeScale.height
        return CorePoint(x: grapeCenter.x + sin(angle) * length,
                         y: grapeCenter.y - cos(angle) * length)
    }

    /// The outer berry edge overlaps the shoulder, letting the bunch hang
    /// behind the body. Compression and sway remain fixed on this support.
    public var grapeBackContact: CorePoint {
        let offset = TheftChoreography.rotatedContact(scale: grapeScale, angle: grapeRotation)
        return CorePoint(x: grapeCenter.x + offset.x, y: grapeCenter.y + offset.y)
    }
}

public enum TheftChoreography {
    public static let duration: TimeInterval = 5.8
    private static let entryTime = 1.25
    private static let catchTime = 2.1
    private static let catchHoldEnd = 2.18
    private static let departureTime = 2.55
    private static let acceleration = 0.45
    private static let offscreenTime = 5.35
    private static let carryScale = 0.88
    private static let carryAngle = -25.0
    private static let catchSourceTime = catchTime - entryTime

    public static func state(at elapsed: TimeInterval, size: CoreSize, origin: CorePoint,
                             reducedMotion: Bool = false) -> TheftSceneState {
        let t = elapsed.isFinite ? max(0, elapsed) : 0
        let stageWidth = size.width.isFinite ? max(0, size.width) : 0
        let stageHeight = size.height.isFinite ? max(0, size.height) : 0
        let landingX = min(max(origin.x, 66), max(66, stageWidth - 230))
        let floorY = max(120, stageHeight - 12)
        let scale = CoreSize(width: carryScale, height: carryScale)
        let catchShoulder = CharacterAnimation.shoulderPoint(at: catchSourceTime)
        let contactOffset = rotatedContact(scale: scale, angle: carryAngle)
        let catchMouse = CorePoint(x: landingX + contactOffset.x - catchShoulder.x,
                                  y: floorY - 104)
        let landing = CorePoint(x: landingX,
                                y: catchMouse.y + catchShoulder.y - contactOffset.y)
        var result = TheftSceneState(grapeCenter: origin, mouseOrigin: catchMouse, floorY: floorY)

        if reducedMotion {
            if t < entryTime {
                result.grapeOpacity = 1 - ramp(t, 0.75, 1.2)
            } else {
                let visibility = ramp(t, 1.4, 1.65) * (1 - ramp(t, 4.5, 5.1))
                result.mouseOpacity = visibility
                result.grapeOpacity = visibility
                result.grapeScale = scale
                result.grapeRotation = carryAngle
                result.grapeCenter = carriedCenter(mouse: catchMouse, sourceTime: 0,
                                                   scale: scale, angle: carryAngle)
            }
            return result
        }

        // Arrive from outside the left edge and brake under the falling bunch.
        let approach = smooth(ramp(t, entryTime, catchTime))
        result.mouseOrigin.x = -CharacterAnimation.mouseSize.width - 24
            + (catchMouse.x + CharacterAnimation.mouseSize.width + 24) * approach
        result.mouseElapsed = sourceTime(at: t)
        result.mouseOpacity = ramp(t, entryTime, entryTime + 0.12)

        if t < 0.9 {
            let shake = sin(t * 29) * ramp(t, 0.1, 0.6) * (1 - ramp(t, 0.72, 0.9))
            result.grapeCenter.x += shake * 3.5
            result.grapeRotation = shake * 5
        } else if t < catchTime {
            let p = ramp(t, 0.9, catchTime)
            result.grapeCenter = mix(origin, landing, p * p)
            result.grapeCenter.x += sin(p * .pi * 2) * 7
            let settle = smooth(p)
            result.grapeRotation = carryAngle * settle + sin(p * .pi * 2) * 8 * (1 - p)
            let fallingScale = 1 + (carryScale - 1) * settle
            result.grapeScale = CoreSize(width: fallingScale, height: fallingScale)
        } else {
            // An 80 ms planted cel makes the hit readable. Then the original
            // cels resume at a slower rate while he recovers and starts running.
            let impactPhase = ramp(t, catchTime, 2.34)
            result.catchImpact = sin(impactPhase * .pi)
            result.mouseOrigin = catchMouse
            result.mouseOrigin.y += result.catchImpact * 2.8
            let travel = travelTime(t - departureTime)
            let speed = max(1, stageWidth + 160 - catchMouse.x)
                / travelTime(offscreenTime - departureTime)
            result.mouseOrigin.x += speed * travel

            let kick = sin(impactPhase * .pi * 2) * (1 - impactPhase) * 7
            let runSway = sin((t - departureTime) * 11) * 2.4
                * ramp(t, departureTime, 3.0)
            result.grapeRotation = carryAngle + kick + runSway
            result.grapeScale = CoreSize(width: carryScale * (1 + result.catchImpact * 0.10),
                                         height: carryScale * (1 - result.catchImpact * 0.12))
            result.grapeCenter = carriedCenter(mouse: result.mouseOrigin, sourceTime: result.mouseElapsed,
                                               scale: result.grapeScale, angle: result.grapeRotation)
            result.dust = ramp(t, departureTime, 2.88)
        }

        // Both the original sprite and the bunch leave the edge before fading.
        let visibility = 1 - ramp(t, 5.45, duration)
        result.mouseOpacity *= visibility
        result.grapeOpacity *= visibility
        result.dust *= visibility
        result.catchImpact *= visibility
        return result
    }

    public static func ramp(_ value: Double, _ start: Double, _ end: Double) -> Double {
        min(1, max(0, (value - start) / (end - start)))
    }

    fileprivate static func rotatedContact(scale: CoreSize, angle: Double) -> CorePoint {
        let radians = angle * .pi / 180
        let x = 22 * scale.width
        let y = 6 * scale.height
        return CorePoint(x: x * cos(radians) - y * sin(radians),
                         y: x * sin(radians) + y * cos(radians))
    }

    private static func carriedCenter(mouse: CorePoint, sourceTime: TimeInterval,
                                      scale: CoreSize, angle: Double) -> CorePoint {
        let shoulder = CharacterAnimation.shoulderPoint(at: sourceTime)
        let offset = rotatedContact(scale: scale, angle: angle)
        return CorePoint(x: mouse.x + shoulder.x - offset.x,
                         y: mouse.y + shoulder.y - offset.y)
    }

    private static func sourceTime(at t: TimeInterval) -> TimeInterval {
        if t < catchTime { return max(0, t - entryTime) }
        if t < catchHoldEnd { return catchSourceTime }
        let recovery = min(max(0, t - catchHoldEnd), departureTime - catchHoldEnd) * 0.35
        let departure = max(0, t - departureTime)
        let ramped = min(departure, acceleration)
        let accelerating = ramped * 0.35 + 0.65 * ramped * ramped / (2 * acceleration)
        return catchSourceTime + recovery + accelerating + max(0, departure - acceleration)
    }

    /// Integral of the departure speed, reaching full speed at three seconds.
    private static func travelTime(_ elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        if elapsed < acceleration { return elapsed * elapsed / (2 * acceleration) }
        return elapsed - acceleration / 2
    }

    private static func smooth(_ p: Double) -> Double { p * p * (3 - 2 * p) }

    private static func mix(_ a: CorePoint, _ b: CorePoint, _ fraction: Double) -> CorePoint {
        CorePoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }
}
