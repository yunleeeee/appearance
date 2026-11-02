import AppKit
import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class DeadlinePanelLifecycleTests: XCTestCase {
    func testExistingDeadlinePanelsSurviveFeedAndStageRefresh() {
        _ = NSApplication.shared
        let suite = "FilePetShell.PanelIdentity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = ISO8601DateFormatter().date(from: "2026-10-31T12:00:00Z")!
        let garden = DeadlineGarden(defaults: defaults, now: now)
        garden.feed([candidate("first", "2026-11-10"),
                     candidate("second", "2026-11-08")], now: now)
        let controller = DeadlineFlowerController(garden: garden,
            screenFrame: { NSRect(x: 0, y: 0, width: 1440, height: 900) },
            onFiles: { _ in })
        defer { controller.stop() }
        let initial = controller.panelIdentities
        XCTAssertEqual(initial.count, 1)
        XCTAssertNotNil(initial["second"], "Earlier due task occupies the single window")

        garden.refreshTime(now: now)
        controller.refreshFromGarden()
        XCTAssertEqual(controller.panelIdentities["second"], initial["second"],
                       "Stage refresh must reuse the same panel")

        garden.feed([candidate("urgent", "2026-11-01")], now: now)
        controller.refreshFromGarden()
        let urgent = controller.panelIdentities["urgent"]
        XCTAssertNotNil(urgent)
        XCTAssertEqual(controller.panelIdentities.count, 1)
        XCTAssertNil(controller.panelIdentities["second"])

        garden.refreshTime(now: now.addingTimeInterval(86_400))
        controller.refreshFromGarden()
        XCTAssertEqual(controller.panelIdentities["urgent"], urgent)
        XCTAssertEqual(controller.panelIdentities.count, 1)

        garden.harvest(id: "urgent", now: now.addingTimeInterval(86_400))
        controller.refreshFromGarden()
        XCTAssertNil(controller.panelIdentities["urgent"])
        XCTAssertNotNil(controller.panelIdentities["second"])
        XCTAssertEqual(controller.panelIdentities.count, 1)
    }

    private func candidate(_ id: String, _ due: String) -> EngineDeadline {
        EngineDeadline(id: id, title: id, project: "课程", dueDate: due,
                       dueTime: "23:59", yearInferred: false, evidence: "ddl " + due)
    }
}
