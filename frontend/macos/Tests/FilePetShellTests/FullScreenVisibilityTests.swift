import AppKit
import XCTest
@testable import FilePetShell

@MainActor
final class FullScreenVisibilityTests: XCTestCase {
    func testPresentationChangesHideAndRestoreWithoutRepeatedCallbacks() {
        _ = NSApplication.shared
        var fullScreen = false
        var changes: [Bool] = []
        let monitor = FullScreenVisibilityMonitor(
            isFullScreen: { fullScreen }, workspaceNotifications: NotificationCenter(),
            applicationNotifications: NotificationCenter(), onChange: { changes.append($0) })
        defer { monitor.stop() }
        XCTAssertEqual(changes, [false])
        fullScreen = true
        monitor.refresh()
        monitor.refresh()
        XCTAssertEqual(changes, [false, true])
        fullScreen = false
        monitor.refresh()
        XCTAssertEqual(changes, [false, true, false])
        monitor.stop()
        fullScreen = true
        monitor.refresh()
        XCTAssertEqual(changes, [false, true, false])
    }

    func testFullScreenSuppressesExistingAndNewFlowersAndRestoresSamePanels() throws {
        _ = NSApplication.shared
        let suite = "FilePetShell.FullScreenVisibility.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let garden = DeadlineGarden(defaults: defaults)
        garden.feed([candidate("first", date: "2099-11-08")])
        let controller = DeadlineFlowerController(garden: garden,
            screenFrame: { NSRect(x: 0, y: 0, width: 1440, height: 900) }, onFiles: { _ in })
        defer { controller.stop() }
        let firstPanel = try XCTUnwrap(controller.panelIdentities["first"])
        XCTAssertEqual(controller.visiblePanelIDs, ["first"])

        controller.setFullScreenSuppressed(true)
        XCTAssertTrue(controller.visiblePanelIDs.isEmpty)
        garden.feed([candidate("second", date: "2099-11-09")])
        garden.setVisibleLimit(2)
        controller.refreshFromGarden()
        let hiddenPanels = controller.panelIdentities
        XCTAssertEqual(hiddenPanels.count, 2)
        XCTAssertTrue(controller.visiblePanelIDs.isEmpty,
                      "A task received during full screen must stay hidden")

        controller.setFullScreenSuppressed(false)
        XCTAssertEqual(controller.visiblePanelIDs, ["first", "second"])
        XCTAssertEqual(controller.panelIdentities, hiddenPanels)
        XCTAssertEqual(controller.panelIdentities["first"], firstPanel)
        XCTAssertEqual(garden.activeDeadlines.count, 2)
        XCTAssertEqual(garden.visibleLimit, 2)

        controller.setVisible(false)
        controller.setFullScreenSuppressed(true)
        controller.setFullScreenSuppressed(false)
        XCTAssertTrue(controller.visiblePanelIDs.isEmpty,
                      "Leaving full screen must respect the user's hidden state")
        controller.setVisible(true)
        XCTAssertEqual(controller.visiblePanelIDs, ["first", "second"])
        XCTAssertEqual(controller.panelIdentities, hiddenPanels)
    }

    private func candidate(_ id: String, date: String) -> EngineDeadline {
        EngineDeadline(id: id, title: id, project: "课程", dueDate: date,
                       dueTime: "23:59", yearInferred: false, evidence: "测试任务")
    }
}
