import AppKit

/// A real double click on opaque flower pixels triggers the cinematic.
/// A single click, a drag, or the transparent gaps do not.
enum HarvestGesturePolicy {
    static func accepts(clickCount: Int, displacement: CGFloat,
                        onArtwork: Bool) -> Bool {
        clickCount >= 2 && displacement < 6 && onArtwork
    }
}

/// The entire plant, including the root, stem, leaves, meadow accents and
/// stage-specific blossom, is captured once. Every shard is clipped from this
/// one image. No live stem is redrawn after the decisive sword cut.
@MainActor
enum HarvestSlashEffect {
    static let duration: TimeInterval = 1.62
    static let reducedDuration: TimeInterval = 0.16
    static let shatterAt: TimeInterval = 0.72
    /// Inksteel: steel-blue sword reflections before the final strike,
    /// strictly achromatic charcoal and silver once the plant breaks.
    enum Palette {
        static let ink = NSColor(calibratedRed: 32.0 / 255, green: 38.0 / 255,
                                 blue: 46.0 / 255, alpha: 1)        // #20262E
        static let steel = NSColor(calibratedRed: 89.0 / 255, green: 107.0 / 255,
                                   blue: 122.0 / 255, alpha: 1)     // #596B7A
        static let silver = NSColor(calibratedRed: 174.0 / 255, green: 187.0 / 255,
                                    blue: 197.0 / 255, alpha: 1)    // #AEBBC5
        static let pearl = NSColor(calibratedRed: 245.0 / 255, green: 247.0 / 255,
                                   blue: 248.0 / 255, alpha: 1)     // #F5F7F8
        static let charcoal = NSColor(calibratedWhite: 0.12, alpha: 1)
        static let ash = NSColor(calibratedWhite: 0.47, alpha: 1)
        static let white = NSColor(calibratedWhite: 0.98, alpha: 1)
    }

    static let floorY: CGFloat = 2
    static let finisherAt: TimeInterval = 0.61

    struct Sample: Equatable {
        let showHead: Bool
        let stemOpacity: CGFloat
        let shardOpacity: CGFloat
        let finished: Bool
    }

    struct Fragment {
        let points: [CGPoint]
        let center: CGPoint
        let speedX: CGFloat
        let launch: CGFloat
        let rotation: CGFloat
        let delay: CGFloat
    }

    struct PlantSnapshot {
        let image: NSImage
        let monochromeImage: NSImage
        /// Stored only for deterministic grayscale pixel tests.
        let monochromeRGBA: [UInt8]
        /// This is the whole plant's rectangle, not the bloom geometry.
        let cutRect: CGRect
        let fragments: [Fragment]
        let pixelWidth: Int
        let pixelHeight: Int
        let alpha: [UInt8]
    }

    static func sample(at seconds: TimeInterval, reduceMotion: Bool) -> Sample {
        let t = max(0, seconds)
        if reduceMotion {
            return Sample(showHead: t < 0.08,
                          stemOpacity: max(0, 1 - CGFloat(t / reducedDuration)),
                          shardOpacity: 0, finished: t >= reducedDuration)
        }
        let broken = t >= shatterAt
        return Sample(showHead: !broken, stemOpacity: broken ? 0 : 1,
                      shardOpacity: broken ? max(0, min(1, CGFloat((duration - t) / 0.48))) : 0,
                      finished: t >= duration)
    }

    /// Color drains out *because* the execution sword lands. Before this beat
    /// the plant is recognizably colored; by the fracture all its pixels and
    /// every separated fragment are fully neutral black/white.
    static func monochromeProgress(at seconds: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return max(0, min(1, CGFloat((seconds - finisherAt) / 0.10)))
    }

    /// The cut area is explicitly rectangular and spans the complete native
    /// plant canvas, down to its rooted ground baseline. No foliage is excluded.
    static func cuttingRect(in bounds: CGRect) -> CGRect { bounds }

    /// VFX frame is wider than the slender plant: deliberate cinematic space,
    /// with the root still aligned to the original grounded stem.
    static func combatRect(in bounds: CGRect, rootX: CGFloat) -> CGRect {
        CGRect(x: rootX - max(77, bounds.width * 0.75), y: 1.5,
               width: max(154, bounds.width * 1.5),
               height: bounds.height - 3)
    }

    /// Nine real diagonals and near-vertical cuts traverse *different heights*
    /// of the rectangle, including the basal stem and ground decoration.
    static func slashSegments(in rect: CGRect) -> [(CGPoint, CGPoint)] {
        let ends: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-0.10, 0.90, 1.10, 0.56), (1.10, 0.82, -0.10, 0.40),
            (-0.08, 0.66, 1.08, 0.06), (1.10, 0.33, -0.10, 0.03),
            (0.10, -0.09, 0.83, 1.08), (0.90, 1.07, 0.04, -0.08),
            (-0.06, 0.98, 1.08, 0.18)
        ]
        return ends.map { item in
            (CGPoint(x: rect.minX + rect.width * item.0,
                     y: rect.minY + rect.height * item.1),
             CGPoint(x: rect.minX + rect.width * item.2,
                     y: rect.minY + rect.height * item.3))
        }
    }

    /// Keeps each shard's center above the desktop baseline. Individual
    /// vertices are also clamped below, after applying each shard's rotation.
    static func verticalOffset(time: CGFloat, launch: CGFloat, centerY: CGFloat) -> CGFloat {
        let t = max(0, time)
        let gravity: CGFloat = 370
        let floorOffset = floorY - centerY
        let ballistic = launch * t - gravity * t * t
        if ballistic >= floorOffset { return ballistic }
        let impact = (launch + sqrt(launch * launch
            + 4 * gravity * max(0, centerY - floorY))) / (2 * gravity)
        let afterImpact = max(0, t - impact)
        let rebound = max(0, (33 + launch * 0.12) * afterImpact
            - 260 * afterImpact * afterImpact)
        return floorOffset + rebound
    }

    /// Capture through the *actual* native six-stage plant renderer so that
    /// the stalk, all three leaves, the root and its soil pixels are included.
    /// Only created once per harvest in HarvestEffectOverlayView.
    static func makeSnapshot(in bounds: CGRect, stage: DeadlineStage,
                             artwork: CompactFlowerArtwork, crownScale: CGFloat,
                             pose: DeadlineFlowerArrangement.PlantPose) -> PlantSnapshot? {
        let width = max(1, Int(ceil(bounds.width * 2)))
        let height = max(1, Int(ceil(bounds.height * 2)))
        let rowBytes = width * 4
        var rgba = [UInt8](repeating: 0, count: rowBytes * height)
        var cgImage: CGImage?
        rgba.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return }
            context.scaleBy(x: CGFloat(width) / bounds.width,
                            y: CGFloat(height) / bounds.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            _ = DeadlineFlowerMotion.draw(
                bounds: CGRect(origin: .zero, size: bounds.size),
                artwork: artwork, stage: stage, stem: 0, head: 0,
                petals: (0, 0, 0), crownScale: crownScale, pose: pose)
            NSGraphicsContext.current?.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            cgImage = context.makeImage()
        }
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: bounds.size)
        let monochromeRGBA = makeMonochromeRGBA(rgba)
        guard let provider = CGDataProvider(data: Data(monochromeRGBA) as CFData),
              let monochromeCG = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        let monochrome = NSImage(cgImage: monochromeCG, size: bounds.size)
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        let rect = cuttingRect(in: CGRect(origin: .zero, size: bounds.size))
        let fragments = makeFragments(rect: rect, width: width, height: height, alpha: alpha)
        return PlantSnapshot(image: image, monochromeImage: monochrome,
                             monochromeRGBA: monochromeRGBA,
                             cutRect: rect, fragments: fragments,
                             pixelWidth: width, pixelHeight: height, alpha: alpha)
    }

    /// Contrast-preserving grayscale on RGBA premultiplied pixels. Alpha is
    /// copied exactly: the original pixel-sharp foliage and edge masks survive.
    static func makeMonochromeRGBA(_ rgba: [UInt8]) -> [UInt8] {
        var output = rgba
        guard rgba.count.isMultiple(of: 4) else { return output }
        for i in stride(from: 0, to: rgba.count, by: 4) {
            let a = Int(rgba[i + 3])
            guard a > 0 else {
                output[i] = 0
                output[i + 1] = 0
                output[i + 2] = 0
                continue
            }
            // Convert to straight RGB before boosting luminance, then
            // premultiply again; avoids dark fringes around thin leaves.
            let r = min(255, Int(rgba[i]) * 255 / a)
            let g = min(255, Int(rgba[i + 1]) * 255 / a)
            let b = min(255, Int(rgba[i + 2]) * 255 / a)
            let luminance = Double(r) * 0.2126 + Double(g) * 0.7152
                + Double(b) * 0.0722
            let gray = max(0, min(255, Int((luminance - 118) * 1.18 + 118)))
            let premultiplied = UInt8((gray * a + 127) / 255)
            output[i] = premultiplied
            output[i + 1] = premultiplied
            output[i + 2] = premultiplied
        }
        return output
    }

    /// Screen-independent 10x17 triangular segmentation. Transparent tiles are
    /// removed by testing actual raster pixels, including narrow root/stem lines.
    private static func makeFragments(rect: CGRect, width: Int, height: Int,
                                      alpha: [UInt8]) -> [Fragment] {
        let columns = 10, rows = 17
        var result: [Fragment] = []
        for row in 0..<rows {
            for col in 0..<columns {
                // Coherent vertex jitter breaks the uniform rectangular tile grid
                // without leaving gaps between adjacent pieces.
                func vertex(_ x: Int, _ y: Int) -> CGPoint {
                    let edgeX = x == 0 || x == columns
                    let edgeY = y == 0 || y == rows
                    let jx = edgeX ? 0 : CGFloat((x * 17 + y * 31) % 9 - 4) * 0.45
                    let jy = edgeY ? 0 : CGFloat((x * 23 + y * 13) % 9 - 4) * 0.40
                    return CGPoint(x: rect.minX + rect.width * CGFloat(x) / CGFloat(columns) + jx,
                                   y: rect.minY + rect.height * CGFloat(y) / CGFloat(rows) + jy)
                }
                let a = vertex(col, row), b = vertex(col + 1, row)
                let c = vertex(col + 1, row + 1), d = vertex(col, row + 1)
                let triangles = (row + col).isMultiple(of: 2)
                    ? [[a, b, c], [a, c, d]] : [[a, b, d], [b, c, d]]
                for (half, triangle) in triangles.enumerated() {
                    guard containsPaint(triangle, rect: rect,
                                        pixelWidth: width, pixelHeight: height,
                                        alpha: alpha) else { continue }
                    let i = (row * columns + col) * 2 + half
                    let center = CGPoint(
                        x: triangle.map(\.x).reduce(0, +) / 3,
                        y: triangle.map(\.y).reduce(0, +) / 3)
                    // Every shard has an independent direction and lift; alternating
                    // columns had looked like two synchronized falling strips.
                    let side: CGFloat = (i * 37 % 11) < 5 ? -1 : 1
                    let offset = CGFloat((i * 43) % 61 - 30)
                    let spread = CGFloat(20 + (i * 19) % 73)
                    let stem = row < rows * 2 / 3
                    result.append(Fragment(points: triangle, center: center,
                        speedX: side * (spread + 64) + offset * 0.95,
                        launch: CGFloat((stem ? 25 : 58) + (i * 29) % 87),
                        rotation: side * CGFloat(1.7 + Double(i % 9) * 0.37),
                        delay: CGFloat(i % 7) * 0.006))
                }
            }
        }
        return result
    }

    private static func containsPaint(_ triangle: [CGPoint], rect: CGRect,
                                      pixelWidth: Int, pixelHeight: Int,
                                      alpha: [UInt8]) -> Bool {
        let minX = max(0, Int(floor((triangle.map(\.x).min()! - rect.minX) / rect.width
                                      * CGFloat(pixelWidth))))
        let maxX = min(pixelWidth - 1, Int(ceil((triangle.map(\.x).max()! - rect.minX)
                                      / rect.width * CGFloat(pixelWidth))))
        let minY = max(0, Int(floor((rect.maxY - triangle.map(\.y).max()!)
                                      / rect.height * CGFloat(pixelHeight))))
        let maxY = min(pixelHeight - 1, Int(ceil((rect.maxY - triangle.map(\.y).min()!)
                                      / rect.height * CGFloat(pixelHeight))))
        guard maxX >= minX && maxY >= minY else { return false }
        for y in minY...maxY {
            for x in minX...maxX {
                guard alpha[y * pixelWidth + x] > 20 else { continue }
                let p = CGPoint(x: rect.minX + (CGFloat(x) + 0.5) / CGFloat(pixelWidth) * rect.width,
                                y: rect.maxY - (CGFloat(y) + 0.5) / CGFloat(pixelHeight) * rect.height)
                let edges = [0, 1, 2].map { i -> CGFloat in
                    let a = triangle[i], b = triangle[(i + 1) % 3]
                    return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
                }
                if !edges.contains(where: { $0 < -0.001 }) ||
                   !edges.contains(where: { $0 > 0.001 }) { return true }
            }
        }
        return false
    }

    static func draw(in bounds: NSRect, stage: DeadlineStage,
                     artwork: CompactFlowerArtwork, crownScale: CGFloat,
                     pose: DeadlineFlowerArrangement.PlantPose,
                     age: TimeInterval, reduceMotion: Bool,
                     snapshot cached: PlantSnapshot? = nil) {
        let state = sample(at: age, reduceMotion: reduceMotion)
        guard !state.finished else { return }
        let snapshot = cached ?? makeSnapshot(in: bounds, stage: stage,
            artwork: artwork, crownScale: crownScale, pose: pose)
        guard let snapshot, let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        let rect = snapshot.cutRect
        let battlefield = combatRect(in: rect, rootX: artwork.stemX)

        if reduceMotion {
            snapshot.image.draw(in: rect, from: .zero, operation: .sourceOver,
                                fraction: state.stemOpacity)
            return
        }

        if age < shatterAt {
            // A deliberate 70ms hit-stop after the flurry makes the final
            // diagonal feel decisive rather than another equal-speed bar.
            let jitter: CGFloat = age > 0.12 && age < 0.52
                ? sin(CGFloat(age) * 165) * 0.48 : 0
            let imageRect = rect.offsetBy(dx: jitter, dy: 0)
            let monochrome = monochromeProgress(at: age, reduceMotion: false)
            snapshot.image.draw(in: imageRect, from: .zero,
                                operation: .sourceOver, fraction: 1)
            if monochrome > 0 {
                snapshot.monochromeImage.draw(in: imageRect, from: .zero,
                    operation: .sourceOver, fraction: monochrome)
            }
            drawRegionGuide(in: battlefield, age: age)
            drawCutScars(in: battlefield, age: age)
        } else {
            drawFragments(snapshot, age: age, opacity: state.shardOpacity, context: ctx)
            drawGroundSparks(centerX: artwork.stemX, age: age)
            drawImpactFlash(at: CGPoint(x: artwork.stemX, y: battlefield.midY), age: age)
            drawBurstDust(in: battlefield, age: age)
        }
        drawSwordStreaks(in: battlefield, age: age)
        drawFinalSlash(in: battlefield, age: age)
    }

    private static func drawFragments(_ snapshot: PlantSnapshot, age: TimeInterval,
                                      opacity: CGFloat, context: CGContext) {
        guard opacity > 0 else { return }
        let time = CGFloat(max(0, age - shatterAt))
        for shard in snapshot.fragments {
            let t = max(0, time - shard.delay)
            let theta = shard.rotation * t
            let cosine = cos(theta), sine = sin(theta)
            // Strong initial lateral blast, then air resistance.
            let dx = shard.speedX * t * max(0.55, 1 - t * 0.32)
                + 12 * sin(t * 5 + shard.center.y * 0.27) * t
            var dy = verticalOffset(time: t, launch: shard.launch, centerY: shard.center.y)
            let bottom = shard.points.map { point -> CGFloat in
                let ox = point.x - shard.center.x, oy = point.y - shard.center.y
                return shard.center.y + dy + ox * sine + oy * cosine
            }.min() ?? floorY
            // Clip correction after spin: rotated corners never tunnel through
            // the ground, even for the thin bottommost root/soil slices.
            dy += max(0, floorY - bottom)

            context.saveGState()
            context.setAlpha(opacity)
            context.translateBy(x: shard.center.x + dx, y: shard.center.y + dy)
            context.rotate(by: theta)
            context.translateBy(x: -shard.center.x, y: -shard.center.y)
            let cut = CGMutablePath()
            for (index, point) in shard.points.enumerated() {
                if index == 0 { cut.move(to: point) } else { cut.addLine(to: point) }
            }
            cut.closeSubpath()
            context.addPath(cut)
            context.clip()
            snapshot.monochromeImage.draw(in: snapshot.cutRect, from: .zero,
                                          operation: .sourceOver, fraction: 1)
            context.restoreGState()
        }
    }

    private static let slashTimes: [TimeInterval] =
        [0.018, 0.082, 0.143, 0.204, 0.272, 0.335, 0.392]

    /// A faint rectangular target field makes the user-perceived cut area
    /// cover the stalk and root rather than the blossom only.
    private static func drawRegionGuide(in rect: CGRect, age: TimeInterval) {
        let alpha = CGFloat(min(1, age / 0.045)
                            * max(0, 1 - age / 0.24)) * 0.30
        guard alpha > 0 else { return }
        let frame = rect.insetBy(dx: 1.5, dy: 2.5)
        Palette.ink.withAlphaComponent(alpha * 0.35).setStroke()
        // Removed the continuous outline: it read as an editable selection
        // box. Short corner locks are enough to sell the target area.

        // Four brighter L-shaped corner markers trace the entire region.
        Palette.silver.withAlphaComponent(alpha * 0.82).setStroke()
        for xSide in [CGFloat(0), CGFloat(1)] {
            for ySide in [CGFloat(0), CGFloat(1)] {
                let x = xSide == 0 ? frame.minX : frame.maxX
                let y = ySide == 0 ? frame.minY : frame.maxY
                let hx: CGFloat = xSide == 0 ? 1 : -1
                let hy: CGFloat = ySide == 0 ? 1 : -1
                let corner = NSBezierPath()
                corner.move(to: CGPoint(x: x + 10 * hx, y: y))
                corner.line(to: CGPoint(x: x, y: y))
                corner.line(to: CGPoint(x: x, y: y + 12 * hy))
                corner.lineWidth = 1.5
                corner.stroke()
            }
        }
    }

    /// Curved-looking afterimage made of a tapered razor quadrilateral.
    /// Never use round-capped thick NSBezierPath strokes: in real recordings
    /// they read as glowing plastic sticks rather than fast sword cuts.
    private static func blade(from tail: CGPoint, to tip: CGPoint,
                              width: CGFloat, color: NSColor) {
        let dx = tip.x - tail.x, dy = tip.y - tail.y
        let len = max(0.01, hypot(dx, dy))
        let nx = -dy / len, ny = dx / len
        func at(_ f: CGFloat, side: CGFloat) -> CGPoint {
            CGPoint(x: tail.x + dx * f + nx * width * side,
                    y: tail.y + dy * f + ny * width * side)
        }
        // Six-point spearhead: needle tips at both ends, with asymmetric
        // luminous mass; no more round-ended neon sticks.
        let path = NSBezierPath()
        path.move(to: at(0, side: 0))
        path.line(to: at(0.27, side: 0.37))
        path.line(to: at(0.64, side: 0.22))
        path.line(to: at(1, side: 0))
        path.line(to: at(0.70, side: -0.19))
        path.line(to: at(0.26, side: -0.33))
        path.close()
        color.setFill()
        path.fill()
    }

    private static func drawSwordStreaks(in rect: CGRect, age: TimeInterval) {
        let lines = slashSegments(in: rect)
        for (index, start) in slashTimes.enumerated() {
            let t = age - start
            guard t >= 0 && t < 0.145 else { continue }
            let p = CGFloat(min(1, t / 0.062))
            let fade = CGFloat(min(1, t / 0.012) * max(0, 1 - t / 0.145))
            let a = lines[index].0, b = lines[index].1
            let tip = CGPoint(x: a.x + (b.x - a.x) * p,
                              y: a.y + (b.y - a.y) * p)
            let len = hypot(b.x - a.x, b.y - a.y)
            let ux = (b.x - a.x) / max(1, len)
            let uy = (b.y - a.y) / max(1, len)
            let trail = min(125, len * 0.63)
            let tail = CGPoint(x: tip.x - ux * trail, y: tip.y - uy * trail)
            // A dark edge is necessary for a white macOS desktop; the core
            // stays narrow with no opaque rounded end caps.
            let tint = index.isMultiple(of: 3)
                ? Palette.steel.withAlphaComponent(fade * 0.81)
                : Palette.ink.withAlphaComponent(fade * 0.88)
            blade(from: tail, to: tip, width: 18, color: tint)
            blade(from: tail, to: tip, width: 5,
                  color: Palette.steel.withAlphaComponent(fade * 0.94))
            blade(from: tail, to: tip, width: 1.1,
                  color: Palette.pearl.withAlphaComponent(fade * 0.98))
            // Needle-thin echo follows, separated in space and time.
            let normal = CGPoint(x: -uy * 4, y: ux * 4)
            let echo = NSBezierPath()
            echo.move(to: CGPoint(x: tail.x + normal.x, y: tail.y + normal.y))
            echo.line(to: CGPoint(x: tip.x + normal.x, y: tip.y + normal.y))
            echo.lineWidth = 0.7
            Palette.silver.withAlphaComponent(fade * 0.58).setStroke()
            echo.stroke()
        }
    }

    /// 70ms still frame, then one full-height white-hot execution slash.
    /// The decisive diagonal is bigger and lasts longer than the preceding cuts.
    private static func drawFinalSlash(in rect: CGRect, age: TimeInterval) {
        let t = age - finisherAt
        guard t >= 0 && t < 0.24 else { return }
        let a = CGPoint(x: rect.minX - 24, y: rect.maxY + 23)
        let b = CGPoint(x: rect.maxX + 23, y: rect.minY - 12)
        let progress = CGFloat(min(1, t / 0.075))
        let tip = CGPoint(x: a.x + (b.x - a.x) * progress,
                          y: a.y + (b.y - a.y) * progress)
        let len = hypot(b.x - a.x, b.y - a.y)
        let ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
        let tail = CGPoint(x: tip.x - ux * len * 0.70,
                           y: tip.y - uy * len * 0.70)
        let fade = CGFloat(max(0, 1 - t / 0.24))
        blade(from: tail, to: tip, width: 33,
              color: Palette.ink.withAlphaComponent(fade * 0.88))
        blade(from: tail, to: tip, width: 12,
              color: Palette.steel.withAlphaComponent(fade * 0.97))
        blade(from: tail, to: tip, width: 2.3,
              color: Palette.pearl.withAlphaComponent(fade))
        // Delayed pale-purple echo of the execution blade, offset from
        // its centerline to read as a fast blade rather than one fat ribbon.
        let side = CGPoint(x: -uy * 5.8, y: ux * 5.8)
        let echo = NSBezierPath()
        echo.move(to: CGPoint(x: tail.x + side.x, y: tail.y + side.y))
        echo.line(to: CGPoint(x: tip.x + side.x, y: tip.y + side.y))
        echo.lineWidth = 1.2
        Palette.silver.withAlphaComponent(fade * 0.70).setStroke()
        echo.stroke()
        // The brightest moment is only a brief central crossing, not a
        // fullscreen flash or a solid rectangular overlay.
        if t > 0.06 && t < 0.115 {
            let impact = CGFloat(sin((t - 0.06) / 0.055 * .pi))
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: rect.minX - 10, y: rect.midY))
            cross.line(to: CGPoint(x: rect.maxX + 10, y: rect.midY))
            cross.lineWidth = 1.5
            Palette.pearl.withAlphaComponent(impact * 0.95).setStroke()
            cross.stroke()
        }
    }

    private static func drawCutScars(in rect: CGRect, age: TimeInterval) {
        let lines = slashSegments(in: rect)
        for (index, start) in slashTimes.enumerated() {
            let elapsed = age - start
            guard elapsed > 0.10 && elapsed < 0.43 else { continue }
            let alpha = CGFloat((0.43 - elapsed) / 0.33) * 0.52
            let path = NSBezierPath()
            path.move(to: lines[index].0)
            path.line(to: lines[index].1)
            path.lineWidth = 1.3
            Palette.steel.withAlphaComponent(alpha * 0.82).setStroke()
            path.stroke()
        }
    }

    private static func drawImpactFlash(at center: CGPoint, age: TimeInterval) {
        let t = age - shatterAt
        guard t >= 0 && t < 0.23 else { return }
        let alpha = CGFloat(1 - t / 0.23)
        let radius = CGFloat(13 + t * 165)
        for i in 0..<16 {
            let angle = CGFloat(i) * .pi / 8
            let start = CGPoint(x: center.x + cos(angle) * radius * 0.21,
                                y: center.y + sin(angle) * radius * 0.21)
            let end = CGPoint(x: center.x + cos(angle) * radius,
                              y: center.y + sin(angle) * radius)
            let beam = NSBezierPath()
            beam.move(to: start)
            beam.line(to: end)
            beam.lineWidth = i.isMultiple(of: 4) ? 3 : 1.4
            (i.isMultiple(of: 8) ? Palette.ash : Palette.steel)
                .withAlphaComponent(alpha * (i.isMultiple(of: 8) ? 0.72 : 0.63)).setStroke()
            beam.stroke()
        }
        Palette.silver.withAlphaComponent(alpha * 0.44).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - radius * 0.3,
                                   y: center.y - radius * 0.3,
                                   width: radius * 0.6, height: radius * 0.6)).fill()
    }

    private static func drawGroundSparks(centerX: CGFloat, age: TimeInterval) {
        let time = age - shatterAt - 0.38
        guard time > 0 && time < 0.63 else { return }
        let fade = CGFloat(1 - time / 0.63)
        let spread = CGFloat(16 + time * 180)
        let ring = NSBezierPath(ovalIn: CGRect(x: centerX - spread / 2,
            y: floorY, width: spread, height: 5 + CGFloat(time * 3)))
        ring.lineWidth = 1.8
        Palette.steel.withAlphaComponent(fade * 0.52).setStroke()
        ring.stroke()
        for i in 0..<23 {
            let sign: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            let x = centerX + sign * CGFloat(time) * CGFloat(40 + i * 6)
            let y = floorY + abs(sin(CGFloat(i) * 2.15))
                * CGFloat(5 + (1 - time / 0.63) * 20)
            (i.isMultiple(of: 9) ? Palette.ash : Palette.silver)
                .withAlphaComponent(fade * 0.78).setFill()
            let size: CGFloat = i.isMultiple(of: 5) ? 3.3 : 1.6
            NSBezierPath(ovalIn: CGRect(x: x, y: y, width: size, height: size)).fill()
        }
    }
    /// Small high-velocity diamond sparks accompany the first fracture.
    private static func drawBurstDust(in rect: CGRect, age: TimeInterval) {
        let t = age - shatterAt
        guard t >= 0 && t < 0.39 else { return }
        let fade = CGFloat(max(0, 1 - t / 0.39))
        for i in 0..<42 {
            let angle = CGFloat(i) * 2.399963
            let radius = CGFloat(9 + (i * 17) % 27)
                + CGFloat(t) * CGFloat(98 + (i * 13) % 190)
            let x = rect.midX + cos(angle) * radius * 0.72
            let y = rect.midY + sin(angle) * radius * 0.86
            let size: CGFloat = i.isMultiple(of: 5) ? 2.9 : 1.5
            let spark = NSBezierPath()
            spark.move(to: CGPoint(x: x, y: y + size * 0.5))
            spark.line(to: CGPoint(x: x + size * 1.2, y: y))
            spark.line(to: CGPoint(x: x, y: y - size * 0.5))
            spark.close()
            (i.isMultiple(of: 9)
                ? Palette.ash.withAlphaComponent(fade * 0.80)
                : Palette.steel.withAlphaComponent(fade * 0.80)
            ).setFill()
            spark.fill()
        }
    }

}
