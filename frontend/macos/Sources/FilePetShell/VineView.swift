import SwiftUI

/// The native app draws the approved pixel trellis, never the old curved vine.
/// Flowers keep their independent always-present windows and real DDL identities.
struct VineView: View {
    @ObservedObject var model: VineModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 400, height: 292)
    private var animating: Bool { model.phase != .hidden && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !animating)) { timeline in
            CompactGardenContentView(branches: model.branches, growth: model.latestGrowth,
                activeTheftCategory: model.activeTheft?.category,
                time: animating ? timeline.date.timeIntervalSinceReferenceDate : 0,
                reduceMotion: reduceMotion)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .opacity(model.isVisible ? 1 : 0)
        .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.45), value: model.isVisible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("轻盈像素葡萄架")
        .accessibilityValue(model.branches.map {
            "\(model.displayName(for: $0.id))，已分类 \(model.count(for: $0.id)) 个文件"
        }.joined(separator: "；"))
    }
}

/// A deterministic native scene shared by live rendering and visual checks.
struct CompactGardenContentView: View {
    let branches: [VineBranch]
    let growth: VineGrowth?
    let activeTheftCategory: String?
    let time: TimeInterval
    let reduceMotion: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: CompactGardenArtwork.croppedTrellis, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: VineView.size.width, height: VineView.size.height)
            ForEach(Array(branches.enumerated()), id: \.element.id) { index, branch in
                let anchor = CompactGardenLayout.branchAnchor(index: index, total: branches.count, time: time)
                let scale = CompactGardenLayout.branchScale(total: branches.count)
                if branches.count > 3 {
                    CompactBranchStem(anchor: CGPoint(x: anchor.x, y: anchor.y), scale: scale)
                }
                GrapeClusterView(branch: branch, growth: growth, reduceMotion: reduceMotion)
                    .frame(width: 64, height: 88)
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(reduceMotion ? 0 : sin(time * 1.25 + Double(index) * 0.8) * 0.7), anchor: .top)
                    .position(x: anchor.x, y: anchor.y)
                    .opacity(activeTheftCategory == branch.id ? 0 : 1)
            }
        }
        .frame(width: VineView.size.width, height: VineView.size.height)
        .clipped()
    }
}

private struct CompactBranchStem: View {
    let anchor: CGPoint
    let scale: Double

    var body: some View {
        Canvas { context, _ in
            let endY = max(49, anchor.y - 32 * scale)
            let x = anchor.x.rounded()
            context.fill(Path(CGRect(x: x, y: 47, width: 1, height: endY - 47)),
                         with: .color(Color(red: 0.34, green: 0.39, blue: 0.21)))
            context.fill(Path(CGRect(x: x - 1, y: endY - 3, width: 2, height: 4)),
                         with: .color(Color(red: 0.47, green: 0.49, blue: 0.28)))
        }
        .allowsHitTesting(false)
    }
}

enum CompactGrapeLayout {
    struct Berry {
        let center: CGPoint
        let size: CGSize
        let depth: Double
    }

    static func berries(count: Int) -> [Berry] {
        guard count > 0 else { return [] }
        let first: [(CGFloat, CGFloat, CGFloat, Double)] = [
            (32, 18, 21, 0.0), (20, 28, 21, 0.1), (44, 28, 21, 0.1),
            (31, 40, 22, 0.0), (13, 43, 20, 0.1), (51, 43, 20, 0.1),
            (22, 55, 21, 0.0), (41, 56, 21, 0.0), (31, 71, 21, 0.0),
            (34, 10, 19, 0.2), (14, 16, 19, 0.2), (50, 17, 19, 0.2),
        ]
        if count <= first.count {
            return first.prefix(count).map {
                Berry(center: CGPoint(x: $0.0, y: $0.1), size: CGSize(width: $0.2, height: $0.2 * 1.04), depth: $0.3)
            }
        }
        let columns = max(4, Int(ceil(sqrt(Double(count) * 0.72))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let side = min(60 / CGFloat(columns), 82 / CGFloat(rows))
        let xInset: CGFloat = (64 - CGFloat(columns) * side) / 2
        let berrySize = CGSize(width: side * 1.08, height: side * 1.10)
        return (0..<count).map { index -> Berry in
            let column = CGFloat(index % columns)
            let row = CGFloat(index / columns)
            let center = CGPoint(x: column * side + xInset + side / 2,
                                 y: row * side + side / 2)
            let depth = Double(index % 2) * 0.1
            return Berry(center: center, size: berrySize, depth: depth)
        }
    }
}

/// Shared by the native hanging fruit and Jerry's falling/carrying scene.
struct GrapeClusterView: View {
    let branch: VineBranch
    let growth: VineGrowth?
    let reduceMotion: Bool

    var body: some View {
        let berries = CompactGrapeLayout.berries(count: branch.count)
        ZStack(alignment: .topLeading) {
            ForEach(Array(berries.indices.sorted { berries[$0].depth > berries[$1].depth }), id: \.self) { index in
                PixelGrapeBerry(category: branch.id,
                    shouldGrow: growth?.category == branch.id && growth?.grapeIndex == index,
                    sequence: growth?.sequence, reduceMotion: reduceMotion)
                    .frame(width: berries[index].size.width, height: berries[index].size.height)
                    .position(berries[index].center)
            }
        }
        .frame(width: 64, height: 88)
    }
}

private struct PixelGrapeBerry: View {
    let category: String
    let shouldGrow: Bool
    let sequence: UInt64?
    let reduceMotion: Bool
    @State private var scale: CGFloat = 1

    var body: some View {
        Image(decorative: CompactGardenArtwork.berry(for: category), scale: 1)
            .resizable()
            .interpolation(.none)
            .scaleEffect(scale, anchor: .top)
            .task(id: sequence) {
                scale = 1
                guard shouldGrow, !reduceMotion else { return }
                scale = 0.08
                await Task.yield()
                guard !Task.isCancelled else { scale = 1; return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { scale = 1 }
            }
    }
}
