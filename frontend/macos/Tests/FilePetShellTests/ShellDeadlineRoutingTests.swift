import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class ShellDeadlineRoutingTests: XCTestCase {
    func testDDLResultsTakeFlowerRouteEvenWhenTopicClassificationSucceeds() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidates = (1...5).map { deadline("ddl-\($0)") }
        let engine = GardenShellEngine(results: [result(deadlines: candidates)])
        let store = makeStore(engine, defaults: defaults)

        store.classifyFiles([file("notice.txt")])
        await store.waitUntilIdle()

        XCTAssertEqual(store.results.map(\.outcome), [.deadline])
        XCTAssertEqual(store.garden.visibleDeadlines.map(\.id), ["ddl-1", "ddl-2", "ddl-3"])
        XCTAssertEqual(store.garden.queuedCount, 2)
        XCTAssertEqual(store.vine.totalGrapes, 0)
        XCTAssertTrue(store.status.contains("1 份 DDL"))
    }

    func testDeadlineOnlyReviewResultStillCreatesFlower() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = GardenShellEngine(results: [result(status: "needs_review", category: nil,
                                                      deadlines: [deadline("only-ddl")])],
                                       terminalStatus: "needs_review")
        let store = makeStore(engine, defaults: defaults)
        store.classifyFiles([file("unclassified-notice.txt")])
        await store.waitUntilIdle()

        XCTAssertEqual(store.results.map(\.outcome), [.deadline])
        XCTAssertEqual(store.garden.visibleDeadlines.map(\.id), ["only-ddl"])
        XCTAssertEqual(store.vine.totalGrapes, 0)
    }

    func testHarvestedDDLStaysCompletedAfterRestartAndRepeatedFileFeed() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let response = result(deadlines: (1...4).map { deadline("ddl-\($0)") })
        let firstStore = makeStore(GardenShellEngine(results: [response]), defaults: defaults)
        firstStore.classifyFiles([file("notice.txt")])
        await firstStore.waitUntilIdle()
        let completedAt = Date(timeIntervalSince1970: 2_000)
        firstStore.garden.harvest(id: "ddl-1", now: completedAt)
        XCTAssertEqual(firstStore.garden.visibleDeadlines.map(\.id), ["ddl-2", "ddl-3", "ddl-4"])

        let restoredStore = makeStore(GardenShellEngine(results: [response]),
                                     defaults: UserDefaults(suiteName: suite)!)
        restoredStore.classifyFiles([file("notice.txt")])
        await restoredStore.waitUntilIdle()

        XCTAssertEqual(restoredStore.garden.deadlines.count, 4)
        XCTAssertEqual(restoredStore.garden.deadlines[0].completedAt, completedAt)
        XCTAssertEqual(restoredStore.garden.visibleDeadlines.map(\.id), ["ddl-2", "ddl-3", "ddl-4"])
        XCTAssertEqual(restoredStore.garden.queuedCount, 0)
        XCTAssertEqual(restoredStore.results.map(\.outcome), [.deadline])
        XCTAssertEqual(restoredStore.vine.totalGrapes, 0)
    }

    func testEachNewOrdinaryFileAddsOneGrapeToItsCategoryAndRepeatedFeedDoesNot() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let response = result()
        let engine = GardenShellEngine(results: [response, response, response])
        let firstStore = makeStore(engine, defaults: defaults)
        firstStore.classifyFiles([file("first.txt"), file("second.txt")])
        await firstStore.waitUntilIdle()
        XCTAssertEqual(firstStore.vine.count(for: "learning"), 2)
        XCTAssertEqual(firstStore.vine.branches.map(\.id), ["learning"])

        firstStore.classifyFiles([file("first.txt")])
        await firstStore.waitUntilIdle()
        XCTAssertEqual(firstStore.vine.count(for: "learning"), 2)
        XCTAssertEqual(firstStore.results.map(\.outcome), [.classified])
        XCTAssertTrue(firstStore.results[0].detail.contains("已分类"))

        let restoredStore = makeStore(GardenShellEngine(results: [response, response]),
                                     defaults: UserDefaults(suiteName: suite)!)
        restoredStore.classifyFiles([file("second.txt"), file("third.txt")])
        await restoredStore.waitUntilIdle()
        XCTAssertEqual(restoredStore.vine.count(for: "learning"), 3)
        XCTAssertEqual(restoredStore.vine.branches.map(\.id), ["learning"])
        XCTAssertTrue(restoredStore.garden.deadlines.isEmpty)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "FilePetShell.ShellDeadlineRoutingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeStore(_ engine: GardenShellEngine, defaults: UserDefaults) -> ShellStore {
        ShellStore(client: engine, defaults: defaults, arguments: [], pollInterval: 1_000_000, jobTimeout: 1)
    }

    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/filepet-garden-tests/" + name) }

    private func deadline(_ id: String) -> EngineDeadline {
        EngineDeadline(id: id, title: "提交实验报告", project: "软件工程",
                       dueDate: "2026-11-03", dueTime: "23:59", yearInferred: false,
                       evidence: "请于2026年11月3日23:59前提交实验报告")
    }

    private func result(status: String = "classified", category: String? = "learning",
                        deadlines: [EngineDeadline] = []) -> EngineClassificationResult {
        EngineClassificationResult(path: "/tmp/placeholder.txt", fileName: "placeholder.txt", status: status,
                                   categoryID: category, categoryLabel: category == nil ? nil : "课程与学习",
                                   confidence: 0.9, matchedKeywords: [], reason: "分类核心结果",
                                   extractionChars: 50, deadlines: deadlines)
    }
}

private actor GardenShellEngine: EngineServing {
    private var results: [EngineClassificationResult]
    private let terminalStatus: String
    private var jobs: [String: EngineJob] = [:]

    init(results: [EngineClassificationResult], terminalStatus: String = "completed") {
        self.results = results
        self.terminalStatus = terminalStatus
    }

    func health() async throws -> EngineHealth { EngineHealth(status: "ok", version: "test") }
    func categories() async throws -> [EngineCategory] {
        [EngineCategory(id: "learning", label: "课程与学习", description: "")]
    }
    func createJob(path: String) async throws -> EngineJobAccepted {
        guard !results.isEmpty else { throw URLError(.badServerResponse) }
        let template = results.removeFirst()
        let result = EngineClassificationResult(path: path, fileName: URL(fileURLWithPath: path).lastPathComponent,
                                               status: template.status, categoryID: template.categoryID,
                                               categoryLabel: template.categoryLabel, confidence: template.confidence,
                                               matchedKeywords: template.matchedKeywords, reason: template.reason,
                                               extractionChars: template.extractionChars, deadlines: template.deadlines)
        let id = UUID().uuidString
        jobs[id] = EngineJob(jobID: id, status: terminalStatus, result: result, error: nil)
        return EngineJobAccepted(jobID: id, status: "queued")
    }
    func job(id: String) async throws -> EngineJob {
        guard let job = jobs[id] else { throw URLError(.badServerResponse) }
        return job
    }
}
