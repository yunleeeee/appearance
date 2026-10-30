import Foundation

/// Shared layout math. Hosts convert these logical coordinates to their UI types.
public enum VineLayout {
    public static let size = CoreSize(width: 520, height: 250)

    public static func height(at x: Double, time: TimeInterval) -> Double {
        103 + sin(x / 79) * 9 + cos(x / 41) * 4
            + sin(time * 1.05 + x * 0.012) * 1.4
    }

    public static func branchX(_ index: Int) -> Double { 464 - Double(index) * 48 }
}
