import Darwin
import Foundation

/// The app owns this local helper's lifetime; explicit external engines use a
/// separate EngineClient and are never stopped by this interface.
@MainActor
protocol EngineRuntimeManaging: AnyObject {
    func ensureRunning() async throws -> URL
    func stop()
}

@MainActor
final class LocalEngineRuntime: EngineRuntimeManaging {
    private let configuredRoot: URL?
    private let allowedRoot: URL
    private let startupTimeout: TimeInterval
    private let environment: [String: String]
    private let bundleURL: URL
    private let configuredEngineRoot: String?
    let logURL: URL

    private var process: Process?
    private var logHandle: FileHandle?
    private var instanceID: String?
    private var startup: Task<URL, Error>?
    private var generation = UUID()
    private(set) var endpoint: URL?
    var managedProcessID: Int32? {
        guard let process, process.isRunning else { return nil }
        return process.processIdentifier
    }

    init(engineRoot: URL? = nil,
         allowedRoot: URL = FileManager.default.homeDirectoryForCurrentUser,
         startupTimeout: TimeInterval = 10,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         bundleURL: URL = Bundle.main.bundleURL,
         configuredEngineRoot: String? = Bundle.main.object(forInfoDictionaryKey: "FilePetEngineRoot") as? String,
         logURL: URL? = nil) {
        configuredRoot = engineRoot
        self.allowedRoot = allowedRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.startupTimeout = startupTimeout
        self.environment = environment
        self.bundleURL = bundleURL
        self.configuredEngineRoot = configuredEngineRoot
        self.logURL = logURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FilePetShell/Logs/engine.log")
    }

    func ensureRunning() async throws -> URL {
        try Task.checkCancellation()
        // A menu reconnect and an arriving file can share one startup. Cancelling
        // either caller does not interrupt the helper needed by the other.
        if let startup {
            let url = try await startup.value
            try Task.checkCancellation()
            return url
        }
        let currentGeneration = UUID()
        generation = currentGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.connectOrLaunch()
        }
        startup = task
        do {
            let url = try await task.value
            if generation == currentGeneration { startup = nil }
            try Task.checkCancellation()
            return url
        } catch {
            if generation == currentGeneration { startup = nil }
            throw error
        }
    }

    func stop() {
        generation = UUID()
        startup?.cancel()
        startup = nil
        terminateOwnedProcess()
    }

    private func connectOrLaunch() async throws -> URL {
        if let process, process.isRunning, let endpoint, let instanceID, await isHealthy(endpoint, instanceID: instanceID) {
            try Task.checkCancellation()
            return endpoint
        }
        try Task.checkCancellation()
        terminateOwnedProcess()
        let root = try locateEngineRoot()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: allowedRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw RuntimeFailure.message("无法读取投喂文件所在目录：\(allowedRoot.path)")
        }

        // Port zero asks the OS for a vacant loopback port. Closing the short
        // reservation can race another process, so a bind collision gets a new
        // port instead of touching the service that won that race.
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let port = try Self.availableLoopbackPort()
            let url = URL(string: "http://127.0.0.1:\(port)")!
            let instanceID = UUID().uuidString
            let helper = try launch(engineRoot: root, port: port, instanceID: instanceID)
            process = helper
            self.instanceID = instanceID
            endpoint = url
            let deadline = Date().addingTimeInterval(startupTimeout)
            do {
                while Date() < deadline {
                    try Task.checkCancellation()
                    guard helper.isRunning else {
                        let status = helper.terminationStatus
                        let collision = recentLog().contains("address already in use")
                        terminateOwnedProcess(ifMatching: helper)
                        if collision && attempt < 2 { break }
                        throw RuntimeFailure.message("分类核心未能启动（\(status)）。日志：\(logURL.path)")
                    }
                    if await isHealthy(url, instanceID: instanceID) {
                        // The responding process must still be the child we
                        // launched, rather than an unrelated loopback listener.
                        try Task.checkCancellation()
                        guard helper.isRunning else { continue }
                        return url
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                if !helper.isRunning, attempt < 2 { continue }
                throw RuntimeFailure.message("等待分类核心启动超时。日志：\(logURL.path)")
            } catch {
                terminateOwnedProcess(ifMatching: helper)
                throw error
            }
        }
        throw RuntimeFailure.message("无法为分类核心分配本机端口，请重新连接。")
    }

    private func launch(engineRoot: URL, port: UInt16, instanceID: String) throws -> Process {
        do {
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            let output = try FileHandle(forWritingTo: logURL)
            // This is a diagnostic log, never document content. Bound old logs
            // before attaching a new helper so repeated launches stay small.
            let size = try output.seekToEnd()
            if size > 2_000_000 {
                try output.truncate(atOffset: 0)
                try output.seek(toOffset: 0)
            }
            try output.write(contentsOf: Data("\n[FilePet app start \(Date())]\n".utf8))
            logHandle = output
            let helper = Process()
            helper.executableURL = engineRoot.appendingPathComponent(".venv/bin/python")
            helper.currentDirectoryURL = engineRoot.appendingPathComponent("backend", isDirectory: true)
            helper.arguments = ["-m", "filepet", "serve", "--root", allowedRoot.path, "--port", String(port)]
            var childEnvironment = environment
            // Finder-launched apps do not receive the interactive shell's PATH.
            // Include common local installation paths for the existing OCR tool.
            let paths = ["/opt/homebrew/bin", "/usr/local/bin", childEnvironment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]
            childEnvironment["PATH"] = paths.joined(separator: ":")
            childEnvironment["FILEPET_INSTANCE_ID"] = instanceID
            childEnvironment["PYTHONUNBUFFERED"] = "1"
            childEnvironment["PYTHONDONTWRITEBYTECODE"] = "1"
            helper.environment = childEnvironment
            helper.standardInput = FileHandle.nullDevice
            helper.standardOutput = output
            helper.standardError = output
            try helper.run()
            return helper
        } catch {
            try? logHandle?.close()
            logHandle = nil
            throw RuntimeFailure.message("无法启动分类核心：\(error.localizedDescription)。日志：\(logURL.path)")
        }
    }

    private func isHealthy(_ endpoint: URL, instanceID: String) async -> Bool {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 0.5
        configuration.timeoutIntervalForResource = 0.7
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: RuntimeSessionDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            var request = URLRequest(url: endpoint.appendingPathComponent("health"), timeoutInterval: 0.5)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            struct Health: Decodable {
                let status: String
                let version: String
                let instance_id: String?
            }
            let health = try JSONDecoder().decode(Health.self, from: data)
            return health.status == "ok" && health.version == "0.1.0" && health.instance_id == instanceID
        } catch { return false }
    }

    private func locateEngineRoot() throws -> URL {
        if let configuredRoot { return try validateRoot(configuredRoot) }
        if let path = environment["FILEPET_ENGINE_ROOT"], !path.isEmpty {
            return try validateRoot(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        }
        if let configuredEngineRoot, !configuredEngineRoot.isEmpty {
            let url = URL(fileURLWithPath: (configuredEngineRoot as NSString).expandingTildeInPath)
            if let root = try? validateRoot(url) { return root }
        }
        var directory = bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        while true {
            for candidate in [directory.appendingPathComponent("filepet-engine", isDirectory: true),
                              directory.deletingLastPathComponent().appendingPathComponent("filepet-engine", isDirectory: true)] {
                if let root = try? validateRoot(candidate) { return root }
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        throw RuntimeFailure.message("找不到分类核心（FilePet Engine）。请将 filepet-engine 与 appearance 放在同一文件夹，再重新构建 App。")
    }

    private func validateRoot(_ url: URL) throws -> URL {
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        let module = root.appendingPathComponent("backend/filepet", isDirectory: true)
        guard FileManager.default.fileExists(atPath: module.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RuntimeFailure.message("找不到分类核心（FilePet Engine）：\(root.path)")
        }
        guard FileManager.default.isExecutableFile(atPath: root.appendingPathComponent(".venv/bin/python").path) else {
            throw RuntimeFailure.message("分类核心缺少 Python 运行环境，请先安装 FilePet Engine 的依赖：\(root.path)")
        }
        return root
    }

    private func terminateOwnedProcess(ifMatching expected: Process? = nil) {
        // A stopped startup may finish its HTTP await after a newer startup has
        // begun. Its cleanup is allowed to touch only its own Process object.
        if let expected, process !== expected { return }
        let helper = process
        process = nil
        endpoint = nil
        instanceID = nil
        if let helper, helper.isRunning {
            helper.terminate()
            let deadline = Date().addingTimeInterval(0.3)
            while helper.isRunning, Date() < deadline { usleep(10_000) }
            if helper.isRunning { Darwin.kill(helper.processIdentifier, SIGKILL) }
            helper.waitUntilExit()
        }
        try? logHandle?.close()
        logHandle = nil
    }

    private func recentLog() -> String {
        guard let input = try? FileHandle(forReadingFrom: logURL) else { return "" }
        defer { try? input.close() }
        do {
            let end = try input.seekToEnd()
            try input.seek(toOffset: end > 4_096 ? end - 4_096 : 0)
            let data = try input.readToEnd() ?? Data()
            return String(decoding: data, as: UTF8.self).lowercased()
        } catch { return "" }
    }

    private static func availableLoopbackPort() throws -> UInt16 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw RuntimeFailure.message("无法创建分类核心的本机连接。") }
        defer { Darwin.close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bindStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else { throw RuntimeFailure.message("无法为分类核心分配本机端口。") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameStatus = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &length)
            }
        }
        guard nameStatus == 0 else { throw RuntimeFailure.message("无法读取分类核心的本机端口。") }
        return UInt16(bigEndian: address.sin_port)
    }
}

private enum RuntimeFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

private final class RuntimeSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
