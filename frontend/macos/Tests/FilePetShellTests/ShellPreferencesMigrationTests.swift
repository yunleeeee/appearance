import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class ShellPreferencesMigrationTests: XCTestCase {
    private let branchesKey = "filepet.shell.appearance.vine.branches.v1"
    private let gardenKey = "filepet.shell.garden.deadlines.v1"

    func testTypedLegacyRecordsKeepGrapesAndCompletedFlowersWithoutChangingSource() throws {
        let (defaults, suite) = isolatedDefaults()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: source)
        }
        let completedAt = Date(timeIntervalSince1970: 2_000)
        let completed = GardenDeadline(id: "harvested", title: "实验报告", project: "软件工程",
            dueDate: "2026-11-03", dueTime: "23:59", yearInferred: false, evidence: "提交实验报告",
            createdAt: Date(timeIntervalSince1970: 1_000), completedAt: completedAt)
        let grapes = try JSONEncoder().encode([VineBranch(id: "finance", count: 7)])
        let flowers = try JSONEncoder().encode([completed])
        let legacy: [String: Any] = [
            branchesKey: grapes, gardenKey: flowers,
            "filepet.shell.inventory.paths.v1": ["/tmp/report.txt"],
            "unrelated.preference": "must not import",
        ]
        let original = try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0)
        try original.write(to: source)

        ShellPreferencesMigration.restoreLegacySandboxValues(into: defaults, legacyFileURL: source)

        XCTAssertEqual(defaults.data(forKey: branchesKey), grapes)
        XCTAssertEqual(defaults.data(forKey: gardenKey), flowers)
        XCTAssertEqual(defaults.stringArray(forKey: "filepet.shell.inventory.paths.v1"), ["/tmp/report.txt"])
        XCTAssertNil(defaults.object(forKey: "unrelated.preference"))
        XCTAssertTrue(defaults.bool(forKey: ShellPreferencesMigration.markerKey))
        XCTAssertEqual(try Data(contentsOf: source), original, "The sandbox copy must remain recoverable")
        XCTAssertEqual(VineModel(defaults: defaults).count(for: "finance"), 7)
        let garden = DeadlineGarden(defaults: defaults)
        XCTAssertEqual(garden.deadlines.first?.completedAt, completedAt)
        XCTAssertTrue(garden.visibleDeadlines.isEmpty, "A harvested legacy flower must not revive during migration")
        XCTAssertEqual(garden.feed([EngineDeadline(id: completed.id, title: completed.title,
            project: completed.project, dueDate: completed.dueDate, dueTime: completed.dueTime,
            yearInferred: completed.yearInferred, evidence: completed.evidence)]), 0)
    }

    func testCurrentValuesWinAndSuccessfulMigrationCannotReimportStaleRecords() throws {
        let (defaults, suite) = isolatedDefaults()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: source)
        }
        let completed = GardenDeadline(id: "same-deadline", title: "终稿", project: "星河",
            dueDate: "2026-11-03", dueTime: nil, yearInferred: false, evidence: "终稿截止",
            createdAt: Date(timeIntervalSince1970: 1_000), completedAt: Date(timeIntervalSince1970: 2_000))
        let current = try JSONEncoder().encode([completed])
        defaults.set(current, forKey: gardenKey)
        try Data("not a property list".utf8).write(to: source)
        ShellPreferencesMigration.restoreLegacySandboxValues(into: defaults, legacyFileURL: source)
        XCTAssertNil(defaults.object(forKey: ShellPreferencesMigration.markerKey), "Read failures must allow retry")
        XCTAssertEqual(defaults.data(forKey: gardenKey), current)

        let oldBranches = try JSONEncoder().encode([VineBranch(id: "research", count: 9)])
        var activeCopy = completed
        activeCopy.completedAt = nil
        let legacy: [String: Any] = [gardenKey: try JSONEncoder().encode([activeCopy]), branchesKey: oldBranches]
        try PropertyListSerialization.data(fromPropertyList: legacy, format: .xml, options: 0).write(to: source)
        ShellPreferencesMigration.restoreLegacySandboxValues(into: defaults, legacyFileURL: source)
        XCTAssertEqual(defaults.data(forKey: gardenKey), current, "The current completion record wins")
        XCTAssertEqual(defaults.data(forKey: branchesKey), oldBranches)
        XCTAssertTrue(defaults.bool(forKey: ShellPreferencesMigration.markerKey))

        defaults.removeObject(forKey: branchesKey)
        ShellPreferencesMigration.restoreLegacySandboxValues(into: defaults, legacyFileURL: source)
        XCTAssertNil(defaults.object(forKey: branchesKey), "Once migrated, an intentionally removed key must stay removed")
        XCTAssertEqual(defaults.data(forKey: gardenKey), current)
        XCTAssertTrue(DeadlineGarden(defaults: defaults).visibleDeadlines.isEmpty)
        XCTAssertEqual(DeadlineGarden(defaults: defaults).deadlines.first?.completedAt, completed.completedAt)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "FilePetShell.PreferencesMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
