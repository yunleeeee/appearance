import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class ShellStoreRuntimeTests: XCTestCase {
    func testRuntimeBecomesReadyBeforeTheShellConnectsOrSubmitsFiles() async throws {
        let events = RuntimeEvents()
        let runtime = ScriptedRuntime(events: events)
        let client = RuntimeOrderEngine(events: events)
        let (store, defaults, suite) = makeStore(client: client, runtime: runtime)
        defer { store.stop(); defaults.removePersistentDomain(forName: suite) }

        store.classifyFiles([URL(fileURLWithPath: "/tmp/filepet-runtime-finance.txt")])
        await store.waitUntilIdle()

        XCTAssertEqual(events.entries, ["runtime", "health", "categories", "createJob", "job"])
        XCTAssertEqual(runtime.ensureCount, 1)
        XCTAssertEqual(store.results.map(\.outcome), [.classified])
        XCTAssertEqual(store.vine.count(for: "finance"), 1)
        XCTAssertTrue(store.connectionStatus.contains("已连接"), store.connectionStatus)
    }

    func testStartupFailureDoesNotPretendToConnectOrSubmitFiles() async throws {
        let events = RuntimeEvents()
        let runtime = ScriptedRuntime(events: events, failure: RuntimeTestError.failed)
        let client = RuntimeOrderEngine(events: events)
        let (store, defaults, suite) = makeStore(client: client, runtime: runtime)
        defer { store.stop(); defaults.removePersistentDomain(forName: suite) }

        store.classifyFiles([URL(fileURLWithPath: "/tmp/filepet-runtime-finance.txt")])
        await store.waitUntilIdle()

        XCTAssertEqual(events.entries, ["runtime"])
        let paths = await client.submittedPaths()
        XCTAssertTrue(paths.isEmpty)
        XCTAssertEqual(store.results.map(\.outcome), [.failed])
        XCTAssertEqual(store.vine.totalGrapes, 0)
        XCTAssertTrue(store.status.contains("测试核心启动失败"), store.status)
        XCTAssertFalse(store.isBusy)
    }

    func testExplicitExternalEndpointDoesNotStartOrStopAnAutomaticRuntime() async throws {
        let events = RuntimeEvents()
        let runtime = ScriptedRuntime(events: events)
        let client = RuntimeOrderEngine(events: events)
        let (store, defaults, suite) = makeStore(client: client, runtime: runtime,
            arguments: ["FilePetShell", "--engine-url", "http://127.0.0.1:19999"])
        defer { defaults.removePersistentDomain(forName: suite) }

        store.refreshConnection()
        await store.waitUntilConnected()
        XCTAssertEqual(runtime.ensureCount, 0)
        XCTAssertEqual(events.entries, ["health", "categories"])
        XCTAssertTrue(store.connectionStatus.contains("已连接"), store.connectionStatus)
        store.stop()
        XCTAssertEqual(runtime.stopCount, 0, "Explicit external services do not belong to this app")
    }

    func testStopRejectsAnUncancelledLateRuntimeStartup() async throws {
        let events = RuntimeEvents()
        let runtime = ScriptedRuntime(events: events, holdsStartup: true)
        let client = RuntimeOrderEngine(events: events)
        let (store, defaults, suite) = makeStore(client: client, runtime: runtime)
        defer { defaults.removePersistentDomain(forName: suite) }

        store.refreshConnection()
        for _ in 0..<300 {
            if runtime.isHoldingStartup { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertTrue(runtime.isHoldingStartup)
        store.stop()
        let stoppedStatus = store.connectionStatus
        runtime.releaseStartup()
        await store.waitUntilConnected()
        // Give the resumed task a turn even if stop intentionally cleared its handle.
        await Task.yield()

        XCTAssertEqual(runtime.stopCount, 1)
        XCTAssertEqual(events.entries, ["runtime"])
        XCTAssertEqual(store.connectionStatus, stoppedStatus)
        XCTAssertFalse(store.connectionStatus.contains("已连接"))
    }

    private func makeStore(client: RuntimeOrderEngine, runtime: ScriptedRuntime,
                           arguments: [String] = []) -> (ShellStore, UserDefaults, String) {
        let suite = "FilePetShell.ShellStoreRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ShellStore(client: client, runtime: runtime, defaults: defaults,
                               arguments: arguments, pollInterval: 1_000_000, jobTimeout: 1)
        return (store, defaults, suite)
    }
}

@MainActor
private final class RuntimeEvents {
    private(set) var entries: [String] = []
    func record(_ event: String) { entries.append(event) }
}

@MainActor
private final class ScriptedRuntime: EngineRuntimeManaging {
    private let events: RuntimeEvents
    private let failure: Error?
    private let holdsStartup: Bool
    private var continuation: CheckedContinuation<URL, Error>?
    private(set) var ensureCount = 0
    private(set) var stopCount = 0
    var isHoldingStartup: Bool { continuation != nil }
    private let endpoint = URL(string: "http://127.0.0.1:19998")!

    init(events: RuntimeEvents, failure: Error? = nil, holdsStartup: Bool = false) {
        self.events = events
        self.failure = failure
        self.holdsStartup = holdsStartup
    }

    func ensureRunning() async throws -> URL {
        ensureCount += 1
        events.record("runtime")
        if let failure { throw failure }
        if holdsStartup {
            // Ignore cancellation deliberately, like a subprocess completing late.
            return try await withCheckedThrowingContinuation { continuation = $0 }
        }
        return endpoint
    }

    func releaseStartup() {
        continuation?.resume(returning: endpoint)
        continuation = nil
    }

    func stop() { stopCount += 1 }
}

private enum RuntimeTestError: LocalizedError {
    case failed
    var errorDescription: String? { "测试核心启动失败" }
}

private actor RuntimeOrderEngine: EngineServing {
    private let events: RuntimeEvents
    private var paths: [String] = []

    init(events: RuntimeEvents) { self.events = events }

    func health() async throws -> EngineHealth {
        await events.record("health")
        return EngineHealth(status: "ok", version: "runtime-test")
    }

    func categories() async throws -> [EngineCategory] {
        await events.record("categories")
        return [EngineCategory(id: "finance", label: "财务与报销", description: "")]
    }

    func createJob(path: String) async throws -> EngineJobAccepted {
        await events.record("createJob")
        paths.append(path)
        return EngineJobAccepted(jobID: "runtime-job", status: "queued")
    }

    func job(id: String) async throws -> EngineJob {
        await events.record("job")
        let path = paths.last ?? "/tmp/filepet-runtime-finance.txt"
        let result = EngineClassificationResult(path: path, fileName: "filepet-runtime-finance.txt",
            status: "classified", categoryID: "finance", categoryLabel: "财务与报销",
            confidence: 0.9, matchedKeywords: ["发票", "报销"], reason: "核心结果", extractionChars: 30)
        return EngineJob(jobID: id, status: "completed", result: result, error: nil)
    }

    func submittedPaths() -> [String] { paths }
}
