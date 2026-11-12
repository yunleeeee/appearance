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
    static let duration: TimeInterval = 1.38
    static let reducedDuration: TimeInterval = 0.16
    static let shatterAt: TimeInterval = 0.54
    static let secondaryAt: TimeInterval = 0.73
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
    static let finisherAt: TimeInterval = 0.42
    static let impactFrameAt: TimeInterval = 0.505
    static let impactFrameDuration: TimeInterval = 0.034

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
        let side: CGFloat
        let delay: CGFloat
    }

    struct PlantSnapshot {
        let image: NSImage
        let monochromeImage: NSImage
        let invertedImage: NSImage
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
        let debris = t >= secondaryAt
        return Sample(showHead: !broken, stemOpacity: broken ? 0 : 1,
                      shardOpacity: debris ? max(0, min(1,
                          CGFloat((duration - t) / 0.42))) : 0,
                      finished: t >= duration)
    }

    /// Color drains out *because* the execution sword lands. Before this beat
    /// the plant is recognizably colored; by the fracture all its pixels and
    /// every separated fragment are fully neutral black/white.
    static func monochromeProgress(at seconds: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return max(0, min(1, CGFloat((seconds - finisherAt - 0.02) / 0.10)))
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

    /// The very same inclined blade line is used to split the plant bitmap.
    /// It passes through the crown and remains close to the rooted stem.
    static func executionLine(in rect: CGRect, rootX: CGFloat)
        -> (start: CGPoint, end: CGPoint) {
        (CGPoint(x: rootX - 17, y: rect.maxY + 10),
         CGPoint(x: rootX + 11, y: rect.minY - 10))
    }

    private static func signedCut(_ point: CGPoint, start: CGPoint,
                                   end: CGPoint) -> CGFloat {
        (end.x - start.x) * (point.y - start.y)
            - (end.y - start.y) * (point.x - start.x)
    }

    /// Clip an arbitrary polygon to the two half-planes of the execution
    /// sword. This is genuine geometry, not an unrelated tile explosion.
    static func splitBySword(_ polygon: [CGPoint], start: CGPoint, end: CGPoint)
        -> (positive: [CGPoint], negative: [CGPoint]) {
        func clip(positive: Bool) -> [CGPoint] {
            guard !polygon.isEmpty else { return [] }
            var result: [CGPoint] = []
            for i in polygon.indices {
                let a = polygon[i], b = polygon[(i + 1) % polygon.count]
                let da = signedCut(a, start: start, end: end)
                let db = signedCut(b, start: start, end: end)
                let insideA = positive ? da >= -0.0001 : da <= 0.0001
                let insideB = positive ? db >= -0.0001 : db <= 0.0001
                if insideA { result.append(a) }
                if insideA != insideB {
                    let t = min(1, max(0, da / (da - db)))
                    result.append(CGPoint(x: a.x + (b.x - a.x) * t,
                                          y: a.y + (b.y - a.y) * t))
                }
            }
            return result
        }
        return (clip(positive: true), clip(positive: false))
    }

    static func polygonArea(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var twiceArea: CGFloat = 0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            twiceArea += a.x * b.y - b.x * a.y
        }
        return abs(twiceArea) * 0.5
    }

    /// A continuous easing curve separates the two primary pieces before
    /// small fragments inherit their positions and disperse.
    static func primarySeparation(at age: TimeInterval) -> CGFloat {
        let t = max(0, min(1, CGFloat((age - shatterAt - 0.035)
                                     / (secondaryAt - shatterAt - 0.035))))
        return 13 * (1 - pow(1 - t, 3))
    }

    /// Seven sampled directions cover different heights before the execution cut.
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
        func imageFromPixels(_ bytes: [UInt8]) -> NSImage? {
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let cg = CGImage(
                    width: width, height: height,
                    bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue:
                        CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue),
                    provider: provider, decode: nil,
                    shouldInterpolate: false, intent: .defaultIntent
                  ) else { return nil }
            return NSImage(cgImage: cg, size: bounds.size)
        }
        let monochromeRGBA = makeMonochromeRGBA(rgba)
        guard let monochrome = imageFromPixels(monochromeRGBA),
              let inverted = imageFromPixels(makeMonochromeRGBA(rgba, inverted: true))
        else { return nil }
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        let rect = cuttingRect(in: CGRect(origin: .zero, size: bounds.size))
        let line = executionLine(in: rect, rootX: artwork.stemX)
        let fragments = makeFragments(rect: rect, width: width, height: height,
                                      alpha: alpha, cutStart: line.start, cutEnd: line.end)
        return PlantSnapshot(image: image, monochromeImage: monochrome,
                             invertedImage: inverted, monochromeRGBA: monochromeRGBA,
                             cutRect: rect, fragments: fragments,
                             pixelWidth: width, pixelHeight: height, alpha: alpha)
    }

    /// Contrast-preserving grayscale on RGBA premultiplied pixels. Alpha is
    /// copied exactly: the original pixel-sharp foliage and edge masks survive.
    static func makeMonochromeRGBA(_ rgba: [UInt8], inverted: Bool = false) -> [UInt8] {
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
            let value = inverted ? 255 - gray : gray
            let premultiplied = UInt8((value * a + 127) / 255)
            output[i] = premultiplied
            output[i + 1] = premultiplied
            output[i + 2] = premultiplied
        }
        return output
    }

    /// Screen-independent 10x17 triangular segmentation. Transparent tiles are
    /// removed by testing actual raster pixels, including narrow root/stem lines.
    private static func makeFragments(rect: CGRect, width: Int, height: Int,
                                      alpha: [UInt8],
                                      cutStart: CGPoint, cutEnd: CGPoint) -> [Fragment] {
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
                    let halves = splitBySword(triangle, start: cutStart, end: cutEnd)
                    let candidates: [([CGPoint], CGFloat)] = [
                        (halves.positive, 1), (halves.negative, -1)
                    ]
                    for (part, candidate) in candidates.enumerated() {
                        let points = candidate.0
                        guard points.count >= 3, polygonArea(points) > 0.03,
                              containsPaint(points, rect: rect,
                                            pixelWidth: width, pixelHeight: height,
                                            alpha: alpha) else { continue }
                        let i = ((row * columns + col) * 2 + half) * 2 + part
                        let center = CGPoint(
                            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                            y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
                        let side = candidate.1
                        let jitter = CGFloat((i * 41) % 47 - 23)
                        let lift = CGFloat((i * 29) % 61)
                        // Side bias follows the actual cutting plane. These
                        // lighter petals lift more than the grounded stem.
                        let isCrown = row > rows * 2 / 3
                        result.append(Fragment(points: points, center: center,
                            speedX: side * CGFloat(42 + (i * 19) % 52) + jitter,
                            launch: CGFloat(isCrown ? 74 : 27) + lift,
                            rotation: side * CGFloat(1.1 + Double(i % 7) * 0.38),
                            side: side, delay: CGFloat(i % 6) * 0.008))
                    }
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
                let edges = triangle.indices.map { i -> CGFloat in
                    let a = triangle[i], b = triangle[(i + 1) % triangle.count]
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
            // The flower stays perfectly still between the two primary
            // strikes and the execution cut: no sinusoidal perpetual jitter.
            let imageRect = rect
            let monochrome = monochromeProgress(at: age, reduceMotion: false)
            snapshot.image.draw(in: imageRect, from: .zero,
                                operation: .sourceOver, fraction: 1)
            if monochrome > 0 {
                snapshot.monochromeImage.draw(in: imageRect, from: .zero,
                    operation: .sourceOver, fraction: monochrome)
            }
            if age >= impactFrameAt &&
               age < impactFrameAt + impactFrameDuration {
                // Only the plant becomes a one/two-frame photographic
                // negative. The entire desktop stays untouched.
                snapshot.invertedImage.draw(in: rect, from: .zero,
                                            operation: .sourceOver, fraction: 1)
            }
            drawRegionGuide(in: battlefield, age: age)
            drawCutScars(in: battlefield, age: age)
        } else if age < secondaryAt {
            drawPrimaryHalves(snapshot, rootX: artwork.stemX,
                              age: age, context: ctx)
        } else {
            drawFragments(snapshot, rootX: artwork.stemX, age: age,
                          opacity: state.shardOpacity, context: ctx)
            drawGroundSparks(centerX: artwork.stemX, age: age)
            drawImpactFlash(at: CGPoint(x: artwork.stemX, y: battlefield.midY), age: age)
            drawBurstDust(in: battlefield, age: age)
        }
        drawSwordStreaks(in: battlefield, age: age)
        // Draw the finishing blade in the same native coordinate system
        // used by splitBySword; its pixel path and geometry now coincide.
        drawFinalSlash(in: rect, rootX: artwork.stemX, age: age)
    }

    /// Two substantial cut masses open along the real execution line
    /// before the smaller shards release. The source is still the complete
    /// monochrome plant, including ground and rooted stem.
    private static func drawPrimaryHalves(_ snapshot: PlantSnapshot,
                                          rootX: CGFloat, age: TimeInterval,
                                          context: CGContext) {
        let rect = snapshot.cutRect
        let line = executionLine(in: rect, rootX: rootX)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        let sides = splitBySword(corners, start: line.start, end: line.end)
        for (polygon, sign) in [(sides.positive, CGFloat(1)),
                                (sides.negative, CGFloat(-1))] {
            guard polygon.count >= 3, polygonArea(polygon) > 0.1 else { continue }
            context.saveGState()
            context.translateBy(x: sign * primarySeparation(at: age), y: 0)
            let path = CGMutablePath()
            for (i, point) in polygon.enumerated() {
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            context.addPath(path)
            context.clip()
            snapshot.monochromeImage.draw(in: rect, from: .zero,
                                          operation: .sourceOver, fraction: 1)
            context.restoreGState()
        }
        // A fine black seam is all that is needed during the hit-stop.
        if age < shatterAt + 0.09 {
            let scar = NSBezierPath()
            scar.move(to: line.start)
            scar.line(to: line.end)
            scar.lineWidth = 0.9
            Palette.charcoal.withAlphaComponent(
                max(0, CGFloat((shatterAt + 0.09 - age) / 0.09)) * 0.74).setStroke()
            scar.stroke()
        }
    }

    private static func drawFragments(_ snapshot: PlantSnapshot, rootX: CGFloat,
                                      age: TimeInterval,
                                      opacity: CGFloat, context: CGContext) {
        guard opacity > 0 else { return }
        let time = CGFloat(max(0, age - secondaryAt))
        let separation = primarySeparation(at: secondaryAt)
        for shard in snapshot.fragments {
            let t = max(0, time - shard.delay)
            let theta = shard.rotation * t
            let cosine = cos(theta), sine = sin(theta)
            // Strong initial lateral blast, then air resistance.
            let dx = shard.side * separation
                + shard.speedX * t * max(0.55, 1 - t * 0.32)
                + 9 * sin(t * 5 + shard.center.y * 0.27) * t
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
        [0.075, 0.094, 0.200, 0.224]

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
        // Only two strokes are full-strength. The interleaved minor strokes
        // provide depth, not four equally bright neon tubes.
        let lineIDs = [0, 1, 4, 3]
        let lines = slashSegments(in: rect)
        for (i, start) in slashTimes.enumerated() {
            let ageOfCut = age - start
            let main = i.isMultiple(of: 2)
            let life: TimeInterval = main ? 0.105 : 0.067
            guard ageOfCut >= 0 && ageOfCut < life else { continue }
            let travel: TimeInterval = main ? 0.055 : 0.033
            let progress = CGFloat(min(1, ageOfCut / travel))
            let fade = CGFloat(min(1, ageOfCut / 0.009)
                               * max(0, 1 - ageOfCut / life))
            let line = lines[lineIDs[i]]
            let a = line.0, b = line.1
            let tip = CGPoint(x: a.x + (b.x - a.x) * progress,
                              y: a.y + (b.y - a.y) * progress)
            let span = hypot(b.x - a.x, b.y - a.y)
            let ux = (b.x - a.x) / max(1, span)
            let uy = (b.y - a.y) / max(1, span)
            let tailLength = min(main ? 128 : 78, span * 0.65)
            let tail = CGPoint(x: tip.x - ux * tailLength,
                               y: tip.y - uy * tailLength)
            let weight: CGFloat = main ? 1 : 0.28
            let shadowTail = CGPoint(x: tail.x - uy * 3.8, y: tail.y + ux * 3.8)
            let shadowTip = CGPoint(x: tip.x - uy * 3.8, y: tip.y + ux * 3.8)
            blade(from: shadowTail, to: shadowTip, width: main ? 7 : 3,
                  color: Palette.ink.withAlphaComponent(fade * 0.50 * weight))
            blade(from: tail, to: tip, width: main ? 17 : 8,
                  color: Palette.ink.withAlphaComponent(fade * 0.80 * weight))
            blade(from: tail, to: tip, width: main ? 5 : 2,
                  color: Palette.silver.withAlphaComponent(fade * 0.95 * weight))
            blade(from: tail, to: tip, width: main ? 1.5 : 0.7,
                  color: Palette.pearl.withAlphaComponent(fade * weight))
        }
    }

    /// 70ms still frame, then one full-height white-hot execution slash.
    /// The decisive diagonal is bigger and lasts longer than the preceding cuts.
    private static func drawFinalSlash(in rect: CGRect,
                                       rootX: CGFloat, age: TimeInterval) {
        let t = age - finisherAt
        guard t >= 0 && t < 0.16 else { return }
        // Finisher display and polygon fracture are the *same line*.
        let line = executionLine(in: rect, rootX: rootX)
        let a = line.start, b = line.end
        let progress = CGFloat(min(1, t / 0.066))
        let tip = CGPoint(x: a.x + (b.x - a.x) * progress,
                          y: a.y + (b.y - a.y) * progress)
        let len = hypot(b.x - a.x, b.y - a.y)
        let ux = (b.x - a.x) / len, uy = (b.y - a.y) / len
        let tail = CGPoint(x: tip.x - ux * len * 0.70,
                           y: tip.y - uy * len * 0.70)
        let fade = CGFloat(max(0, 1 - t / 0.16))
        // The execution stroke is monochrome even while the last patches of
        // color are draining out of the flower beneath it.
        blade(from: tail, to: tip, width: 33,
              color: Palette.charcoal.withAlphaComponent(fade * 0.92))
        blade(from: tail, to: tip, width: 12,
              color: Palette.ash.withAlphaComponent(fade * 0.96))
        blade(from: tail, to: tip, width: 2.3,
              color: Palette.white.withAlphaComponent(fade))
        // One charcoal shadow peels away from the silvery finishing stroke,
        // establishing swordlight and sword-shadow as two separate layers.
        let side = CGPoint(x: -uy * 5.8, y: ux * 5.8)
        let echo = NSBezierPath()
        echo.move(to: CGPoint(x: tail.x + side.x, y: tail.y + side.y))
        echo.line(to: CGPoint(x: tip.x + side.x, y: tip.y + side.y))
        echo.lineWidth = 1.2
        Palette.charcoal.withAlphaComponent(fade * 0.75).setStroke()
        echo.stroke()
        // The brightest moment is only a brief central crossing, not a
        // fullscreen flash or a solid rectangular overlay.
        if t > 0.060 && t < 0.093 {
            let impact = CGFloat(sin((t - 0.060) / 0.033 * .pi))
            // Restrained perpendicular spark at the exact blade crossing,
            // not an unrelated full-width horizontal scan line.
            let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: center.x - uy * 15,
                                    y: center.y + ux * 15))
            cross.line(to: CGPoint(x: center.x + uy * 15,
                                    y: center.y - ux * 15))
            cross.lineWidth = 1.4
            Palette.charcoal.withAlphaComponent(impact * 0.82).setStroke()
            cross.stroke()
        }
    }

    private static func drawCutScars(in rect: CGRect, age: TimeInterval) {
        let lines = slashSegments(in: rect)
        for (index, start) in slashTimes.enumerated() {
            let elapsed = age - start
            guard elapsed > 0.035 && elapsed < 0.29 else { continue }
            let alpha = CGFloat((0.29 - elapsed) / 0.255)
                * (index.isMultiple(of: 2) ? 0.56 : 0.14)
            let path = NSBezierPath()
            let line = lines[[0, 1, 4, 3][index]]
            path.move(to: line.0)
            path.line(to: line.1)
            path.lineWidth = 1.3
            Palette.steel.withAlphaComponent(alpha * 0.82).setStroke()
            path.stroke()
        }
    }

    private static func drawImpactFlash(at center: CGPoint, age: TimeInterval) {
        let t = age - secondaryAt
        guard t >= 0 && t < 0.19 else { return }
        let alpha = CGFloat(1 - t / 0.19)
        let radius = CGFloat(9 + t * 155)
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
            (i.isMultiple(of: 8) ? Palette.charcoal : Palette.ash)
                .withAlphaComponent(alpha * (i.isMultiple(of: 8) ? 0.86 : 0.71)).setStroke()
            beam.stroke()
        }
        Palette.ash.withAlphaComponent(alpha * 0.35).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - radius * 0.3,
                                   y: center.y - radius * 0.3,
                                   width: radius * 0.6, height: radius * 0.6)).fill()
    }

    private static func drawGroundSparks(centerX: CGFloat, age: TimeInterval) {
        let time = age - secondaryAt - 0.25
        guard time > 0 && time < 0.63 else { return }
        let fade = CGFloat(1 - time / 0.63)
        let spread = CGFloat(16 + time * 180)
        let ring = NSBezierPath(ovalIn: CGRect(x: centerX - spread / 2,
            y: floorY, width: spread, height: 5 + CGFloat(time * 3)))
        ring.lineWidth = 1.8
        Palette.charcoal.withAlphaComponent(fade * 0.58).setStroke()
        ring.stroke()
        for i in 0..<23 {
            let sign: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            let x = centerX + sign * CGFloat(time) * CGFloat(40 + i * 6)
            let y = floorY + abs(sin(CGFloat(i) * 2.15))
                * CGFloat(5 + (1 - time / 0.63) * 20)
            (i.isMultiple(of: 9) ? Palette.charcoal : Palette.ash)
                .withAlphaComponent(fade * 0.78).setFill()
            let size: CGFloat = i.isMultiple(of: 5) ? 3.3 : 1.6
            NSBezierPath(ovalIn: CGRect(x: x, y: y, width: size, height: size)).fill()
        }
    }
    /// Small high-velocity diamond sparks accompany the first fracture.
    private static func drawBurstDust(in rect: CGRect, age: TimeInterval) {
        let t = age - secondaryAt
        guard t >= 0 && t < 0.30 else { return }
        let fade = CGFloat(max(0, 1 - t / 0.30))
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
                ? Palette.charcoal.withAlphaComponent(fade * 0.82)
                : Palette.ash.withAlphaComponent(fade * 0.77)
            ).setFill()
            spark.fill()
        }
    }

}
