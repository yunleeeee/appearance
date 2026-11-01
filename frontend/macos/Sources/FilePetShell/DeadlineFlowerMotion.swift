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

    private static let atlas: CGImage? = {
        let bundles = [Bundle.module, Bundle.main]
        guard let url = bundles.lazy.compactMap({
            $0.url(forResource: "FlowerAtlas", withExtension: "png", subdirectory: "Flowers")
        }).first, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    /// Use the original v2 leaf rather than replacing it with a bare green line.
    /// It is decoded and cropped once; every stage shares the same texture.
    static let leaf: Sprite? = {
        guard let atlas else { return nil }
        return makeSprite(atlas, x: 895, y: 654, width: 220, height: 248,
                          nativeWidth: 9.90, nativeHeight: 11.16,
                          anchorX: 0.90, anchorY: 10.305)
    }()

    static let heads: [Sprite] = {
        guard let atlas else { return [] }
        return specs.compactMap { item -> Sprite? in
            makeSprite(atlas, x: item.0, y: item.1, width: item.2, height: item.3,
                       nativeWidth: item.4, nativeHeight: item.5,
                       anchorX: item.6, anchorY: item.7)
        }
    }()

    private static func makeSprite(_ atlas: CGImage, x: Int, y: Int, width: Int, height: Int,
                                   nativeWidth: CGFloat, nativeHeight: CGFloat,
                                   anchorX: CGFloat, anchorY: CGFloat) -> Sprite? {
        guard let img = atlas.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else { return nil }
        var rgba = [UInt8](repeating: 0, count: img.width * img.height * 4)
        rgba.withUnsafeMutableBytes { bytes in
            if let bitmap = CGContext(data: bytes.baseAddress, width: img.width, height: img.height,
                bitsPerComponent: 8, bytesPerRow: img.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                bitmap.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            }
        }
        return Sprite(image: NSImage(cgImage: img,
            size: CGSize(width: nativeWidth, height: nativeHeight)),
            width: nativeWidth, height: nativeHeight,
            anchorX: anchorX, anchorY: anchorY,
            pixelsWide: img.width, pixelsHigh: img.height,
            alpha: stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] })
    }

    struct LeafJoint {
        let attach: NSPoint
        let side: CGFloat
        let size: CGSize
        let tip: NSPoint
    }

    /// Three original textured leaves grow from cubic-stem joints. Two turn
    /// left at different heights, and a right leaf balances the crown.
    /// Their anchors follow their own joints, never floating above the stem.
    static func leaves(bounds: NSRect, artwork: CompactFlowerArtwork, stage: DeadlineStage,
                       stem: CGFloat, head: CGFloat, leafLag: CGFloat = 0,
                       pose: DeadlineFlowerArrangement.PlantPose = .solo) -> [LeafJoint] {
        guard let g = geometry(bounds: bounds, artwork: artwork, stage: stage,
                               stem: stem, head: head, pose: pose),
              let sprite = leaf else { return [] }
        let controls = stemControls(g: g, stem: stem, pose: pose)
        let placements: [(CGFloat, CGFloat, CGFloat)] = [
            (0.59, -1, 2.20), // upper, broad left leaf
            (0.36, 1, 1.95),  // mid-stem right leaf
            (0.17, -1, 1.35)  // restrained basal shoot restores the old silhouette
        ]
        return placements.map { placement in
            let (fraction, side, scale) = placement
            let attach = cubic(controls.0, controls.1, controls.2, controls.3, fraction)
            let adjusted = NSPoint(x: attach.x + leafLag * side * 0.55, y: attach.y)
            let size = CGSize(width: sprite.width * scale, height: sprite.height * scale)
            return LeafJoint(attach: adjusted, side: side, size: size,
                             tip: NSPoint(x: adjusted.x + side * size.width * 0.75,
                                          y: adjusted.y + size.height * 0.55))
        }
    }

    private static func stemControls(g: (root: NSPoint, calyx: NSPoint, rect: NSRect),
                                     stem: CGFloat, pose: DeadlineFlowerArrangement.PlantPose)
                                     -> (NSPoint, NSPoint, NSPoint, NSPoint) {
        let rise = g.calyx.y - g.root.y
        return (g.root,
                NSPoint(x: g.root.x + pose.bow * 0.27 + stem * 0.4,
                        y: g.root.y + rise * 0.27),
                NSPoint(x: g.calyx.x + pose.bow + stem * 1.8,
                        y: g.root.y + rise * 0.75),
                g.calyx)
    }

    private static func cubic(_ a: NSPoint, _ b: NSPoint, _ c: NSPoint,
                              _ d: NSPoint, _ t: CGFloat) -> NSPoint {
        let u = 1 - t
        return NSPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x,
                       y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y)
    }

    private static func leafRect(_ leaf: LeafJoint, sprite: Sprite) -> CGRect {
        let factor = leaf.size.width / sprite.width
        let left = leaf.side > 0
            ? leaf.attach.x - sprite.anchorX * factor
            : leaf.attach.x - (sprite.width - sprite.anchorX) * factor
        return CGRect(x: left, y: leaf.attach.y - (sprite.height - sprite.anchorY) * factor,
                      width: leaf.size.width, height: leaf.size.height)
    }

    private static func drawLeaves(_ joints: [LeafJoint]) {
        guard let sprite = leaf, let context = NSGraphicsContext.current?.cgContext else { return }
        for joint in joints {
            // A restrained thin petiole connects the sprite to the actual stem.
            let petiole = NSBezierPath()
            petiole.move(to: joint.attach)
            petiole.line(to: NSPoint(x: joint.attach.x + joint.side * 3.5,
                                    y: joint.attach.y + 2.0))
            petiole.lineWidth = 1.15
            NSColor(calibratedRed: 0.20, green: 0.35, blue: 0.24, alpha: 1).setStroke()
            petiole.stroke()
            let rect = leafRect(joint, sprite: sprite)
            context.saveGState()
            if joint.side < 0 {
                // Keep source calyx/petiole pivot fixed while mirroring the
                // approved texture across the lower leaf's axis.
                context.translateBy(x: joint.attach.x, y: 0)
                context.scaleBy(x: -1, y: 1)
                context.translateBy(x: -joint.attach.x, y: 0)
                let flipped = CGRect(x: 2 * joint.attach.x - rect.maxX, y: rect.minY,
                                     width: rect.width, height: rect.height)
                sprite.image.draw(in: flipped, from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                sprite.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            }
            context.restoreGState()
        }
    }

    /// Small, static meadow accents rather than a second persistent widget.
    /// All stems and blades originate at the desktop baseline; these details
    /// intentionally do not intercept clicks or grow with file count.
    private static func drawGround(root: NSPoint, cover: CGFloat) {
        guard cover > 0 else { return }
        let green = NSColor(calibratedRed: 0.24, green: 0.42, blue: 0.27, alpha: 0.90)
        let highlight = NSColor(calibratedRed: 0.46, green: 0.59, blue: 0.32, alpha: 0.75)
        let extent = 14 + 13 * cover
        let blades: [(CGFloat, CGFloat, CGFloat)] = [
            (-0.95, -0.62, 8), (-0.72, -0.19, 12), (-0.51, -0.39, 7),
            (-0.25, 0.25, 11), (0.28, -0.16, 10), (0.56, 0.37, 8),
            (0.81, 0.64, 13)
        ]
        for (index, blade) in blades.enumerated() {
            let startX = root.x + blade.0 * extent
            let endX = startX + blade.1 * (5 + 4 * cover)
            let tipY = 3 + blade.2 * cover
            let path = NSBezierPath()
            path.move(to: NSPoint(x: startX, y: 1.5))
            path.curve(to: NSPoint(x: endX, y: tipY),
                       controlPoint1: NSPoint(x: startX, y: 5),
                       controlPoint2: NSPoint(x: endX - blade.1 * 2, y: tipY * 0.8))
            path.lineWidth = index.isMultiple(of: 3) ? 1.4 : 1.0
            (index.isMultiple(of: 3) ? highlight : green).setStroke()
            path.stroke()
        }
        // A few muted pixel-sized hints of soil; never a visible hard platform.
        NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.28, alpha: 0.55).setFill()
        let soilOffsets: [CGFloat] = [-16, -7, 9, 19]
        for x in soilOffsets {
            NSBezierPath(rect: NSRect(x: root.x + x * cover,
                                      y: 0.5, width: 2, height: 1)).fill()
        }
    }

    static func geometry(bounds: NSRect, artwork: CompactFlowerArtwork, stage: DeadlineStage,
                         stem: CGFloat, head: CGFloat, crownScale: CGFloat = 1,
                         pose: DeadlineFlowerArrangement.PlantPose = .solo)
                         -> (root: NSPoint, calyx: NSPoint, rect: NSRect)? {
        guard heads.count == 6 else { return nil }
        let i = stage.rawValue
        let sprite = heads[i]
        let root = NSPoint(x: artwork.stemX, y: 3)
        // Root remains fixed. Upper stem responds before head; calyx remains attached.
        // Keep every approved stage crown inside the compact NSPanel. The
        // calyx remains the stem/head joint even as petals expand or droop.
        let scale = max(0.5, min(1, crownScale))
        // Preserve the original calyx height when resizing a crown. Only the
        // petal image gets smaller; the stem joint cannot jump on 1↔2 changes.
        let requiredCrownRoom = calyxOffsets[i].1 + sprite.anchorY
        let y = max(28, min(bounds.height * 0.74 + pose.heightShift,
                            bounds.height - 8 - requiredCrownRoom))
        let calyx = NSPoint(x: root.x + pose.tipShift + head * 2.4, y: y)
        let dx = calyxOffsets[i].0, dy = calyxOffsets[i].1
        // Scale only the blossom around the stem's calyx joint: the root,
        // stalk, and original leaf sprites are never stretched or moved.
        let rect = NSRect(x: calyx.x - (dx + sprite.anchorX) * scale,
                          y: calyx.y + (dy - sprite.height + sprite.anchorY) * scale,
                          width: sprite.width * scale, height: sprite.height * scale)
        return (root, calyx, rect)
    }

    @discardableResult
    static func draw(bounds: NSRect, artwork: CompactFlowerArtwork, stage: DeadlineStage,
                     stem: CGFloat, head: CGFloat,
                     petals: (CGFloat, CGFloat, CGFloat), crownScale: CGFloat = 1,
                     pose: DeadlineFlowerArrangement.PlantPose = .solo) -> Bool {
        guard let g = geometry(bounds: bounds, artwork: artwork, stage: stage,
                               stem: stem, head: head, crownScale: crownScale,
                               pose: pose) else { return false }
        NSGraphicsContext.current?.imageInterpolation = .none
        drawGround(root: g.root, cover: pose.groundCover)
        let controls = stemControls(g: g, stem: stem, pose: pose)
        let path = NSBezierPath()
        path.move(to: controls.0)
        path.curve(to: controls.3, controlPoint1: controls.1,
                   controlPoint2: controls.2)
        path.lineWidth = 2
        NSColor(calibratedRed: 0.15, green: 0.30, blue: 0.22, alpha: 1).setStroke()
        path.stroke()

        let second = NSBezierPath()
        second.move(to: NSPoint(x: g.root.x - 0.5, y: g.root.y))
        second.curve(to: NSPoint(x: controls.3.x - 0.5, y: controls.3.y),
            controlPoint1: NSPoint(x: controls.1.x - 0.5, y: controls.1.y),
            controlPoint2: NSPoint(x: controls.2.x - 0.5, y: controls.2.y))
        second.lineWidth = 1
        NSColor(calibratedRed: 0.39, green: 0.56, blue: 0.37, alpha: 1).setStroke()
        second.stroke()

        // Reuse the original textured leaf artwork at two real stem joints.
        // Leaves are behind the head, and follow wind just after the stalk.
        drawLeaves(leaves(bounds: bounds, artwork: artwork, stage: stage, stem: stem,
                          head: head, leafLag: (petals.0 - stem), pose: pose))
        let sprite = heads[stage.rawValue]
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        if stage == .bloom {
            // Three overlapping petal sectors share one anchored core but follow
            // slightly different time delays (170/200/235 ms). No sprite stretch.
            let renderScale = g.rect.width / sprite.width
            let heart = CGPoint(x: g.rect.minX + sprite.anchorX * renderScale,
                                y: g.rect.maxY - sprite.anchorY * renderScale)
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
                    path.addLine(to: CGPoint(x: heart.x + cos(theta) * 36 * renderScale,
                                             y: heart.y + sin(theta) * 36 * renderScale))
                }
                path.closeSubpath()
                context.addPath(path)
                context.clip()
                sprite.image.draw(in: g.rect, from: .zero, operation: .sourceOver, fraction: 1)
                context.restoreGState()
            }
            // Retain the approved atlas core, concealing joints between petals.
            context.saveGState()
            context.clip(to: CGRect(x: heart.x - 5.5 * renderScale,
                                    y: heart.y - 5.5 * renderScale,
                                    width: 11 * renderScale, height: 11 * renderScale))
            sprite.image.draw(in: g.rect, from: .zero, operation: .sourceOver, fraction: 1)
            context.restoreGState()
        } else {
            sprite.image.draw(in: g.rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        return true
    }

    static func hit(_ point: NSPoint, bounds: NSRect, artwork: CompactFlowerArtwork,
                    stage: DeadlineStage, stem: CGFloat, head: CGFloat,
                    crownScale: CGFloat = 1,
                    pose: DeadlineFlowerArrangement.PlantPose = .solo) -> Bool {
        guard let g = geometry(bounds: bounds, artwork: artwork, stage: stage,
                               stem: stem, head: head, crownScale: crownScale,
                               pose: pose) else { return false }
        if heads[stage.rawValue].contains(point, in: g.rect) { return true }
        if let sprite = leaf {
            for joint in leaves(bounds: bounds, artwork: artwork, stage: stage,
                                stem: stem, head: head, pose: pose) {
                let rect = leafRect(joint, sprite: sprite)
                let pointInSprite = joint.side < 0
                    ? NSPoint(x: 2 * joint.attach.x - point.x, y: point.y) : point
                let positiveRect = joint.side < 0
                    ? CGRect(x: 2 * joint.attach.x - rect.maxX, y: rect.minY,
                             width: rect.width, height: rect.height) : rect
                if sprite.contains(pointInSprite, in: positiveRect) { return true }
            }
        }
        let c = stemControls(g: g, stem: stem, pose: pose)
        var last = c.0
        for i in 1...24 {
            let current = cubic(c.0, c.1, c.2, c.3, CGFloat(i) / 24)
            let dx = current.x - last.x, dy = current.y - last.y
            let lengthSquared = dx * dx + dy * dy
            let fraction = lengthSquared > 0
                ? max(0, min(1, ((point.x - last.x) * dx + (point.y - last.y) * dy) / lengthSquared))
                : CGFloat(0)
            if hypot(point.x - last.x - fraction * dx,
                     point.y - last.y - fraction * dy) <= 2 { return true }
            last = current
        }
        // Grass is decorative, intentionally click-through.
        return false
    }
}
