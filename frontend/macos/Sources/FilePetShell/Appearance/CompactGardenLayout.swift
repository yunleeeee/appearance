import Foundation

/// Coordinates of the confirmed compact artwork, independent of legacy vine
/// animation math. All local positions use the layer's top-left origin.
public enum CompactGardenLayout {
    public static let size = CoreSize(width: 400, height: 292)
    public static let rightInset = 15.0
    public static let bottomInset = 0.0
    public static let flowerRightInset = 13.0

    /// The source crop is (29, 38, 1401, 1022). These centers correspond to its
    /// three fruit windows, so one and two categories retain the original slots.
    private static let sourceCenters = [
        CorePoint(x: (203 + 153.0 / 2 - 29) * 400 / 1401,
                  y: (310 + 163.0 / 2 - 38) * 292 / 1022),
        CorePoint(x: (616 + 141.0 / 2 - 29) * 400 / 1401,
                  y: (328 + 166.0 / 2 - 38) * 292 / 1022),
        CorePoint(x: (1016 + 142.0 / 2 - 29) * 400 / 1401,
                  y: (310 + 161.0 / 2 - 38) * 292 / 1022),
    ]

    public static func branchAnchor(index: Int, total: Int, time: TimeInterval = 0) -> CorePoint {
        let count = max(1, total)
        let slot = min(max(0, index), count - 1)
        let center: CorePoint
        if count <= sourceCenters.count {
            center = sourceCenters[slot]
        } else {
            let spacing = 288.0 / Double(count - 1)
            center = CorePoint(x: 42 + Double(slot) * spacing,
                               y: slot.isMultiple(of: 2) ? 101 : 107)
        }
        // Keep source centers exact at t=0. A shared displacement lets the host's
        // release origin remain attached to the rendered bunch while it sways.
        let safeTime = time.isFinite ? time : 0
        let movement = sin(safeTime * 1.1 + Double(slot) * 0.8) - sin(Double(slot) * 0.8)
        return CorePoint(x: center.x + movement * 0.45, y: center.y)
    }

    /// GrapeClusterView's logical 64 x 88 bunch is rendered at the compact source
    /// size. Additional categories fit between the trellis posts without clipping.
    public static func branchScale(total: Int) -> Double {
        guard total > 8 else { return 0.60 }
        return min(0.60, 288.0 / Double(total - 1) / 70.0)
    }

    /// Apply the appearance scale without moving the initial release position or
    /// losing the original shoulder contact after the falling bunch is caught.
    public static func grapeCenter(for state: TheftSceneState, elapsed: TimeInterval,
                                   reducedMotion: Bool, visualScale: Double) -> CorePoint {
        let scale = visualScale.isFinite ? max(0, visualScale) : 0.60
        let time = elapsed.isFinite ? max(0, elapsed) : 0
        let blend: Double
        if reducedMotion {
            blend = time >= 1.25 ? 1 : 0
        } else {
            let progress = min(1, max(0, (time - 0.9) / 1.2))
            blend = progress * progress * (3 - 2 * progress)
        }
        let contact = state.grapeBackContact
        return CorePoint(x: state.grapeCenter.x + (contact.x - state.grapeCenter.x) * (1 - scale) * blend,
                         y: state.grapeCenter.y + (contact.y - state.grapeCenter.y) * (1 - scale) * blend)
    }
}
