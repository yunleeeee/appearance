import AppKit
import XCTest
@testable import FilePetShell

@MainActor
final class CompactMenuTests: XCTestCase {
    func testTopLevelMenuIsConciseAndFlowerCountOffersExactlyThreeChoices() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let menu = NSMenu()
        delegate.menuNeedsUpdate(menu)
        let labels = menu.items.map(\.title).filter { !$0.isEmpty }
        XCTAssertEqual(labels.filter { $0 == "导入文件…" }.count, 1)
        XCTAssertEqual(labels.filter { $0.hasPrefix("DDL 任务（") }.count, 1)
        XCTAssertEqual(labels.filter { $0.hasPrefix("显示花朵：") }.count, 1)
        XCTAssertTrue(labels.contains("更多操作"))
        XCTAssertTrue(labels.contains("退出 FilePet"))
        XCTAssertLessThanOrEqual(labels.count, 9,
                                  "Main menu should never become a settings checklist")
        XCTAssertFalse(labels.contains { $0.contains("杰瑞") || $0.contains("预览葡萄架") })
        XCTAssertFalse(labels.contains { $0.contains("重新连接分类引擎") })
        XCTAssertFalse(labels.contains { $0.contains("撤销最近一次采摘") })

        let countMenu = try XCTUnwrap(menu.items.first {
            $0.title.hasPrefix("显示花朵：")
        }?.submenu)
        XCTAssertEqual(countMenu.items.map(\.title), ["1 朵", "2 朵", "3 朵"])
        XCTAssertEqual(countMenu.items.filter { $0.state == .on }.count, 1,
                       "Exactly one persistent count preference is selected")
        XCTAssertEqual(countMenu.items.compactMap { $0.representedObject as? Int },
                       [1, 2, 3])
    }

    func testSecondaryActionsRemainAccessibleWithoutTopLevelClutter() throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let menu = NSMenu()
        delegate.menuNeedsUpdate(menu)
        let more = try XCTUnwrap(menu.items.first { $0.title == "更多操作" }?.submenu)
        let titles = more.items.map(\.title)
        XCTAssertTrue(titles.contains("自动识别图片 DDL"))
        XCTAssertTrue(titles.contains("显示葡萄藤"))
        XCTAssertTrue(titles.contains("查看最近结果…"))
        XCTAssertTrue(titles.contains("撤销上次采摘"))
        XCTAssertTrue(titles.contains("重新连接引擎"))
    }
}
