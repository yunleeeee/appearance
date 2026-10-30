import Foundation

/// Original sprite timing and measured body anchors; image decoding remains in each host.
public enum CharacterAnimation {
    public static let mouseSize = CoreSize(width: 140.4, height: 117)
    public static let frameDuration: TimeInterval = 0.04
    public static let frameCount = 30
    public static let cycleDuration: TimeInterval = frameDuration * Double(frameCount)

    public static func frameIndex(at elapsed: TimeInterval) -> Int {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        // Division can place an exact 40 ms boundary one ULP below its frame.
        // Only promote that single-ULP neighbor after checking the original time;
        // a timestamp immediately before the boundary must stay in the old frame.
        let quotient = elapsed / frameDuration
        if quotient.isFinite {
            var frame = floor(quotient)
            let neighbor = floor(quotient.nextUp)
            if neighbor == frame + 1, elapsed >= neighbor * frameDuration {
                frame = neighbor
            }
            // Reduce before converting to Int so long-running sessions cannot overflow.
            return Int(frame.truncatingRemainder(dividingBy: Double(frameCount)))
        }
        let withinCycle = elapsed.truncatingRemainder(dividingBy: cycleDuration)
        return min(frameCount - 1, Int(floor(withinCycle / frameDuration)))
    }

    /// Hand positions transformed through the original fixed crop and mirror.
    public static func handPoint(at elapsed: TimeInterval, facingRight: Bool = true) -> CorePoint {
        let points = [
            CorePoint(x: 259, y: 245), CorePoint(x: 278, y: 235),
            CorePoint(x: 288, y: 277), CorePoint(x: 258, y: 247),
            CorePoint(x: 280, y: 209), CorePoint(x: 270, y: 222),
        ]
        let source = points[frameIndex(at: elapsed) % points.count]
        let x = source.x - 190
        return CorePoint(x: (facingRight ? 270 - x : x) * 0.52,
                         y: (source.y - 165) * 0.52)
    }

    /// Opaque shoulder/back pixels in the six original run poses. The bunch
    /// rests here, so it follows the actual back silhouette on every cel.
    public static func shoulderPoint(at elapsed: TimeInterval, facingRight: Bool = true) -> CorePoint {
        let rightFacingPoints = [
            CorePoint(x: 75.40, y: 61.36), CorePoint(x: 76.44, y: 56.16),
            CorePoint(x: 78.00, y: 63.44), CorePoint(x: 74.36, y: 62.40),
            CorePoint(x: 73.32, y: 55.64), CorePoint(x: 74.36, y: 58.76),
        ]
        let point = rightFacingPoints[frameIndex(at: elapsed) % rightFacingPoints.count]
        return CorePoint(x: facingRight ? point.x : mouseSize.width - point.x, y: point.y)
    }
}
