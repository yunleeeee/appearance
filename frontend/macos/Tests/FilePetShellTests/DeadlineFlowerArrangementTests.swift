import AppKit
import XCTest
@testable import FilePetShell

@MainActor
final class DeadlineFlowerArrangementTests: XCTestCase {
    func testSinglePlantKeepsApprovedRootLocation() throws {
        let screen = NSRect(x: 0, y: 0, width: 1152, height: 800)
        let artwork = CompactFlowerArtwork.plants[0]
        let origin = try XCTUnwrap(DeadlineFlowerArrangement.frameOrigin(
            screen: screen, stemX: artwork.stemX, index: 0, count: 1))
        XCTAssertEqual(origin.x + artwork.stemX, screen.maxX - 266)
        XCTAssertEqual(origin.y, screen.minY)
    }

    func testTwoFlowersFormCompactPairOnSameGroundLine() throws {
        let screen = NSRect(x: 120, y: 35, width: 1152, height: 800)
        let plants = CompactFlowerArtwork.plants
        let small = try XCTUnwrap(DeadlineFlowerArrangement.frameOrigin(
            screen: screen, stemX: plants[0].stemX, index: 0, count: 2))
        let tall = try XCTUnwrap(DeadlineFlowerArrangement.frameOrigin(
            screen: screen, stemX: plants[1].stemX, index: 1, count: 2))
        let gap = (tall.x + plants[1].stemX) - (small.x + plants[0].stemX)
        XCTAssertEqual(gap, 67)
        XCTAssertEqual(small.y, tall.y)
        let heightRatio = plants[1].size.height / plants[0].size.height
        XCTAssertLessThan(heightRatio, 1.5,
            "A second flower must not dwarf the original companion")
        XCTAssertGreaterThan(heightRatio, 1.15,
            "Keep intentional natural differences in height")
    }

    func testThreeFlowersFitAndAreStableAcrossRecalculations() throws {
        let screen = NSRect(x: -1440, y: 30, width: 1440, height: 900)
        let offsets = DeadlineFlowerArrangement.rootOffsets(count: 3)
        XCTAssertEqual(offsets.count, 3)
        XCTAssertEqual(offsets[1] - offsets[0], 68)
        XCTAssertEqual(offsets[2] - offsets[1], 68)
        for (i, artwork) in CompactFlowerArtwork.plants.enumerated() {
            let origin = try XCTUnwrap(DeadlineFlowerArrangement.frameOrigin(
                screen: screen, stemX: artwork.stemX, index: i, count: 3))
            XCTAssertEqual(origin.y, screen.minY)
            XCTAssertGreaterThanOrEqual(origin.x, screen.minX)
            XCTAssertLessThan(origin.x + artwork.size.width, screen.maxX)
            XCTAssertEqual(origin,
                DeadlineFlowerArrangement.frameOrigin(
                    screen: screen, stemX: artwork.stemX, index: i, count: 3))
        }
    }

    func testUnsupportedCountsDoNotInventExtraWindows() {
        XCTAssertTrue(DeadlineFlowerArrangement.rootOffsets(count: 0).isEmpty)
        XCTAssertTrue(DeadlineFlowerArrangement.rootOffsets(count: 4).isEmpty)
    }
}
