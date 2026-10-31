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
}

/// The queue and completion record survive app and engine restarts.
@MainActor
final class DeadlineGarden: ObservableObject {
    @Published private(set) var deadlines: [GardenDeadline] = []
    @Published private(set) var persistenceError: String?
    private let defaults: UserDefaults
    private let key = "filepet.shell.garden.deadlines.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key) else { return }
        do { deadlines = try JSONDecoder().decode([GardenDeadline].self, from: data) }
        catch { persistenceError = "读取花朵记录失败：\(error.localizedDescription)" }
    }

    var activeDeadlines: [GardenDeadline] { deadlines.filter { $0.completedAt == nil } }
    var visibleDeadlines: [GardenDeadline] { Array(activeDeadlines.prefix(3)) }
    var queuedCount: Int { max(0, activeDeadlines.count - 3) }

    @discardableResult
    func feed(_ candidates: [EngineDeadline], now: Date = Date()) -> Int {
        var known = Set(deadlines.map(\.id))
        let additions = candidates.filter { !$0.id.isEmpty && known.insert($0.id).inserted }.map {
            GardenDeadline(id: $0.id, title: $0.title, project: $0.project,
                           dueDate: $0.dueDate, dueTime: $0.dueTime,
                           yearInferred: $0.yearInferred, evidence: $0.evidence,
                           createdAt: now, completedAt: nil)
        }
        guard !additions.isEmpty else { return 0 }
        save(deadlines + additions)
        return additions.count
    }

    func harvest(id: String, now: Date = Date()) {
        // Only a visible flower can be harvested; repeated clicks are harmless.
        guard visibleDeadlines.contains(where: { $0.id == id }),
              let index = deadlines.firstIndex(where: { $0.id == id }) else { return }
        var updated = deadlines
        updated[index].completedAt = now
        save(updated)
    }

    private func save(_ updated: [GardenDeadline]) {
        do {
            let data = try JSONEncoder().encode(updated)
            defaults.set(data, forKey: key)
            deadlines = updated
            persistenceError = nil
        } catch { persistenceError = "保存花朵记录失败：\(error.localizedDescription)" }
    }
}
