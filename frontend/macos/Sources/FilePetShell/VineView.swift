import SwiftUI

/// 葡萄藤自动淡出；花朵设计预览始终留在独立的展示层。
struct VineView: View {
    @ObservedObject var model: VineModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 520, height: 250)

    private var animating: Bool {
        model.phase != .hidden && !reduceMotion
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { timeline in
                let time = animating ? timeline.date.timeIntervalSinceReferenceDate : 0
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        VineArtwork(time: time, foreground: false)

                        ForEach(Array(model.branches.enumerated()), id: \.element.id) { index, branch in
                            let x = VineGeometry.branchX(index)
                            let y = VineGeometry.height(at: x, time: time)
                            VineBranchView(
                                branch: branch,
                                index: index,
                                time: time,
                                growth: model.latestGrowth,
                                reduceMotion: reduceMotion,
                                hidesGrapes: model.activeTheft?.category == branch.id
                            )
                            .position(x: x, y: y + 53)
                        }

                        VineArtwork(time: time, foreground: true)
                    }
                    .frame(width: Self.size.width, height: Self.size.height)
                    .opacity(model.isVisible ? 1 : 0)
                    .animation(.easeInOut(duration: reduceMotion ? 0.15 : (model.isVisible ? 0.45 : 0.5)),
                               value: model.isVisible)

                    DeadlineFlowerPreviewView(time: time)
                }
                .frame(width: Self.size.width, height: Self.size.height)
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("文件分类葡萄藤；常驻花朵设计预览：含苞、待放、初绽、盛放、萎垂、凋零")
        .accessibilityValue(model.branches.map { "\(model.displayName(for: $0.id))，累计分类反馈 \(model.count(for: $0.id)) 次" }.joined(separator: "；"))
    }
}

private struct VineBranchView: View {
    let branch: VineBranch
    let index: Int
    let time: TimeInterval
    let growth: VineGrowth?
    let reduceMotion: Bool
    let hidesGrapes: Bool

    @State private var extended = false
    @State private var weight = false

    private var newBranch: Bool {
        growth?.category == branch.id && growth?.grapeIndex == 0
    }

    var body: some View {
        let swing = sin(time * 1.32 + Double(index) * 0.82) * 2.0
        ZStack(alignment: .topLeading) {
            BranchStemShape(bend: CGFloat(index % 2 == 0 ? 1 : -1))
                .trim(from: 0, to: extended ? 1 : 0)
                .stroke(Color(red: 0.34, green: 0.25, blue: 0.12),
                        style: StrokeStyle(lineWidth: 4.4, lineCap: .round, lineJoin: .round))
                .frame(width: 64, height: 34)
            BranchStemShape(bend: CGFloat(index % 2 == 0 ? 1 : -1))
                .trim(from: 0, to: extended ? 1 : 0)
                .stroke(Color(red: 0.76, green: 0.61, blue: 0.25),
                        style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                .frame(width: 64, height: 34)

            GrapeClusterView(branch: branch, growth: growth, reduceMotion: reduceMotion)
                .frame(width: 64, height: 88)
                .offset(y: 24)
                .opacity(hidesGrapes ? 0 : 1)

            // 每串自己的小叶随新分枝展开，叶柄与葡萄的悬挂点连在一起。
            Canvas { context, _ in
                VinePainter.leaf(in: &context, at: CGPoint(x: 35, y: 13),
                                 size: 31, angle: index % 2 == 0 ? 53 : -49,
                                 variant: index, time: time)
            }
            .frame(width: 64, height: 44)
            .scaleEffect(extended ? 1 : 0.05, anchor: UnitPoint(x: 0.55, y: 0.30))
        }
        .frame(width: 64, height: 112, alignment: .topLeading)
        .rotationEffect(.degrees(swing + (weight ? 2.2 : 0)), anchor: .top)
        .offset(y: weight ? 2 : 0)
        .onAppear {
            if newBranch && !reduceMotion {
                withAnimation(.easeOut(duration: 0.38)) { extended = true }
            } else {
                extended = true
            }
        }
        .task(id: growth?.sequence) {
            guard !reduceMotion, growth?.category == branch.id, branch.count > 1 else { return }
            withAnimation(.easeOut(duration: 0.14)) { weight = true }
            do { try await Task.sleep(nanoseconds: 140_000_000) } catch { return }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.40)) {
                weight = false
            }
        }
    }
}

private struct BranchStemShape: Shape {
    let bend: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        path.move(to: CGPoint(x: x - 7 * bend, y: 0))
        path.addCurve(to: CGPoint(x: x + 1, y: rect.height),
                      control1: CGPoint(x: x + 12 * bend, y: 8),
                      control2: CGPoint(x: x - 10 * bend, y: 19))
        path.move(to: CGPoint(x: x, y: rect.height - 9))
        path.addQuadCurve(to: CGPoint(x: x - 13, y: rect.height + 5),
                          control: CGPoint(x: x - 12, y: rect.height - 8))
        path.move(to: CGPoint(x: x + 1, y: rect.height - 12))
        path.addQuadCurve(to: CGPoint(x: x + 13, y: rect.height + 3),
                          control: CGPoint(x: x + 12, y: rect.height - 12))
        return path
    }
}

struct GrapeClusterView: View {
    let branch: VineBranch
    let growth: VineGrowth?
    let reduceMotion: Bool

    /// 先形成三角骨架，再补上后排果实；满串呈上宽下尖的自然轮廓。
    private static let berries: [(x: CGFloat, y: CGFloat, size: CGFloat, depth: Double)] = [
        (32, 17, 20, 0.03), (20, 25, 21, 0.12), (44, 27, 20, 0.18),
        (31, 37, 22, 0.03), (14, 42, 20, 0.06), (49, 44, 20, 0.12),
        (22, 55, 21, 0.02), (40, 57, 22, 0.05), (31, 72, 21, 0.02),
        (34, 9, 19, 0.18), (17, 15, 19, 0.11), (48, 17, 19, 0.15),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 后排先绘制，保证果粒相互遮挡的层次始终正确。
            ForEach(Array((0..<min(branch.count, VineModel.grapesPerBranchLimit)).sorted {
                Self.berries[$0].depth > Self.berries[$1].depth
            }), id: \.self) { index in
                let berry = Self.berries[index]
                GrapeBerryView(
                    category: branch.id,
                    variation: index,
                    depth: berry.depth,
                    shouldGrow: growth?.category == branch.id && growth?.grapeIndex == index,
                    reduceMotion: reduceMotion
                )
                .frame(width: berry.size, height: berry.size * 1.10)
                .position(x: berry.x, y: berry.y)
            }
        }
    }
}

private struct GrapeBerryView: View {
    let category: String
    let variation: Int
    let depth: Double
    let shouldGrow: Bool
    let reduceMotion: Bool

    @State private var grown = false

    var body: some View {
        let color = GrapePalette.color(for: category).blend(with: .black, t: depth)
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                Ellipse()
                    .fill(RadialGradient(
                        colors: [GrapePalette.highlight(for: category), color,
                                 GrapePalette.shade(for: category)],
                        center: UnitPoint(x: 0.26, y: 0.22), startRadius: 0,
                        endRadius: w * 0.95))
                Ellipse()
                    .strokeBorder(GrapePalette.outline(for: category), lineWidth: 0.85)
                // 冷色反光与暖色高光，让果粒保持手绘动画的光泽。
                Ellipse()
                    .trim(from: 0.03, to: 0.28)
                    .stroke(GrapePalette.highlight(for: category).opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
                    .frame(width: w * 0.80, height: h * 0.82)
                    .rotationEffect(.degrees(18))
                Ellipse()
                    .fill(Color(red: 1, green: 0.98, blue: 0.87).opacity(0.83))
                    .frame(width: w * 0.20, height: h * 0.30)
                    .rotationEffect(.degrees(30))
                    .offset(x: -w * 0.23, y: -h * 0.23)
                Circle()
                    .fill(.white.opacity(0.87))
                    .frame(width: w * 0.10, height: w * 0.10)
                    .offset(x: -w * 0.08, y: -h * 0.36)
                Circle()
                    .fill(GrapePalette.highlight(for: category).opacity(0.38))
                    .frame(width: w * 0.12, height: w * 0.12)
                    .offset(x: w * 0.20, y: h * 0.21)
            }
            .rotationEffect(.degrees(Double(variation % 3 - 1) * 8))
            .scaleEffect(grown ? 1 : 0.05, anchor: .top)
            .opacity(grown ? 1 : 0)
            .offset(y: grown ? 0 : -6)
        }
        .onAppear {
            if shouldGrow && !reduceMotion {
                withAnimation(.spring(response: 0.58, dampingFraction: 0.52).delay(0.18)) {
                    grown = true
                }
            } else {
                grown = true
            }
        }
    }
}
