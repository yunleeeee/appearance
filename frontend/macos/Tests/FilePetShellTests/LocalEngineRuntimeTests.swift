import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class LocalEngineRuntimeTests: XCTestCase {
    func testMissingCoreExplainsTheProblemWithoutStartingAProcess() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = LocalEngineRuntime(
            engineRoot: directory.appendingPathComponent("missing core"),
            allowedRoot: directory, startupTimeout: 1, environment: [:],
            bundleURL: directory.appendingPathComponent("Detached.app"),
            configuredEngineRoot: nil, logURL: directory.appendingPathComponent("engine.log"))
        defer { runtime.stop() }

        do {
            _ = try await runtime.ensureRunning()
            XCTFail("A missing core must not silently connect to an unrelated local service")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("分类核心"), error.localizedDescription)
        }
        XCTAssertNil(runtime.managedProcessID)
        XCTAssertNil(runtime.endpoint)
    }

    func testUnavailablePythonCannotBeReportedAsConnected() async throws {
        let directory = temporaryDirectory()
        let core = directory.appendingPathComponent("engine without runtime")
        try FileManager.default.createDirectory(at: core.appendingPathComponent("backend/filepet"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = LocalEngineRuntime(
            engineRoot: core, allowedRoot: directory, startupTimeout: 1,
            environment: [:], bundleURL: directory.appendingPathComponent("Detached.app"),
            configuredEngineRoot: nil, logURL: directory.appendingPathComponent("engine.log"))
        defer { runtime.stop() }

        do {
            _ = try await runtime.ensureRunning()
            XCTFail("A core without a usable Python runtime cannot start")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertNil(runtime.managedProcessID)
        XCTAssertNil(runtime.endpoint)
    }

    func testStartupFailureCleansUpItsOwnedProcess() async throws {
        let directory = temporaryDirectory()
        let core = directory.appendingPathComponent("failed engine")
        let python = core.appendingPathComponent(".venv/bin/python")
        try FileManager.default.createDirectory(at: core.appendingPathComponent("backend/filepet"),
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: python.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: python,
                                                   withDestinationURL: URL(fileURLWithPath: "/usr/bin/false"))
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = LocalEngineRuntime(
            engineRoot: core, allowedRoot: directory, startupTimeout: 1,
            environment: [:], bundleURL: directory.appendingPathComponent("Detached.app"),
            configuredEngineRoot: nil, logURL: directory.appendingPathComponent("engine.log"))
        defer { runtime.stop() }

        do {
            _ = try await runtime.ensureRunning()
            XCTFail("A process that exits immediately cannot be a healthy engine")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        XCTAssertNil(runtime.managedProcessID)
        XCTAssertNil(runtime.endpoint)
    }

    func testRealCoreStartsOnceHandlesFilesAndStopsOnlyItsOwnService() async throws {
        let core = try liveCoreRoot()
        let directory = temporaryDirectory()
        let input = directory.appendingPathComponent("允许读取的文件夹 with spaces", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = input.appendingPathComponent("课程截止通知.txt")
        let original = Data("课程名称：软件工程\n请于2026年11月3日23:59前提交实验报告".utf8)
        try original.write(to: file)
        let firstRuntime = makeRuntime(core: core, allowedRoot: input, directory: directory, logName: "first.log")
        let independentRuntime = makeRuntime(core: core, allowedRoot: input, directory: directory, logName: "independent.log")
        defer { firstRuntime.stop(); independentRuntime.stop() }

        async let firstRequest = firstRuntime.ensureRunning()
        async let concurrentRequest = firstRuntime.ensureRunning()
        let (firstEndpoint, concurrentEndpoint) = try await (firstRequest, concurrentRequest)
        XCTAssertEqual(firstEndpoint, concurrentEndpoint)
        let firstPID = try XCTUnwrap(firstRuntime.managedProcessID)
        let repeatedEndpoint = try await firstRuntime.ensureRunning()
        XCTAssertEqual(repeatedEndpoint, firstEndpoint)
        XCTAssertEqual(firstRuntime.managedProcessID, firstPID, "Connection checks must reuse the owned process")
        let client = try EngineClient(baseURL: firstEndpoint)
        let health = try await client.health()
        let categories = try await client.categories()
        XCTAssertEqual(health.status, "ok")
        XCTAssertFalse(categories.isEmpty)
        let accepted = try await client.createJob(path: file.path)
        let completed = try await finishedJob(client: client, id: accepted.jobID)
        XCTAssertEqual(completed.status, "completed")
        XCTAssertEqual(completed.result?.deadlines.count, 1)
        XCTAssertEqual(completed.result?.categoryID, "learning")
        XCTAssertEqual(completed.result?.deadlines.first?.project, completed.result?.categoryLabel)
        XCTAssertEqual(completed.result?.deadlines.first?.dueTime, "23:59")
        XCTAssertEqual(try Data(contentsOf: file), original)

        let independentEndpoint = try await independentRuntime.ensureRunning()
        let independentPID = try XCTUnwrap(independentRuntime.managedProcessID)
        XCTAssertNotEqual(independentEndpoint, firstEndpoint)
        XCTAssertNotEqual(independentPID, firstPID)
        let independentClient = try EngineClient(baseURL: independentEndpoint)
        firstRuntime.stop()
        XCTAssertNil(firstRuntime.managedProcessID)
        XCTAssertNil(firstRuntime.endpoint)
        let independentHealth = try await independentClient.health()
        XCTAssertEqual(independentHealth.status, "ok",
                       "Quitting one app-owned runtime must leave another service alive")
        XCTAssertEqual(independentRuntime.managedProcessID, independentPID)

        let restartedEndpoint = try await firstRuntime.ensureRunning()
        XCTAssertNotNil(firstRuntime.managedProcessID)
        XCTAssertNotEqual(firstRuntime.managedProcessID, firstPID)
        let restartedHealth = try await EngineClient(baseURL: restartedEndpoint).health()
        XCTAssertEqual(restartedHealth.status, "ok")
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testRealCoreCanBeLocatedThroughAPathContainingSpaces() async throws {
        let core = try liveCoreRoot()
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let link = directory.appendingPathComponent("FilePet core with spaces")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: core)
        let runtime = makeRuntime(core: link, allowedRoot: directory, directory: directory)
        defer { runtime.stop() }

        let endpoint = try await runtime.ensureRunning()
        let health = try await EngineClient(baseURL: endpoint).health()
        XCTAssertEqual(health.status, "ok")
        XCTAssertNotNil(runtime.managedProcessID)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("FilePet runtime tests \(UUID().uuidString)", isDirectory: true)
    }

    private func liveCoreRoot() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["FILEPET_TEST_ENGINE_ROOT"] else {
            throw XCTSkip("Set FILEPET_TEST_ENGINE_ROOT to verify the app-managed Python service lifecycle")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func makeRuntime(core: URL, allowedRoot: URL, directory: URL, logName: String = "engine.log") -> LocalEngineRuntime {
        LocalEngineRuntime(engineRoot: core, allowedRoot: allowedRoot, startupTimeout: 10,
                           environment: [:], bundleURL: directory.appendingPathComponent("Detached.app"),
                           configuredEngineRoot: nil, logURL: directory.appendingPathComponent(logName))
    }

    private func finishedJob(client: EngineClient, id: String) async throws -> EngineJob {
        for _ in 0..<300 {
            let job = try await client.job(id: id)
            if ["completed", "needs_review", "failed"].contains(job.status) { return job }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw URLError(.timedOut)
    }
}
