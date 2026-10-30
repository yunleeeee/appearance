import AppKit
import Combine
import Foundation

struct ShellFileResult: Identifiable, Equatable {
    enum Outcome: Equatable { case classified, needsReview, failed }
    let id = UUID()
    let fileName: String
    let outcome: Outcome
    let categoryLabel: String?
    let detail: String
}

/// UI orchestration only: the service owns every classification decision.
/// This adapter never extracts file contents or copies/moves the original.
@MainActor
final class ShellStore: ObservableObject {
    @Published private(set) var status = "把文件投给葡萄藤，或先预览动画"
    @Published private(set) var connectionStatus = "分类引擎：尚未连接"
    @Published private(set) var isBusy = false
    @Published private(set) var results: [ShellFileResult] = []
    @Published var petVisible = true

    let vine: VineModel
    private let client: (any EngineServing)?
    private let configurationError: String?
    private let pollInterval: UInt64
    private let jobTimeout: TimeInterval
    private var work: Task<Void, Never>?
    private var connectionCheck: Task<Void, Never>?
    private var runID = UUID()
    private(set) var categoryLabels: [String: String] = [:]

    init(client: (any EngineServing)? = nil, defaults: UserDefaults = .standard,
         arguments: [String] = CommandLine.arguments,
         pollInterval: UInt64 = 250_000_000, jobTimeout: TimeInterval = 90) {
        vine = VineModel(defaults: defaults)
        self.pollInterval = pollInterval
        self.jobTimeout = jobTimeout
        if let client {
            self.client = client
            configurationError = nil
        } else {
            do {
                var endpoint = EngineClient.defaultBaseURL
                if let index = arguments.firstIndex(of: "--engine-url") {
                    guard arguments.indices.contains(index + 1),
                          let supplied = URL(string: arguments[index + 1]) else {
                        throw EngineClientError.invalidEndpoint
                    }
                    endpoint = supplied
                }
                self.client = try EngineClient(baseURL: endpoint)
                configurationError = nil
            } catch {
                self.client = nil
                configurationError = error.localizedDescription
            }
        }
    }

    func refreshConnection() {
        guard !isBusy else { return }
        connectionCheck?.cancel()
        connectionCheck = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.connect()
                self.status = "分类引擎已连接，把文件投给葡萄藤吧"
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.connectionStatus = "分类引擎：未连接"
                self.status = self.friendlyError(error)
            }
        }
    }

    private func connect() async throws {
        guard let client else {
            throw ShellError.message(configurationError ?? "分类引擎未配置")
        }
        let health = try await client.health()
        guard health.status == "ok" else { throw EngineClientError.invalidResponse }
        let categories = try await client.categories()
        try Task.checkCancellation()
        categoryLabels = Dictionary(categories.map { ($0.id, $0.label) }, uniquingKeysWith: { _, new in new })
        vine.setCategoryLabels(categoryLabels)
        connectionStatus = "分类引擎：已连接（\(health.version)）"
    }

    func chooseFiles() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要分类的文件"
        panel.message = "请选择分类引擎已授权目录中的文件"
        panel.prompt = "开始分类"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { classifyFiles(panel.urls) }
    }

    func classifyFiles(_ urls: [URL]) {
        guard !isBusy else { return }
        var seen = Set<String>()
        let files = urls.filter { $0.isFileURL && seen.insert($0.standardizedFileURL.path).inserted }
        guard !files.isEmpty else { return }
        connectionCheck?.cancel()
        runID = UUID()
        let batchID = runID
        isBusy = true
        results = []
        status = "正在连接分类引擎…"
        vine.beginReceiving()
        work = Task { [weak self] in
            guard let self else { return }
            await self.process(files, batchID: batchID)
        }
    }

    /// Awaitable seam for integration tests and alternative hosts.
    func waitUntilIdle() async { await work?.value }

    private func process(_ files: [URL], batchID: UUID) async {
        var successfulCategories: [String] = []
        defer {
            if runID == batchID {
                vine.recordSuccesses(categories: successfulCategories)
                isBusy = false
                vine.scheduleSleep()
            }
        }
        do {
            try await connect()
            for (index, url) in files.enumerated() {
                try Task.checkCancellation()
                guard runID == batchID else { return }
                status = "正在分类（\(index + 1)/\(files.count)）\(url.lastPathComponent)"
                let scope = url.startAccessingSecurityScopedResource()
                defer { if scope { url.stopAccessingSecurityScopedResource() } }
                do {
                    let job = try await finishedJob(path: url.path)
                    try Task.checkCancellation()
                    guard runID == batchID else { return }
                    if job.status == "completed", let result = job.result,
                       result.status == "classified", let category = result.categoryID, !category.isEmpty {
                        let label = result.categoryLabel ?? categoryLabels[category] ?? category
                        categoryLabels[category] = label
                        vine.setCategoryLabels(categoryLabels)
                        successfulCategories.append(category)
                        results.append(ShellFileResult(fileName: url.lastPathComponent, outcome: .classified,
                                                       categoryLabel: label, detail: result.reason))
                    } else if job.status == "needs_review" {
                        results.append(ShellFileResult(fileName: url.lastPathComponent, outcome: .needsReview,
                                                       categoryLabel: nil, detail: job.result?.reason ?? "需要你确认分类"))
                    } else {
                        results.append(ShellFileResult(fileName: url.lastPathComponent, outcome: .failed,
                                                       categoryLabel: nil, detail: job.error?.detail ?? "分类引擎未返回有效结果"))
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    if Task.isCancelled { throw CancellationError() }
                    results.append(ShellFileResult(fileName: url.lastPathComponent, outcome: .failed,
                                                   categoryLabel: nil, detail: friendlyError(error)))
                }
            }
            let confirmed = results.filter { $0.outcome == .classified }.count
            let review = results.filter { $0.outcome == .needsReview }.count
            let failed = results.filter { $0.outcome == .failed }.count
            status = "分类完成：\(confirmed) 个已识别，\(review) 个待确认，\(failed) 个失败"
        } catch is CancellationError {
            if runID == batchID { status = "已停止等待分类结果" }
        } catch {
            guard runID == batchID else { return }
            if Task.isCancelled {
                status = "已停止等待分类结果"
                return
            }
            connectionStatus = "分类引擎：未连接"
            status = friendlyError(error)
            results = files.map { ShellFileResult(fileName: $0.lastPathComponent, outcome: .failed,
                                                  categoryLabel: nil, detail: status) }
        }
    }

    private func finishedJob(path: String) async throws -> EngineJob {
        guard let client else { throw EngineClientError.invalidEndpoint }
        let accepted = try await client.createJob(path: path)
        let deadline = Date().addingTimeInterval(jobTimeout)
        while true {
            try Task.checkCancellation()
            let job = try await client.job(id: accepted.jobID)
            guard job.jobID == accepted.jobID else { throw EngineClientError.invalidResponse }
            switch job.status {
            case "completed", "needs_review", "failed": return job
            default: break
            }
            guard Date() < deadline else { throw ShellError.message("分类等待超时，请稍后重试") }
            try await Task.sleep(nanoseconds: pollInterval)
        }
    }

    func stop() {
        // The service has no cancellation endpoint. Stop UI polling and commit
        // only results already received; no claim that server work was undone.
        connectionCheck?.cancel()
        work?.cancel()
    }

    func showResults() {
        let alert = NSAlert()
        alert.messageText = "最近一批分类结果"
        alert.informativeText = results.isEmpty ? status : results.prefix(30).map { item in
            let label: String
            switch item.outcome {
            case .classified: label = item.categoryLabel ?? "已识别"
            case .needsReview: label = "待确认"
            case .failed: label = "失败"
            }
            return "\(item.fileName) → \(label)\n\(item.detail)"
        }.joined(separator: "\n\n")
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func friendlyError(_ error: Error) -> String {
        if let urlError = error as? URLError,
           [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut].contains(urlError.code) {
            return "无法连接本机分类引擎，请先启动引擎；动画预览仍可使用"
        }
        return error.localizedDescription
    }
}

private enum ShellError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
