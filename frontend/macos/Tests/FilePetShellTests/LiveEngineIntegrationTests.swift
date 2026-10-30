import Foundation
import XCTest
@testable import FilePetShell

/// Opt in against a separately started engine whose --root is the bundled examples directory.
/// The normal test suite stays independent of a running service and skips this case.
@MainActor
final class LiveEngineIntegrationTests: XCTestCase {
    func testRealHTTPClassificationFeedsAppearanceWithoutChangingOriginals() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["FILEPET_LIVE_ENGINE_URL"],
              let examplesPath = environment["FILEPET_LIVE_EXAMPLES"] else {
            throw XCTSkip("Set FILEPET_LIVE_ENGINE_URL and FILEPET_LIVE_EXAMPLES to run the live bridge check")
        }
        let url = try XCTUnwrap(URL(string: endpoint))
        let client = try EngineClient(baseURL: url)
        let examples = URL(fileURLWithPath: examplesPath, isDirectory: true).standardizedFileURL
        let files = ["recruitment.txt", "finance.txt", "unknown.txt"].map { examples.appendingPathComponent($0) }
        let originals = try files.map { try Data(contentsOf: $0) }
        let directoryBefore = try FileManager.default.contentsOfDirectory(atPath: examples.path).sorted()

        let health = try await client.health()
        XCTAssertEqual(health.status, "ok")
        let categories = try await client.categories()
        XCTAssertTrue(categories.contains { $0.id == "recruitment" && $0.label == "招聘项目" })
        XCTAssertTrue(categories.contains { $0.id == "finance" && $0.label == "财务与报销" })

        let suite = "FilePetShell.LiveEngineIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShellStore(client: client, defaults: defaults, arguments: [],
                               pollInterval: 20_000_000, jobTimeout: 15)
        store.classifyFiles(files)
        await store.waitUntilIdle()

        XCTAssertFalse(store.isBusy)
        XCTAssertEqual(store.results.map(\.fileName), ["recruitment.txt", "finance.txt", "unknown.txt"])
        XCTAssertEqual(store.results.map(\.outcome), [.classified, .classified, .needsReview])
        XCTAssertEqual(store.results.map(\.categoryLabel), ["招聘项目", "财务与报销", nil])
        XCTAssertEqual(store.vine.count(for: "recruitment"), 1)
        XCTAssertEqual(store.vine.count(for: "finance"), 1)
        XCTAssertEqual(store.vine.count(for: "文档"), 0)
        XCTAssertEqual(store.vine.totalGrapes, 2)
        XCTAssertEqual(store.vine.displayName(for: "recruitment"), "招聘项目")
        XCTAssertEqual(store.vine.displayName(for: "finance"), "财务与报销")
        XCTAssertTrue(store.status.contains("2 个已识别，1 个待确认，0 个失败"), store.status)

        // Exercise Python's actual --root guard through the same shell path.
        let outsideRoot = examples.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("README.md")
        if FileManager.default.fileExists(atPath: outsideRoot.path) {
            let outsideOriginal = try Data(contentsOf: outsideRoot)
            store.classifyFiles([outsideRoot])
            await store.waitUntilIdle()
            XCTAssertEqual(store.results.map(\.outcome), [.failed])
            XCTAssertTrue(store.results[0].detail.contains("授权"), store.results[0].detail)
            XCTAssertEqual(store.vine.totalGrapes, 2)
            XCTAssertEqual(try Data(contentsOf: outsideRoot), outsideOriginal)
        }

        for (file, original) in zip(files, originals) {
            XCTAssertEqual(try Data(contentsOf: file), original, file.lastPathComponent)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: examples.path).sorted(), directoryBefore)
    }
}
