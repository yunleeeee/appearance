import Foundation
import XCTest
@testable import FilePetShell

/// Opt-in end-to-end check using a synthetic image and a real OCR engine.
@MainActor
final class LiveImageArchiveIntegrationTests: XCTestCase {
    func testRealOCRArchivesOnceAndPreservesTaskIdentityAfterRestart() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["FILEPET_LIVE_ENGINE_URL"],
              let examplesPath = environment["FILEPET_LIVE_EXAMPLES"],
              let imagePath = environment["FILEPET_LIVE_OCR_IMAGE"],
              let expectedTitle = environment["FILEPET_LIVE_OCR_TITLE"],
              let expectedDate = environment["FILEPET_LIVE_OCR_DATE"] else {
            throw XCTSkip("Set the live engine and synthetic OCR image fixture variables")
        }
        let client = try EngineClient(baseURL: XCTUnwrap(URL(string: endpoint)))
        let manager = FileManager.default
        let backend = URL(fileURLWithPath: examplesPath, isDirectory: true)
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = backend.appendingPathComponent(".live-image-archive-\(UUID().uuidString)")
        try manager.createDirectory(at: fixture, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: fixture) }
        let archive = fixture.appendingPathComponent("archive", isDirectory: true)
        try manager.createDirectory(at: archive, withIntermediateDirectories: false)
        let bytes = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let first = fixture.appendingPathComponent("已粘贴 2026-11-07 下午8.14.18.png")
        let duplicate = fixture.appendingPathComponent("已粘贴 2026-11-07 下午8.15.19.png")
        try bytes.write(to: first)
        try bytes.write(to: duplicate)

        let suite = "FilePetShell.LiveImageArchiveIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShellStore(client: client, defaults: defaults, arguments: [],
                               pollInterval: 20_000_000, jobTimeout: 30)
        store.archive.selectDestination(archive)
        store.classifyFiles([first])
        await store.waitUntilIdle()

        XCTAssertEqual(store.results.map(\.outcome), [.deadline], store.status)
        XCTAssertEqual(store.vine.count(for: "learning"), 1)
        XCTAssertEqual(store.garden.deadlines.count, 1)
        XCTAssertTrue(store.reviewInbox.items.isEmpty)
        let task = try XCTUnwrap(store.garden.deadlines.first)
        XCTAssertEqual(task.title, expectedTitle)
        XCTAssertEqual(task.dueDate, expectedDate)
        XCTAssertEqual(task.dueTime, "23:59")
        XCTAssertNotNil(task.semanticKey)
        let stored = URL(fileURLWithPath: try XCTUnwrap(task.sourcePath))
        XCTAssertTrue(stored.path.hasPrefix(archive.path + "/"))
        XCTAssertEqual(stored.lastPathComponent, expectedTitle + ".png")
        XCTAssertEqual(try Data(contentsOf: stored), bytes)
        XCTAssertFalse(manager.fileExists(atPath: first.path))

        store.classifyFiles([duplicate])
        await store.waitUntilIdle()
        XCTAssertEqual(store.results.map(\.outcome), [.deadline], store.status)
        XCTAssertEqual(store.vine.totalGrapes, 1)
        XCTAssertEqual(store.garden.deadlines.map(\.id), [task.id])
        XCTAssertFalse(manager.fileExists(atPath: duplicate.path))
        XCTAssertEqual(try manager.contentsOfDirectory(atPath: stored.deletingLastPathComponent().path),
                       [stored.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: stored), bytes)

        let completedAt = Date()
        store.garden.harvest(id: task.id, now: completedAt)
        XCTAssertEqual(store.garden.deadlines.first?.completedAt, completedAt)
        let restored = ShellStore(client: client, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)),
                                  arguments: [], pollInterval: 20_000_000, jobTimeout: 30)
        restored.classifyFiles([stored])
        await restored.waitUntilIdle()
        XCTAssertEqual(restored.results.count, 1)
        XCTAssertNotEqual(restored.results.first?.outcome, .failed, restored.status)
        XCTAssertEqual(restored.vine.totalGrapes, 1)
        XCTAssertEqual(restored.garden.deadlines.count, 1)
        XCTAssertEqual(restored.garden.deadlines.first?.completedAt, completedAt)
        XCTAssertTrue(restored.garden.visibleDeadlines.isEmpty)
        XCTAssertEqual(restored.garden.deadlines.first?.sourcePath, stored.path)
        XCTAssertEqual(try Data(contentsOf: stored), bytes)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: imagePath)), bytes)
    }
}
