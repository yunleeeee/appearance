import AppKit

/// A short, self-contained particle/sword-light scene. It owns no deadline data:
/// the completion is committed as soon as the second click is received.
enum HarvestSlashTimeline {
    // The flower remains readable during the crossing sword cuts. The final
    // cut releases its pieces; each fragment lands independently afterward.
    static let fractureTime: TimeInterval = 0.48
    static let floorY: CGFloat = 6

    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.24 : 1.58
    }

    static func fallOffset(elapsed: TimeInterval, launch: CGFloat, centerY: CGFloat) -> CGFloat {
        let t = CGFloat(max(0, elapsed))
        let gravity: CGFloat = 295
        let floorOffset = floorY - centerY
        let ballistic = launch * t - gravity * t * t
        if ballistic >= floorOffset { return ballistic }

        // Analytic impact time keeps each shard on the ground instead of
        // pushing it below the panel or snapping upward on its first frame.
        let impact = (launch + sqrt(launch * launch
            + 4 * gravity * max(0, centerY - floorY))) / (2 * gravity)
        let afterImpact = max(0, t - impact)
        let rebound = max(0, (40 + launch * 0.11) * afterImpact
            - 260 * afterImpact * afterImpact)
        return floorOffset + rebound
    }

    static func opacity(elapsed: TimeInterval) -> CGFloat {
        max(0, min(1, CGFloat((1.53 - elapsed) / 0.53)))
    }
}

/// An independent, click-through NSPanel hosts this view while the real flower
/// has already been harvested. That keeps queued flowers from interrupting VFX.
@MainActor
final class HarvestSlashEffectView: NSView {
    private struct Shard {
        let points: [CGPoint] // Original image coordinates, bottom-left origin.
        let center: CGPoint
        let velocityX: CGFloat
        let velocityY: CGFloat
        let spin: CGFloat
        let delay: TimeInterval
    }

    let artwork: CompactFlowerArtwork
    let reduceMotion: Bool
    var onFinish: (() -> Void)?
    private let image: NSImage
    private let shards: [Shard]
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private(set) var elapsed: TimeInterval = 0

    static func canvasSize(for artwork: CompactFlowerArtwork) -> CGSize {
        CGSize(width: max(310, artwork.size.width + 200),
               height: max(235, artwork.size.height + 70))
    }

    init(artwork: CompactFlowerArtwork, reduceMotion: Bool) {
        self.artwork = artwork
        self.reduceMotion = reduceMotion
        image = NSImage(cgImage: artwork.image, size: artwork.size)
        shards = Self.makeShards(artwork: artwork)
        super.init(frame: CGRect(origin: .zero, size: Self.canvasSize(for: artwork)))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }

    func start() {
        guard timer == nil else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        elapsed = 0
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        onFinish = nil
    }

    private func advance() {
        elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        if elapsed >= HarvestSlashTimeline.duration(reduceMotion: reduceMotion) {
            let callback = onFinish
            stop()
            callback?()
        } else {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let graphics = NSGraphicsContext.current else { return }
        graphics.imageInterpolation = .none
        let imageRect = CGRect(x: (bounds.width - artwork.size.width) / 2, y: 6,
                               width: artwork.size.width, height: artwork.size.height)

        if reduceMotion {
            let fade = max(0, 1 - CGFloat(elapsed / HarvestSlashTimeline.duration(reduceMotion: true)))
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: fade)
            return
        }

        if elapsed < HarvestSlashTimeline.fractureTime {
            // Sub-pixel vibration conveys the repeated impacts; keep the
            // silhouette intact until the final cut.
            let shake: CGFloat = elapsed > 0.11 ? CGFloat(sin(elapsed * 143)) * 0.9 : 0
            image.draw(in: imageRect.offsetBy(dx: shake, dy: 0),
                       from: .zero, operation: .sourceOver, fraction: 1)
            drawCutScars(around: imageRect)
        } else {
            drawShards(in: imageRect, graphics: graphics)
            drawFloorSparks(below: imageRect)
        }
        drawSlashes(around: imageRect)
        drawFractureFlash(at: CGPoint(x: imageRect.midX,
            y: imageRect.minY + imageRect.height * 0.81))
    }

    private func drawShards(in imageRect: CGRect, graphics: NSGraphicsContext) {
        let t = max(0, elapsed - HarvestSlashTimeline.fractureTime)
        let fade = HarvestSlashTimeline.opacity(elapsed: elapsed)
        guard fade > 0 else { return }
        for shard in shards {
            if t < shard.delay { continue }
            let shardTime = t - shard.delay
            let center = CGPoint(x: imageRect.minX + shard.center.x,
                                 y: imageRect.minY + shard.center.y)
            let dx = shard.velocityX * CGFloat(shardTime)
            let dy = HarvestSlashTimeline.fallOffset(elapsed: shardTime,
                launch: shard.velocityY, centerY: center.y)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: center.x + dx, yBy: center.y + dy)
            transform.rotate(byDegrees: shard.spin * CGFloat(shardTime))
            transform.translateX(by: -center.x, yBy: -center.y)
            transform.concat()

            let clip = NSBezierPath()
            for (index, point) in shard.points.enumerated() {
                let transformed = CGPoint(x: imageRect.minX + point.x, y: imageRect.minY + point.y)
                if index == 0 { clip.move(to: transformed) } else { clip.line(to: transformed) }
            }
            clip.close()
            clip.addClip()
            graphics.cgContext.setAlpha(fade)
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private static let slashStarts: [TimeInterval] =
        [0.012, 0.076, 0.139, 0.205, 0.274, 0.344, 0.408]
    private static let slashAngles: [CGFloat] = [27, -34, 15, -24, 41, -18, 35]

    private func drawSlashes(around rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.81)
        for (index, startTime) in Self.slashStarts.enumerated() {
            let age = elapsed - startTime
            guard age >= 0 && age < 0.175 else { continue }
            let progress = CGFloat(min(1, age / 0.105))
            let fade = CGFloat(min(1, age / 0.024)) * CGFloat(max(0, 1 - age / 0.175))
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let angle = Self.slashAngles[index] * .pi / 180
            let ux = cos(angle) * direction
            let uy = sin(angle) * direction
            let reach: CGFloat = max(230, rect.width * 3.4)
            let position = -reach / 2 + reach * progress
            let tail = min(95, CGFloat(age / 0.105) * reach * 0.62 + 8)
            let height = CGFloat((index % 3) - 1) * 7
            let head = CGPoint(x: center.x + ux * position,
                               y: center.y + uy * position + height)
            let back = CGPoint(x: head.x - ux * tail,
                               y: head.y - uy * tail)

            let blade = NSBezierPath()
            blade.move(to: back)
            blade.line(to: head)
            blade.lineCapStyle = .round
            // A saturated violet outer contour is readable on white desktops;
            // the pink core and white-hot pinline add the sword-light glint.
            for (width, color) in [
                (CGFloat(24), NSColor(calibratedRed: 0.31, green: 0.08, blue: 0.66, alpha: 0.20 * fade)),
                (CGFloat(12), NSColor(calibratedRed: 0.43, green: 0.14, blue: 0.84, alpha: 0.59 * fade)),
                (CGFloat(5), NSColor(calibratedRed: 0.94, green: 0.43, blue: 1, alpha: 0.91 * fade)),
                (CGFloat(1.5), NSColor(calibratedRed: 1, green: 0.99, blue: 1, alpha: fade)),
            ] {
                blade.lineWidth = width
                color.setStroke()
                blade.stroke()
            }

            let glint = NSBezierPath(ovalIn:
                CGRect(x: head.x - 3.3, y: head.y - 3.3, width: 6.6, height: 6.6))
            NSColor(calibratedRed: 0.56, green: 0.18, blue: 0.90, alpha: fade).setFill()
            glint.fill()
        }
    }

    private func drawCutScars(around rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.81)
        for (index, start) in Self.slashStarts.enumerated() {
            let age = elapsed - start
            guard age > 0.078 && age < 0.33 else { continue }
            let angle = Self.slashAngles[index] * .pi / 180
            let half: CGFloat = max(22, rect.width * 0.37)
            let offset = CGFloat((index % 3) - 1) * 7
            let path = NSBezierPath()
            path.move(to: CGPoint(x: center.x - cos(angle) * half,
                                  y: center.y - sin(angle) * half + offset))
            path.line(to: CGPoint(x: center.x + cos(angle) * half,
                                  y: center.y + sin(angle) * half + offset))
            path.lineWidth = 1.2
            let alpha = CGFloat(min(0.65, (0.33 - age) * 3))
            NSColor(calibratedRed: 0.49, green: 0.14, blue: 0.83, alpha: alpha).setStroke()
            path.stroke()
        }
    }

    private func drawFractureFlash(at center: CGPoint) {
        let t = elapsed - HarvestSlashTimeline.fractureTime
        guard t >= 0 && t < 0.28 else { return }
        let alpha = CGFloat(max(0, 1 - t / 0.28))
        let radius = CGFloat(8 + t * 145)

        // Radiating narrow beams sell the impact without washing out the
        // whole desktop in a white circular flash.
        for i in 0..<16 {
            let angle = CGFloat(i) * .pi / 8 + 0.08
            let inner: CGFloat = radius * 0.20
            let outer: CGFloat = radius * (i.isMultiple(of: 4) ? 1.15 : 0.76)
            let beam = NSBezierPath()
            beam.move(to: CGPoint(x: center.x + cos(angle) * inner,
                                  y: center.y + sin(angle) * inner))
            beam.line(to: CGPoint(x: center.x + cos(angle) * outer,
                                  y: center.y + sin(angle) * outer))
            beam.lineCapStyle = .round
            beam.lineWidth = i.isMultiple(of: 4) ? 3.5 : 1.4
            NSColor(calibratedRed: 0.54, green: 0.15, blue: 0.90,
                    alpha: alpha * 0.85).setStroke()
            beam.stroke()
        }
        NSColor(calibratedRed: 0.82, green: 0.38, blue: 1,
                alpha: alpha * 0.56).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - radius * 0.30,
                                   y: center.y - radius * 0.30,
                                   width: radius * 0.60,
                                   height: radius * 0.60)).fill()
    }

    private func drawFloorSparks(below imageRect: CGRect) {
        let age = elapsed - (HarvestSlashTimeline.fractureTime + 0.40)
        guard age > 0 && age < 0.64 else { return }
        let fade = CGFloat(1 - age / 0.64)
        let centerX = imageRect.midX

        // A low, spreading ring reads as ground impact; deterministic dust
        // specks scatter sideways and fade as the fragments settle.
        let spread = CGFloat(12 + age * 145)
        let ring = NSBezierPath(ovalIn:
            CGRect(x: centerX - spread / 2, y: 4,
                   width: spread, height: 5 + CGFloat(age) * 3))
        ring.lineWidth = 1.6
        NSColor(calibratedRed: 0.55, green: 0.21, blue: 0.87, alpha: fade * 0.55).setStroke()
        ring.stroke()

        for i in 0..<24 {
            let side: CGFloat = i.isMultiple(of: 2) ? 1 : -1
            let distance = CGFloat(age) * CGFloat(48 + (i * 23) % 110)
            let x = centerX + side * distance
            let y = HarvestSlashTimeline.floorY
                + abs(sin(CGFloat(i) * 1.91)) * CGFloat(7 + 16 * (1 - age / 0.64))
            let size: CGFloat = i.isMultiple(of: 5) ? 3.1 : 1.8
            NSColor(calibratedRed: 0.55 + CGFloat(i % 3) * 0.1,
                    green: 0.21, blue: 0.90, alpha: fade * 0.80).setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: y, width: size, height: size)).fill()
        }
    }

    private static func makeShards(artwork: CompactFlowerArtwork) -> [Shard] {
        let size = artwork.size
        // Smaller cells make irregular petal-sized pieces, not the previous
        // conspicuous big tile chunks. Skip fully transparent cells to reduce
        // work every 60 Hz tick.
        let columns = 6, rows = 9
        var result: [Shard] = []

        func hasArtwork(_ points: [CGPoint]) -> Bool {
            let center = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                                 y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
            let samples = [center] + points.map { vertex in
                CGPoint(x: center.x * 0.5 + vertex.x * 0.5,
                        y: center.y * 0.5 + vertex.y * 0.5)
            }
            return samples.contains { point in
                let x = min(artwork.image.width - 1,
                    max(0, Int(point.x / size.width * CGFloat(artwork.image.width))))
                let y = min(artwork.image.height - 1,
                    max(0, Int((size.height - point.y) / size.height * CGFloat(artwork.image.height))))
                return artwork.alpha[(y * artwork.image.width + x) * 4 + 3] > 28
            }
        }

        for row in 0..<rows {
            for column in 0..<columns {
                let x0 = CGFloat(column) * size.width / CGFloat(columns)
                let x1 = CGFloat(column + 1) * size.width / CGFloat(columns)
                let y0 = CGFloat(row) * size.height / CGFloat(rows)
                let y1 = CGFloat(row + 1) * size.height / CGFloat(rows)
                let a = CGPoint(x: x0, y: y0), b = CGPoint(x: x1, y: y0)
                let c = CGPoint(x: x1, y: y1), d = CGPoint(x: x0, y: y1)
                let triangles = (row + column).isMultiple(of: 2)
                    ? [[a, b, c], [a, c, d]] : [[a, b, d], [b, c, d]]
                for (half, points) in triangles.enumerated() {
                    guard hasArtwork(points) else { continue }
                    let index = (row * columns + column) * 2 + half
                    let center = CGPoint(x: points.map(\.x).reduce(0, +) / 3,
                                         y: points.map(\.y).reduce(0, +) / 3)
                    let direction: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                    let bloom = row >= rows * 2 / 3
                    result.append(Shard(points: points, center: center,
                        velocityX: direction * CGFloat((bloom ? 74 : 35) + (index * 17) % 117),
                        velocityY: CGFloat((bloom ? 112 : 30) + (index * 23) % 90),
                        spin: direction * CGFloat(100 + (index * 41) % 370),
                        delay: Double(index % 5) * 0.013))
                }
            }
        }
        return result
    }
}
