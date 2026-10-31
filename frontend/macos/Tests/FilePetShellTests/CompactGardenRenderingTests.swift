import AppKit
import SwiftUI
import XCTest
@testable import FilePetShell

@MainActor
final class CompactGardenRenderingTests: XCTestCase {
    func testRuntimeTrellisRemovesSourceBunchesButKeepsTheWood() throws {
        let source = NSBitmapImageRep(cgImage: CompactGardenArtwork.source)
        let trellis = NSBitmapImageRep(cgImage: CompactGardenArtwork.trellis)
        XCTAssertEqual(source.pixelsWide, trellis.pixelsWide)
        XCTAssertEqual(source.pixelsHigh, trellis.pixelsHigh)
        // Interior points cover all three baked bunches, including their bottom
        // berries. They must be transparent before real file sprites are added.
        let fruitPoints = [(232, 344), (278, 341), (266, 410), (282, 444),
                           (642, 364), (684, 357), (692, 428), (677, 465),
                           (1046, 337), (1093, 338), (1062, 407), (1086, 444)]
        for (x, y) in fruitPoints {
            XCTAssertGreaterThan(try XCTUnwrap(source.colorAt(x: x, y: y)).alphaComponent, 0.75,
                                 "The source must really have a baked berry at this test point")
            XCTAssertLessThan(try XCTUnwrap(trellis.colorAt(x: x, y: y)).alphaComponent, 0.05,
                              "An empty category must never inherit source fruit at \(x),\(y)")
        }
        for (x, y) in [(55, 220), (1340, 100), (1340, 950)] {
            XCTAssertGreaterThan(try XCTUnwrap(trellis.colorAt(x: x, y: y)).alphaComponent, 0.75,
                                 "Removing source fruit must preserve the wooden trellis")
        }
    }

    func testThreePixelBerrySpritesAreDistinctAndHaveTransparentEdges() throws {
        var encodings: [Data] = []
        for category in ["research", "learning", "finance"] {
            let image = CompactGardenArtwork.berry(for: category)
            let bitmap = NSBitmapImageRep(cgImage: image)
            XCTAssertGreaterThan(image.width, 8)
            XCTAssertGreaterThan(image.height, 8)
            XCTAssertLessThan(image.width, 100)
            XCTAssertLessThan(image.height, 100)
            var opaque = 0
            var transparent = 0
            for y in 0..<image.height {
                for x in 0..<image.width {
                    let alpha = try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent
                    if alpha > 0.75 { opaque += 1 }
                    if alpha < 0.05 { transparent += 1 }
                }
            }
            XCTAssertGreaterThan(opaque, image.width * image.height / 4)
            XCTAssertGreaterThan(transparent, 10, "A sprite must not bring a rectangular fragment of neighbouring fruit")
            encodings.append(try XCTUnwrap(bitmap.representation(using: .png, properties: [:])))
        }
        XCTAssertEqual(Set(encodings).count, 3, "The confirmed purple, green and gold berries must remain distinct")
    }

    func testEveryFileHasOneBerryEvenBeyondTheOldTwelveBerryLimit() {
        for count in [0, 1, 4, 12, 13, 31, 100] {
            let berries = CompactGrapeLayout.berries(count: count)
            XCTAssertEqual(berries.count, count, "The visual count must match the file inventory")
            for berry in berries {
                XCTAssertTrue(berry.center.x.isFinite && berry.center.y.isFinite)
                XCTAssertGreaterThan(berry.size.width, 0)
                XCTAssertGreaterThan(berry.size.height, 0)
                XCTAssertGreaterThanOrEqual(berry.center.x - berry.size.width / 2, -1)
                XCTAssertLessThanOrEqual(berry.center.x + berry.size.width / 2, 65)
                XCTAssertGreaterThanOrEqual(berry.center.y - berry.size.height / 2, -1)
                XCTAssertLessThanOrEqual(berry.center.y + berry.size.height / 2, 89)
            }
        }
    }

    func testDenseGrapeClustersFormAHandingTaperInsteadOfRectangularRows() {
        for count in [13, 20, 31, 64, 100] {
            let grapes = CompactGrapeLayout.berries(count: count)
            XCTAssertEqual(grapes.count, count)
            let bands = Dictionary(grouping: grapes) { Int(($0.center.y * 100).rounded()) }
            let counts = bands.keys.sorted().map { bands[$0]!.count }
            XCTAssertGreaterThan(counts.count, 3)
            XCTAssertGreaterThan(counts.first ?? 0, counts.last ?? 0,
                                 "The upper shoulder should be wider than the tail")
            XCTAssertTrue(grapes.allSatisfy {
                $0.center.x - $0.size.width / 2 >= 0 &&
                $0.center.x + $0.size.width / 2 <= 64 &&
                $0.center.y - $0.size.height / 2 >= 0 &&
                $0.center.y + $0.size.height / 2 <= 88
            })
        }
        XCTAssertTrue(CompactGrapeLayout.berries(count: 0).isEmpty)
    }

    func testRuntimeAnchorsMatchTheConfirmedSourceCropAndKeepExtraCategoriesOnscreen() {
        XCTAssertEqual(CompactGardenLayout.size, CoreSize(width: 400, height: 292))
        // The design's three source bunch centres, transformed from the supplied
        // 1401×1022 crop into the native 400×292 layer.
        let sourceCentres = [(279.5, 391.5), (686.5, 411.0), (1087.0, 390.5)]
        for (index, centre) in sourceCentres.enumerated() {
            let expectedX = (centre.0 - 29) / 1401 * 400
            let expectedY = (centre.1 - 38) / 1022 * 292
            let actual = CompactGardenLayout.branchAnchor(index: index, total: 3, time: 0)
            XCTAssertEqual(actual.x, expectedX, accuracy: 2)
            XCTAssertEqual(actual.y, expectedY, accuracy: 2)
        }
        for count in [1, 2, 3, 4, 8, 16, 32] {
            let scale = CompactGardenLayout.branchScale(total: count)
            XCTAssertGreaterThan(scale, 0)
            XCTAssertLessThanOrEqual(scale, 1)
            var anchors: [CorePoint] = []
            for index in 0..<count {
                let point = CompactGardenLayout.branchAnchor(index: index, total: count, time: 0)
                XCTAssertTrue(point.x.isFinite && point.y.isFinite)
                XCTAssertGreaterThan(point.x - 32 * scale, 0)
                XCTAssertLessThan(point.x + 32 * scale, 400)
                XCTAssertGreaterThan(point.y - 44 * scale, 0)
                XCTAssertLessThan(point.y + 44 * scale, 292)
                anchors.append(point)
            }
            XCTAssertEqual(Set(anchors.map { String(format: "%.4f", $0.x) }).count, count,
                           "Each category must keep a separate plant position")
        }
    }

    func testCompactTheftStartsAtTheSourceAndKeepsTheShoulderContact() {
        let origin = CompactGardenLayout.branchAnchor(index: 1, total: 3, time: 0)
        let scale = CompactGardenLayout.branchScale(total: 3)
        let initial = TheftChoreography.state(at: 0, size: CoreSize(width: 1440, height: 900),
                                             origin: origin)
        XCTAssertEqual(CompactGardenLayout.grapeCenter(for: initial, elapsed: 0,
            reducedMotion: false, visualScale: scale), origin)
        for time in [2.1, 2.55, 3.2, 4.5] {
            let state = TheftChoreography.state(at: time, size: CoreSize(width: 1440, height: 900),
                                               origin: origin)
            let center = CompactGardenLayout.grapeCenter(for: state, elapsed: time,
                reducedMotion: false, visualScale: scale)
            let contact = state.grapeBackContact
            XCTAssertEqual(center.x + (contact.x - state.grapeCenter.x) * scale, contact.x, accuracy: 0.001)
            XCTAssertEqual(center.y + (contact.y - state.grapeCenter.y) * scale, contact.y, accuracy: 0.001)
        }
    }

    func testExportNativeCompactGardenProofs() throws {
        guard ProcessInfo.processInfo.environment["FILEPET_RENDER_COMPACT"] == "1" else {
            throw XCTSkip("Set FILEPET_RENDER_COMPACT=1 to export native compact garden proofs")
        }
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".tmp/compact-qa", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cases: [(String, [VineBranch], Bool, Bool, Bool)] = [
            ("empty-dark", [], false, false, true),
            ("two-files-dark", [VineBranch(id: "finance", count: 1), VineBranch(id: "recruitment", count: 1)], false, false, true),
            ("two-files-light", [VineBranch(id: "finance", count: 1), VineBranch(id: "recruitment", count: 1)], false, true, true),
            ("full-dark", [VineBranch(id: "research", count: 12), VineBranch(id: "learning", count: 12), VineBranch(id: "finance", count: 12)], true, false, true),
            ("full-light", [VineBranch(id: "research", count: 12), VineBranch(id: "learning", count: 12), VineBranch(id: "finance", count: 12)], true, true, true),
            ("flowers-only-dark", [], true, false, false),
            ("thirty-one-files", [VineBranch(id: "research", count: 31)], false, false, true),
        ]
        for (name, branches, flowers, light, trellis) in cases {
            let content = CompactGardenProofView(branches: branches, flowers: flowers,
                                                light: light, showsTrellis: trellis)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage, "The native view must render into an image")
            XCTAssertEqual(image.width, 800)
            XCTAssertEqual(image.height, Int((CompactGardenLayout.size.height + CompactGardenLayout.bottomInset) * 2))
            let bitmap = NSBitmapImageRep(cgImage: image)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: output.appendingPathComponent(name + ".png"))
        }
        print("Native compact garden proofs: \(output.path)")
    }
}

private struct CompactGardenProofView: View {
    let branches: [VineBranch]
    let flowers: Bool
    let light: Bool
    let showsTrellis: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            (light ? Color(red: 0.95, green: 0.94, blue: 0.91) : Color(red: 0.09, green: 0.13, blue: 0.15))
            if showsTrellis {
                CompactGardenContentView(branches: branches, growth: nil, activeTheftCategory: nil,
                                         time: 0, reduceMotion: true)
                    .frame(width: 400, height: 292)
            }
            if flowers {
                ForEach(Array(CompactFlowerArtwork.plants.enumerated()), id: \.offset) { _, plant in
                    Image(decorative: plant.image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: plant.size.width, height: plant.size.height)
                        .position(x: 115 + plant.rootX - plant.stemX + plant.size.width / 2,
                                  y: CGFloat(CompactGardenLayout.size.height + CompactGardenLayout.bottomInset) - plant.size.height / 2)
                }
            }
        }
        .frame(width: 400, height: CGFloat(CompactGardenLayout.size.height + CompactGardenLayout.bottomInset))
    }
}
