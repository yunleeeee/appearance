import AppKit

/// Grounded flower grouping at the screen edge, independent of their deadlines.
/// Single and grouped flowers share a screen-relative baseline. Two or three
/// plants form a compact asymmetrical garden rather than separate widgets.
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
        case (2, 0): return PlantPose(tipShift: -6.2, bow: 3.0,
                                      heightShift: -2.0, groundCover: 0.85)
        case (2, 1): return PlantPose(tipShift: 3.2, bow: -2.4,
                                      heightShift: 0, groundCover: 0.95)
        case (3, 0): return PlantPose(tipShift: -6.8, bow: 3.4,
                                      heightShift: -3.0, groundCover: 0.85)
        case (3, 1): return PlantPose(tipShift: 0.8, bow: -2.0,
                                      heightShift: 0, groundCover: 1.0)
        case (3, 2): return PlantPose(tipShift: 5.3, bow: -2.8,
                                      heightShift: -3.5, groundCover: 0.85)
        default: return .solo
        }
    }

    static func rootOffsets(count: Int) -> [CGFloat] {
        switch count {
        case 1: [-180]
        case 2: [-180, -123] // compact 57pt gap lets basal meadow shoots visually connect
        case 3: [-205, -149, -93] // 56pt gaps with gentle outward secondary poses
        default: []
        }
    }

    /// Keep a solo blossom in proportion to its stalk and leaves. The paired
    /// left crown retains its smaller scale beside the taller right plant.
    /// Scaling stays anchored at the calyx and is shared by drawing and hits.
    static func crownScale(index: Int, count: Int) -> CGFloat {
        if count == 1 { return 0.72 }
        return count == 2 && index == 0 ? 0.68 : 1
    }

    /// Give a solo plant a longer stalk without stretching its crown or moving
    /// its grounded root. Grouped plants retain their approved canvas sizes.
    static func canvasSize(for artworkSize: CGSize, count: Int) -> CGSize {
        CGSize(width: artworkSize.width,
               height: artworkSize.height + (count == 1 ? 18 : 0))
    }

    static func frameOrigin(screen: NSRect, stemX: CGFloat,
                            index: Int, count: Int) -> NSPoint? {
        let offsets = rootOffsets(count: count)
        guard offsets.indices.contains(index) else { return nil }
        return NSPoint(x: screen.maxX + offsets[index] - stemX, y: screen.minY)
    }
}
