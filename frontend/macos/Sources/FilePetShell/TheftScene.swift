import SwiftUI

private extension CorePoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// The falling bunch settles onto the shoulder in Jerry's original run frames.
/// Fruit is drawn behind the body, with every pose using its own support point.
struct TheftScene: View {
    let category: String
    let origin: CGPoint
    let elapsed: TimeInterval
    var reducedMotion = false

    var body: some View {
        GeometryReader { geometry in
            let state = TheftChoreography.state(at: elapsed, size: CoreSize(width: Double(geometry.size.width), height: Double(geometry.size.height)),
                                                origin: CorePoint(x: Double(origin.x), y: Double(origin.y)),
                                                reducedMotion: reducedMotion)
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    // A short floor puff marks the feet taking the load. It
                    // stays below the body so the shoulder contact stays clear.
                    if state.catchImpact > 0 && !reducedMotion {
                        for side in [-1.0, 1.0] {
                            let spread = (1 - state.catchImpact) * 19
                            let x = CGFloat(state.mouseOrigin.x + 79 + side * (14 + spread))
                            let y = CGFloat(state.floorY - 4 - (1 - state.catchImpact) * 6)
                            let width = CGFloat(5 + (1 - state.catchImpact) * 10)
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: width, height: width * 0.4)),
                                         with: .color(Color(red: 0.76, green: 0.65, blue: 0.43)
                                            .opacity(state.catchImpact * 0.32)))
                        }
                    }
                    if state.dust > 0 && !reducedMotion {
                        for i in 0..<4 {
                            let phase = (elapsed * 3 + Double(i) * 0.23).truncatingRemainder(dividingBy: 1)
                            let radius = 2 + phase * 4
                            let x = CGFloat(state.mouseOrigin.x) - CGFloat(phase) * 40 - CGFloat(i) * 5
                            let y = CGFloat(state.floorY) - CGFloat(phase) * 9
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius)),
                                         with: .color(Color(red: 0.76, green: 0.65, blue: 0.43)
                                            .opacity(state.dust * (1 - phase) * 0.26)))
                        }
                    }
                    if elapsed > 0.98 && elapsed < 2.06 && !reducedMotion {
                        for i in 0..<3 {
                            let x = CGFloat(state.grapeCenter.x) - 18 + CGFloat(i) * 18
                            let y = CGFloat(state.grapeCenter.y) - 59 - CGFloat(i % 2) * 9
                            var streak = Path()
                            streak.move(to: CGPoint(x: x, y: y))
                            streak.addLine(to: CGPoint(x: x, y: y - 16))
                            context.stroke(streak, with: .color(GrapePalette.highlight(for: category).opacity(0.48)),
                                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        }
                    }
                }

                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        var stem = Path()
                        stem.move(to: CGPoint(x: 32, y: -7))
                        stem.addQuadCurve(to: CGPoint(x: 31, y: 10), control: CGPoint(x: 36, y: -1))
                        context.stroke(stem, with: .color(Color(red: 0.30, green: 0.24, blue: 0.11)),
                                       style: StrokeStyle(lineWidth: 3.4, lineCap: .round))
                        context.stroke(stem, with: .color(Color(red: 0.62, green: 0.57, blue: 0.23)),
                                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                    GrapeClusterView(branch: VineBranch(id: category, count: 12), growth: nil, reduceMotion: true)
                }
                .frame(width: 64, height: 88)
                .scaleEffect(x: CGFloat(state.grapeScale.width), y: CGFloat(state.grapeScale.height))
                .rotationEffect(.degrees(state.grapeRotation))
                .position(state.grapeCenter.cgPoint)
                .opacity(state.grapeOpacity)

                ThievingMouseView(elapsed: state.mouseElapsed, reducedMotion: reducedMotion, facingRight: true)
                    .frame(width: OriginalCharacterMedia.mouseSize.width,
                           height: OriginalCharacterMedia.mouseSize.height)
                    .offset(x: CGFloat(state.mouseOrigin.x), y: CGFloat(state.mouseOrigin.y))
                    .opacity(state.mouseOpacity)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("成熟葡萄落到杰瑞肩背上，杰瑞背着葡萄跑向屏幕右侧")
    }
}
