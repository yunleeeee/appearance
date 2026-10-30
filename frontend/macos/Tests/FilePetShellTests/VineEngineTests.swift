import Foundation
import XCTest
@testable import FilePetShell

final class VineEngineTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 10_000)

    private func advanceUntilTheft(_ engine: VineEngine, file: StaticString = #filePath, line: UInt = #line) throws -> VineTheft {
        for _ in 0..<100 {
            if let event = engine.snapshot.activeTheft { return event }
            guard let next = engine.nextDeadline else { break }
            engine.advance(to: next)
        }
        return try XCTUnwrap(engine.snapshot.activeTheft, "Expected a mature branch to start its theft", file: file, line: line)
    }

    private func feed(_ engine: VineEngine, count: Int, category: String = "图片") {
        engine.beginReceiving()
        engine.recordSuccesses(categories: Array(repeating: category, count: count))
        engine.scheduleSleep()
    }

    func testBatchPersistsBeforeFinishingVisualGrowth() throws {
        let storage = MemoryVineStorage()
        let engine = VineEngine(storage: storage, now: epoch)
        feed(engine, count: 3)
        XCTAssertEqual(engine.count(for: "图片"), 3)
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 1)
        let data = try XCTUnwrap(storage.data(forKey: VineEngine.branchesKey))
        XCTAssertEqual(try JSONDecoder().decode([VineBranch].self, from: data), [VineBranch(id: "图片", count: 3)])
        engine.advance(to: epoch.addingTimeInterval(0.31))
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 1)
        engine.advance(to: epoch.addingTimeInterval(0.33))
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 2)
        XCTAssertEqual(engine.snapshot.latestGrowth?.grapeIndex, 1)
        engine.advance(to: epoch.addingTimeInterval(0.65))
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 3)
    }

    func testTheftConsumesOnlyVisualFruitAndDuplicateCompletionIsIgnored() throws {
        let engine = VineEngine(now: epoch)
        feed(engine, count: 12)
        let event = try advanceUntilTheft(engine)
        XCTAssertFalse(event.isPreview)
        engine.completeTheft(id: UUID())
        XCTAssertEqual(engine.snapshot.activeTheft, event)
        engine.completeTheft(id: event.id)
        engine.completeTheft(id: event.id)
        XCTAssertEqual(engine.totalGrapes, 12)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 12)
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 0)
        XCTAssertNil(engine.snapshot.activeTheft)
    }

    func testPreviewDoesNotCreateCountsOrHarvests() throws {
        let storage = MemoryVineStorage()
        let engine = VineEngine(storage: storage, now: epoch)
        engine.previewTheft()
        let event = try XCTUnwrap(engine.snapshot.activeTheft)
        XCTAssertTrue(event.isPreview)
        engine.completeTheft(id: event.id)
        XCTAssertEqual(engine.totalGrapes, 0)
        XCTAssertTrue(engine.snapshot.recordedBranches.isEmpty)
        XCTAssertTrue(engine.snapshot.harvestedCounts.isEmpty)
        XCTAssertTrue(storage.values.isEmpty)
    }

    func testCanceledTheftCanReplayWithoutConsumingFruit() throws {
        let engine = VineEngine(now: epoch)
        feed(engine, count: 12)
        let canceled = try advanceUntilTheft(engine)
        engine.setTheftPresentationEnabled(false)
        engine.advance(to: engine.currentTime.addingTimeInterval(20))
        XCTAssertNil(engine.snapshot.activeTheft)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 0)
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 12)
        engine.setTheftPresentationEnabled(true)
        let replay = try advanceUntilTheft(engine)
        XCTAssertNotEqual(replay.id, canceled.id)
        engine.completeTheft(id: canceled.id)
        XCTAssertEqual(engine.snapshot.activeTheft, replay)
        engine.completeTheft(id: replay.id)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 12)
    }

    func testLargeBatchPlaysOnlyOneTheftPerCategory() throws {
        let engine = VineEngine(now: epoch)
        feed(engine, count: 30)
        let first = try advanceUntilTheft(engine)
        engine.completeTheft(id: first.id)
        engine.advance(to: engine.currentTime.addingTimeInterval(100))
        XCTAssertNil(engine.snapshot.activeTheft)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 12)
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 12)
        feed(engine, count: 1)
        let second = try advanceUntilTheft(engine)
        engine.completeTheft(id: second.id)
        XCTAssertEqual(engine.count(for: "图片"), 31)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 24)
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 7)
    }

    func testOneBatchCanPlayOneTheftForEachMatureCategory() throws {
        let engine = VineEngine(now: epoch)
        engine.beginReceiving()
        engine.recordSuccesses(categories: Array(repeating: "图片", count: 13) + Array(repeating: "文档", count: 12))
        engine.scheduleSleep()
        let first = try advanceUntilTheft(engine)
        engine.completeTheft(id: first.id)
        let second = try advanceUntilTheft(engine)
        XCTAssertNotEqual(first.category, second.category)
        engine.completeTheft(id: second.id)
        engine.advance(to: engine.currentTime.addingTimeInterval(100))
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 12)
        XCTAssertEqual(engine.harvestedGrapes(for: "文档"), 12)
        XCTAssertEqual(engine.totalGrapes, 25)
    }

    func testRestoreRetainsLegacyEncodingAndWaitsForRealWake() throws {
        let storage = MemoryVineStorage(values: [
            VineEngine.branchesKey: try JSONEncoder().encode([VineBranch(id: "图片", count: 25)]),
            VineEngine.harvestedKey: try JSONEncoder().encode(["图片": 12])
        ])
        let engine = VineEngine(storage: storage, now: epoch)
        XCTAssertEqual(engine.totalGrapes, 25)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 12)
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 12)
        XCTAssertNil(engine.snapshot.latestGrowth)
        XCTAssertNil(engine.nextDeadline)
        engine.preview()
        engine.advance(to: epoch.addingTimeInterval(10))
        XCTAssertNil(engine.snapshot.activeTheft)
        XCTAssertEqual(engine.snapshot.phase, .hidden)
        engine.wake()
        engine.calmDown()
        let event = try advanceUntilTheft(engine)
        engine.completeTheft(id: event.id)
        let restored = VineEngine(storage: storage, now: engine.currentTime)
        XCTAssertEqual(restored.count(for: "图片"), 25)
        XCTAssertEqual(restored.harvestedGrapes(for: "图片"), 24)
        XCTAssertEqual(restored.visibleGrapes(for: "图片"), 1)
    }

    func testReturningDragCancelsPendingDisappearance() {
        let engine = VineEngine(now: epoch)
        engine.wake()
        engine.advance(to: epoch.addingTimeInterval(0.46))
        XCTAssertEqual(engine.snapshot.phase, .swaying)
        engine.calmDown()
        engine.advance(to: epoch.addingTimeInterval(0.72))
        XCTAssertEqual(engine.snapshot.phase, .disappearing)
        XCTAssertFalse(engine.snapshot.isVisible)
        engine.wake()
        engine.advance(to: epoch.addingTimeInterval(2))
        XCTAssertTrue(engine.snapshot.isVisible)
        XCTAssertEqual(engine.snapshot.phase, .swaying)
    }

    func testPreviewFadesAndStopsSchedulingWhileHidden() {
        let engine = VineEngine(now: epoch)
        engine.preview()
        engine.advance(to: epoch.addingTimeInterval(6.1))
        XCTAssertEqual(engine.snapshot.phase, .disappearing)
        XCTAssertFalse(engine.snapshot.isVisible)
        engine.advance(to: epoch.addingTimeInterval(6.6))
        XCTAssertEqual(engine.snapshot.phase, .hidden)
        XCTAssertNil(engine.nextDeadline)
    }

    func testDragTargetBlocksMatureTheftUntilItLeaves() throws {
        let engine = VineEngine(now: epoch)
        engine.wake()
        feed(engine, count: 12)
        engine.advance(to: epoch.addingTimeInterval(20))
        XCTAssertNil(engine.snapshot.activeTheft)
        engine.calmDown()
        XCTAssertNotNil(try advanceUntilTheft(engine))
    }

    func testConcurrentImportDuringTheftRemainsCounted() throws {
        let engine = VineEngine(now: epoch)
        feed(engine, count: 12)
        let event = try advanceUntilTheft(engine)
        feed(engine, count: 2, category: "文档")
        engine.completeTheft(id: event.id)
        engine.advance(to: engine.currentTime.addingTimeInterval(1))
        XCTAssertEqual(engine.count(for: "图片"), 12)
        XCTAssertEqual(engine.count(for: "文档"), 2)
        XCTAssertEqual(engine.visibleGrapes(for: "文档"), 2)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 12)
    }

    func testWatchdogCompletesAnUnreportedTheft() throws {
        let engine = VineEngine(now: epoch)
        feed(engine, count: 12)
        let event = try advanceUntilTheft(engine)
        engine.advance(to: event.startedAt.addingTimeInterval(VineEngine.theftDuration + 1.01))
        XCTAssertNil(engine.snapshot.activeTheft)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 12)
    }

    func testBackwardsClockDoesNotRewindState() {
        let engine = VineEngine(now: epoch)
        engine.preview()
        engine.advance(to: epoch.addingTimeInterval(1))
        engine.advance(to: epoch.addingTimeInterval(-1))
        XCTAssertEqual(engine.currentTime, epoch.addingTimeInterval(1))
        XCTAssertTrue(engine.snapshot.isVisible)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let engine = VineEngine(now: epoch)
        feed(engine, count: 1)
        let encoded = try JSONEncoder().encode(engine.snapshot)
        XCTAssertEqual(try JSONDecoder().decode(VineSnapshot.self, from: encoded), engine.snapshot)
    }
}
