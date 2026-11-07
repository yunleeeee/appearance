import AppKit

/// A short, self-contained particle/sword-light scene. It owns no deadline data:
/// the completion is committed as soon as the second click is received.
enum HarvestSlashTimeline {
    static let fractureTime: TimeInterval = 0.34

    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.22 : 1.42
    }

    static func fallOffset(elapsed: TimeInterval, launch: CGFloat, centerY: CGFloat) -> CGFloat {
        let time = CGFloat(max(0, elapsed))
        // In the local panel coordinate system the desktop floor is y = 0.
        return max(7 - centerY, launch * time - 350 * time * time)
    }

    static func opacity(elapsed: TimeInterval) -> CGFloat {
        max(0, min(1, CGFloat((1.38 - elapsed) / 0.47)))
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
        CGSize(width: max(240, artwork.size.width + 170),
               height: max(215, artwork.size.height + 70))
    }

    init(artwork: CompactFlowerArtwork, reduceMotion: Bool) {
        self.artwork = artwork
        self.reduceMotion = reduceMotion
        image = NSImage(cgImage: artwork.image, size: artwork.size)
        shards = Self.makeShards(size: artwork.size)
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
            // The first cuts cross a still-recognizable silhouette before it
            // breaks into independent triangular pieces.
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            drawShards(in: imageRect, graphics: graphics)
            drawFloorSparks(below: imageRect)
        }
        drawSlashes(around: imageRect)
        drawFractureFlash(at: CGPoint(x: imageRect.midX, y: imageRect.minY + imageRect.height * 0.65))
    }

    private func drawShards(in imageRect: CGRect, graphics: NSGraphicsContext) {
        let t = max(0, elapsed - HarvestSlashTimeline.fractureTime)
        let fade = HarvestSlashTimeline.opacity(elapsed: elapsed)
        guard fade > 0 else { return }
        for shard in shards {
            let center = CGPoint(x: imageRect.minX + shard.center.x,
                                 y: imageRect.minY + shard.center.y)
            let dx = shard.velocityX * CGFloat(t)
            let dy = HarvestSlashTimeline.fallOffset(elapsed: t,
                launch: shard.velocityY, centerY: center.y)
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: center.x + dx, yBy: center.y + dy)
            transform.rotate(byDegrees: shard.spin * CGFloat(t))
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

    private func drawSlashes(around imageRect: CGRect) {
        let starts: [TimeInterval] = [0.015, 0.088, 0.165, 0.242, 0.315, 0.394]
        for (index, startTime) in starts.enumerated() {
            let age = elapsed - startTime
            guard age >= 0 && age < 0.19 else { continue }
            let progress = min(1, age / 0.092)
            let fade = CGFloat(max(0, 1 - age / 0.19))
            let forward: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let angle = CGFloat([24, -30, 37, -22, 16, -42][index]) * .pi / 180
            let length = max(175, imageRect.width * 2.7)
            let vx = cos(angle) * length / 2 * forward
            let vy = sin(angle) * length / 2 * forward
            let center = CGPoint(x: imageRect.midX,
                y: imageRect.minY + imageRect.height * CGFloat(0.48 + Double(index % 3) * 0.13))
            let from = CGPoint(x: center.x - vx, y: center.y - vy)
            let to = CGPoint(x: from.x + vx * 2 * CGFloat(progress),
                             y: from.y + vy * 2 * CGFloat(progress))
            let line = NSBezierPath()
            line.move(to: from)
            line.line(to: to)
            line.lineCapStyle = .round

            for (width, color) in [
                (CGFloat(19), NSColor(calibratedRed: 0.36, green: 0.15, blue: 1, alpha: 0.20 * fade)),
                (CGFloat(8), NSColor(calibratedRed: 0.59, green: 0.36, blue: 1, alpha: 0.76 * fade)),
                (CGFloat(2.6), NSColor(calibratedRed: 0.98, green: 0.96, blue: 1, alpha: 0.98 * fade)),
            ] {
                line.lineWidth = width
                color.setStroke()
                line.stroke()
            }

            let spark = NSBezierPath(ovalIn: CGRect(x: to.x - 3.5, y: to.y - 3.5, width: 7, height: 7))
            NSColor(calibratedRed: 0.94, green: 0.87, blue: 1, alpha: fade).setFill()
            spark.fill()
        }
    }

    private func drawFractureFlash(at center: CGPoint) {
        let t = elapsed - HarvestSlashTimeline.fractureTime
        guard t >= 0 && t < 0.25 else { return }
        let spread = CGFloat(14 + t * 130)
        let alpha = CGFloat(max(0, 0.48 * (1 - t / 0.25)))
        NSColor(calibratedRed: 0.58, green: 0.34, blue: 1, alpha: alpha).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - spread / 2,
                                   y: center.y - spread / 2, width: spread, height: spread)).fill()
        // Short starburst lines emphasize the frame where the sprite fractures.
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6
            let inner: CGFloat = spread * 0.32
            let outer: CGFloat = spread * (i.isMultiple(of: 3) ? 1.12 : 0.76)
            let path = NSBezierPath()
            path.move(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner))
            path.line(to: CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer))
            path.lineWidth = i.isMultiple(of: 3) ? 2 : 1
            NSColor(calibratedRed: 0.88, green: 0.77, blue: 1, alpha: alpha).setStroke()
            path.stroke()
        }
    }

    private func drawFloorSparks(below imageRect: CGRect) {
        let t = elapsed - 0.67
        guard t > 0 && t < 0.71 else { return }
        let fade = CGFloat(1 - t / 0.71)
        for i in 0..<19 {
            let angle = CGFloat(i) * 2.39996
            let distance = CGFloat(t * (45 + Double(i % 7) * 13))
            let x = imageRect.midX + sin(angle) * distance
            let y = CGFloat(4 + (i % 3) * 3) + abs(cos(angle)) * CGFloat((1 - t / 0.71) * 14)
            let size: CGFloat = i.isMultiple(of: 4) ? 3 : 1.5
            NSColor(calibratedRed: 0.68, green: 0.49, blue: 1, alpha: fade * 0.85).setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: y, width: size, height: size)).fill()
        }
    }

    private static func makeShards(size: CGSize) -> [Shard] {
        var result: [Shard] = []
        let columns = 4, rows = 5
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
                    let index = (row * columns + column) * 2 + half
                    let center = CGPoint(x: points.map(\.x).reduce(0, +) / 3,
                                         y: points.map(\.y).reduce(0, +) / 3)
                    // Fixed pseudo-random velocities: no visual jump between redraws.
                    let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                    result.append(Shard(points: points, center: center,
                        velocityX: side * CGFloat(24 + (index * 17) % 95),
                        velocityY: CGFloat(36 + (index * 23) % 100),
                        spin: side * CGFloat(80 + (index * 41) % 285)))
                }
            }
        }
        return result
    }
}
