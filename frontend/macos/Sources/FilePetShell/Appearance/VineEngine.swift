import Foundation

/// State and scheduling for the current vine appearance. Serialize access on one
/// host thread: advance(to:) before sending commands, render snapshot, then arrange
/// the next host wakeup at nextDeadline. This type owns no timers or event loop.
public final class VineEngine {
    public static let grapesPerBranchLimit = 12
    public static let fullThreshold = 60
    public static let theftDuration: TimeInterval = 5.8
    public static let branchesKey = "vine.branches.v1"
    public static let harvestedKey = "vine.harvestedCounts.v1"

    public private(set) var currentTime: Date
    public private(set) var persistenceError: String?
    private var phase: VinePhase = .hidden
    private var branches: [VineBranch] = []
    private var latestGrowth: VineGrowth?
    private var activeTheft: VineTheft?
    private var isVisible = false
    private var isFull = false
    private var recordedBranches: [VineBranch] = []
    private var harvestedCounts: [String: Int] = [:]
    private var pendingGrowth: [String] = []
    private var growthSequence: UInt64 = 0
    private var isTargeted = false
    private var isReceiving = false
    private var armedTheftCategories: [String] = []
    private var restoredMatureCategories: [String] = []
    private var isTheftPresentationEnabled = true
    private let storage: any VineStorage

    private enum PhaseAction { case finishAppearance, beginDisappearance, finishDisappearance }
    private var phaseAction: PhaseAction?
    private var phaseDeadline: Date?
    private var growthDeadline: Date?
    private var theftDeadline: Date?
    private var watchdogDeadline: Date?

    public init(storage: any VineStorage = MemoryVineStorage(), now: Date = Date()) {
        self.storage = storage
        self.currentTime = now
        restore()
    }

    public var snapshot: VineSnapshot {
        VineSnapshot(phase: phase, branches: branches, latestGrowth: latestGrowth,
                     activeTheft: activeTheft, isVisible: isVisible, isFull: isFull,
                     recordedBranches: recordedBranches, harvestedCounts: harvestedCounts,
                     persistenceError: persistenceError)
    }

    public var nextDeadline: Date? {
        [growthDeadline, theftDeadline, phaseDeadline, watchdogDeadline].compactMap { $0 }.min()
    }

    /// Saturates at Int.max if an imported archive exceeds the representable total.
    public var totalGrapes: Int { recordedBranches.reduce(0) { Self.addCounts($0, $1.count) } }
    public func count(for category: String) -> Int { recordedBranches.first { $0.id == category }?.count ?? 0 }
    public func visibleGrapes(for category: String) -> Int { branches.first { $0.id == category }?.count ?? 0 }
    public func harvestedGrapes(for category: String) -> Int { harvestedCounts[category] ?? 0 }

    /// Execute due transitions in chronological order. Backwards clock movement is ignored.
    public func advance(to date: Date) {
        guard date >= currentTime else { return }
        while let next = nextDeadline, next <= date {
            currentTime = next
            if growthDeadline == next {
                growthDeadline = nil
                growNextGrape()
            } else if theftDeadline == next {
                theftDeadline = nil
                beginArmedTheft()
            } else if phaseDeadline == next {
                let action = phaseAction
                cancelPhase()
                performPhase(action)
            } else if watchdogDeadline == next {
                watchdogDeadline = nil
                if let event = activeTheft { completeTheft(id: event.id) }
            }
        }
        currentTime = date
    }

    public func recordSuccess(category: String) { recordSuccesses(categories: [category]) }

    /// Persist the successful batch first, then provide one growth event per 0.32s.
    public func recordSuccesses(categories: [String]) {
        guard !categories.isEmpty else { return }
        theftDeadline = nil
        var batchCategories: [String] = []
        for category in categories {
            if !batchCategories.contains(category) { batchCategories.append(category) }
            if let index = recordedBranches.firstIndex(where: { $0.id == category }) {
                if unharvestedCount(for: category) < Self.grapesPerBranchLimit { pendingGrowth.append(category) }
                recordedBranches[index].count = Self.addCounts(recordedBranches[index].count, 1)
            } else {
                recordedBranches.append(VineBranch(id: category, count: 1))
                pendingGrowth.append(category)
            }
        }
        persist(recordedBranches, forKey: Self.branchesKey)
        for category in batchCategories where unharvestedCount(for: category) >= Self.grapesPerBranchLimit {
            let alreadyInFlight = activeTheft?.category == category && activeTheft?.isPreview == false
            if !alreadyInFlight || unharvestedCount(for: category) >= Self.grapesPerBranchLimit * 2 {
                armTheft(category)
            }
        }
        guard growthDeadline == nil else { return }
        if pendingGrowth.isEmpty {
            syncVisibleBranches()
            settleFeedbackIfIdle()
        } else {
            growNextGrape()
        }
    }

    public func previewTheft() {
        guard isTheftPresentationEnabled, activeTheft == nil,
              !isTargeted, !isReceiving, growthDeadline == nil else { return }
        let selected = branches.first(where: { $0.isMature }) ?? branches.first
        let category = selected?.id ?? "文档"
        startTheft(category: category, branchIndex: branches.firstIndex { $0.id == category } ?? 0, isPreview: true)
    }

    /// Cancel without consuming fruit. Re-enabling can replay from the start.
    public func setTheftPresentationEnabled(_ enabled: Bool) {
        guard enabled != isTheftPresentationEnabled else { return }
        isTheftPresentationEnabled = enabled
        if !enabled {
            theftDeadline = nil
            watchdogDeadline = nil
            if let event = activeTheft, !event.isPreview {
                armedTheftCategories.removeAll { $0 == event.category }
                armedTheftCategories.insert(event.category, at: 0)
            }
            activeTheft = nil
        } else {
            settleFeedbackIfIdle()
        }
    }

    public func completeTheft(id: UUID) {
        guard let event = activeTheft, event.id == id else { return }
        watchdogDeadline = nil
        if !event.isPreview {
            harvestedCounts[event.category] = min(count(for: event.category),
                                                  Self.addCounts(harvestedGrapes(for: event.category), Self.grapesPerBranchLimit))
            persist(harvestedCounts, forKey: Self.harvestedKey)
            if let index = branches.firstIndex(where: { $0.id == event.category }) {
                branches[index].count = min(Self.grapesPerBranchLimit, unharvestedCount(for: event.category))
            }
        }
        activeTheft = nil
        if growthDeadline == nil { latestGrowth = nil }
        refreshFullState()
        phase = isReceiving ? .receiving : (isFull ? .full : .swaying)
        settleFeedbackIfIdle()
    }

    public func preview() {
        guard !isTargeted, !isReceiving, growthDeadline == nil, activeTheft == nil else { return }
        isVisible = true
        phase = isFull ? .full : .swaying
        scheduleDisappearance(after: 6)
    }

    public func wake() {
        let wasTargeted = isTargeted
        isTargeted = true
        isVisible = true
        theftDeadline = nil
        for category in restoredMatureCategories { armTheft(category) }
        restoredMatureCategories.removeAll()
        if phase == .appearing && wasTargeted { return }
        cancelPhase()
        guard phase == .hidden || phase == .disappearing || phase == .appearing else { return }
        phase = .appearing
        schedulePhase(.finishAppearance, after: 0.45)
    }

    public func calmDown(after delay: TimeInterval = 0.25) {
        isTargeted = false
        guard !isReceiving, growthDeadline == nil, activeTheft == nil else { return }
        if planTheftIfPossible() { return }
        scheduleDisappearance(after: delay)
    }

    public func beginReceiving() {
        cancelPhase()
        theftDeadline = nil
        isReceiving = true
        isVisible = true
        phase = .receiving
    }

    public func scheduleSleep(after delay: TimeInterval = 2.5) {
        isReceiving = false
        guard !isTargeted, growthDeadline == nil, activeTheft == nil else { return }
        if planTheftIfPossible() { return }
        scheduleDisappearance(after: delay)
    }

    private func growNextGrape() {
        while !pendingGrowth.isEmpty {
            let category = pendingGrowth.removeFirst()
            let index = branches.firstIndex { $0.id == category }
            let previousCount = index.map { branches[$0].count } ?? 0
            guard previousCount < Self.grapesPerBranchLimit else { continue }
            growthSequence += 1
            latestGrowth = VineGrowth(category: category, grapeIndex: previousCount, sequence: growthSequence)
            if let index { branches[index].count += 1 }
            else { branches.append(VineBranch(id: category, count: 1)) }
            refreshFullState()
            growthDeadline = currentTime.addingTimeInterval(0.32)
            return
        }
        growthDeadline = nil
        syncVisibleBranches()
        settleFeedbackIfIdle()
    }

    private func unharvestedCount(for category: String) -> Int { max(0, count(for: category) - harvestedGrapes(for: category)) }

    /// Counters are nonnegative, including legacy archive input. Saturation avoids
    /// crashing either platform on a large but syntactically valid imported count.
    private static func addCounts(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = max(0, lhs).addingReportingOverflow(max(0, rhs))
        return overflow ? Int.max : sum
    }

    private func armTheft(_ category: String) {
        if !armedTheftCategories.contains(category) { armedTheftCategories.append(category) }
    }

    @discardableResult
    private func planTheftIfPossible() -> Bool {
        armedTheftCategories.removeAll { unharvestedCount(for: $0) < Self.grapesPerBranchLimit }
        guard isTheftPresentationEnabled, activeTheft == nil, !armedTheftCategories.isEmpty,
              !isTargeted, !isReceiving, growthDeadline == nil, isVisible else { return false }
        if theftDeadline != nil { return true }
        cancelPhase()
        phase = .full
        theftDeadline = currentTime.addingTimeInterval(0.8)
        return true
    }

    private func beginArmedTheft() {
        guard isTheftPresentationEnabled, activeTheft == nil, !isTargeted, !isReceiving,
              growthDeadline == nil, isVisible, let category = armedTheftCategories.first else { return }
        armedTheftCategories.removeFirst()
        guard unharvestedCount(for: category) >= Self.grapesPerBranchLimit,
              let index = branches.firstIndex(where: { $0.id == category }) else {
            settleFeedbackIfIdle()
            return
        }
        startTheft(category: category, branchIndex: index, isPreview: false)
    }

    private func startTheft(category: String, branchIndex: Int, isPreview: Bool) {
        guard isTheftPresentationEnabled else { return }
        cancelPhase()
        theftDeadline = nil
        isVisible = true
        phase = .full
        activeTheft = VineTheft(id: UUID(), category: category, branchIndex: branchIndex,
                               startedAt: currentTime, isPreview: isPreview)
        watchdogDeadline = currentTime.addingTimeInterval(Self.theftDuration + 1)
    }

    private func settleFeedbackIfIdle() {
        guard !isReceiving, !isTargeted, growthDeadline == nil, activeTheft == nil, isVisible else { return }
        if !planTheftIfPossible() { scheduleDisappearance(after: 2.5) }
    }

    private func syncVisibleBranches() {
        branches = recordedBranches.map {
            VineBranch(id: $0.id, count: min(Self.grapesPerBranchLimit, unharvestedCount(for: $0.id)))
        }
        refreshFullState()
    }

    private func refreshFullState() {
        isFull = branches.contains { $0.isMature }
        if phase == .swaying && isFull { phase = .full }
        if phase == .full && !isFull && activeTheft == nil { phase = .swaying }
    }

    private func persist<Value: Encodable>(_ value: Value, forKey key: String) {
        do { try storage.set(JSONEncoder().encode(value), forKey: key) }
        catch { persistenceError = error.localizedDescription }
    }

    private func restore() {
        do {
            guard let data = try storage.data(forKey: Self.branchesKey) else { return }
            let saved = try JSONDecoder().decode([VineBranch].self, from: data)
            // Legacy/custom archives may repeat a category. Keep its first position
            // while normalizing to one branch per id for stable rendering on all hosts.
            for branch in saved {
                if let index = recordedBranches.firstIndex(where: { $0.id == branch.id }) {
                    recordedBranches[index].count = Self.addCounts(recordedBranches[index].count, branch.count)
                } else {
                    recordedBranches.append(VineBranch(id: branch.id, count: max(0, branch.count)))
                }
            }
            if let data = try storage.data(forKey: Self.harvestedKey) {
                let savedHarvests = try JSONDecoder().decode([String: Int].self, from: data)
                for branch in recordedBranches {
                    harvestedCounts[branch.id] = min(branch.count, max(0, savedHarvests[branch.id] ?? 0))
                }
            }
        } catch { persistenceError = error.localizedDescription }
        syncVisibleBranches()
        restoredMatureCategories = branches.filter(\.isMature).map(\.id)
    }

    private func cancelPhase() { phaseDeadline = nil; phaseAction = nil }
    private func schedulePhase(_ action: PhaseAction, after delay: TimeInterval) {
        phaseAction = action
        phaseDeadline = currentTime.addingTimeInterval(max(0, delay))
    }
    private func scheduleDisappearance(after delay: TimeInterval) {
        guard activeTheft == nil else { return }
        schedulePhase(.beginDisappearance, after: delay)
    }
    private func performPhase(_ action: PhaseAction?) {
        switch action {
        case .finishAppearance:
            if phase == .appearing { phase = isFull ? .full : .swaying }
        case .beginDisappearance:
            guard !isTargeted, !isReceiving, growthDeadline == nil,
                  activeTheft == nil, theftDeadline == nil else { return }
            phase = .disappearing
            isVisible = false
            schedulePhase(.finishDisappearance, after: 0.5)
        case .finishDisappearance:
            guard phase == .disappearing, activeTheft == nil else { return }
            phase = .hidden
            latestGrowth = nil
        case nil: break
        }
    }
}
