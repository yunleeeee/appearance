import AppKit
import XCTest
@testable import FilePetShell

@MainActor
final class HarvestSlashEffectTests: XCTestCase {
    func testOnlyActualDoubleClickOnArtworkHarvests() {
        XCTAssertFalse(HarvestGesturePolicy.accepts(
            clickCount: 1, displacement: 0, onArtwork: true))
        XCTAssertTrue(HarvestGesturePolicy.accepts(
            clickCount: 2, displacement: 2.4, onArtwork: true))
        XCTAssertFalse(HarvestGesturePolicy.accepts(
            clickCount: 2, displacement: 7, onArtwork: true),
            "Drag-like gestures must not complete a task")
        XCTAssertFalse(HarvestGesturePolicy.accepts(
            clickCount: 2, displacement: 0, onArtwork: false),
            "Transparent desktop pixels must remain click-through")
    }

    func testSwordCutsThenShatteringThenGravityAndCompleteDisappear() {
        let fresh = HarvestSlashEffect.sample(at: 0, reduceMotion: false)
        XCTAssertTrue(fresh.showHead)
        XCTAssertEqual(fresh.stemOpacity, 1)
        XCTAssertEqual(fresh.shardOpacity, 0)

        let cuts = HarvestSlashEffect.sample(at: 0.21, reduceMotion: false)
        XCTAssertTrue(cuts.showHead)
        XCTAssertFalse(cuts.finished)
        let shatter = HarvestSlashEffect.sample(at: 0.42, reduceMotion: false)
        XCTAssertFalse(shatter.showHead)
        XCTAssertGreaterThan(shatter.shardOpacity, 0)
        XCTAssertGreaterThan(shatter.stemOpacity, 0)
        let falling = HarvestSlashEffect.sample(at: 0.82, reduceMotion: false)
        XCTAssertEqual(falling.stemOpacity, 0)
        XCTAssertGreaterThan(falling.shardOpacity, 0)
        XCTAssertLessThan(falling.shardOpacity, 1)
        let end = HarvestSlashEffect.sample(at: HarvestSlashEffect.duration, reduceMotion: false)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(end.stemOpacity, 0)
        XCTAssertEqual(end.shardOpacity, 0)
        XCTAssertFalse(end.showHead)
    }

    func testReduceMotionPreservesRecognitionAndDisablesSwordFlight() {
        let first = HarvestSlashEffect.sample(at: 0, reduceMotion: true)
        XCTAssertTrue(first.showHead)
        XCTAssertEqual(first.shardOpacity, 0)
        let middle = HarvestSlashEffect.sample(at: 0.11, reduceMotion: true)
        XCTAssertFalse(middle.showHead)
        XCTAssertEqual(middle.shardOpacity, 0)
        XCTAssertFalse(middle.finished)
        let end = HarvestSlashEffect.sample(
            at: HarvestSlashEffect.reducedDuration, reduceMotion: true)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(end.stemOpacity, 0)
        XCTAssertEqual(end.shardOpacity, 0)
        XCTAssertLessThan(HarvestSlashEffect.reducedDuration, HarvestSlashEffect.duration)
    }

    func testRenderedHarvestFramesChangeAndEndTransparent() throws {
        let flower = DeadlineFlowerView(artwork: CompactFlowerArtwork.plants[1])
        flower.deadlineStage = .bloom
        flower.reduceMotionOverride = false
        flower.previewHarvestAge = 0.16
        let slash = try bitmap(for: flower)
        flower.previewHarvestAge = 0.50
        let breakApart = try bitmap(for: flower)
        flower.previewHarvestAge = 0.80
        let falling = try bitmap(for: flower)
        flower.previewHarvestAge = HarvestSlashEffect.duration
        let final = try bitmap(for: flower)
        XCTAssertNotEqual(slash, breakApart)
        XCTAssertNotEqual(breakApart, falling)
        XCTAssertNotEqual(falling, final)
        XCTAssertTrue(final.allSatisfy { $0 == 0 },
                      "After falling there should be no lingering flower, beam or spark")

        flower.reduceMotionOverride = true
        flower.previewHarvestAge = HarvestSlashEffect.reducedDuration
        XCTAssertTrue(try bitmap(for: flower).allSatisfy { $0 == 0 })
    }

    private func bitmap(for flower: DeadlineFlowerView) throws -> [UInt8] {
        let width = Int(ceil(flower.bounds.width))
        let height = Int(ceil(flower.bounds.height))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        flower.draw(flower.bounds)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let raw = try XCTUnwrap(bitmap.bitmapData)
        return Array(UnsafeBufferPointer(start: raw, count: width * height * 4))
    }
}
