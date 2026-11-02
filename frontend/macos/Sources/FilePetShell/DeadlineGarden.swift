import Combine
import Foundation

struct GardenDeadline: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let project: String
    let dueDate: String
    let dueTime: String?
    let yearInferred: Bool
    let evidence: String
    let createdAt: Date
    var completedAt: Date?
    // Optional addition: old v1 UserDefaults records remain decodable.
    var sourcePath: String? = nil
    var semanticKey: String? = nil // Optional for legacy v1 persistence
}

@MainActor
final class DeadlineGarden: ObservableObject {
    @Published private(set) var deadlines: [GardenDeadline] = []
    @Published private(set) var persistenceError: String?
    private let defaults: UserDefaults
    private let key = "filepet.shell.garden.deadlines.v1"
    private var resolver: DeadlineStageResolver
    private(set) var currentTime: Date

    init(defaults: UserDefaults = .standard, now: Date = Date(),
         resolver: DeadlineStageResolver = DeadlineStageResolver()) {
        self.defaults = defaults
        self.currentTime = now
        self.resolver = resolver
        guard let data = defaults.data(forKey: key) else { return }
        do { deadlines = try JSONDecoder().decode([GardenDeadline].self, from: data) }
        catch { persistenceError = "读取花朵记录失败：\(error.localizedDescription)" }
    }

    /// Called on launch, wake, time-zone/clock changes and stage boundaries.
    func refreshTime(now: Date = Date()) {
        currentTime = now
        resolver = DeadlineStageResolver(thresholds: resolver.thresholds, calendar: .current)
        objectWillChange.send()
    }

    var activeDeadlines: [GardenDeadline] { deadlines.filter { $0.completedAt == nil } }

    func nextStageBoundary(after now: Date) -> Date? {
        activeDeadlines.compactMap {
            resolver.nextChange(dueDate: $0.dueDate, dueTime: $0.dueTime, now: now)
        }.min()
    }

    func stage(for deadline: GardenDeadline, now: Date? = nil) -> DeadlineStage? {
        resolver.resolve(dueDate: deadline.dueDate, dueTime: deadline.dueTime,
                         completedAt: deadline.completedAt, now: now ?? currentTime)
    }

    /// A single unobtrusive flower is resident at a time. Upcoming tasks
    /// have priority by due time; overdue tasks remain persisted in the queue
    /// and become visible only when no upcoming task is available.
    var visibleDeadlines: [GardenDeadline] {
        let upcoming = activeDeadlines.filter { stage(for: $0) != .withered }
            .sorted(by: earlier)
        if let closest = upcoming.first { return [closest] }
        let overdue = activeDeadlines.filter { stage(for: $0) == .withered }
            .sorted(by: earlier)
        return overdue.last.map { [$0] } ?? []
    }

    private func earlier(_ lhs: GardenDeadline, _ rhs: GardenDeadline) -> Bool {
        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
        if lhs.dueTime != rhs.dueTime { return (lhs.dueTime ?? "zz") < (rhs.dueTime ?? "zz") }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id < rhs.id
    }

    var queuedCount: Int { max(0, activeDeadlines.count - visibleDeadlines.count) }

    @discardableResult
    func feed(_ candidates: [EngineDeadline], now: Date = Date()) -> Int {
        var known = Set(deadlines.map(\.id))
        var semantic = Set(deadlines.compactMap(\.semanticKey))
        let added = candidates.filter { candidate in
            guard !candidate.id.isEmpty, known.insert(candidate.id).inserted else { return false }
            guard let key = candidate.semanticKey, !key.isEmpty else { return true }
            return semantic.insert(key).inserted
        }.map {
            GardenDeadline(id: $0.id, title: $0.title, project: $0.project,
                           dueDate: $0.dueDate, dueTime: $0.dueTime,
                           yearInferred: $0.yearInferred, evidence: $0.evidence,
                           createdAt: now, completedAt: nil,
                           sourcePath: $0.sourcePath, semanticKey: $0.semanticKey)
        }
        guard !added.isEmpty else { return 0 }
        save(deadlines + added)
        return added.count
    }

    func harvest(id: String, now: Date = Date()) {
        guard visibleDeadlines.contains(where: { $0.id == id }),
              let index = deadlines.firstIndex(where: { $0.id == id }),
              deadlines[index].completedAt == nil else { return }
        var updated = deadlines
        updated[index].completedAt = now
        save(updated)
    }

    @discardableResult
    func edit(id: String, title: String, project: String, dueDate: String,
              dueTime: String?) -> String? {
        if let error = DeadlineInput.validationError(title: title, project: project,
            dueDate: dueDate, dueTime: dueTime) { return error }
        guard let index = deadlines.firstIndex(where: { $0.id == id }) else {
            return "找不到对应的 DDL。"
        }
        let previous = deadlines[index]
        var updated = deadlines
        updated[index] = GardenDeadline(id: id, title: title, project: project,
            dueDate: dueDate, dueTime: dueTime, yearInferred: false,
            evidence: previous.evidence, createdAt: previous.createdAt,
            completedAt: previous.completedAt, sourcePath: previous.sourcePath,
            semanticKey: previous.semanticKey)
        save(updated)
        return persistenceError
    }

    @discardableResult
    func undoLastHarvest() -> String? {
        guard let index = deadlines.indices.filter({ deadlines[$0].completedAt != nil })
            .max(by: { deadlines[$0].completedAt! < deadlines[$1].completedAt! }) else { return nil }
        var updated = deadlines
        updated[index].completedAt = nil
        save(updated)
        return updated[index].id
    }

    private func save(_ updated: [GardenDeadline]) {
        do {
            defaults.set(try JSONEncoder().encode(updated), forKey: key)
            deadlines = updated
            persistenceError = nil
        } catch { persistenceError = "保存花朵记录失败：\(error.localizedDescription)" }
    }
}
