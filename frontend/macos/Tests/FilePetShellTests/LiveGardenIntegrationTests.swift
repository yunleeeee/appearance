import Foundation
import XCTest
@testable import FilePetShell

/// Start the live service with backend/ as its authorized root so the temporary
/// fixtures and scripts/examples/ are both inside the same explicit boundary.
@MainActor
final class LiveGardenIntegrationTests: XCTestCase {
    func testRealHTTPFeedsFlowersAndGrapesAndPersistsHarvestWithoutChangingFiles() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["FILEPET_LIVE_ENGINE_URL"],
              let examplesPath = environment["FILEPET_LIVE_EXAMPLES"] else {
            throw XCTSkip("Set FILEPET_LIVE_ENGINE_URL and FILEPET_LIVE_EXAMPLES to run the live garden check")
        }
        let client = try EngineClient(baseURL: XCTUnwrap(URL(string: endpoint)))
        let examples = URL(fileURLWithPath: examplesPath, isDirectory: true).standardizedFileURL
        let backend = examples.deletingLastPathComponent().deletingLastPathComponent()
        let manager = FileManager.default
        let backendBefore = try manager.contentsOfDirectory(atPath: backend.path).sorted()
        let fixtures = backend.appendingPathComponent(".live-garden-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: fixtures, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: fixtures) }

        let ddlFiles = try (1...4).map { index -> URL in
            let file = fixtures.appendingPathComponent("deadline-\(index).txt")
            let text = "软件工程实验报告。请于2026年11月\(index + 2)日23:59前提交第\(index)次实验报告。"
            try text.write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        let financeFiles = try (1...2).map { index -> URL in
            let file = fixtures.appendingPathComponent("finance-\(index).txt")
            try "差旅报销：发票、付款金额、费用核对。".write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        let files = ddlFiles + financeFiles
        let originals = try files.map { try Data(contentsOf: $0) }
        let fixtureNames = try manager.contentsOfDirectory(atPath: fixtures.path).sorted()

        let suite = "FilePetShell.LiveGardenIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShellStore(client: client, defaults: defaults, arguments: [],
                               pollInterval: 20_000_000, jobTimeout: 15)
        store.classifyFiles(files)
        await store.waitUntilIdle()

        XCTAssertEqual(store.results.map(\.outcome), [.deadline, .deadline, .deadline, .deadline, .classified, .classified])
        XCTAssertEqual(store.garden.deadlines.count, 4, store.status)
        XCTAssertEqual(store.garden.visibleDeadlines.count, 3)
        XCTAssertEqual(store.garden.queuedCount, 1)
        XCTAssertEqual(store.garden.deadlines.map(\.dueDate), ["2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"])
        XCTAssertEqual(store.garden.deadlines.map(\.dueTime), Array(repeating: "23:59", count: 4))
        XCTAssertEqual(store.vine.count(for: "finance"), 2)
        XCTAssertEqual(store.vine.totalGrapes, 2, "DDL-bearing files must use the flower route")
        let firstFlower = try XCTUnwrap(store.garden.visibleDeadlines.first)
        let originallyQueued = try XCTUnwrap(store.garden.deadlines.last)
        XCTAssertFalse(firstFlower.title.isEmpty)
        XCTAssertFalse(firstFlower.project.isEmpty)

        let completedAt = Date()
        store.garden.harvest(id: firstFlower.id, now: completedAt)
        XCTAssertEqual(store.garden.visibleDeadlines.map(\.id), Array(store.garden.deadlines.dropFirst().map(\.id)))
        XCTAssertEqual(store.garden.visibleDeadlines.last?.id, originallyQueued.id)
        XCTAssertEqual(store.garden.queuedCount, 0)
        XCTAssertEqual(store.garden.deadlines.first?.completedAt, completedAt)

        let restoredStore = ShellStore(client: client, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)),
                                       arguments: [], pollInterval: 20_000_000, jobTimeout: 15)
        XCTAssertEqual(restoredStore.garden.deadlines, store.garden.deadlines)
        XCTAssertEqual(restoredStore.vine.count(for: "finance"), 2)
        restoredStore.classifyFiles(files)
        await restoredStore.waitUntilIdle()

        XCTAssertEqual(restoredStore.results.map(\.outcome), [.deadline, .deadline, .deadline, .deadline, .classified, .classified])
        XCTAssertEqual(restoredStore.garden.deadlines.count, 4)
        XCTAssertEqual(restoredStore.garden.deadlines.first?.completedAt, completedAt)
        XCTAssertFalse(restoredStore.garden.visibleDeadlines.contains { $0.id == firstFlower.id })
        XCTAssertEqual(restoredStore.garden.visibleDeadlines.count, 3)
        XCTAssertEqual(restoredStore.garden.queuedCount, 0)
        XCTAssertEqual(restoredStore.vine.count(for: "finance"), 2)
        XCTAssertEqual(restoredStore.vine.totalGrapes, 2)
        for (file, original) in zip(files, originals) {
            XCTAssertEqual(try Data(contentsOf: file), original, file.lastPathComponent)
        }
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: fixtures.path).sorted(), fixtureNames)
        try manager.removeItem(at: fixtures)
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: backend.path).sorted(), backendBefore)
    }
}
