import AppKit

/// Grounded flower grouping at the screen edge, independent of their deadlines.
/// Single-flower placement is unchanged. Two or three plants share a compact
/// baseline and form a small asymmetrical garden rather than separate widgets.
/// Layout is pure and can be checked without creating an NSPanel.
enum DeadlineFlowerArrangement {
    /// Static character of a plant, separate from the deadline stage or wind.
    /// Offsets are in native view points, intentionally smaller than the petals.
    /// All variants keep their roots on the same desktop baseline.
    struct PlantPose: Equatable {
        let tipShift: CGFloat
        let bow: CGFloat
        let heightShift: CGFloat
        let groundCover: CGFloat

        static let solo = PlantPose(tipShift: 0, bow: 0.65,
                                    heightShift: 0, groundCover: 0.45)
    }

    static func pose(index: Int, count: Int) -> PlantPose {
        switch (count, index) {
        case (1, _): return .solo  // user-approved single bloom stays nearly upright
        case (2, 0): return PlantPose(tipShift: -3.7, bow: -2.0,
                                      heightShift: -2.0, groundCover: 0.85)
        case (2, 1): return PlantPose(tipShift: 2.1, bow: -1.3,
                                      heightShift: 0, groundCover: 0.95)
        case (3, 0): return PlantPose(tipShift: -4.5, bow: -1.4,
                                      heightShift: -3.0, groundCover: 0.85)
        case (3, 1): return PlantPose(tipShift: 1.1, bow: -1.0,
                                      heightShift: 0, groundCover: 1.0)
        case (3, 2): return PlantPose(tipShift: 3.8, bow: 1.4,
                                      heightShift: -3.5, groundCover: 0.85)
        default: return .solo
        }
    }

    static func rootOffsets(count: Int) -> [CGFloat] {
        switch count {
        case 1: [-266]
        case 2: [-266, -199] // 67pt apart, instead of the old ~100pt
        case 3: [-297, -229, -161]
        default: []
        }
    }

    /// In a two-flower composition a fully-bloomed left crown was visually
    /// larger than the opening right crown. Reduce only the left blossom,
    /// preserving the planted stem, leaves, NSPanel size, and hit geometry.
    static func crownScale(index: Int, count: Int) -> CGFloat {
        count == 2 && index == 0 ? 0.68 : 1
    }

    static func frameOrigin(screen: NSRect, stemX: CGFloat,
                            index: Int, count: Int) -> NSPoint? {
        let offsets = rootOffsets(count: count)
        guard offsets.indices.contains(index) else { return nil }
        return NSPoint(x: screen.maxX + offsets[index] - stemX, y: screen.minY)
    }
}
