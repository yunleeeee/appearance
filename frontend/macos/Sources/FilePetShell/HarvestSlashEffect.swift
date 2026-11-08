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
    static let duration: TimeInterval = 1.74
    static let reducedDuration: TimeInterval = 0.16
    static let shatterAt: TimeInterval = 0.67
    static let floorY: CGFloat = 2

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

    /// The cut area is explicitly rectangular and spans the complete native
    /// plant canvas, down to its rooted ground baseline. No foliage is excluded.
    static func cuttingRect(in bounds: CGRect) -> CGRect {
        bounds
    }

    /// Nine real diagonals and near-vertical cuts traverse *different heights*
    /// of the rectangle, including the basal stem and ground decoration.
    static func slashSegments(in rect: CGRect) -> [(CGPoint, CGPoint)] {
        let ends: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, 0.96, 1, 0.59), (1, 0.93, 0, 0.51),
            (0, 0.72, 1, 0.10), (1, 0.39, 0, 0.02),
            (0.14, 0, 0.86, 1), (0.05, 1, 0.94, 0),
            (0, 0.84, 1, 0.18), (1, 0.73, 0, 0.13),
            (0.43, 0, 0.62, 1)
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
        let gravity: CGFloat = 300
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
        let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        let rect = cuttingRect(in: CGRect(origin: .zero, size: bounds.size))
        let fragments = makeFragments(rect: rect, width: width, height: height, alpha: alpha)
        return PlantSnapshot(image: image, cutRect: rect, fragments: fragments,
                             pixelWidth: width, pixelHeight: height, alpha: alpha)
    }

    /// Screen-independent 8x14 triangular segmentation. Transparent tiles are
    /// removed by testing actual raster pixels, including narrow root/stem lines.
    private static func makeFragments(rect: CGRect, width: Int, height: Int,
                                      alpha: [UInt8]) -> [Fragment] {
        let columns = 8, rows = 14
        var result: [Fragment] = []
        for row in 0..<rows {
            for col in 0..<columns {
                let x0 = rect.minX + rect.width * CGFloat(col) / CGFloat(columns)
                let x1 = rect.minX + rect.width * CGFloat(col + 1) / CGFloat(columns)
                let y0 = rect.minY + rect.height * CGFloat(row) / CGFloat(rows)
                let y1 = rect.minY + rect.height * CGFloat(row + 1) / CGFloat(rows)
                let a = CGPoint(x: x0, y: y0), b = CGPoint(x: x1, y: y0)
                let c = CGPoint(x: x1, y: y1), d = CGPoint(x: x0, y: y1)
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
                    let side: CGFloat = col < columns / 2 ? -1 : 1
                    let stem = row < rows * 2 / 3
                    result.append(Fragment(points: triangle, center: center,
                        speedX: side * CGFloat((stem ? 24 : 48) + (i * 19) % 95),
                        launch: CGFloat((stem ? 38 : 78) + (i * 29) % 99),
                        rotation: side * CGFloat(1.8 + Double(i % 7) * 0.49),
                        delay: CGFloat(i % 5) * 0.012))
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

        if reduceMotion {
            snapshot.image.draw(in: rect, from: .zero, operation: .sourceOver,
                                fraction: state.stemOpacity)
            return
        }

        if age < shatterAt {
            // An unbroken whole-plant silhouette is visible during every cut.
            let jitter: CGFloat = age > 0.09 ? sin(CGFloat(age) * 150) * 0.6 : 0
            snapshot.image.draw(in: rect.offsetBy(dx: jitter, dy: 0),
                                from: .zero, operation: .sourceOver, fraction: 1)
            drawRegionGuide(in: rect, age: age)
            drawCutScars(in: rect, age: age)
        } else {
            drawFragments(snapshot, age: age, opacity: state.shardOpacity, context: ctx)
            drawGroundSparks(centerX: rect.midX, age: age)
            drawImpactFlash(at: CGPoint(x: rect.midX, y: rect.midY), age: age)
        }
        drawSwordStreaks(in: rect, age: age)
    }

    private static func drawFragments(_ snapshot: PlantSnapshot, age: TimeInterval,
                                      opacity: CGFloat, context: CGContext) {
        guard opacity > 0 else { return }
        let time = CGFloat(max(0, age - shatterAt))
        for shard in snapshot.fragments {
            let t = max(0, time - shard.delay)
            let theta = shard.rotation * t
            let cosine = cos(theta), sine = sin(theta)
            let dx = shard.speedX * t
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
            snapshot.image.draw(in: snapshot.cutRect, from: .zero,
                                operation: .sourceOver, fraction: 1)
            context.restoreGState()
        }
    }

    private static let slashTimes: [TimeInterval] =
        [0.022, 0.089, 0.151, 0.216, 0.282, 0.348, 0.413, 0.478, 0.544]

    /// A faint rectangular target field makes the user-perceived cut area
    /// cover the stalk and root rather than the blossom only.
    private static func drawRegionGuide(in rect: CGRect, age: TimeInterval) {
        let alpha = CGFloat(min(1, age / 0.07)
                            * max(0, 1 - age / shatterAt)) * 0.42
        guard alpha > 0 else { return }
        let frame = rect.insetBy(dx: 1.5, dy: 2.5)
        NSColor(calibratedRed: 0.43, green: 0.20, blue: 0.82,
                alpha: alpha * 0.45).setStroke()
        let outline = NSBezierPath(rect: frame)
        outline.lineWidth = 0.75
        outline.stroke()

        // Four brighter L-shaped corner markers trace the entire region.
        NSColor(calibratedRed: 0.80, green: 0.52, blue: 1,
                alpha: alpha).setStroke()
        for xSide: CGFloat in [0, 1] {
            for ySide: CGFloat in [0, 1] {
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

    private static func drawSwordStreaks(in rect: CGRect, age: TimeInterval) {
        let lines = slashSegments(in: rect.insetBy(dx: 2, dy: 2))
        for (index, start) in slashTimes.enumerated() {
            let t = age - start
            guard t >= 0 && t < 0.20 else { continue }
            let p = CGFloat(min(1, t / 0.118))
            let fade = CGFloat(min(1, t / 0.018) * max(0, 1 - t / 0.20))
            let a = lines[index].0, b = lines[index].1
            let tip = CGPoint(x: a.x + (b.x - a.x) * p,
                              y: a.y + (b.y - a.y) * p)
            let length = hypot(b.x - a.x, b.y - a.y)
            let trail = min(110, length * 0.48, CGFloat(t / 0.118) * length + 3)
            let ux = (b.x - a.x) / max(1, length)
            let uy = (b.y - a.y) / max(1, length)
            let tail = CGPoint(x: tip.x - ux * trail, y: tip.y - uy * trail)

            // Saturated purple border / cyan accents / pink inner edge /
            // razor-white center, plus a slimmer echo stroke.
            let violet = index.isMultiple(of: 2)
            let ghost = NSBezierPath()
            ghost.move(to: CGPoint(x: tail.x - uy * 2, y: tail.y + ux * 2))
            ghost.line(to: CGPoint(x: tip.x - uy * 2, y: tip.y + ux * 2))
            ghost.lineCapStyle = .round
            ghost.lineWidth = 4
            NSColor(calibratedRed: 0.88, green: 0.46, blue: 1,
                    alpha: fade * 0.28).setStroke()
            ghost.stroke()

            let blade = NSBezierPath()
            blade.move(to: tail)
            blade.line(to: tip)
            blade.lineCapStyle = .round
            let contour = violet
                ? NSColor(calibratedRed: 0.27, green: 0.06, blue: 0.66, alpha: 0.29 * fade)
                : NSColor(calibratedRed: 0.07, green: 0.31, blue: 0.65, alpha: 0.27 * fade)
            contour.setStroke()
            blade.lineWidth = 23
            blade.stroke()
            (violet
                ? NSColor(calibratedRed: 0.49, green: 0.18, blue: 0.93, alpha: 0.78 * fade)
                : NSColor(calibratedRed: 0.19, green: 0.69, blue: 0.98, alpha: 0.76 * fade)
            ).setStroke()
            blade.lineWidth = 9
            blade.stroke()
            NSColor(calibratedRed: 0.97, green: 0.67, blue: 1, alpha: fade).setStroke()
            blade.lineWidth = 3
            blade.stroke()
            NSColor(calibratedWhite: 1, alpha: fade).setStroke()
            blade.lineWidth = 1
            blade.stroke()

            let glint = NSBezierPath(ovalIn: CGRect(
                x: tip.x - 3.5, y: tip.y - 3.5, width: 7, height: 7))
            NSColor(calibratedRed: 0.91, green: 0.82, blue: 1,
                    alpha: fade * 0.92).setFill()
            glint.fill()
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
            NSColor(calibratedRed: 0.48, green: 0.16, blue: 0.86,
                    alpha: alpha).setStroke()
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
            NSColor(calibratedRed: 0.59, green: 0.25, blue: 0.95,
                    alpha: alpha * 0.75).setStroke()
            beam.stroke()
        }
        NSColor(calibratedRed: 0.87, green: 0.57, blue: 1,
                alpha: alpha * 0.45).setFill()
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
        NSColor(calibratedRed: 0.56, green: 0.24, blue: 0.91,
                alpha: fade * 0.65).setStroke()
        ring.stroke()
        for i in 0..<23 {
            let sign: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            let x = centerX + sign * CGFloat(time) * CGFloat(40 + i * 6)
            let y = floorY + abs(sin(CGFloat(i) * 2.15))
                * CGFloat(5 + (1 - time / 0.63) * 20)
            NSColor(calibratedRed: 0.64, green: 0.30, blue: 0.98,
                    alpha: fade * 0.80).setFill()
            let size: CGFloat = i.isMultiple(of: 5) ? 3.3 : 1.6
            NSBezierPath(ovalIn: CGRect(x: x, y: y, width: size, height: size)).fill()
        }
    }
}
