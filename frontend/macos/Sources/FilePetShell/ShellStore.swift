import AppKit
import Combine
import Foundation

struct ShellFileResult: Identifiable, Equatable {
    enum Outcome: Equatable { case classified, deadline, needsReview, failed }
    let id = UUID()
    let fileName: String
    let outcome: Outcome
    let categoryLabel: String?
    let detail: String
    var reviewID: String? = nil
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
    let garden: DeadlineGarden
    let reviewInbox: FileReviewInbox
    var onShowPendingReviews: (() -> Void)?
    private let defaults: UserDefaults
    private var classifiedPaths: Set<String>
    private let pathsKey = "filepet.shell.inventory.paths.v1"
    private var client: (any EngineServing)?
    private let runtime: (any EngineRuntimeManaging)?
    private let usesInjectedClient: Bool
    private var managedEndpoint: URL?
    private let configurationError: String?
    private let pollInterval: UInt64
    private let jobTimeout: TimeInterval
    private var work: Task<Void, Never>?
    private var connectionCheck: Task<Void, Never>?
    private var connectionID = UUID()
    private var reconnectTimer: Timer?
    private var runID = UUID()
    private(set) var categoryLabels: [String: String] = [:]

    init(client: (any EngineServing)? = nil, runtime: (any EngineRuntimeManaging)? = nil,
         defaults: UserDefaults = .standard,
         arguments: [String] = CommandLine.arguments,
         pollInterval: UInt64 = 250_000_000, jobTimeout: TimeInterval = 90) {
        if defaults === UserDefaults.standard {
            ShellPreferencesMigration.restoreLegacySandboxValues(into: defaults)
        }
        vine = VineModel(defaults: defaults)
        garden = DeadlineGarden(defaults: defaults)
        reviewInbox = FileReviewInbox(defaults: defaults)
        self.defaults = defaults
        classifiedPaths = Set(defaults.stringArray(forKey: "filepet.shell.inventory.paths.v1") ?? [])
        categoryLabels = defaults.dictionary(forKey: "filepet.shell.inventory.labels.v1") as? [String: String] ?? [:]
        vine.setCategoryLabels(categoryLabels)
        self.pollInterval = pollInterval
        self.jobTimeout = jobTimeout
        usesInjectedClient = client != nil
        if arguments.contains("--engine-url") {
            // An explicit endpoint is external mode: never start or stop its service.
            self.runtime = nil
            do {
                guard let index = arguments.firstIndex(of: "--engine-url"),
                      arguments.indices.contains(index + 1),
                      let endpoint = URL(string: arguments[index + 1]) else {
                    throw EngineClientError.invalidEndpoint
                }
                let external = try EngineClient(baseURL: endpoint)
                self.client = client ?? external
                configurationError = nil
            } catch {
                self.client = nil
                configurationError = error.localizedDescription
            }
        } else if let client {
            self.client = client
            self.runtime = runtime
            configurationError = nil
        } else {
            self.client = nil
            self.runtime = runtime ?? LocalEngineRuntime()
            configurationError = nil
            connectionStatus = "分类引擎：正在准备"
        }
    }

    /// Called once when the app opens. Recovery only manages the app's own core.
    func startConnectionMonitoring() {
        refreshConnection()
        guard runtime != nil, reconnectTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshConnection(quietly: true) }
        }
        timer.tolerance = 0.5
        reconnectTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func refreshConnection(quietly: Bool = false) {
        guard !isBusy, !quietly || connectionCheck == nil else { return }
        connectionCheck?.cancel()
        connectionID = UUID()
        let attemptID = connectionID
        let wasConnected = connectionStatus.hasPrefix("分类引擎：已连接")
        if !quietly || !wasConnected {
            status = runtime == nil ? "正在连接分类引擎…" : "正在准备分类引擎…"
        }
        connectionCheck = Task { [weak self] in
            guard let self else { return }
            defer { if self.connectionID == attemptID { self.connectionCheck = nil } }
            do {
                try await self.connect()
                try Task.checkCancellation()
                guard self.connectionID == attemptID else { return }
                if !quietly || !wasConnected {
                    self.status = "分类引擎已连接，把文件投给葡萄藤吧"
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.connectionID == attemptID else { return }
                self.connectionStatus = "分类引擎：未连接"
                self.status = self.friendlyError(error)
            }
        }
    }

    func waitUntilConnected() async { await connectionCheck?.value }

    private func connect() async throws {
        if let runtime {
            if !connectionStatus.hasPrefix("分类引擎：已连接") {
                connectionStatus = "分类引擎：正在启动…"
            }
            let endpoint = try await runtime.ensureRunning()
            try Task.checkCancellation()
            if !usesInjectedClient, client == nil || managedEndpoint != endpoint {
                client = try EngineClient(baseURL: endpoint)
                managedEndpoint = endpoint
            }
        }
        guard let client else {
            throw ShellError.message(configurationError ?? "分类引擎未配置")
        }
        let health = try await client.health()
        guard health.status == "ok" else { throw EngineClientError.invalidResponse }
        let categories = try await client.categories()
        try Task.checkCancellation()
        categoryLabels = Dictionary(categories.map { ($0.id, $0.label) }, uniquingKeysWith: { _, new in new })
        vine.setCategoryLabels(categoryLabels)
        defaults.set(categoryLabels, forKey: "filepet.shell.inventory.labels.v1")
        connectionStatus = "分类引擎：已连接（\(health.version)）"
    }

    func chooseFiles() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "选择要分类的文件"
        panel.message = "选择要投喂的文件，App 会自动连接分类核心"
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
        connectionID = UUID()
        connectionCheck = nil
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
        defer {
            if runID == batchID {
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
                    if ["completed", "needs_review"].contains(job.status), let result = job.result {
                        // Classification and DDL candidates are independent outcomes.
                        let identity = URL(fileURLWithPath: result.path).standardizedFileURL.path
                        var label: String?
                        var newGrape = false
                        if result.status == "classified", let category = result.categoryID, !category.isEmpty {
                            let resolved = result.categoryLabel ?? categoryLabels[category] ?? category
                            label = resolved
                            categoryLabels[category] = resolved
                            vine.setCategoryLabels(categoryLabels)
                            defaults.set(categoryLabels, forKey: "filepet.shell.inventory.labels.v1")
                            if classifiedPaths.insert(identity).inserted {
                                vine.recordSuccess(category: category)
                                defaults.set(classifiedPaths.sorted(), forKey: pathsKey)
                                newGrape = true
                            }
                        }
                        let known = Set(garden.deadlines.map(\.id))
                        let toReview = result.deadlines.filter {
                            $0.requiresConfirmation && !known.contains($0.id)
                        }
                        let added = garden.feed(result.deadlines.filter { !$0.requiresConfirmation })
                        let categoryPending = label == nil
                        if categoryPending || !toReview.isEmpty {
                            reviewInbox.enqueue(result: result, candidates: toReview,
                                                needsCategoryReview: categoryPending)
                        } else {
                            reviewInbox.remove(id: identity)
                        }
                        let outcome: ShellFileResult.Outcome
                        if categoryPending || !toReview.isEmpty { outcome = .needsReview }
                        else if result.deadlines.isEmpty { outcome = .classified }
                        else { outcome = .deadline }
                        let categorySummary = label == nil ? "分类待确认" :
                            (newGrape ? "已新增分类葡萄" : "分类葡萄已计数")
                        let deadlineSummary = !toReview.isEmpty
                            ? "\(toReview.count) 条 DDL 待核对"
                            : (result.deadlines.isEmpty ? "无 DDL" : "新增 \(added) 朵花")
                        results.append(ShellFileResult(
                            fileName: url.lastPathComponent, outcome: outcome,
                            categoryLabel: label, detail: "\(categorySummary)；\(deadlineSummary)",
                            reviewID: (categoryPending || !toReview.isEmpty) ? identity : nil))
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
            let confirmed = results.filter { $0.categoryLabel != nil }.count
            let review = results.filter { $0.outcome == .needsReview }.count
            let failed = results.filter { $0.outcome == .failed }.count
            let deadlineFiles = results.filter { $0.outcome == .deadline || $0.detail.contains("DDL 待核对") }.count
            status = "分类完成：\(confirmed) 个已识别，\(review) 个待确认，\(failed) 个失败"
            if deadlineFiles > 0 { status += "；\(deadlineFiles) 份 DDL，\(garden.visibleDeadlines.count) 朵花，\(garden.queuedCount) 个排队" }
            if review > 0, !reviewInbox.items.isEmpty { onShowPendingReviews?() }
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

    @discardableResult
    func confirmDeadline(reviewID: String, candidateID: String?, title: String, project: String,
                         dueDate: String, dueTime: String?) -> String? {
        guard let review = reviewInbox.items.first(where: { $0.id == reviewID }) else { return "这项待确认记录已处理。" }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = dueDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let time = dueTime?.trimmingCharacters(in: .whitespacesAndNewlines)
        let optionalTime = time.flatMap { $0.isEmpty ? nil : $0 }
        if let error = DeadlineInput.validationError(title: title, project: project, dueDate: date, dueTime: optionalTime) { return error }
        let candidate = candidateID.flatMap { id in review.candidates.first { $0.id == id } }
        if candidateID != nil, candidate == nil { return "这条候选 DDL 已处理，请选择其他事项。" }
        let id = candidate?.id ?? DeadlineInput.manualID(path: review.path, title: title, dueDate: date, dueTime: optionalTime)
        let confirmed = EngineDeadline(id: id, title: title, project: project, dueDate: date,
            dueTime: optionalTime, yearInferred: false, evidence: candidate?.evidence ?? "用户补充：" + title,
            signal: "user_confirmed")
        garden.feed([confirmed])
        if let error = garden.persistenceError { return error }
        reviewInbox.resolveCandidate(reviewID: reviewID, candidateID: candidateID)
        status = "DDL 已确认；当前 \(garden.visibleDeadlines.count) 朵花，\(garden.queuedCount) 个排队"
        updateReviewedResult(review, outcome: .deadline, detail: status)
        return nil
    }

    @discardableResult
    func confirmCategory(reviewID: String, categoryID: String) -> String? {
        guard let review = reviewInbox.items.first(where: { $0.id == reviewID }) else { return "这项待确认记录已处理。" }
        guard let label = categoryLabels[categoryID], !label.isEmpty else { return "请选择核心提供的分类。" }
        if classifiedPaths.insert(review.path).inserted {
            vine.beginReceiving()
            vine.recordSuccess(category: categoryID)
            vine.scheduleSleep()
            defaults.set(classifiedPaths.sorted(), forKey: pathsKey)
        }
        reviewInbox.resolveCategory(reviewID: reviewID)
        status = "已确认为“\(label)”，葡萄计数已更新"
        updateReviewedResult(review, outcome: .classified, detail: status, categoryLabel: label)
        return nil
    }

    func dismissReview(id: String) {
        reviewInbox.remove(id: id)
        status = "已忽略这项待确认记录"
    }

    private func updateReviewedResult(_ review: PendingFileReview, outcome: ShellFileResult.Outcome,
                                      detail: String, categoryLabel: String? = nil) {
        let remains = reviewInbox.items.first { $0.id == review.id }
        results = results.map { item in
            guard item.reviewID == review.id else { return item }
            return ShellFileResult(fileName: item.fileName,
                outcome: remains == nil ? outcome : .needsReview,
                categoryLabel: categoryLabel,
                detail: remains == nil ? detail : "还有 \(remains?.candidates.count ?? 0) 条 DDL 待确认",
                reviewID: review.id)
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
        connectionID = UUID()
        connectionCheck?.cancel()
        connectionCheck = nil
        work?.cancel()
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        runtime?.stop()
    }

    func showResults() {
        let alert = NSAlert()
        alert.messageText = "最近一批分类结果"
        alert.informativeText = results.isEmpty ? status : results.prefix(30).map { item in
            let label: String
            switch item.outcome {
            case .classified: label = item.categoryLabel ?? "已识别"
            case .deadline: label = "DDL 花朵"
            case .needsReview: label = "待确认"
            case .failed: label = "失败"
            }
            return "\(item.fileName) → \(label)\n\(item.detail)"
        }.joined(separator: "\n\n")
        alert.addButton(withTitle: "好")
        if !reviewInbox.items.isEmpty { alert.addButton(withTitle: "处理待确认…") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { onShowPendingReviews?() }
    }

    private func friendlyError(_ error: Error) -> String {
        if let urlError = error as? URLError,
           [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut].contains(urlError.code) {
            return runtime == nil
                ? "无法连接本机分类引擎，请检查外部服务是否已启动"
                : "分类引擎暂时断开，App 会自动重新连接，请稍后重试"
        }
        return error.localizedDescription
    }
}

private enum ShellError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
