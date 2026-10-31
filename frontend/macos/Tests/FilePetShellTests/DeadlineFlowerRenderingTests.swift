import AppKit
import XCTest
@testable import FilePetShell

@MainActor
final class DeadlineFlowerRenderingTests: XCTestCase {
    func testDynamicStageKeepsCalyxInsidePanelAndStemRootFixed() throws {
        let artwork = CompactFlowerArtwork.plants[1]
        let view = DeadlineFlowerView(artwork: artwork)
        for stage in DeadlineStage.allCases {
            let still = try XCTUnwrap(DeadlineFlowerMotion.geometry(
                bounds: view.bounds, artwork: artwork, stage: stage, stem: 0, head: 0))
            let swayed = try XCTUnwrap(DeadlineFlowerMotion.geometry(
                bounds: view.bounds, artwork: artwork, stage: stage, stem: 0.8, head: 0.5))
            XCTAssertEqual(still.root, swayed.root, "Wind cannot move the attached root")
            XCTAssertLessThanOrEqual(still.rect.maxY, view.bounds.maxY + 0.01, stage.label)
            XCTAssertGreaterThanOrEqual(still.rect.minY, view.bounds.minY - 0.01, stage.label)
        }
    }

    func testDynamicTransparentPixelsPassThroughWhilePetalsAreClickable() throws {
        let view = DeadlineFlowerView(artwork: CompactFlowerArtwork.plants[1])
        view.deadlineStage = .bloom
        XCTAssertFalse(view.containsArtwork(NSPoint(x: 1, y: 1)))
        let sprite = try XCTUnwrap(DeadlineFlowerMotion.heads.last)
        let g = try XCTUnwrap(DeadlineFlowerMotion.geometry(
            bounds: view.bounds, artwork: view.artwork, stage: .withered, stem: 0, head: 0))
        view.deadlineStage = .withered
        let index = try XCTUnwrap(sprite.alpha.firstIndex(where: { $0 > 200 }))
        let x = index % sprite.pixelsWide, y = index / sprite.pixelsWide
        let px = g.rect.minX + (CGFloat(x) + 0.5) / CGFloat(sprite.pixelsWide) * g.rect.width
        let py = g.rect.maxY - (CGFloat(y) + 0.5) / CGFloat(sprite.pixelsHigh) * g.rect.height
        XCTAssertTrue(view.containsArtwork(NSPoint(x: px, y: py)))
    }

    func testArtworkHitTargetsMatchTheRenderedAlpha() throws {
        for artwork in CompactFlowerArtwork.plants {
            let view = DeadlineFlowerView(artwork: artwork)
            // Render at source resolution so interpolation cannot hide a flipped mask.
            view.frame.size = CGSize(width: artwork.image.width, height: artwork.image.height)
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: artwork.image.width,
                pixelsHigh: artwork.image.height, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: artwork.image.width * 4, bitsPerPixel: 32)!
            let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            view.draw(view.bounds)
            NSGraphicsContext.restoreGraphicsState()
            var tested = 0
            var mismatches = 0
            for y in stride(from: 8, to: artwork.image.height - 8, by: 11) {
                for x in stride(from: 8, to: artwork.image.width - 8, by: 11) {
                    let alpha = try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent
                    guard alpha < 0.02 || alpha > 0.95 else { continue }
                    let hit = view.containsArtwork(NSPoint(x: CGFloat(x) + 0.5,
                        y: CGFloat(artwork.image.height - 1 - y) + 0.5))
                    if hit != (alpha > 0.5) { mismatches += 1 }
                    tested += 1
                }
            }
            XCTAssertGreaterThan(tested, 500)
            XCTAssertEqual(mismatches, 0, "Transparent gaps and flower clicks must use the same orientation as drawing")
            XCTAssertFalse(view.containsArtwork(NSPoint(x: -1, y: 10)))
            XCTAssertFalse(view.containsArtwork(NSPoint(x: 0, y: -1)))
        }
    }
}
