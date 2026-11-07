import AppKit

/// Mouse semantics are pure/testable: hover and one click inspect the flower,
/// while a true second click with no drag completes the task.
enum HarvestGesturePolicy {
    static func accepts(clickCount: Int, displacement: CGFloat,
                        onArtwork: Bool) -> Bool {
        clickCount >= 2 && displacement < 6 && onArtwork
    }
}

/// Original, time-limited harvest VFX: crossing luminous cuts, a sliced
/// blossom, then pixel-textured shards falling to the desktop baseline.
/// No third-party game assets, shaders, particle engines or idle timers.
@MainActor
enum HarvestSlashEffect {
    static let duration: TimeInterval = 1.12
    static let reducedDuration: TimeInterval = 0.16
    static let shatterAt: TimeInterval = 0.31

    struct Sample: Equatable {
        let showHead: Bool
        let stemOpacity: CGFloat
        let shardOpacity: CGFloat
        let finished: Bool
    }

    static func sample(at seconds: TimeInterval, reduceMotion: Bool) -> Sample {
        let t = max(0, seconds)
        if reduceMotion {
            return Sample(showHead: t < 0.08,
                          stemOpacity: max(0, 1 - CGFloat(t / reducedDuration)),
                          shardOpacity: 0, finished: t >= reducedDuration)
        }
        let broken = t >= shatterAt
        return Sample(showHead: !broken,
                      stemOpacity: broken ? max(0, 1 - CGFloat((t - shatterAt) / 0.50)) : 1,
                      shardOpacity: broken ? max(0, min(1, CGFloat((duration - t) / 0.36))) : 0,
                      finished: t >= duration)
    }

    static func draw(in bounds: NSRect, stage: DeadlineStage,
                     artwork: CompactFlowerArtwork, crownScale: CGFloat,
                     pose: DeadlineFlowerArrangement.PlantPose,
                     age: TimeInterval, reduceMotion: Bool) {
        let state = sample(at: age, reduceMotion: reduceMotion)
        guard let g = DeadlineFlowerMotion.geometry(
            bounds: bounds, artwork: artwork, stage: stage,
            stem: 0, head: 0, crownScale: crownScale, pose: pose
        ), let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.current?.imageInterpolation = .none

        if state.stemOpacity > 0 {
            ctx.saveGState()
            ctx.setAlpha(state.stemOpacity)
            _ = DeadlineFlowerMotion.draw(bounds: bounds, artwork: artwork,
                stage: stage, stem: 0, head: 0, petals: (0, 0, 0),
                crownScale: crownScale, pose: pose, showHead: state.showHead)
            ctx.restoreGState()
        }
        if reduceMotion {
            // Accessibility: a single soft stationary glow, then disappear.
            let alpha = max(0, 1 - CGFloat(age / reducedDuration))
            if alpha > 0 {
                NSColor(calibratedRed: 0.62, green: 0.59, blue: 0.90,
                        alpha: alpha * 0.25).setFill()
                NSBezierPath(ovalIn: g.rect.insetBy(dx: -4, dy: -4)).fill()
            }
            return
        }

        if age >= shatterAt, state.shardOpacity > 0 {
            drawFragments(rect: g.rect, stage: stage, age: age,
                          opacity: state.shardOpacity, context: ctx)
        }
        drawSwordStreaks(around: CGPoint(x: g.rect.midX, y: g.rect.midY),
                         width: max(55, g.rect.width * 2.8), age: age)
    }

    /// Twelve pieces of the *existing pixel blossom* break away independently.
    /// Only image regions are clipped and moved; no stretched or blurred PNG.
    private static func drawFragments(rect: CGRect, stage: DeadlineStage,
                                      age: TimeInterval, opacity: CGFloat,
                                      context: CGContext) {
        guard DeadlineFlowerMotion.heads.indices.contains(stage.rawValue) else { return }
        let sprite = DeadlineFlowerMotion.heads[stage.rawValue]
        let t = CGFloat(max(0, age - shatterAt))
        let pivot = CGPoint(x: rect.midX, y: rect.midY)
        for row in 0..<3 {
            for col in 0..<4 {
                let i = row * 4 + col
                let piece = CGRect(x: rect.minX + rect.width * CGFloat(col) / 4,
                                   y: rect.minY + rect.height * CGFloat(row) / 3,
                                   width: rect.width / 4 + 0.15,
                                   height: rect.height / 3 + 0.15)
                let side = CGFloat(col) - 1.5
                let scatter = CGFloat((i * 7) % 5) - 2
                let dx = (side * 19 + scatter * 2.6) * t
                let lift = CGFloat((i * 11) % 7) * 1.9 + 13
                let dy = lift * t - 125 * t * t
                let angle = (side * 0.68 + scatter * 0.17) * t
                context.saveGState()
                context.setAlpha(opacity)
                context.translateBy(x: dx + pivot.x, y: dy + pivot.y)
                context.rotate(by: angle)
                context.translateBy(x: -pivot.x, y: -pivot.y)
                context.clip(to: piece)
                sprite.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                context.restoreGState()
            }
        }
        // Brief sparks settle where fragments meet the desktop edge.
        if t > 0.34 && t < 0.68 {
            let opacity = (0.68 - t) / 0.34 * 0.8
            NSColor(calibratedRed: 0.89, green: 0.68, blue: 0.94, alpha: opacity).setFill()
            for i in 0..<6 {
                let x = pivot.x + CGFloat(i - 3) * 6
                let y = CGFloat((i * 5) % 4) + 1
                NSBezierPath(rect: CGRect(x: x, y: y, width: 2, height: 2)).fill()
            }
        }
    }

    /// Four fast alternating diagonal cuts, each with a tinted halo and bright
    /// core. Beams have pauses and different directions, never a continuous
    /// rotation or full-screen flashing overlay.
    private static func drawSwordStreaks(around center: CGPoint, width: CGFloat,
                                         age: TimeInterval) {
        let directions: [(CGFloat, CGFloat, TimeInterval)] = [
            (0.66, -1, 0.045), (-0.73, 1, 0.125),
            (0.42, -1, 0.207), (-0.56, 1, 0.275)
        ]
        for (i, slash) in directions.enumerated() {
            let elapsed = age - slash.2
            guard elapsed >= 0 && elapsed < 0.145 else { continue }
            let life = CGFloat(elapsed / 0.145)
            let alpha = pow(1 - life, 1.35)
            let normal = CGPoint(x: -sin(slash.0), y: cos(slash.0))
            let offset = (life - 0.5) * 23 * slash.1
            let cx = center.x + normal.x * offset
            let cy = center.y + normal.y * offset
            let length = width * (0.73 + life * 0.27)
            let dx = cos(slash.0) * length / 2
            let dy = sin(slash.0) * length / 2
            let a = CGPoint(x: cx - dx, y: cy - dy)
            let b = CGPoint(x: cx + dx, y: cy + dy)
            let trail = NSBezierPath()
            trail.move(to: a)
            trail.line(to: b)
            trail.lineCapStyle = .round
            let violet = i.isMultiple(of: 2)
            let halo = violet
                ? NSColor(calibratedRed: 0.70, green: 0.36, blue: 0.99, alpha: 0.32 * alpha)
                : NSColor(calibratedRed: 0.26, green: 0.78, blue: 0.99, alpha: 0.32 * alpha)
            halo.setStroke()
            trail.lineWidth = 8
            trail.stroke()
            (violet
                ? NSColor(calibratedRed: 0.86, green: 0.66, blue: 1, alpha: 0.90 * alpha)
                : NSColor(calibratedRed: 0.69, green: 0.94, blue: 1, alpha: 0.90 * alpha)
            ).setStroke()
            trail.lineWidth = 3
            trail.stroke()
            NSColor(calibratedWhite: 1, alpha: 0.95 * alpha).setStroke()
            trail.lineWidth = 1.25
            trail.stroke()
            NSColor(calibratedWhite: 1, alpha: 0.72 * alpha).setFill()
            NSBezierPath(rect: CGRect(x: b.x - 1, y: b.y - 1, width: 2, height: 2)).fill()
        }
    }
}
