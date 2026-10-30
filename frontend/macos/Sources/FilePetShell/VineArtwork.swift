import SwiftUI

/// 共用挂点，枝条和主藤使用同一条曲线，风摆时不会分离。
enum VineGeometry {
    static func height(at x: CGFloat, time: TimeInterval) -> CGFloat {
        CGFloat(VineLayout.height(at: Double(x), time: time))
    }

    static func branchX(_ index: Int) -> CGFloat { CGFloat(VineLayout.branchX(index)) }
}

struct VineArtwork: View {
    let time: TimeInterval
    let foreground: Bool

    var body: some View {
        Canvas { context, _ in
            if foreground {
                for leaf in Self.frontLeaves {
                    VinePainter.leaf(in: &context,
                                     at: CGPoint(x: leaf.x, y: VineGeometry.height(at: leaf.x, time: time)),
                                     size: leaf.size, angle: leaf.angle,
                                     variant: leaf.variant, time: time)
                }
            } else {
                for leaf in Self.backLeaves {
                    VinePainter.leaf(in: &context,
                                     at: CGPoint(x: leaf.x, y: VineGeometry.height(at: leaf.x, time: time)),
                                     size: leaf.size, angle: leaf.angle,
                                     variant: leaf.variant, time: time)
                }
                VinePainter.tendril(in: &context, x: 43, size: 39, angle: -58, time: time)
                VinePainter.tendril(in: &context, x: 143, size: 41, angle: 16, time: time)
                VinePainter.tendril(in: &context, x: 245, size: 31, angle: 156, time: time)
                VinePainter.tendril(in: &context, x: 371, size: 49, angle: -12, time: time)
                VinePainter.tendril(in: &context, x: 495, size: 35, angle: 143, time: time)
                VinePainter.trunk(in: &context, time: time)
            }
        }
        .frame(width: VineView.size.width, height: VineView.size.height)
        .allowsHitTesting(false)
    }

    private struct Leaf {
        let x: CGFloat
        let size: CGFloat
        let angle: Double
        let variant: Int
    }

    private static let backLeaves: [Leaf] = [
        .init(x: 71, size: 32, angle: -59, variant: 1),
        .init(x: 130, size: 41, angle: 147, variant: 2),
        .init(x: 207, size: 47, angle: -19, variant: 3),
        .init(x: 326, size: 39, angle: 131, variant: 4),
        .init(x: 438, size: 43, angle: -48, variant: 1),
        .init(x: 517, size: 53, angle: 126, variant: 2),
    ]

    private static let frontLeaves: [Leaf] = [
        .init(x: 96, size: 39, angle: 19, variant: 0),
        .init(x: 174, size: 55, angle: -36, variant: 2),
        .init(x: 265, size: 64, angle: 9, variant: 0),
        .init(x: 354, size: 43, angle: -43, variant: 3),
        .init(x: 411, size: 56, angle: 18, variant: 1),
        .init(x: 491, size: 65, angle: -23, variant: 2),
    ]
}

enum VinePainter {
    private static let ink = Color(red: 0.34, green: 0.27, blue: 0.12)
    private static let gold = Color(red: 0.88, green: 0.74, blue: 0.34)

    static func trunk(in context: inout GraphicsContext, time: TimeInterval) {
        let xs = stride(from: CGFloat(15), through: 535, by: 3).map { $0 }
        func thickness(_ x: CGFloat) -> CGFloat { 1.2 + pow(x / 520, 0.8) * 6 }
        var silhouette = Path()
        silhouette.move(to: CGPoint(x: xs[0], y: VineGeometry.height(at: xs[0], time: time) - thickness(xs[0])))
        for x in xs.dropFirst() {
            silhouette.addLine(to: CGPoint(x: x, y: VineGeometry.height(at: x, time: time) - thickness(x)))
        }
        for x in xs.reversed() {
            silhouette.addLine(to: CGPoint(x: x, y: VineGeometry.height(at: x, time: time) + thickness(x)))
        }
        silhouette.closeSubpath()
        context.fill(silhouette, with: .linearGradient(
            Gradient(colors: [Color(red: 0.88, green: 0.69, blue: 0.32),
                              Color(red: 0.58, green: 0.35, blue: 0.16),
                              Color(red: 0.40, green: 0.29, blue: 0.14)]),
            startPoint: CGPoint(x: 0, y: 91), endPoint: CGPoint(x: 0, y: 115)))
        context.stroke(silhouette, with: .color(ink), lineWidth: 1.35)

        var ribbon = Path()
        ribbon.addLines(xs.map {
            CGPoint(x: $0, y: VineGeometry.height(at: $0, time: time) + sin($0 / 19) * thickness($0) * 0.67)
        })
        context.stroke(ribbon, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
        context.stroke(ribbon, with: .color(Color(red: 0.92, green: 0.71, blue: 0.36)),
                       style: StrokeStyle(lineWidth: 2.3, lineCap: .round))

        var greenVine = Path()
        greenVine.addLines(xs.map {
            CGPoint(x: $0, y: VineGeometry.height(at: $0, time: time) + sin($0 / 28 + 1.3) * 6)
        })
        context.stroke(greenVine, with: .color(ink), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
        context.stroke(greenVine, with: .color(Color(red: 0.52, green: 0.61, blue: 0.24)),
                       style: StrokeStyle(lineWidth: 2.1, lineCap: .round))

        for x in stride(from: CGFloat(51), to: 530, by: 37) {
            let y = VineGeometry.height(at: x, time: time)
            var grain = Path()
            grain.move(to: CGPoint(x: x - 5, y: y + 1))
            grain.addQuadCurve(to: CGPoint(x: x + 10, y: y - 1), control: CGPoint(x: x + 2, y: y - 4))
            context.stroke(grain, with: .color(Color(red: 0.97, green: 0.82, blue: 0.46).opacity(0.8)),
                           style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
        }
    }

    /// 五裂葡萄叶：不规则锯齿轮廓、偏色叶面和放射叶脉。
    static func leaf(in context: inout GraphicsContext, at point: CGPoint,
                     size: CGFloat, angle: Double, variant: Int, time: TimeInterval) {
        var ctx = context
        ctx.translateBy(x: point.x, y: point.y)
        let flutter = sin(time * 1.48 + Double(variant) * 1.17 + Double(point.x) * 0.018) * 3.5
        ctx.rotate(by: .degrees(angle + flutter))
        ctx.scaleBy(x: size / 100, y: size / 100)

        var stem = Path()
        stem.move(to: .zero)
        stem.addQuadCurve(to: CGPoint(x: -3, y: -25), control: CGPoint(x: 5, y: -14))
        ctx.stroke(stem, with: .color(ink), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
        ctx.stroke(stem, with: .color(gold), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

        let outline = leafPath()
        let dark = variant % 3 == 0
            ? Color(red: 0.27, green: 0.43, blue: 0.28)
            : Color(red: 0.35, green: 0.49, blue: 0.25)
        let light = variant % 3 == 1
            ? Color(red: 0.76, green: 0.78, blue: 0.28)
            : Color(red: 0.65, green: 0.73, blue: 0.28)
        ctx.fill(outline, with: .linearGradient(Gradient(colors: [light, dark]),
                                               startPoint: CGPoint(x: -35, y: -77),
                                               endPoint: CGPoint(x: 35, y: -25)))
        // 用大色块分出叶片受光面，避免缩小时细节糊成一团。
        var lit = Path()
        lit.move(to: CGPoint(x: -3, y: -27))
        lit.addLines([CGPoint(x: -43, y: -37), CGPoint(x: -37, y: -48),
                      CGPoint(x: -46, y: -56), CGPoint(x: -21, y: -56),
                      CGPoint(x: -26, y: -79), CGPoint(x: -8, y: -68),
                      CGPoint(x: 0, y: -99), CGPoint(x: 10, y: -67)])
        lit.closeSubpath()
        var face = ctx
        face.clip(to: outline)
        face.fill(lit, with: .color(Color(red: 0.89, green: 0.82, blue: 0.30).opacity(0.42)))
        ctx.stroke(outline, with: .color(ink.opacity(0.94)),
                   style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round))

        let origin = CGPoint(x: -3, y: -27)
        var veins = Path()
        for end in [CGPoint(x: 0, y: -92), CGPoint(x: -24, y: -75),
                    CGPoint(x: -47, y: -54), CGPoint(x: -38, y: -33),
                    CGPoint(x: 30, y: -77), CGPoint(x: 47, y: -53), CGPoint(x: 39, y: -31)] {
            veins.move(to: origin)
            veins.addQuadCurve(to: end, control: CGPoint(x: end.x * 0.28, y: end.y + 11))
        }
        face.stroke(veins, with: .color(gold.opacity(0.88)),
                   style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
        var smallVeins = Path()
        for side in [-1.0, 1.0] {
            for n in 0..<3 {
                let y = CGFloat(-47 - n * 13)
                smallVeins.move(to: CGPoint(x: 0, y: y))
                smallVeins.addQuadCurve(to: CGPoint(x: side * Double(18 - n * 3), y: Double(y) - 9),
                                       control: CGPoint(x: side * 8, y: Double(y) - 7))
            }
        }
        face.stroke(smallVeins, with: .color(gold.opacity(0.56)), lineWidth: 0.85)
    }

    private static func leafPath() -> Path {
        // 宽叶裂片之间有凹口，锯齿只留在边缘，避免画成细长的枫叶。
        let points: [CGPoint] = [
            .init(x: -3, y: -27), .init(x: -16, y: -17), .init(x: -31, y: -20),
            .init(x: -29, y: -27), .init(x: -43, y: -28), .init(x: -39, y: -35),
            .init(x: -51, y: -38), .init(x: -43, y: -46), .init(x: -54, y: -50),
            .init(x: -50, y: -60), .init(x: -39, y: -60), .init(x: -41, y: -69),
            .init(x: -28, y: -66), .init(x: -22, y: -57), .init(x: -27, y: -77),
            .init(x: -20, y: -75), .init(x: -19, y: -86), .init(x: -9, y: -79),
            .init(x: -7, y: -91), .init(x: -1, y: -87), .init(x: 5, y: -101),
            .init(x: 12, y: -87), .init(x: 20, y: -89), .init(x: 19, y: -78),
            .init(x: 28, y: -81), .init(x: 25, y: -68), .init(x: 19, y: -60),
            .init(x: 38, y: -71), .init(x: 43, y: -62), .init(x: 38, y: -57),
            .init(x: 51, y: -57), .init(x: 48, y: -49), .init(x: 56, y: -45),
            .init(x: 44, y: -40), .init(x: 51, y: -33), .init(x: 39, y: -31),
            .init(x: 42, y: -23), .init(x: 30, y: -25), .init(x: 26, y: -17),
            .init(x: 13, y: -19), .init(x: 4, y: -29),
        ]
        var p = Path()
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        p.move(to: midpoint(points[points.count - 1], points[0]))
        for i in points.indices {
            p.addQuadCurve(to: midpoint(points[i], points[(i + 1) % points.count]), control: points[i])
        }
        p.closeSubpath()
        return p
    }

    /// 连续螺旋曲线，而非接在线尾的独立圆圈。
    static func tendril(in context: inout GraphicsContext, x: CGFloat, size: CGFloat,
                        angle: Double, time: TimeInterval) {
        var ctx = context
        ctx.translateBy(x: x, y: VineGeometry.height(at: x, time: time))
        ctx.rotate(by: .degrees(angle + sin(time * 1.2 + Double(x)) * 2.4))
        ctx.scaleBy(x: size / 50, y: size / 50)
        var p = Path()
        p.move(to: .zero)
        p.addCurve(to: CGPoint(x: 13, y: -31),
                   control1: CGPoint(x: -17, y: -15), control2: CGPoint(x: 12, y: -14))
        for step in 0...70 {
            let theta = Double(step) / 70 * .pi * 3.0
            let radius = 13 * (1 - Double(step) / 88)
            let point = CGPoint(x: 13 + sin(theta) * radius, y: -44 + cos(theta) * radius)
            p.addLine(to: point)
        }
        ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 3.4, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(Color(red: 0.73, green: 0.69, blue: 0.25)),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        ctx.translateBy(x: -0.45, y: -0.55)
        ctx.stroke(p, with: .color(gold.opacity(0.65)), style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
    }
}
