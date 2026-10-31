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
        var row: Int = 0
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
                Berry(center: CGPoint(x: 32 + ($0.0 - 32) * 0.88, y: 12 + $0.1 * 0.80),
                      size: CGSize(width: $0.2 * 0.82, height: $0.2 * 0.84), depth: $0.3)
            }
        }
        // Shape dense grape bunches as a hanging, tapered cluster rather than
        // switching from hand-placed berries to a rectangular spreadsheet grid.
        // Every real file still owns exactly one visible berry.
        let rows = max(5, Int(ceil(sqrt(Double(count) * 1.55))))
        var widest = max(4, Int(ceil(Double(count) / (Double(rows) * 0.70))))
        func capacities(_ width: Int) -> [Int] {
            (0..<rows).map { row in
                let taper = 1.0 - 0.56 * Double(row) / Double(max(1, rows - 1))
                return max(2, Int((Double(width) * taper).rounded()))
            }
        }
        var rowsOfFruit = capacities(widest)
        while rowsOfFruit.reduce(0, +) < count {
            widest += 1
            rowsOfFruit = capacities(widest)
        }

        let horizontalStep = min(CGFloat(15), 60 / CGFloat(widest))
        let verticalStep = min(CGFloat(13), 72 / CGFloat(rows))
        let diameter = min(CGFloat(18), horizontalStep * 1.11, verticalStep * 1.13)
        let size = CGSize(width: diameter, height: diameter * 1.04)
        var output: [Berry] = []
        output.reserveCapacity(count)
        for row in rowsOfFruit.indices {
            let amount = min(rowsOfFruit[row], count - output.count)
            if amount <= 0 { break }
            for column in 0..<amount {
                let stagger: CGFloat = row.isMultiple(of: 2) ? -0.10 : 0.10
                // Tiny deterministic variations in placement and fruit size
                // remove the abacus-like rows without randomizing each redraw.
                let dx = CGFloat(((row + 1) * 41 + (column + 3) * 73) % 17 - 8) * 0.16
                let dy = CGFloat(((column + 1) * 11 + row * 7) % 9 - 4) * 0.18
                let variation = CGFloat(0.93 + Double((row * 7 + column * 3) % 5) * 0.025)
                let berrySize = CGSize(width: size.width * variation, height: size.height * variation)
                let initialX = 32 + (CGFloat(column) - CGFloat(amount - 1) / 2 + stagger) * horizontalStep + dx
                let initialY = 14 + (CGFloat(row) + 0.5) * verticalStep + dy
                let x = min(64 - berrySize.width / 2, max(berrySize.width / 2, initialX))
                let y = min(88 - berrySize.height / 2, max(berrySize.height / 2, initialY))
                output.append(Berry(center: CGPoint(x: x, y: y), size: berrySize,
                                    depth: Double((column + row) % 3) * 0.05, row: row))
            }
        }
        return output
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
            if !berries.isEmpty {
                GrapeCrownView()
                    .frame(width: 64, height: 30)
                    .allowsHitTesting(false)
            }
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

/// A tiny native fruit stalk and two original textured leaves. Reuses the
/// approved v2 leaf crop for a consistent plant vocabulary; no vector glow,
/// breathing, overlay counter, or extra phantom grapes.
private struct GrapeCrownView: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let stalk = Path { p in
                    p.move(to: CGPoint(x: 32, y: 0))
                    p.addLine(to: CGPoint(x: 32, y: 12))
                    p.addLine(to: CGPoint(x: 28, y: 18))
                }
                context.stroke(stalk, with: .color(Color(red: 0.22, green: 0.35, blue: 0.22)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .square))
                let light = Path { p in
                    p.move(to: CGPoint(x: 33, y: 2))
                    p.addLine(to: CGPoint(x: 33, y: 11))
                }
                context.stroke(light, with: .color(Color(red: 0.39, green: 0.52, blue: 0.32)),
                               lineWidth: 1)
            }
            if let leaf = DeadlineFlowerMotion.leaf?.image {
                Image(nsImage: leaf)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 15, height: 17)
                    .scaleEffect(x: -1, y: 1)
                    .position(x: 24, y: 9)
                Image(nsImage: leaf)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 13, height: 15)
                    .position(x: 39, y: 8)
            }
        }
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
