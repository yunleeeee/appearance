import AppKit
import XCTest
@testable import FilePetShell

@MainActor
final class FlowerHarvestEffectTests: XCTestCase {
    func testDoubleClickIsRequiredAndCannotHarvestAgainDuringAnimation() throws {
        let artwork = try XCTUnwrap(CompactFlowerArtwork.plants.first)
        let view = DeadlineFlowerView(artwork: artwork)
        var harvested = 0
        view.onHarvest = {
            harvested += 1
            view.isHarvesting = true
        }

        let point = try XCTUnwrap(opaquePoint(in: artwork, view: view))
        view.completeClick(at: point, clickCount: 1)
        XCTAssertEqual(harvested, 0, "Single clicks only show deadline details")
        view.completeClick(at: point, clickCount: 2)
        XCTAssertEqual(harvested, 1, "Second click harvests immediately")
        view.completeClick(at: point, clickCount: 3)
        XCTAssertEqual(harvested, 1, "The same flower cannot be harvested twice")
        XCTAssertFalse(view.isPressed)
        view.completeClick(at: CGPoint(x: -1, y: -1), clickCount: 2)
        XCTAssertEqual(harvested, 1)
    }

    func testSlashSceneTimelineFallsToFloorThenFades() {
        XCTAssertEqual(HarvestSlashTimeline.fractureTime, 0.48)
        XCTAssertEqual(HarvestSlashTimeline.duration(reduceMotion: false), 1.58)
        XCTAssertEqual(HarvestSlashTimeline.duration(reduceMotion: true), 0.24)

        let initial = HarvestSlashTimeline.fallOffset(elapsed: 0, launch: 90, centerY: 86)
        let lift = HarvestSlashTimeline.fallOffset(elapsed: 0.1, launch: 90, centerY: 86)
        let landed = HarvestSlashTimeline.fallOffset(elapsed: 1.0, launch: 90, centerY: 86)
        XCTAssertEqual(initial, 0)
        XCTAssertGreaterThan(lift, initial)
        XCTAssertEqual(landed, HarvestSlashTimeline.floorY - 86, accuracy: 0.001,
                       "Pieces must settle on the desktop floor")
        for centerY: CGFloat in [26, 53, 86, 150] {
            for sample in stride(from: 0.0, through: 1.5, by: 0.05) {
                let offset = HarvestSlashTimeline.fallOffset(
                    elapsed: sample, launch: 90, centerY: centerY)
                XCTAssertGreaterThanOrEqual(centerY + offset,
                    HarvestSlashTimeline.floorY - 0.001,
                    "No piece should fall through the floor")
            }
        }

        XCTAssertEqual(HarvestSlashTimeline.opacity(elapsed: 0.48), 1)
        XCTAssertGreaterThan(HarvestSlashTimeline.opacity(elapsed: 1.0), 0)
        XCTAssertEqual(HarvestSlashTimeline.opacity(elapsed: 1.58), 0)
    }

    func testEffectIsLargerThanArtworkAndDoesNotConsumeMouseEvents() throws {
        let artwork = try XCTUnwrap(CompactFlowerArtwork.plants.first)
        let effect = HarvestSlashEffectView(artwork: artwork, reduceMotion: false)
        XCTAssertGreaterThan(effect.bounds.width, artwork.size.width)
        XCTAssertGreaterThan(effect.bounds.height, artwork.size.height)
        XCTAssertFalse(effect.isOpaque)
        XCTAssertEqual(effect.bounds.width, HarvestSlashEffectView.canvasSize(for: artwork).width)
    }

    private func opaquePoint(in artwork: CompactFlowerArtwork, view: DeadlineFlowerView) -> CGPoint? {
        for y in 0..<artwork.image.height {
            for x in 0..<artwork.image.width {
                if artwork.alpha[(y * artwork.image.width + x) * 4 + 3] > 240 {
                    let point = CGPoint(
                        x: (CGFloat(x) + 0.5) / CGFloat(artwork.image.width) * view.bounds.width,
                        y: view.bounds.height - (CGFloat(y) + 0.5) / CGFloat(artwork.image.height) * view.bounds.height)
                    if view.containsArtwork(point) { return point }
                }
            }
        }
        return nil
    }
}
