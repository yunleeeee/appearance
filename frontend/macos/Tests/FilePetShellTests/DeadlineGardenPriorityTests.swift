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
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["next"])
        garden.feed([candidate("tomorrow", "2026-11-01")], now: now)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["tomorrow"])
        XCTAssertEqual(garden.queuedCount, 3)
        garden.harvest(id: "tomorrow", now: now)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["next"])
        let restored = DeadlineGarden(defaults: defaults, now: now)
        XCTAssertEqual(restored.visibleDeadlines.map(\.id), ["next"])
        XCTAssertEqual(restored.undoLastHarvest(), "tomorrow")
        XCTAssertEqual(restored.visibleDeadlines.map(\.id), ["tomorrow"])
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
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["urgent"])
        XCTAssertEqual(garden.queuedCount, 7)
        XCTAssertEqual(garden.deadlines.count, 8)
    }

    func testFlowerCountCanBeSelectedFromOneToThreeAndPersistsAcrossRestart() {
        let suite = "FilePetShell.FlowerSlots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
        let garden = DeadlineGarden(defaults: defaults, now: now)
        XCTAssertEqual(garden.visibleLimit, 1, "Existing installations default to solo view")
        garden.feed([
            candidate("third", "2026-11-04"),
            candidate("first", "2026-11-02"),
            candidate("fourth", "2026-11-06"),
            candidate("second", "2026-11-03")
        ], now: now)

        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["first"])
        XCTAssertEqual(garden.queuedCount, 3)

        garden.setVisibleLimit(2)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["first", "second"])
        XCTAssertEqual(garden.queuedCount, 2)
        garden.setVisibleLimit(3)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["first", "second", "third"])
        XCTAssertEqual(garden.queuedCount, 1)

        let restored = DeadlineGarden(defaults: UserDefaults(suiteName: suite)!, now: now)
        XCTAssertEqual(restored.visibleLimit, 3)
        XCTAssertEqual(restored.visibleDeadlines.map(\.id), ["first", "second", "third"])

        restored.setVisibleLimit(0)
        XCTAssertEqual(restored.visibleLimit, 1, "Count below one must be clamped")
        restored.setVisibleLimit(100)
        XCTAssertEqual(restored.visibleLimit, 3, "Count above three must be clamped")
        restored.setVisibleLimit(2)
        XCTAssertEqual(restored.visibleLimit, 2)

        restored.harvest(id: "first", now: now)
        XCTAssertEqual(restored.visibleDeadlines.map(\.id), ["second", "third"])
        XCTAssertEqual(restored.queuedCount, 1)
        XCTAssertNotNil(restored.deadlines.first { $0.id == "first" }?.completedAt)
        XCTAssertEqual(restored.undoLastHarvest(), "first")
        XCTAssertEqual(restored.visibleDeadlines.map(\.id), ["first", "second"])
    }

    func testOnlyOneOverdueFlowerUsesSpareSlotAcrossAllCountSettings() {
        let suite = "FilePetShell.FlowerExpiredSlots.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
        let garden = DeadlineGarden(defaults: defaults, now: now)
        garden.feed([
            candidate("oldest", "2026-08-01"),
            candidate("expired", "2026-10-01"),
            candidate("upcoming", "2026-11-02"),
            candidate("later", "2026-11-05")
        ], now: now)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["upcoming"])

        garden.setVisibleLimit(2)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["upcoming", "later"])
        garden.setVisibleLimit(3)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["upcoming", "later", "expired"])
        XCTAssertEqual(garden.queuedCount, 1)
        XCTAssertEqual(garden.activeDeadlines.count, 4)
    }

    private func candidate(_ id: String, _ date: String) -> EngineDeadline {
        EngineDeadline(id: id, title: id, project: "Course", dueDate: date,
                       dueTime: "12:00", yearInferred: false, evidence: "due " + date)
    }
}
