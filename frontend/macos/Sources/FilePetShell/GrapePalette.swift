import AppKit
import SwiftUI

/// 设计稿中的七种果色，只负责分类反馈的外观。
enum GrapePalette {
    static func color(for category: String) -> Color {
        color(GrapeColors.base(for: category))
    }

    static func shade(for category: String) -> Color {
        color(GrapeColors.shade(for: category))
    }

    static func highlight(for category: String) -> Color {
        color(GrapeColors.highlight(for: category))
    }

    static func outline(for category: String) -> Color {
        color(GrapeColors.outline(for: category))
    }

    private static func color(_ rgb: AppearanceRGBColor) -> Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension Color {
    func blend(with other: Color, t: Double) -> Color {
        let fraction = min(max(t, 0), 1)
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let b = NSColor(other).usingColorSpace(.sRGB) ?? .white
        return Color(
            red: Double(a.redComponent) * (1 - fraction) + Double(b.redComponent) * fraction,
            green: Double(a.greenComponent) * (1 - fraction) + Double(b.greenComponent) * fraction,
            blue: Double(a.blueComponent) * (1 - fraction) + Double(b.blueComponent) * fraction
        )
    }
}
