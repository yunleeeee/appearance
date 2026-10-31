import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class ShellStoreTests: XCTestCase {
    func testClassifiedResultsGrowEngineCategoryIDsAndLabels() async {
        let engine = ScriptedShellEngine(scripts: [
            [Self.completed("job-a", category: "recruitment", label: "招聘项目")],
            [Self.completed("job-b", category: "finance", label: "财务与报销")],
        ])
        let (store, suite) = makeStore(engine)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.classifyFiles([file("a.pdf"), file("b.md")])
        await store.waitUntilIdle()

        XCTAssertFalse(store.isBusy)
        XCTAssertEqual(store.vine.count(for: "recruitment"), 1)
        XCTAssertEqual(store.vine.count(for: "finance"), 1)
        XCTAssertEqual(store.vine.count(for: "文档"), 0)
        XCTAssertEqual(store.vine.totalGrapes, 2)
        XCTAssertEqual(store.vine.displayName(for: "recruitment"), "招聘项目")
        XCTAssertEqual(store.results.map(\.outcome), [.classified, .classified])
        XCTAssertEqual(store.results.map(\.categoryLabel), ["招聘项目", "财务与报销"])
        XCTAssertTrue(store.status.contains("2 个已识别"))
    }

    func testNeedsReviewAndFailureDoNotGrowSuccessFruit() async {
        let review = EngineJob(jobID: "review", status: "needs_review", result: Self.result(status: "needs_review"), error: nil)
        let failed = EngineJob(jobID: "failed", status: "failed", result: nil,
                               error: EngineJobFailure(detail: "文件不在授权的 root 文件夹内", statusCode: 403))
        let engine = ScriptedShellEngine(scripts: [[review], [failed]])
        let (store, suite) = makeStore(engine)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.classifyFiles([file("unknown.txt"), file("denied.txt")])
        await store.waitUntilIdle()

        XCTAssertEqual(store.vine.totalGrapes, 0)
        XCTAssertEqual(store.results.map(\.outcome), [.needsReview, .failed])
        XCTAssertTrue(store.results[1].detail.contains("授权"))
        XCTAssertTrue(store.status.contains("1 个待确认，1 个失败"))
    }

    func testDuplicateAndNonFileURLsAreNotSubmittedTwice() async {
        let engine = ScriptedShellEngine(scripts: [[Self.completed("only", category: "learning", label: "学习资料")]])
        let (store, suite) = makeStore(engine)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let original = file("same.txt")
        let equivalent = URL(fileURLWithPath: "/tmp/filepet-shell-tests/../filepet-shell-tests/same.txt")
        store.classifyFiles([original, equivalent, URL(string: "https://example.com/file.txt")!])
        // A second drop during the same batch is ignored rather than double-counted.
        store.classifyFiles([original])
        await store.waitUntilIdle()

        let submitted = await engine.submittedPaths()
        XCTAssertEqual(submitted, [original.path])
        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.vine.totalGrapes, 1)
    }

    func testOfflineEngineLeavesCountsUntouchedAndReportsConnectionProblem() async {
        let engine = ScriptedShellEngine(scripts: [], offline: true)
        let (store, suite) = makeStore(engine)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.classifyFiles([file("a.txt"), file("b.txt")])
        await store.waitUntilIdle()

        let submitted = await engine.submittedPaths()
        XCTAssertTrue(submitted.isEmpty)
        XCTAssertEqual(store.vine.totalGrapes, 0)
        XCTAssertEqual(store.results.map(\.outcome), [.failed, .failed])
        XCTAssertFalse(store.isBusy)
        XCTAssertTrue(store.connectionStatus.contains("未连接"))
        XCTAssertTrue(store.status.contains("无法连接本机分类引擎"))
    }

    func testStoppingPollRejectsCompletedCallbackThatArrivesLate() async {
        let engine = ScriptedShellEngine(scripts: [[Self.completed("late", category: "research", label: "研究资料")]], holdFirstPoll: true)
        let (store, suite) = makeStore(engine)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.classifyFiles([file("late.txt")])
        await waitForFirstPoll(engine)
        store.stop()
        // This mock deliberately ignores task cancellation until released, like a late server callback.
        await engine.releaseHeldPoll()
        await store.waitUntilIdle()

        XCTAssertEqual(store.vine.totalGrapes, 0)
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertFalse(store.isBusy)
        XCTAssertEqual(store.status, "已停止等待分类结果")
    }

    func testTimeoutDoesNotTurnQueuedJobIntoSuccess() async {
        let queued = EngineJob(jobID: "waiting", status: "queued", result: nil, error: nil)
        let engine = ScriptedShellEngine(scripts: [[queued]])
        let (store, suite) = makeStore(engine, timeout: 0)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.classifyFiles([file("slow.txt")])
        await store.waitUntilIdle()

        XCTAssertEqual(store.vine.totalGrapes, 0)
        XCTAssertEqual(store.results.map(\.outcome), [.failed])
        XCTAssertTrue(store.results[0].detail.contains("超时"))
        XCTAssertFalse(store.isBusy)
    }

    func testUnknownIntermediateStageKeepsPollingUntilConfirmedClassification() async {
        let future = EngineJob(jobID: "future", status: "embedding_future", result: nil, error: nil)
        let done = Self.completed("future", category: "engineering", label: "工程开发")
        let engine = ScriptedShellEngine(scripts: [[future, done]])
        let (store, suite) = makeStore(engine)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.classifyFiles([file("design.txt")])
        await store.waitUntilIdle()

        let polls = await engine.numberOfPolls()
        XCTAssertEqual(polls, 2)
        XCTAssertEqual(store.vine.count(for: "engineering"), 1)
        XCTAssertEqual(store.results.map(\.outcome), [.classified])
    }

    func testMalformedCompletedJobCannotInventCategoryOrGrowFruit() async {
        let noCategory = EngineJob(jobID: "bad-result", status: "completed", result: Self.result(status: "classified"), error: nil)
        let noResult = EngineJob(jobID: "missing-result", status: "completed", result: nil, error: nil)
        let engine = ScriptedShellEngine(scripts: [[noCategory], [noResult]])
        let (store, suite) = makeStore(engine)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        store.classifyFiles([file("bad.txt"), file("empty.txt")])
        await store.waitUntilIdle()

        XCTAssertEqual(store.vine.totalGrapes, 0)
        XCTAssertEqual(store.results.map(\.outcome), [.failed, .failed])
    }

    private func makeStore(_ engine: ScriptedShellEngine, timeout: TimeInterval = 1) -> (ShellStore, String) {
        let suite = "FilePetShell.ShellStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (ShellStore(client: engine, defaults: defaults, arguments: [], pollInterval: 1_000_000, jobTimeout: timeout), suite)
    }

    private func file(_ name: String) -> URL { URL(fileURLWithPath: "/tmp/filepet-shell-tests/" + name) }

    private func waitForFirstPoll(_ engine: ScriptedShellEngine) async {
        for _ in 0..<300 {
            if await engine.numberOfPolls() > 0 { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("The classification batch never reached polling")
    }

    private static func completed(_ id: String, category: String, label: String) -> EngineJob {
        EngineJob(jobID: id, status: "completed", result: result(status: "classified", category: category, label: label), error: nil)
    }

    private static func result(status: String, category: String? = nil, label: String? = nil) -> EngineClassificationResult {
        EngineClassificationResult(path: "/tmp/example.txt", fileName: "example.txt", status: status,
                                   categoryID: category, categoryLabel: label, confidence: category == nil ? 0 : 0.9,
                                   matchedKeywords: [], reason: category == nil ? "内容线索不足" : "核心分类结果", extractionChars: 50)
    }
}

private actor ScriptedShellEngine: EngineServing {
    private var scripts: [[EngineJob]]
    private let offline: Bool
    private var holdFirstPoll: Bool
    private var active: [String: [EngineJob]] = [:]
    private var paths: [String] = []
    private var polls = 0
    private var held: CheckedContinuation<EngineJob, Never>?
    private var heldJob: EngineJob?

    init(scripts: [[EngineJob]], offline: Bool = false, holdFirstPoll: Bool = false) {
        self.scripts = scripts
        self.offline = offline
        self.holdFirstPoll = holdFirstPoll
    }

    func health() async throws -> EngineHealth {
        if offline { throw URLError(.cannotConnectToHost) }
        return EngineHealth(status: "ok", version: "test")
    }
    func categories() async throws -> [EngineCategory] {
        [EngineCategory(id: "recruitment", label: "招聘项目", description: ""),
         EngineCategory(id: "finance", label: "财务与报销", description: "")]
    }
    func createJob(path: String) async throws -> EngineJobAccepted {
        paths.append(path)
        guard !scripts.isEmpty, let first = scripts.first?.first else { throw URLError(.badServerResponse) }
        // The service returns the actual submitted file identity. Reusing a
        // placeholder path would make independent files appear to be repeats.
        active[first.jobID] = scripts.removeFirst().map { job in
            let result = job.result.map {
                EngineClassificationResult(path: path, fileName: URL(fileURLWithPath: path).lastPathComponent,
                                           status: $0.status, categoryID: $0.categoryID,
                                           categoryLabel: $0.categoryLabel, confidence: $0.confidence,
                                           matchedKeywords: $0.matchedKeywords, reason: $0.reason,
                                           extractionChars: $0.extractionChars, deadlines: $0.deadlines)
            }
            return EngineJob(jobID: job.jobID, status: job.status, result: result, error: job.error)
        }
        return EngineJobAccepted(jobID: first.jobID, status: "queued")
    }
    func job(id: String) async throws -> EngineJob {
        polls += 1
        guard var sequence = active[id], let first = sequence.first else { throw URLError(.badServerResponse) }
        if sequence.count > 1 { sequence.removeFirst(); active[id] = sequence }
        if holdFirstPoll {
            holdFirstPoll = false
            heldJob = first
            return await withCheckedContinuation { held = $0 }
        }
        return first
    }
    func submittedPaths() -> [String] { paths }
    func numberOfPolls() -> Int { polls }
    func releaseHeldPoll() {
        guard let held, let heldJob else { return }
        self.held = nil
        self.heldJob = nil
        held.resume(returning: heldJob)
    }
}
