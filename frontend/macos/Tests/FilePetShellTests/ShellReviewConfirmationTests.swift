import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class ShellReviewConfirmationTests: XCTestCase {
    func testOCRDeadlineWaitsForConfirmationAndOpensTheReviewEntry() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = candidate("ocr-one", signal: "ocr_deadline")
        let store = makeStore([result(candidates: [source])], defaults: defaults)
        var reviewPresentations = 0
        store.onShowPendingReviews = { reviewPresentations += 1 }
        store.classifyFiles([file("notice.png")])
        await store.waitUntilIdle()

        XCTAssertEqual(store.results.map(\.outcome), [.needsReview])
        XCTAssertEqual(store.reviewInbox.items.count, 1)
        XCTAssertEqual(store.reviewInbox.items[0].candidates, [source])
        XCTAssertTrue(store.garden.deadlines.isEmpty, "An uncertain OCR reading needs a human decision")
        XCTAssertEqual(store.vine.totalGrapes, 0)
        XCTAssertEqual(reviewPresentations, 1, "A new pending batch must expose its actionable review window")
        let reviewID = try XCTUnwrap(store.reviewInbox.items.first?.id)
        XCTAssertNil(store.confirmDeadline(reviewID: reviewID, candidateID: source.id,
                                          title: "第二次作业", project: "软件工程",
                                          dueDate: "2026-10-18", dueTime: "23:59"))
        XCTAssertEqual(store.reviewInbox.items.count, 1, "Category review remains after accepting OCR")
        XCTAssertEqual(store.garden.visibleDeadlines.count, 1)
        XCTAssertEqual(store.garden.deadlines.first?.id, source.id)
        XCTAssertEqual(store.garden.deadlines.first?.title, "第二次作业")
        XCTAssertEqual(store.garden.deadlines.first?.dueDate, "2026-10-18", "Past dates must not roll forward without the user asking")
        XCTAssertEqual(store.garden.deadlines.first?.dueTime, "23:59")
        XCTAssertEqual(store.vine.totalGrapes, 0)
        _ = store.confirmDeadline(reviewID: reviewID, candidateID: source.id,
                                  title: "第二次作业", project: "软件工程", dueDate: "2026-10-18", dueTime: "23:59")
        XCTAssertEqual(store.garden.deadlines.count, 1, "Repeated presses must not create duplicate flowers")
    }

    func testSeveralOCRCandidatesConfirmIndependentlyAndUseTheThreeFlowerQueue() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidates = (1...4).map { candidate("ocr-\($0)", signal: "ocr_deadline") }
        let store = makeStore([result(candidates: candidates)], defaults: defaults)
        store.classifyFiles([file("many.png")])
        await store.waitUntilIdle()
        let reviewID = try XCTUnwrap(store.reviewInbox.items.first?.id)
        for (index, candidate) in candidates.enumerated() {
            XCTAssertNil(store.confirmDeadline(reviewID: reviewID, candidateID: candidate.id,
                                              title: candidate.title, project: candidate.project,
                                              dueDate: candidate.dueDate, dueTime: candidate.dueTime))
            XCTAssertEqual(store.garden.deadlines.count, index + 1)
            if index < candidates.count - 1 {
                XCTAssertEqual(store.reviewInbox.items[0].candidates.count, candidates.count - index - 1)
            }
        }
        XCTAssertEqual(store.reviewInbox.items.count, 1, "Category review remains after DDLs")
        XCTAssertEqual(store.garden.visibleDeadlines.map(\.id), ["ocr-4"])
        XCTAssertEqual(store.garden.queuedCount, 3)
        store.garden.harvest(id: "ocr-4")
        XCTAssertEqual(store.garden.visibleDeadlines.map(\.id), ["ocr-3"])
        XCTAssertEqual(store.garden.queuedCount, 2)
    }

    func testPendingReviewSurvivesRestartAndInvalidInputCannotDiscardIt() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore([result(candidates: [candidate("pending", signal: "ocr_deadline")])], defaults: defaults)
        store.classifyFiles([file("persist.png")])
        await store.waitUntilIdle()
        let restored = makeStore([], defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.reviewInbox.items, store.reviewInbox.items)
        let reviewID = try XCTUnwrap(restored.reviewInbox.items.first?.id)
        XCTAssertNotNil(restored.confirmDeadline(reviewID: reviewID, candidateID: "pending", title: "作业",
                                                project: "软件工程", dueDate: "2026-02-30", dueTime: "24:00"))
        XCTAssertTrue(restored.garden.deadlines.isEmpty)
        XCTAssertEqual(restored.reviewInbox.items, store.reviewInbox.items, "Validation failure must leave the review available")
    }

    func testUnknownClassificationCanBeManuallyEnteredAsDDLWithoutInventingATime() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore([result(candidates: [])], defaults: defaults)
        store.classifyFiles([file("unknown.png")])
        await store.waitUntilIdle()
        let reviewID = try XCTUnwrap(store.reviewInbox.items.first?.id)
        XCTAssertTrue(store.reviewInbox.items[0].candidates.isEmpty)
        XCTAssertNil(store.confirmDeadline(reviewID: reviewID, candidateID: nil, title: "手动补充作业",
                                          project: "课程", dueDate: "2026-11-03", dueTime: nil))
        XCTAssertEqual(store.garden.deadlines.count, 1)
        XCTAssertNil(store.garden.deadlines[0].dueTime)
        XCTAssertEqual(store.garden.deadlines[0].title, "手动补充作业")
        XCTAssertEqual(store.reviewInbox.items.count, 1, "Category review remains actionable")
        XCTAssertEqual(store.vine.totalGrapes, 0)
    }

    func testOrdinaryReviewCanConfirmACoreCategoryAndRepeatedFileDoesNotAddFruit() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let response = result(candidates: [])
        let store = makeStore([response, response], defaults: defaults)
        let path = file("ordinary.txt")
        store.classifyFiles([path])
        await store.waitUntilIdle()
        let firstID = try XCTUnwrap(store.reviewInbox.items.first?.id)
        XCTAssertNotNil(store.confirmCategory(reviewID: firstID, categoryID: "unknown-category"))
        XCTAssertEqual(store.vine.totalGrapes, 0)
        XCTAssertEqual(store.reviewInbox.items.count, 1)
        XCTAssertNil(store.confirmCategory(reviewID: firstID, categoryID: "learning"))
        XCTAssertEqual(store.vine.count(for: "learning"), 1)
        XCTAssertTrue(store.reviewInbox.items.isEmpty)
        XCTAssertTrue(store.garden.deadlines.isEmpty)

        store.classifyFiles([path])
        await store.waitUntilIdle()
        let repeatedID = try XCTUnwrap(store.reviewInbox.items.first?.id)
        XCTAssertNil(store.confirmCategory(reviewID: repeatedID, categoryID: "learning"))
        XCTAssertEqual(store.vine.count(for: "learning"), 1)
    }

    func testClearDeadlineStillGeneratesAFlowerWithoutTheOCRReviewGate() async {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let clear = candidate("clear", signal: "explicit_deadline")
        let store = makeStore([result(candidates: [clear])], defaults: defaults)
        store.classifyFiles([file("clear.txt")])
        await store.waitUntilIdle()
        XCTAssertEqual(store.reviewInbox.items.count, 1, "Unknown classification remains actionable")
        XCTAssertEqual(store.garden.visibleDeadlines.map(\.id), ["clear"])
        XCTAssertEqual(store.vine.totalGrapes, 0)
    }

    private func candidate(_ id: String, signal: String) -> EngineDeadline {
        EngineDeadline(id: id, title: "提交第二次作业", project: "软件工程", dueDate: "2026-10-18",
                       dueTime: "23:59", yearInferred: false, evidence: "dd|为2026年10月18日23:59", signal: signal)
    }

    private func result(candidates: [EngineDeadline]) -> EngineClassificationResult {
        EngineClassificationResult(path: "/tmp/placeholder.png", fileName: "placeholder.png", status: "needs_review",
                                   categoryID: nil, categoryLabel: nil, confidence: 0.5, matchedKeywords: ["作业"],
                                   reason: "有效内容线索不足，建议人工指定类别", extractionChars: 70, deadlines: candidates)
    }

    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/filepet-confirmation-tests/" + name) }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "FilePetShell.ShellReviewConfirmationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeStore(_ responses: [EngineClassificationResult], defaults: UserDefaults) -> ShellStore {
        ShellStore(client: ReviewShellEngine(responses: responses), defaults: defaults, arguments: [],
                   pollInterval: 1_000_000, jobTimeout: 1)
    }
}

private actor ReviewShellEngine: EngineServing {
    private var responses: [EngineClassificationResult]
    private var jobs: [String: EngineJob] = [:]

    init(responses: [EngineClassificationResult]) { self.responses = responses }
    func health() async throws -> EngineHealth { EngineHealth(status: "ok", version: "test") }
    func categories() async throws -> [EngineCategory] {
        [EngineCategory(id: "learning", label: "课程与学习", description: "")]
    }
    func createJob(path: String) async throws -> EngineJobAccepted {
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let source = responses.removeFirst()
        let result = EngineClassificationResult(path: path, fileName: URL(fileURLWithPath: path).lastPathComponent,
            status: source.status, categoryID: source.categoryID, categoryLabel: source.categoryLabel,
            confidence: source.confidence, matchedKeywords: source.matchedKeywords, reason: source.reason,
            extractionChars: source.extractionChars, deadlines: source.deadlines)
        let id = UUID().uuidString
        jobs[id] = EngineJob(jobID: id, status: result.deadlines.isEmpty ? "needs_review" : "completed", result: result, error: nil)
        return EngineJobAccepted(jobID: id, status: "queued")
    }
    func job(id: String) async throws -> EngineJob {
        guard let job = jobs[id] else { throw URLError(.badServerResponse) }
        return job
    }
}
