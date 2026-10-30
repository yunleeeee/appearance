import Foundation
import XCTest
@testable import FilePetShell

final class VineStorageTests: XCTestCase {
    func testJSONArchivePersistsAcrossInstancesAndKeepsReadableValues() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("state.json")
        let storage = JSONFileVineStorage(fileURL: archive)
        let engine = VineEngine(storage: storage)
        engine.beginReceiving()
        engine.recordSuccesses(categories: ["图片", "文档", "图片"])
        let restored = VineEngine(storage: JSONFileVineStorage(fileURL: archive))
        XCTAssertEqual(restored.count(for: "图片"), 2)
        XCTAssertEqual(restored.count(for: "文档"), 1)
        XCTAssertNil(restored.snapshot.persistenceError)
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: archive)) as? [String: Any])
        XCTAssertNotNil(values[VineEngine.branchesKey] as? [[String: Any]])
    }

    func testMalformedArchiveSurfacesErrorWithoutOverwritingIt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let invalid = Data("this is not JSON".utf8)
        try invalid.write(to: file)
        let engine = VineEngine(storage: JSONFileVineStorage(fileURL: file))
        XCTAssertNotNil(engine.snapshot.persistenceError)
        engine.recordSuccess(category: "图片")
        XCTAssertEqual(try Data(contentsOf: file), invalid)
        XCTAssertEqual(engine.count(for: "图片"), 1)
    }

    func testLegacyNegativeCountsAndExcessHarvestAreClamped() throws {
        let storage = MemoryVineStorage(values: [
            VineEngine.branchesKey: try JSONEncoder().encode([VineBranch(id: "图片", count: 3), VineBranch(id: "文档", count: -2)]),
            VineEngine.harvestedKey: try JSONEncoder().encode(["图片": 100, "文档": -10])
        ])
        let engine = VineEngine(storage: storage)
        XCTAssertEqual(engine.count(for: "文档"), 0)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), 3)
        XCTAssertEqual(engine.harvestedGrapes(for: "文档"), 0)
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 0)
    }

    func testDuplicateLegacyCategoriesMergeWithoutChangingFirstSeenOrder() throws {
        let storage = MemoryVineStorage(values: [
            VineEngine.branchesKey: try JSONEncoder().encode([
                VineBranch(id: "图片", count: 2), VineBranch(id: "文档", count: 5),
                VineBranch(id: "图片", count: 3), VineBranch(id: "文档", count: -4)
            ]),
            VineEngine.harvestedKey: try JSONEncoder().encode(["图片": 1])
        ])
        let engine = VineEngine(storage: storage)
        XCTAssertEqual(engine.snapshot.recordedBranches, [VineBranch(id: "图片", count: 5), VineBranch(id: "文档", count: 5)])
        XCTAssertEqual(engine.snapshot.branches.map(\.id), ["图片", "文档"])
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 4)
        XCTAssertEqual(engine.totalGrapes, 10)
        engine.recordSuccess(category: "图片")
        let normalized = try JSONDecoder().decode([VineBranch].self, from: XCTUnwrap(storage.data(forKey: VineEngine.branchesKey)))
        XCTAssertEqual(normalized, [VineBranch(id: "图片", count: 6), VineBranch(id: "文档", count: 5)])
    }

    func testMaximumCountsSaturateWhenMergingSummingAndRecording() throws {
        let storage = MemoryVineStorage(values: [
            VineEngine.branchesKey: try JSONEncoder().encode([
                VineBranch(id: "图片", count: Int.max), VineBranch(id: "文档", count: 1),
                VineBranch(id: "图片", count: 20)
            ])
        ])
        let engine = VineEngine(storage: storage)
        XCTAssertEqual(engine.count(for: "图片"), Int.max)
        XCTAssertEqual(engine.totalGrapes, Int.max)
        XCTAssertEqual(engine.snapshot.recordedBranches.count, 2)
        engine.recordSuccess(category: "图片")
        XCTAssertEqual(engine.count(for: "图片"), Int.max)
        XCTAssertEqual(engine.totalGrapes, Int.max)
        XCTAssertNil(engine.persistenceError)
    }

    func testHarvestNearMaximumCountDoesNotOverflow() throws {
        let storage = MemoryVineStorage(values: [
            VineEngine.branchesKey: try JSONEncoder().encode([VineBranch(id: "图片", count: Int.max)]),
            VineEngine.harvestedKey: try JSONEncoder().encode(["图片": Int.max - 12])
        ])
        let engine = VineEngine(storage: storage)
        engine.wake()
        engine.calmDown()
        let deadline = try XCTUnwrap(engine.nextDeadline)
        engine.advance(to: deadline)
        let event = try XCTUnwrap(engine.snapshot.activeTheft)
        engine.completeTheft(id: event.id)
        XCTAssertEqual(engine.harvestedGrapes(for: "图片"), Int.max)
        XCTAssertEqual(engine.visibleGrapes(for: "图片"), 0)
        XCTAssertEqual(engine.count(for: "图片"), Int.max)
    }
}
