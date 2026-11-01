import AppKit

/// Grounded flower grouping at the screen edge, independent of their deadlines.
/// Single-flower placement is unchanged. Two or three plants share a compact
/// baseline and form a small asymmetrical garden rather than separate widgets.
/// Layout is pure and can be checked without creating an NSPanel.
enum DeadlineFlowerArrangement {
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
