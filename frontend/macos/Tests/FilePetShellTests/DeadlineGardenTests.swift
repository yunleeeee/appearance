import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class DeadlineGardenTests: XCTestCase {
    func testMultipleDeadlinesUseThreeVisibleSlotsAndFIFOQueue() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let garden = DeadlineGarden(defaults: defaults)
        let fedAt = Date(timeIntervalSince1970: 1_000)
        let candidates = (1...5).map { deadline("ddl-\($0)", day: 10 - $0) }

        XCTAssertEqual(garden.feed(candidates + [candidates[0], deadline("")], now: fedAt), 5)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["ddl-1", "ddl-2", "ddl-3"])
        XCTAssertEqual(garden.queuedCount, 2)
        XCTAssertEqual(garden.activeDeadlines.count, 5)
        XCTAssertEqual(garden.deadlines.map(\.createdAt), Array(repeating: fedAt, count: 5))
        XCTAssertEqual(garden.feed(candidates, now: fedAt.addingTimeInterval(1)), 0)
        XCTAssertEqual(garden.deadlines.count, 5)
    }

    func testHarvestCompletesVisibleFlowerAndImmediatelyPromotesNext() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let garden = DeadlineGarden(defaults: defaults)
        garden.feed((1...5).map { deadline("ddl-\($0)") })
        let harvestedAt = Date(timeIntervalSince1970: 2_000)

        garden.harvest(id: "ddl-5", now: harvestedAt)
        XCTAssertNil(garden.deadlines[4].completedAt, "A queued item has no clickable flower yet")
        garden.harvest(id: "ddl-2", now: harvestedAt)
        XCTAssertEqual(garden.deadlines[1].completedAt, harvestedAt)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["ddl-1", "ddl-3", "ddl-4"])
        XCTAssertEqual(garden.queuedCount, 1)

        garden.harvest(id: "ddl-2", now: harvestedAt.addingTimeInterval(30))
        XCTAssertEqual(garden.deadlines[1].completedAt, harvestedAt, "Repeated clicks must preserve completion")
        garden.harvest(id: "ddl-1", now: harvestedAt)
        XCTAssertEqual(garden.visibleDeadlines.map(\.id), ["ddl-3", "ddl-4", "ddl-5"])
        XCTAssertEqual(garden.queuedCount, 0)
    }

    func testCompletionAndDetailsPersistAndRepeatedFeedCannotReviveFlower() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidate = deadline("done", day: 3)
        let garden = DeadlineGarden(defaults: defaults)
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let completedAt = Date(timeIntervalSince1970: 2_000)
        garden.feed([candidate], now: createdAt)
        garden.harvest(id: candidate.id, now: completedAt)

        let restored = DeadlineGarden(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.deadlines, garden.deadlines)
        XCTAssertEqual(restored.deadlines[0].title, "提交实验报告")
        XCTAssertEqual(restored.deadlines[0].project, "软件工程")
        XCTAssertEqual(restored.deadlines[0].dueDate, "2026-11-03")
        XCTAssertEqual(restored.deadlines[0].dueTime, "23:59")
        XCTAssertEqual(restored.deadlines[0].completedAt, completedAt)
        XCTAssertTrue(restored.visibleDeadlines.isEmpty)
        XCTAssertEqual(restored.feed([candidate], now: completedAt.addingTimeInterval(1)), 0)
        XCTAssertTrue(restored.visibleDeadlines.isEmpty)
        XCTAssertEqual(restored.deadlines.count, 1)
        XCTAssertNil(restored.persistenceError)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "FilePetShell.DeadlineGardenTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func deadline(_ id: String, day: Int = 3) -> EngineDeadline {
        EngineDeadline(id: id, title: "提交实验报告", project: "软件工程",
                       dueDate: String(format: "2026-11-%02d", day), dueTime: "23:59",
                       yearInferred: false, evidence: "请于11月3日23:59前提交实验报告")
    }
}
