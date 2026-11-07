import AppKit

/// Hover and one click only inspect a flower. The native second-click event
/// is accepted only when it ends on painted pixels without a drag.
enum HarvestGesturePolicy {
    static func accepts(clickCount: Int, displacement: CGFloat,
                        onArtwork: Bool) -> Bool {
        clickCount >= 2 && displacement < 6 && onArtwork
    }
}

/// Original, deterministic native effect. It uses the same six-stage flower
/// atlas as the garden, rather than substituting the legacy static artwork.
@MainActor
enum HarvestSlashEffect {
    static let duration: TimeInterval = 1.48
    static let reducedDuration: TimeInterval = 0.16
    static let shatterAt: TimeInterval = 0.46
    static let floorY: CGFloat = 3

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
                      stemOpacity: broken ? max(0, 1 - CGFloat((t - shatterAt) / 0.40)) : 1,
                      shardOpacity: broken ? max(0, min(1, CGFloat((duration - t) / 0.45))) : 0,
                      finished: t >= duration)
    }

    /// Exact collision with y = floorY; subtle short rebound but no fragment
    /// penetrates the desktop baseline regardless of launch or crown height.
    static func verticalOffset(time: CGFloat, launch: CGFloat, centerY: CGFloat) -> CGFloat {
        let t = max(0, time)
        let gravity: CGFloat = 300
        let distanceToFloor = floorY - centerY
        let ballistic = launch * t - gravity * t * t
        if ballistic >= distanceToFloor { return ballistic }
        let impact = (launch + sqrt(launch * launch
            + 4 * gravity * max(0, centerY - floorY))) / (2 * gravity)
        let sinceImpact = max(0, t - impact)
        let rebound = max(0, (33 + launch * 0.12) * sinceImpact
                          - 260 * sinceImpact * sinceImpact)
        return distanceToFloor + rebound
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
            let alpha = max(0, 1 - CGFloat(age / reducedDuration))
            if alpha > 0 {
                NSColor(calibratedRed: 0.55, green: 0.32, blue: 0.90,
                        alpha: alpha * 0.22).setFill()
                NSBezierPath(ovalIn: g.rect.insetBy(dx: -3, dy: -3)).fill()
            }
            return
        }
        if state.finished { return }

        if age >= shatterAt {
            if state.shardOpacity > 0 {
                drawFragments(rect: g.rect, stage: stage, age: age,
                              opacity: state.shardOpacity, context: ctx)
            }
            drawGroundSparks(centerX: g.rect.midX, age: age)
            drawImpactFlash(at: CGPoint(x: g.rect.midX, y: g.rect.midY), age: age)
        } else {
            drawCutScars(around: CGPoint(x: g.rect.midX, y: g.rect.midY),
                         flowerWidth: g.rect.width, age: age)
        }
        drawSwordStreaks(around: CGPoint(x: g.rect.midX, y: g.rect.midY),
                         width: max(210, g.rect.width * 4.4), age: age)
    }

    private static func spriteHasPixels(_ points: [CGPoint], rect: CGRect,
                                        sprite: DeadlineFlowerMotion.Sprite) -> Bool {
        let middle = CGPoint(x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                             y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
        let samples = [middle] + points.map { point in
            CGPoint(x: (middle.x + point.x) * 0.5, y: (middle.y + point.y) * 0.5)
        }
        return samples.contains { point in
            let x = min(sprite.pixelsWide - 1,
                max(0, Int((point.x - rect.minX) / rect.width * CGFloat(sprite.pixelsWide))))
            let y = min(sprite.pixelsHigh - 1,
                max(0, Int((rect.maxY - point.y) / rect.height * CGFloat(sprite.pixelsHigh))))
            return sprite.alpha[y * sprite.pixelsWide + x] > 22
        }
    }

    /// Forty triangular pieces, culled against the actual bloom alpha mask.
    /// Different launch velocities and tiny delays remove the tiled-grid look.
    private static func drawFragments(rect: CGRect, stage: DeadlineStage,
                                      age: TimeInterval, opacity: CGFloat,
                                      context: CGContext) {
        guard DeadlineFlowerMotion.heads.indices.contains(stage.rawValue) else { return }
        let sprite = DeadlineFlowerMotion.heads[stage.rawValue]
        let elapsed = CGFloat(max(0, age - shatterAt))
        let columns = 5, rows = 4

        for row in 0..<rows {
            for column in 0..<columns {
                let x0 = rect.minX + rect.width * CGFloat(column) / CGFloat(columns)
                let x1 = rect.minX + rect.width * CGFloat(column + 1) / CGFloat(columns)
                let y0 = rect.minY + rect.height * CGFloat(row) / CGFloat(rows)
                let y1 = rect.minY + rect.height * CGFloat(row + 1) / CGFloat(rows)
                let a = CGPoint(x: x0, y: y0), b = CGPoint(x: x1, y: y0)
                let c = CGPoint(x: x1, y: y1), d = CGPoint(x: x0, y: y1)
                let triangles = (row + column).isMultiple(of: 2)
                    ? [[a, b, c], [a, c, d]] : [[a, b, d], [b, c, d]]
                for (half, points) in triangles.enumerated() {
                    guard spriteHasPixels(points, rect: rect, sprite: sprite) else { continue }
                    let i = (row * columns + column) * 2 + half
                    let wait = CGFloat(i % 4) * 0.012
                    let t = max(0, elapsed - wait)
                    let center = CGPoint(x: points.map(\.x).reduce(0, +) / 3,
                                         y: points.map(\.y).reduce(0, +) / 3)
                    let direction: CGFloat = i.isMultiple(of: 2) ? -1 : 1
                    let vx = direction * CGFloat(36 + (i * 37) % 112)
                    let lift = CGFloat(54 + (i * 19) % 125)
                    let dx = vx * t
                    let dy = verticalOffset(time: t, launch: lift, centerY: center.y)
                    let turn = direction * CGFloat(2.4 + Double((i * 13) % 7) * 0.31) * t

                    context.saveGState()
                    context.setAlpha(opacity)
                    context.translateBy(x: center.x + dx, y: center.y + dy)
                    context.rotate(by: turn)
                    context.translateBy(x: -center.x, y: -center.y)
                    let shape = CGMutablePath()
                    for (index, point) in points.enumerated() {
                        if index == 0 { shape.move(to: point) } else { shape.addLine(to: point) }
                    }
                    shape.closeSubpath()
                    context.addPath(shape)
                    context.clip()
                    sprite.image.draw(in: rect, from: .zero,
                                      operation: .sourceOver, fraction: 1)
                    context.restoreGState()
                }
            }
        }
    }

    private static let slashStarts: [TimeInterval] =
        [0.025, 0.084, 0.146, 0.211, 0.277, 0.343, 0.408]
    private static let angles: [CGFloat] = [0.54, -0.60, 0.27, -0.45, 0.72, -0.28, 0.55]

    /// Direction-reversing comet strokes with a purple outer contour: readable
    /// on a bright desktop. Their 210pt+ flight lives on the expanded overlay.
    private static func drawSwordStreaks(around center: CGPoint, width: CGFloat,
                                         age: TimeInterval) {
        for (i, start) in slashStarts.enumerated() {
            let t = age - start
            guard t >= 0 && t < 0.17 else { continue }
            let progress = CGFloat(min(1, t / 0.105))
            let fade = CGFloat(min(1, t / 0.022)) * CGFloat(max(0, 1 - t / 0.17))
            let direction: CGFloat = i.isMultiple(of: 2) ? 1 : -1
            let ux = cos(angles[i]) * direction
            let uy = sin(angles[i]) * direction
            let position = -width / 2 + width * progress
            let tail = min(96, CGFloat(t / 0.105) * width * 0.63 + 8)
            let offset = CGFloat(i % 3 - 1) * 5
            let tip = CGPoint(x: center.x + ux * position,
                              y: center.y + uy * position + offset)
            let back = CGPoint(x: tip.x - ux * tail, y: tip.y - uy * tail)
            let blade = NSBezierPath()
            blade.move(to: back)
            blade.line(to: tip)
            blade.lineCapStyle = .round
            let violet = i.isMultiple(of: 2)
            let tint = violet
                ? NSColor(calibratedRed: 0.34, green: 0.09, blue: 0.73, alpha: 0.23 * fade)
                : NSColor(calibratedRed: 0.09, green: 0.49, blue: 0.72, alpha: 0.23 * fade)
            tint.setStroke()
            blade.lineWidth = 21
            blade.stroke()
            (violet
                ? NSColor(calibratedRed: 0.48, green: 0.17, blue: 0.88, alpha: 0.74 * fade)
                : NSColor(calibratedRed: 0.17, green: 0.64, blue: 0.91, alpha: 0.74 * fade)
            ).setStroke()
            blade.lineWidth = 8
            blade.stroke()
            NSColor(calibratedRed: 0.97, green: 0.76, blue: 1, alpha: fade).setStroke()
            blade.lineWidth = 2.5
            blade.stroke()
            NSColor(calibratedWhite: 1, alpha: fade).setStroke()
            blade.lineWidth = 1
            blade.stroke()
            NSColor(calibratedRed: 0.56, green: 0.20, blue: 0.84, alpha: fade).setFill()
            NSBezierPath(ovalIn: CGRect(x: tip.x - 2.5, y: tip.y - 2.5,
                                       width: 5, height: 5)).fill()
        }
    }

    private static func drawCutScars(around center: CGPoint,
                                     flowerWidth: CGFloat, age: TimeInterval) {
        for (i, start) in slashStarts.enumerated() {
            let elapsed = age - start
            guard elapsed > 0.08 && elapsed < 0.29 else { continue }
            let alpha = CGFloat((0.29 - elapsed) / 0.21) * 0.58
            let half = max(18, flowerWidth * 0.48)
            let offset = CGFloat(i % 3 - 1) * 5
            let scar = NSBezierPath()
            scar.move(to: CGPoint(x: center.x - cos(angles[i]) * half,
                                  y: center.y - sin(angles[i]) * half + offset))
            scar.line(to: CGPoint(x: center.x + cos(angles[i]) * half,
                                  y: center.y + sin(angles[i]) * half + offset))
            scar.lineWidth = 1
            NSColor(calibratedRed: 0.45, green: 0.13, blue: 0.81, alpha: alpha).setStroke()
            scar.stroke()
        }
    }

    private static func drawImpactFlash(at center: CGPoint, age: TimeInterval) {
        let time = age - shatterAt
        guard time >= 0 && time < 0.24 else { return }
        let alpha = CGFloat(1 - time / 0.24)
        let radius = CGFloat(7 + time * 122)
        for i in 0..<12 {
            let a = CGFloat(i) * .pi / 6
            let beam = NSBezierPath()
            beam.move(to: CGPoint(x: center.x + cos(a) * radius * 0.20,
                                  y: center.y + sin(a) * radius * 0.20))
            beam.line(to: CGPoint(x: center.x + cos(a) * radius,
                                  y: center.y + sin(a) * radius))
            beam.lineWidth = i.isMultiple(of: 3) ? 2.7 : 1.2
            NSColor(calibratedRed: 0.53, green: 0.14, blue: 0.89,
                    alpha: alpha * 0.72).setStroke()
            beam.stroke()
        }
        NSColor(calibratedRed: 0.83, green: 0.48, blue: 1,
                alpha: alpha * 0.50).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - radius * 0.35,
                                   y: center.y - radius * 0.35,
                                   width: radius * 0.70, height: radius * 0.70)).fill()
    }

    private static func drawGroundSparks(centerX: CGFloat, age: TimeInterval) {
        let time = age - shatterAt - 0.38
        guard time > 0 && time < 0.61 else { return }
        let fade = CGFloat(1 - time / 0.61)
        let span = CGFloat(14 + time * 135)
        let ring = NSBezierPath(ovalIn: CGRect(x: centerX - span / 2,
            y: floorY, width: span, height: 5 + CGFloat(time * 2)))
        ring.lineWidth = 1.4
        NSColor(calibratedRed: 0.52, green: 0.23, blue: 0.85,
                alpha: fade * 0.60).setStroke()
        ring.stroke()
        for i in 0..<18 {
            let sign: CGFloat = i.isMultiple(of: 2) ? 1 : -1
            let x = centerX + sign * CGFloat(time) * CGFloat(40 + i * 7)
            let y = floorY + abs(sin(CGFloat(i) * 2.1)) * CGFloat(5 + (1 - time / 0.61) * 17)
            NSColor(calibratedRed: 0.59, green: 0.28, blue: 0.95,
                    alpha: fade * 0.80).setFill()
            let size: CGFloat = i.isMultiple(of: 5) ? 3 : 1.6
            NSBezierPath(ovalIn: CGRect(x: x, y: y, width: size, height: size)).fill()
        }
    }
}
