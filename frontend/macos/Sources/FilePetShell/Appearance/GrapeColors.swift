/// Appearance sRGB components in the range 0...1.
public struct AppearanceRGBColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public func blended(with other: AppearanceRGBColor, fraction: Double) -> AppearanceRGBColor {
        let t = min(1, max(0, fraction))
        return AppearanceRGBColor(red: red * (1 - t) + other.red * t,
                        green: green * (1 - t) + other.green * t,
                        blue: blue * (1 - t) + other.blue * t)
    }
}

/// The current Mac appearance's category palette, independent of classification rules.
public enum GrapeColors {
    private static let colors: [AppearanceRGBColor] = [
        AppearanceRGBColor(red: 0.61, green: 0.20, blue: 0.65),
        AppearanceRGBColor(red: 0.96, green: 0.76, blue: 0.18),
        AppearanceRGBColor(red: 0.29, green: 0.39, blue: 0.76),
        AppearanceRGBColor(red: 0.83, green: 0.23, blue: 0.40),
        AppearanceRGBColor(red: 0.70, green: 0.80, blue: 0.30),
        AppearanceRGBColor(red: 0.96, green: 0.43, blue: 0.12),
        AppearanceRGBColor(red: 0.65, green: 0.59, blue: 0.73),
    ]

    // These are visual theme choices, not classification rules or a category list.
    private static let themeSlots: [String: Int] = [
        "recruitment": 6, "learning": 4, "research": 0, "finance": 1,
        "engineering": 2, "travel": 5, "daily": 4, "entertainment": 3,
    ]

    public static func base(for category: String) -> AppearanceRGBColor {
        if let slot = themeSlots[category] { return colors[slot] }
        // Keep old fixture colors for the standalone animation previews.
        switch category {
        case "文档": return colors[0]
        case "图片": return colors[1]
        case "代码": return colors[2]
        case "视频": return colors[3]
        case "音频": return colors[4]
        case "压缩包": return colors[5]
        case "其他", "文件夹", "应用安装包": return colors[6]
        default:
            // Swift's Hasher changes between processes; FNV-1a keeps an added
            // engine category's color stable across launches and label edits.
            let hash = category.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { value, byte in
                (value ^ UInt64(byte)) &* 1_099_511_628_211
            }
            return colors[Int(hash % UInt64(colors.count))]
        }
    }

    public static func shade(for category: String) -> AppearanceRGBColor {
        base(for: category).blended(with: AppearanceRGBColor(red: 0.22, green: 0.10, blue: 0.26), fraction: 0.42)
    }

    public static func highlight(for category: String) -> AppearanceRGBColor {
        base(for: category).blended(with: AppearanceRGBColor(red: 1, green: 0.97, blue: 0.74), fraction: 0.48)
    }

    public static func outline(for category: String) -> AppearanceRGBColor {
        base(for: category).blended(with: AppearanceRGBColor(red: 0.25, green: 0.16, blue: 0.17), fraction: 0.66)
    }
}
