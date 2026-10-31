import AppKit
import ImageIO

/// Stage heads are cropped once from the frozen v2 atlas (unaltered original).
/// Coordinates are from the approved atlas manifest; nearest-neighbor drawing.
enum DeadlineFlowerMotion {
    struct Sprite {
        let image: NSImage
        let width: CGFloat
        let height: CGFloat
        let anchorX: CGFloat
        let anchorY: CGFloat
        let pixelsWide: Int
        let pixelsHigh: Int
        let alpha: [UInt8]

        func contains(_ point: NSPoint, in rect: NSRect) -> Bool {
            guard rect.contains(point), rect.width > 0, rect.height > 0 else { return false }
            let x = min(pixelsWide - 1, max(0, Int((point.x - rect.minX) / rect.width * CGFloat(pixelsWide))))
            let y = min(pixelsHigh - 1, max(0, Int((rect.maxY - point.y) / rect.height * CGFloat(pixelsHigh))))
            return alpha[y * pixelsWide + x] > 32
        }
    }

    // image top-left crop, logical dimensions, anchor point (v2 assets.json).
    private static let specs: [(Int, Int, Int, Int, CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (107, 220, 173, 249, 15.57, 22.41, 7.74, 10.17),
        (370, 191, 255, 293, 22.95, 26.37, 10.80, 12.51),
        (677, 154, 359, 357, 32.31, 32.13, 18.36, 15.66),
        (1060, 70, 457, 455, 41.13, 40.95, 21.78, 19.44),
        (35, 571, 374, 346, 33.66, 31.14, 15.84, 18.09),
        (435, 586, 389, 352, 35.01, 31.68, 13.95, 17.37)
    ]
    // Heart→calyx vectors, original sprite coordinates (top-to-bottom y).
    private static let calyxOffsets: [(CGFloat, CGFloat)] = [
        (2.52, 10.35), (0.90, 10.80), (-0.90, 13.77),
        (-3.60, 18.99), (3.15, -13.14), (3.51, -12.24)
    ]

    static let heads: [Sprite] = {
        let bundles = [Bundle.module, Bundle.main]
        guard let url = bundles.lazy.compactMap({
            $0.url(forResource: "FlowerAtlas", withExtension: "png", subdirectory: "Flowers")
        }).first, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        return specs.compactMap { item -> Sprite? in
            guard let img = atlas.cropping(to: CGRect(x: item.0, y: item.1,
                width: item.2, height: item.3)) else { return nil }
            var rgba = [UInt8](repeating: 0, count: img.width * img.height * 4)
            rgba.withUnsafeMutableBytes { bytes in
                if let bitmap = CGContext(data: bytes.baseAddress, width: img.width, height: img.height,
                    bitsPerComponent: 8, bytesPerRow: img.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    bitmap.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
                }
            }
            return Sprite(image: NSImage(cgImage: img, size: CGSize(width: item.4, height: item.5)),
                width: item.4, height: item.5, anchorX: item.6, anchorY: item.7,
                pixelsWide: img.width, pixelsHigh: img.height,
                alpha: stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] })
        }
    }()

    static func geometry(bounds: NSRect, artwork: CompactFlowerArtwork, stage: DeadlineStage,
                         stem: CGFloat, head: CGFloat) -> (root: NSPoint, calyx: NSPoint, rect: NSRect)? {
        guard heads.count == 6 else { return nil }
        let i = stage.rawValue
        let sprite = heads[i]
        let root = NSPoint(x: artwork.stemX, y: 3)
        // Root remains fixed. Upper stem responds before head; calyx remains attached.
        let y = bounds.height * ((stage == .drooping || stage == .withered) ? 0.66 : 0.82)
        let calyx = NSPoint(x: root.x + head * 2.4, y: y)
        let dx = calyxOffsets[i].0, dy = calyxOffsets[i].1
        let heart = NSPoint(x: calyx.x - dx, y: calyx.y + dy)
        let rect = NSRect(x: heart.x - sprite.anchorX,
                          y: heart.y - sprite.height + sprite.anchorY,
                          width: sprite.width, height: sprite.height)
        return (root, calyx, rect)
    }

    @discardableResult
    static func draw(bounds: NSRect, artwork: CompactFlowerArtwork, stage: DeadlineStage,
                     stem: CGFloat, head: CGFloat,
                     petals: (CGFloat, CGFloat, CGFloat)) -> Bool {
        guard let g = geometry(bounds: bounds, artwork: artwork, stage: stage,
                               stem: stem, head: head) else { return false }
        NSGraphicsContext.current?.imageInterpolation = .none
        let path = NSBezierPath()
        path.move(to: g.root)
        path.curve(to: g.calyx,
                   controlPoint1: NSPoint(x: g.root.x + stem * 0.4, y: bounds.height * 0.25),
                   controlPoint2: NSPoint(x: g.calyx.x + stem * 1.8, y: bounds.height * 0.63))
        path.lineWidth = 2
        NSColor(calibratedRed: 0.15, green: 0.30, blue: 0.22, alpha: 1).setStroke()
        path.stroke()

        let second = NSBezierPath()
        second.move(to: NSPoint(x: g.root.x - 0.5, y: g.root.y))
        second.curve(to: NSPoint(x: g.calyx.x - 0.5, y: g.calyx.y),
            controlPoint1: NSPoint(x: g.root.x + stem * 0.4 - 0.5, y: bounds.height * 0.25),
            controlPoint2: NSPoint(x: g.calyx.x + stem * 1.8 - 0.5, y: bounds.height * 0.63))
        second.lineWidth = 1
        NSColor(calibratedRed: 0.39, green: 0.56, blue: 0.37, alpha: 1).setStroke()
        second.stroke()

        let leaf = NSBezierPath()
        let joint = NSPoint(x: g.root.x + stem * 0.2, y: bounds.height * 0.33)
        leaf.move(to: joint)
        leaf.curve(to: NSPoint(x: joint.x + 7 + stem * 0.4, y: joint.y + 4),
                   controlPoint1: NSPoint(x: joint.x + 3, y: joint.y + 6),
                   controlPoint2: NSPoint(x: joint.x + 7, y: joint.y + 8))
        leaf.lineWidth = 3
        NSColor(calibratedRed: 0.26, green: 0.45, blue: 0.28, alpha: 1).setStroke()
        leaf.stroke()

        let sprite = heads[stage.rawValue]
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        if stage == .bloom {
            // Three overlapping petal sectors share one anchored core but follow
            // slightly different time delays (170/200/235 ms). No sprite stretch.
            let heart = CGPoint(x: g.rect.minX + sprite.anchorX,
                                y: g.rect.maxY - sprite.anchorY)
            let groups: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (210, 330, petals.0, -1), (-30, 90, petals.1, 1),
                (90, 210, petals.2, -1)
            ]
            for group in groups {
                let radians = max(-1.2, min(1.2,
                    (group.2 - head) * 2.6 * group.3)) * .pi / 180
                context.saveGState()
                context.translateBy(x: heart.x, y: heart.y)
                context.rotate(by: radians)
                context.translateBy(x: -heart.x, y: -heart.y)
                let path = CGMutablePath()
                path.move(to: heart)
                for step in 0...28 {
                    let degrees = group.0 - 10 + (group.1 - group.0 + 20) * CGFloat(step) / 28
                    let theta = degrees * .pi / 180
                    path.addLine(to: CGPoint(x: heart.x + cos(theta) * 36,
                                             y: heart.y + sin(theta) * 36))
                }
                path.closeSubpath()
                context.addPath(path)
                context.clip()
                sprite.image.draw(in: g.rect, from: .zero, operation: .sourceOver, fraction: 1)
                context.restoreGState()
            }
            // Retain the approved atlas core, concealing joints between petals.
            context.saveGState()
            context.clip(to: CGRect(x: heart.x - 5.5, y: heart.y - 5.5,
                                    width: 11, height: 11))
            sprite.image.draw(in: g.rect, from: .zero, operation: .sourceOver, fraction: 1)
            context.restoreGState()
        } else {
            sprite.image.draw(in: g.rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        return true
    }

    static func hit(_ point: NSPoint, bounds: NSRect, artwork: CompactFlowerArtwork,
                    stage: DeadlineStage, stem: CGFloat, head: CGFloat) -> Bool {
        guard let g = geometry(bounds: bounds, artwork: artwork, stage: stage,
                               stem: stem, head: head) else { return false }
        if heads[stage.rawValue].contains(point, in: g.rect) { return true }
        let t = min(1, max(0, (point.y - g.root.y) / max(1, g.calyx.y - g.root.y)))
        return point.y >= g.root.y && point.y <= g.calyx.y &&
            abs(point.x - (g.root.x * (1 - t) + g.calyx.x * t)) <= 2
    }
}
