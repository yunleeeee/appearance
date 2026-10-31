import Combine
import Foundation

/// 分类反馈的外观适配：发布画面状态并调度动画，不判断文件所属分类。
@MainActor
final class VineModel: ObservableObject {
    static let grapesPerBranchLimit = VineEngine.grapesPerBranchLimit
    static let fullThreshold = VineEngine.fullThreshold
    static let theftDuration = VineEngine.theftDuration

    @Published private(set) var phase: VinePhase = .hidden
    @Published private(set) var branches: [VineBranch] = []
    @Published private(set) var latestGrowth: VineGrowth?
    @Published private(set) var activeTheft: VineTheft?
    @Published private(set) var isVisible = false
    @Published private(set) var isFull = false
    @Published private(set) var persistenceError: String?
    @Published private(set) var categoryLabels: [String: String] = [:]
    private let engine: VineEngine
    private var timer: Timer?

    init(defaults: UserDefaults = .standard) {
        engine = VineEngine(storage: DefaultsVineStorage(defaults: defaults), inventoryMode: true)
        synchronize()
    }

    deinit { timer?.invalidate() }

    /// Labels come from the connected engine; branch identities stay as engine IDs.
    func setCategoryLabels(_ labels: [String: String]) {
        categoryLabels = labels.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func displayName(for categoryID: String) -> String {
        if let label = categoryLabels[categoryID], !label.isEmpty { return label }
        return categoryID.isEmpty ? "未命名分类" : categoryID
    }

    var totalGrapes: Int { engine.totalGrapes }
    func count(for category: String) -> Int { engine.count(for: category) }
    func visibleGrapes(for category: String) -> Int { engine.visibleGrapes(for: category) }
    func harvestedGrapes(for category: String) -> Int { engine.harvestedGrapes(for: category) }
    func recordSuccess(category: String) { update { $0.recordSuccess(category: category) } }
    func recordSuccesses(categories: [String]) { update { $0.recordSuccesses(categories: categories) } }
    func previewTheft() { update { $0.previewTheft() } }
    func setTheftPresentationEnabled(_ enabled: Bool) { update { $0.setTheftPresentationEnabled(enabled) } }
    func completeTheft(id: UUID) { update { $0.completeTheft(id: id) } }
    func preview() { update { $0.preview() } }
    func wake() { update { $0.wake() } }
    func calmDown(after delay: TimeInterval = 0.25) { update { $0.calmDown(after: delay) } }
    func beginReceiving() { update { $0.beginReceiving() } }
    func scheduleSleep(after delay: TimeInterval = 2.5) { update { $0.scheduleSleep(after: delay) } }

    private func update(_ command: (VineEngine) -> Void) {
        engine.advance(to: Date())
        command(engine)
        synchronize()
    }

    private func synchronize() {
        let state = engine.snapshot
        objectWillChange.send()
        if phase != state.phase { phase = state.phase }
        if latestGrowth != state.latestGrowth { latestGrowth = state.latestGrowth }
        if branches != state.branches { branches = state.branches }
        if activeTheft != state.activeTheft { activeTheft = state.activeTheft }
        if isVisible != state.isVisible { isVisible = state.isVisible }
        if isFull != state.isFull { isFull = state.isFull }
        if persistenceError != state.persistenceError { persistenceError = state.persistenceError }

        timer?.invalidate()
        timer = nil
        guard let deadline = engine.nextDeadline else { return }
        let wakeup = Timer(timeInterval: max(0.001, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.engine.advance(to: Date())
                self.synchronize()
            }
        }
        timer = wakeup
        RunLoop.main.add(wakeup, forMode: .common)
    }
}

/// Shell-only feedback counts, separated from the old app's archived-file counters.
private final class DefaultsVineStorage: VineStorage {
    let defaults: UserDefaults
    private let prefix = "filepet.shell.appearance."
    init(defaults: UserDefaults) { self.defaults = defaults }
    func data(forKey key: String) throws -> Data? { defaults.data(forKey: prefix + key) }
    func set(_ data: Data, forKey key: String) throws { defaults.set(data, forKey: prefix + key) }
}
