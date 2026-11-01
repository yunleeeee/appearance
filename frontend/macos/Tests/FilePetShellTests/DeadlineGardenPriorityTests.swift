import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class DeadlineGardenPriorityTests: XCTestCase {
    func testUrgentNewTaskDisplacesOldOneWithoutDroppingQueuedData() {
        let suite = "FilePetShell.Priority.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
        let garden = DeadlineGarden(defaults: defaults, now: now)
        garden.feed([candidate("late", "2026-11-28"),
                     candidate("next", "2026-11-10"),
                     candidate("later", "2026-11-15")], now: now)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["next", "later", "late"])
        garden.feed([candidate("tomorrow", "2026-11-01")], now: now)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["tomorrow", "next", "later"])
        XCTAssertEqual(garden.queuedCount, 1)
        garden.harvest(id: "tomorrow", now: now)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["next", "later", "late"])
        let restored = DeadlineGarden(defaults: defaults, now: now)
        XCTAssertEqual(restored.visibleDeadlines.map(\.id), ["next", "later", "late"])
        XCTAssertEqual(restored.undoLastHarvest(), "tomorrow")
        XCTAssertEqual(restored.visibleDeadlines.map(\.id), ["tomorrow", "next", "later"])
    }

    func testExpiredTasksRemainQueuedButNeverMonopolizeThreeSlots() {
        let suite = "FilePetShell.Expired.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
        let garden = DeadlineGarden(defaults: defaults, now: now)
        garden.feed((1...5).map { candidate("old-\($0)", "2026-09-01") }, now: now)
        XCTAssertEqual(garden.visibleDeadlines.count, 1)
        XCTAssertEqual(garden.queuedCount, 4)
        garden.feed([candidate("urgent", "2026-11-01"),
                     candidate("soon", "2026-11-02"),
                     candidate("week", "2026-11-06")], now: now)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["urgent", "soon", "week"])
        XCTAssertEqual(garden.deadlines.count, 8)
    }

    private func candidate(_ id: String, _ date: String) -> EngineDeadline {
        EngineDeadline(id: id, title: id, project: "Course", dueDate: date,
                       dueTime: "12:00", yearInferred: false, evidence: "due " + date)
    }
}
