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
        XCTAssertEqual(gap, 57)
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
        XCTAssertEqual(offsets[1] - offsets[0], 56)
        XCTAssertEqual(offsets[2] - offsets[1], 56)
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

    func testOnlyPairedLeftBlossomShrinksAndCalyxRemainsAttached() throws {
        XCTAssertEqual(DeadlineFlowerArrangement.crownScale(index: 0, count: 1), 1)
        XCTAssertEqual(DeadlineFlowerArrangement.crownScale(index: 0, count: 2), 0.68)
        XCTAssertEqual(DeadlineFlowerArrangement.crownScale(index: 1, count: 2), 1)
        XCTAssertEqual(DeadlineFlowerArrangement.crownScale(index: 0, count: 3), 1)
        XCTAssertEqual(DeadlineFlowerArrangement.crownScale(index: 1, count: 3), 1)

        let left = CompactFlowerArtwork.plants[0]
        let right = CompactFlowerArtwork.plants[1]
        let unscaled = try XCTUnwrap(DeadlineFlowerMotion.geometry(
            bounds: NSRect(origin: .zero, size: left.size), artwork: left,
            stage: .bloom, stem: 0, head: 0))
        let scaled = try XCTUnwrap(DeadlineFlowerMotion.geometry(
            bounds: NSRect(origin: .zero, size: left.size), artwork: left,
            stage: .bloom, stem: 0, head: 0,
            crownScale: DeadlineFlowerArrangement.crownScale(index: 0, count: 2)))
        let neighbor = try XCTUnwrap(DeadlineFlowerMotion.geometry(
            bounds: NSRect(origin: .zero, size: right.size), artwork: right,
            stage: .opening, stem: 0, head: 0))

        XCTAssertEqual(unscaled.root, scaled.root)
        XCTAssertEqual(unscaled.calyx, scaled.calyx,
            "Do not break the calyx/stem joint when reducing the blossom")
        XCTAssertEqual(scaled.rect.width / unscaled.rect.width, 0.68, accuracy: 0.001)
        XCTAssertLessThan(scaled.rect.width, neighbor.rect.width,
            "The left bloom must not visually dominate the right opening flower")
        XCTAssertGreaterThan(scaled.rect.width, neighbor.rect.width * 0.8,
            "Do not make the left bloom unnaturally tiny")

        let leftView = DeadlineFlowerView(artwork: left)
        leftView.deadlineStage = .bloom
        leftView.crownScale = 0.68
        XCTAssertFalse(leftView.containsArtwork(NSPoint(x: 1, y: 1)),
            "The large transparent panel must still let clicks through")
    }

    func testMeadowPoseIsUprightSoloAndNaturallyOutwardInGroups() throws {
        let solo = DeadlineFlowerArrangement.pose(index: 0, count: 1)
        XCTAssertEqual(solo.tipShift, 0)
        XCTAssertLessThan(abs(solo.bow), 1, "The approved solo flower must stay upright")
        XCTAssertLessThan(solo.groundCover, 0.6)

        let left = DeadlineFlowerArrangement.pose(index: 0, count: 2)
        let right = DeadlineFlowerArrangement.pose(index: 1, count: 2)
        XCTAssertLessThan(left.tipShift, 0)
        XCTAssertGreaterThan(right.tipShift, 0)
        XCTAssertLessThan(abs(left.tipShift), 9)
        XCTAssertLessThan(abs(right.tipShift), 9)
        XCTAssertGreaterThan(left.groundCover, solo.groundCover)
        XCTAssertGreaterThan(right.groundCover, solo.groundCover)

        let trio = (0..<3).map { DeadlineFlowerArrangement.pose(index: $0, count: 3) }
        XCTAssertLessThan(trio[0].tipShift, 0)
        XCTAssertGreaterThan(trio[2].tipShift, 0)
        XCTAssertLessThan(abs(trio[1].tipShift), 2)
        XCTAssertNotEqual(trio[0].heightShift, trio[2].heightShift)
    }

    func testEachPoseKeepsRootsAnchoredAndCalyxStemConnected() throws {
        for count in 1...3 {
            for index in 0..<count {
                let artwork = CompactFlowerArtwork.plants[index]
                let pose = DeadlineFlowerArrangement.pose(index: index, count: count)
                let bounds = NSRect(origin: .zero, size: artwork.size)
                for stage in DeadlineStage.allCases {
                    let still = try XCTUnwrap(DeadlineFlowerMotion.geometry(
                        bounds: bounds, artwork: artwork, stage: stage,
                        stem: 0, head: 0, pose: pose))
                    let moving = try XCTUnwrap(DeadlineFlowerMotion.geometry(
                        bounds: bounds, artwork: artwork, stage: stage,
                        stem: 0.7, head: -0.4, pose: pose))
                    XCTAssertEqual(still.root, moving.root)
                    XCTAssertEqual(still.root.y, 3)
                    XCTAssertEqual(still.calyx.x, artwork.stemX + pose.tipShift)
                    XCTAssertGreaterThan(still.calyx.y, still.root.y)
                    XCTAssertTrue(bounds.contains(NSPoint(x: still.rect.midX, y: still.rect.midY)),
                                  "Petals should remain in the existing window")
                    XCTAssertTrue(DeadlineFlowerMotion.hit(
                        still.calyx, bounds: bounds, artwork: artwork,
                        stage: stage, stem: 0, head: 0, pose: pose),
                        "The calyx must remain an interactive extension of the stem")
                }
            }
        }
    }

    func testUnsupportedCountsDoNotInventExtraWindows() {
        XCTAssertTrue(DeadlineFlowerArrangement.rootOffsets(count: 0).isEmpty)
        XCTAssertTrue(DeadlineFlowerArrangement.rootOffsets(count: 4).isEmpty)
    }
}
