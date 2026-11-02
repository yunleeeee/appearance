import XCTest
@testable import FilePetShell

final class FileDisplayNameTests: XCTestCase {
    func testGeneratedNamesAreHiddenButOriginalPathsStillAvailable() {
        XCTAssertEqual(FileDisplayName.label("已粘贴 2026-11-01 下午8.14.18.png"), "截图")
        XCTAssertEqual(FileDisplayName.label("屏幕快照 2026-11-01 下午8.14.18.png"), "截图")
        XCTAssertEqual(FileDisplayName.label("Screenshot 2026-11-01 at 8.14.18 PM.png"), "截图")
        XCTAssertEqual(FileDisplayName.label("IMG_20261101_201418.jpg"), "图片")
        XCTAssertEqual(FileDisplayName.label("screen.png"), "图片")
        XCTAssertEqual(FileDisplayName.label("image.jpg"), "图片")
    }

    func testMeaningfulNamesRemainVisible() {
        XCTAssertEqual(FileDisplayName.label("软件工程实验报告.png"), "软件工程实验报告.png")
        XCTAssertEqual(FileDisplayName.label("第四章.docx"), "第四章.docx")
        XCTAssertEqual(FileDisplayName.label("截图-2026-11-01 软件工程作业.png"),
                       "截图-2026-11-01 软件工程作业.png")
    }
}
