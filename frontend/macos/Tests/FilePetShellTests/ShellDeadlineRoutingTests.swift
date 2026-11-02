import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class ShellDeadlineRoutingTests: XCTestCase {
    func testDDLAndGrapeAreBothRecordedWhenTopicClassificationSucceeds() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidates = (1...5).map { deadline("ddl-\($0)") }
        let engine = GardenShellEngine(results: [result(deadlines: candidates)])
        let store = makeStore(engine, defaults: defaults)

        store.classifyFiles([file("notice.txt")])
        await store.waitUntilIdle()

        XCTAssertEqual(store.results.map(\.outcome), [.deadline])
        XCTAssertEqual(store.garden.visibleDeadlines.map(\.id), ["ddl-1"])
        XCTAssertEqual(store.garden.queuedCount, 4)
        XCTAssertEqual(store.vine.totalGrapes, 1)
        XCTAssertEqual(store.vine.count(for: "learning"), 1)
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

        XCTAssertEqual(store.results.map(\.outcome), [.needsReview])
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
        XCTAssertEqual(firstStore.garden.visibleDeadlines.map(\.id), ["ddl-2"])

        let restoredStore = makeStore(GardenShellEngine(results: [response]),
                                     defaults: UserDefaults(suiteName: suite)!)
        restoredStore.classifyFiles([file("notice.txt")])
        await restoredStore.waitUntilIdle()

        XCTAssertEqual(restoredStore.garden.deadlines.count, 4)
        XCTAssertEqual(restoredStore.garden.deadlines[0].completedAt, completedAt)
        XCTAssertEqual(restoredStore.garden.visibleDeadlines.map(\.id), ["ddl-2"])
        XCTAssertEqual(restoredStore.garden.queuedCount, 2)
        XCTAssertEqual(restoredStore.results.map(\.outcome), [.deadline])
        XCTAssertEqual(restoredStore.vine.totalGrapes, 1)
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
        XCTAssertTrue(firstStore.results[0].detail.contains("已计数"))

        let restoredStore = makeStore(GardenShellEngine(results: [response, response]),
                                     defaults: UserDefaults(suiteName: suite)!)
        restoredStore.classifyFiles([file("second.txt"), file("third.txt")])
        await restoredStore.waitUntilIdle()
        XCTAssertEqual(restoredStore.vine.count(for: "learning"), 3)
        XCTAssertEqual(restoredStore.vine.branches.map(\.id), ["learning"])
        XCTAssertTrue(restoredStore.garden.deadlines.isEmpty)
    }

    func testRenamedSameScreenshotOnlyAddsOneGrapeAndOneFlowerAcrossRestart() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = result(deadlines: [deadline("capture-1")])
        first.contentFingerprint = String(repeating: "a", count: 64)
        first.deadlines[0].semanticKey = "same-assignment"
        var second = result(deadlines: [deadline("capture-2")])
        second.contentFingerprint = first.contentFingerprint
        second.deadlines[0].semanticKey = "same-assignment"

        let store = makeStore(GardenShellEngine(results: [first, second]), defaults: defaults)
        let imgA = file("已粘贴 2026-11-01 下午8.14.18.png")
        let imgB = file("已粘贴 2026-11-02 下午8.14.18.png")
        store.classifyFiles([imgA, imgB])
        await store.waitUntilIdle()
        XCTAssertEqual(store.results.map(\.fileName), ["截图", "截图"])
        XCTAssertEqual(store.vine.count(for: "learning"), 1)
        XCTAssertEqual(store.garden.deadlines.count, 1)
        XCTAssertTrue(store.results[1].detail.contains("相同截图已处理"))

        let restored = makeStore(GardenShellEngine(results: [second]),
                                 defaults: UserDefaults(suiteName: suite)!)
        restored.classifyFiles([imgB])
        await restored.waitUntilIdle()
        XCTAssertEqual(restored.vine.count(for: "learning"), 1)
        XCTAssertEqual(restored.garden.deadlines.count, 1)
    }

    func testDuplicateUnconfirmedOCROnTwoPathsStaysOneQuietReview() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var first = result(deadlines: [deadline("ocr-one")])
        first.contentFingerprint = String(repeating: "b", count: 64)
        first.deadlines[0].semanticKey = "same-ocr-review"
        first.deadlines[0].confirmationRequired = true
        var second = result(deadlines: [deadline("ocr-two")])
        second.contentFingerprint = first.contentFingerprint
        second.deadlines[0].semanticKey = "same-ocr-review"
        second.deadlines[0].confirmationRequired = true
        let store = makeStore(GardenShellEngine(results: [first, second]), defaults: defaults)
        let pathA = file("已粘贴 2026-11-01 下午8.14.18.png")
        let pathB = file("已粘贴 2026-11-02 下午8.14.18.png")
        store.classifyFiles([pathA, pathB])
        await store.waitUntilIdle()
        XCTAssertEqual(store.garden.deadlines.count, 0)
        XCTAssertEqual(store.reviewInbox.items.count, 1)
        XCTAssertEqual(store.reviewInbox.items[0].candidates.count, 1)
        XCTAssertEqual(store.vine.count(for: "learning"), 1)

        // Re-feeding the same source must not silently erase the pending DDL.
        let again = makeStore(GardenShellEngine(results: [first]),
                              defaults: UserDefaults(suiteName: suite)!)
        again.classifyFiles([pathA])
        await again.waitUntilIdle()
        XCTAssertEqual(again.reviewInbox.items.count, 1)
        XCTAssertEqual(again.reviewInbox.items[0].candidates.count, 1)
    }

    func testTwoUnknownDuplicatesShareReviewAndManualConfirmationCountsOneGrape() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var uncertain = result(status: "needs_review", category: nil)
        uncertain.contentFingerprint = String(repeating: "c", count: 64)
        let one = file("已粘贴 2026-11-01 下午8.14.18.png")
        let two = file("已粘贴 2026-11-02 下午8.14.18.png")
        let store = makeStore(GardenShellEngine(results: [uncertain, uncertain]),
                              defaults: defaults)
        store.classifyFiles([one, two])
        await store.waitUntilIdle()
        XCTAssertEqual(store.reviewInbox.items.count, 1)
        XCTAssertEqual(store.vine.totalGrapes, 0)
        let pending = store.reviewInbox.items[0]
        XCTAssertEqual(store.confirmCategory(reviewID: pending.id, categoryID: "learning"), nil)
        XCTAssertEqual(store.vine.count(for: "learning"), 1)

        var classified = result()
        classified.contentFingerprint = uncertain.contentFingerprint
        let reopened = makeStore(GardenShellEngine(results: [classified]),
                                 defaults: UserDefaults(suiteName: suite)!)
        reopened.classifyFiles([two])
        await reopened.waitUntilIdle()
        XCTAssertEqual(reopened.vine.count(for: "learning"), 1)
    }

    func testClassifiedFileMovesToChosenFolderAndUpdatesDeadlineSource() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("分类存储")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("作业.txt")
        try Data("original content".utf8).write(to: original)

        var sourceDeadline = deadline("archived-ddl")
        sourceDeadline.sourcePath = original.path
        let response = result(deadlines: [sourceDeadline])
        let shell = makeStore(GardenShellEngine(results: [response, response]), defaults: defaults)
        shell.archive.selectDestination(destination)
        shell.classifyFiles([original])
        await shell.waitUntilIdle()
        let copied = destination.appendingPathComponent("课程与学习/作业.txt")
        XCTAssertEqual(try Data(contentsOf: copied), Data("original content".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(shell.vine.totalGrapes, 1)
        XCTAssertEqual(shell.garden.deadlines.count, 1)
        XCTAssertEqual(shell.garden.deadlines[0].sourcePath, copied.path)
        XCTAssertTrue(shell.results[0].detail.contains("已移动至课程与学习"))

        shell.classifyFiles([original])
        await shell.waitUntilIdle()
        XCTAssertEqual(shell.vine.totalGrapes, 1)
        XCTAssertEqual(shell.garden.deadlines.count, 1)
        XCTAssertTrue(shell.results[0].detail.contains("文件已归档"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("课程与学习/作业 (2).txt").path))
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
        var result = EngineClassificationResult(path: path, fileName: URL(fileURLWithPath: path).lastPathComponent,
                                               status: template.status, categoryID: template.categoryID,
                                               categoryLabel: template.categoryLabel, confidence: template.confidence,
                                               matchedKeywords: template.matchedKeywords, reason: template.reason,
                                               extractionChars: template.extractionChars, deadlines: template.deadlines)
        result.contentFingerprint = template.contentFingerprint
        let id = UUID().uuidString
        jobs[id] = EngineJob(jobID: id, status: terminalStatus, result: result, error: nil)
        return EngineJobAccepted(jobID: id, status: "queued")
    }
    func job(id: String) async throws -> EngineJob {
        guard let job = jobs[id] else { throw URLError(.badServerResponse) }
        return job
    }
}
