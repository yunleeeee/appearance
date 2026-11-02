import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class AutomaticImageDeadlineTests: XCTestCase {
    func testClearlyDatedScreenshotGrowsGrapeAndFlowerByDefault() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = AutomaticDeadlineEngine(results: [
            response(deadlines: [deadline("auto-1", key: "task-1")])
        ])
        let store = makeStore(engine, defaults: defaults)
        XCTAssertTrue(store.autoAcceptImageDeadlines)
        store.classifyFiles([image("assignment.png")])
        await store.waitUntilIdle()
        XCTAssertEqual(store.vine.count(for: "learning"), 1)
        XCTAssertEqual(store.garden.activeDeadlines.map(\.id), ["auto-1"])
        XCTAssertTrue(store.reviewInbox.items.isEmpty)
        XCTAssertEqual(store.results.map(\.outcome), [.deadline])
    }

    func testStrictModeHoldsClearImagesButCanBeDisabledAgain() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidate = deadline("auto-2", key: "task-2")
        let store = makeStore(AutomaticDeadlineEngine(results: [
            response(deadlines: [candidate]),
            response(deadlines: [candidate])
        ]), defaults: defaults)
        store.setAutoAcceptImageDeadlines(false)
        XCTAssertFalse(store.autoAcceptImageDeadlines)
        store.classifyFiles([image("assignment.png")])
        await store.waitUntilIdle()
        XCTAssertTrue(store.garden.deadlines.isEmpty)
        XCTAssertEqual(store.reviewInbox.items.first?.candidates.count, 1)
        XCTAssertEqual(store.vine.totalGrapes, 1)

        store.setAutoAcceptImageDeadlines(true)
        store.classifyFiles([image("assignment.png")])
        await store.waitUntilIdle()
        XCTAssertEqual(store.garden.deadlines.map(\.id), ["auto-2"])
        XCTAssertTrue(store.reviewInbox.items.isEmpty,
            "Do not leave an old OCR review after accepting the same candidate automatically")
        XCTAssertEqual(store.vine.totalGrapes, 1)

        let restarted = makeStore(AutomaticDeadlineEngine(results: []),
                              defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(restarted.autoAcceptImageDeadlines)
        XCTAssertEqual(restarted.garden.deadlines.count, 1)
    }

    func testInferredYearRemainsPendingEvenWithAutomaticMode() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var uncertain = deadline("inferred", key: "task-inferred")
        // Mimic a backend which insists on manual review for inferred years.
        uncertain.confirmationRequired = true
        uncertain.reliability = "low"
        let store = makeStore(AutomaticDeadlineEngine(results: [
            response(deadlines: [uncertain])
        ]), defaults: defaults)
        store.classifyFiles([image("uncertain.png")])
        await store.waitUntilIdle()
        XCTAssertTrue(store.garden.deadlines.isEmpty)
        XCTAssertEqual(store.reviewInbox.items.first?.candidates.count, 1)
        XCTAssertEqual(store.vine.totalGrapes, 1)
    }

    func testRepeatedAutoScreenshotDoesNotDuplicateGardenOrGrape() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = deadline("source-one", key: "same-task")
        let second = deadline("source-two", key: "same-task")
        let engine = AutomaticDeadlineEngine(results: [
            response(deadlines: [first]),
            response(deadlines: [second])
        ])
        let store = makeStore(engine, defaults: defaults)
        store.classifyFiles([image("first.png"), image("second.png")])
        await store.waitUntilIdle()
        XCTAssertEqual(store.garden.deadlines.count, 1)
        XCTAssertEqual(store.vine.totalGrapes, 1)
        store.garden.harvest(id: "source-one")
        XCTAssertNotNil(store.garden.deadlines.first?.completedAt)
        XCTAssertEqual(store.garden.undoLastHarvest(), "source-one")
    }

    func testDifferentCropsOfOneTaskDoNotGrowExtraGrapesAcrossRestart() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var whole = response(deadlines: [deadline("whole", key: "network-chapter-four")])
        whole.contentFingerprint = String(repeating: "a", count: 64)
        var crop = response(deadlines: [deadline("crop", key: "network-chapter-four")])
        crop.contentFingerprint = String(repeating: "b", count: 64)
        let initial = makeStore(AutomaticDeadlineEngine(results: [whole, crop]), defaults: defaults)
        initial.classifyFiles([image("full.png"), image("tight-crop.png")])
        await initial.waitUntilIdle()
        XCTAssertEqual(initial.vine.totalGrapes, 1,
                       "Different OCR text can still describe the same verified assignment")
        XCTAssertEqual(initial.garden.deadlines.count, 1)
        XCTAssertEqual(initial.results.count, 2)

        var newTask = response(deadlines: [
            deadline("existing-another-crop", key: "network-chapter-four"),
            deadline("distinct", key: "network-chapter-five")
        ])
        newTask.contentFingerprint = String(repeating: "c", count: 64)
        let restarted = makeStore(AutomaticDeadlineEngine(results: [newTask]),
                                  defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restarted.vine.totalGrapes, 1)
        restarted.classifyFiles([image("two-homeworks.png")])
        await restarted.waitUntilIdle()
        XCTAssertEqual(restarted.vine.totalGrapes, 2,
                       "A screenshot with a genuinely new task must still count")
        XCTAssertEqual(restarted.garden.deadlines.count, 2)
    }

    func testSemanticGrapeIdentityIsCategoryScoped() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var learning = response(deadlines: [deadline("learning", key: "shared-id")])
        learning.contentFingerprint = String(repeating: "d", count: 64)
        var finance = EngineClassificationResult(
            path: "/tmp/invoice.png", fileName: "invoice.png",
            status: "classified", categoryID: "finance", categoryLabel: "财务与票据",
            confidence: 0.9, matchedKeywords: ["发票"], reason: "明确的分类",
            extractionChars: 80, deadlines: [deadline("finance", key: "shared-id")])
        finance.contentFingerprint = String(repeating: "e", count: 64)
        let store = makeStore(AutomaticDeadlineEngine(results: [learning, finance]), defaults: defaults)
        store.classifyFiles([image("course.png"), image("invoice.png")])
        await store.waitUntilIdle()
        XCTAssertEqual(store.vine.totalGrapes, 2,
                       "An accidental cross-category matching key must not hide a file")
    }

    private func image(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/filepet-automatic-image-tests/" + name)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "FilePetShell.AutoOCR.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeStore(_ engine: AutomaticDeadlineEngine, defaults: UserDefaults) -> ShellStore {
        ShellStore(client: engine, defaults: defaults, arguments: [],
                   pollInterval: 1_000_000, jobTimeout: 1)
    }

    private func deadline(_ id: String, key: String) -> EngineDeadline {
        var d = EngineDeadline(id: id, title: "软件工程课程作业", project: "课程与学习",
                               dueDate: "2026-11-06", dueTime: "23:59",
                               yearInferred: false, evidence: "截止：2026年11月6日23:59",
                               signal: "explicit_deadline")
        d.confirmationRequired = false
        d.reliability = "high"
        d.semanticKey = key
        return d
    }

    private func response(deadlines: [EngineDeadline]) -> EngineClassificationResult {
        var result = EngineClassificationResult(
            path: "/tmp/placeholder.png", fileName: "placeholder.png",
            status: "classified", categoryID: "learning", categoryLabel: "课程与学习",
            confidence: 0.8, matchedKeywords: ["课程"],
            reason: "明确的截止", extractionChars: 80, deadlines: deadlines)
        result.contentFingerprint = String(repeating: "a", count: 64)
        return result
    }
}

private actor AutomaticDeadlineEngine: EngineServing {
    private var results: [EngineClassificationResult]
    private var jobs: [String: EngineJob] = [:]

    init(results: [EngineClassificationResult]) {
        self.results = results
    }

    func health() async throws -> EngineHealth {
        EngineHealth(status: "ok", version: "test")
    }

    func categories() async throws -> [EngineCategory] {
        [EngineCategory(id: "learning", label: "课程与学习", description: "")]
    }

    func createJob(path: String) async throws -> EngineJobAccepted {
        guard !results.isEmpty else { throw URLError(.badServerResponse) }
        let source = results.removeFirst()
        var output = EngineClassificationResult(
            path: path, fileName: URL(fileURLWithPath: path).lastPathComponent,
            status: source.status, categoryID: source.categoryID,
            categoryLabel: source.categoryLabel, confidence: source.confidence,
            matchedKeywords: source.matchedKeywords, reason: source.reason,
            extractionChars: source.extractionChars, deadlines: source.deadlines)
        output.contentFingerprint = source.contentFingerprint
        let id = UUID().uuidString
        jobs[id] = EngineJob(jobID: id, status: "completed", result: output, error: nil)
        return EngineJobAccepted(jobID: id, status: "queued")
    }

    func job(id: String) async throws -> EngineJob {
        guard let job = jobs[id] else { throw URLError(.badServerResponse) }
        return job
    }
}
