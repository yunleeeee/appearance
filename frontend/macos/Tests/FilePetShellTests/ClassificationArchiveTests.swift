import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class ClassificationArchiveTests: XCTestCase {
    func testVerifiedMoveKeepsOnlyDestinationAndPreservesOtherFiles() async throws {
        let (root, archive, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("source", isDirectory: true)
        let output = root.appendingPathComponent("organized", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let file = input.appendingPathComponent("report.txt")
        let original = Data("untouched".utf8)
        try original.write(to: file)
        XCTAssertEqual(archive.destination, nil)
        let unconfigured = try await archive.copyClassifiedFile(
            source: file, categoryID: "learning", categoryLabel: "课程与学习")
        XCTAssertEqual(unconfigured, .notConfigured)

        archive.selectDestination(output)
        let first = try await archive.copyClassifiedFile(
            source: file, categoryID: "learning", categoryLabel: "课程与学习")
        guard case .moved(let firstPath) = first else { return XCTFail("Expected a verified move") }
        XCTAssertEqual(URL(fileURLWithPath: firstPath).deletingLastPathComponent().lastPathComponent, "课程与学习")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: firstPath)), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Original must disappear after verified move")

        let duplicate = try await archive.copyClassifiedFile(
            source: file, categoryID: "learning", categoryLabel: "课程与学习")
        XCTAssertEqual(duplicate, .alreadyStored(firstPath))

        // Re-importing identical bytes from the original location must still
        // leave only the single verified archived image, even with a new mtime.
        try original.write(to: file)
        let sameBytes = try await archive.copyClassifiedFile(
            source: file, categoryID: "learning", categoryLabel: "课程与学习")
        XCTAssertEqual(sameBytes, .moved(firstPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: output.appendingPathComponent("课程与学习/report (2).txt").path))

        // An identical screenshot copied from another source folder is one
        // logical image; retain one verified destination file, not " (2)".
        let twinFolder = root.appendingPathComponent("twin")
        try FileManager.default.createDirectory(at: twinFolder, withIntermediateDirectories: true)
        let twin = twinFolder.appendingPathComponent("report.txt")
        try original.write(to: twin)
        let identical = try await archive.copyClassifiedFile(
            source: twin, categoryID: "learning", categoryLabel: "课程与学习")
        XCTAssertEqual(identical, .moved(firstPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: twin.path))

        // Another physical file with the same name but distinct bytes
        // must not overwrite it.
        let other = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let colliding = other.appendingPathComponent("report.txt")
        try Data("independent".utf8).write(to: colliding)
        let second = try await archive.copyClassifiedFile(
            source: colliding, categoryID: "learning", categoryLabel: "课程与学习")
        guard case .moved(let secondPath) = second else { return XCTFail("Expected collision-safe move") }
        XCTAssertNotEqual(firstPath, secondPath)
        XCTAssertTrue(secondPath.hasSuffix("report (2).txt"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: firstPath)), original)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: secondPath)), Data("independent".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: colliding.path))

        // A new ShellStore uses the persisted destination and copy receipts.
        let restored = ClassificationArchive(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.destination, output.standardizedFileURL)
        let persistedCopy = try await restored.copyClassifiedFile(
            source: file, categoryID: "learning", categoryLabel: "课程与学习")
        XCTAssertEqual(persistedCopy, .alreadyStored(firstPath))
    }

    func testInvalidCategoryCannotEscapeDestinationAndDisableStopsCopying() async throws {
        let (root, archive, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("draft.png")
        try Data([0, 1, 2]).write(to: source)
        let destination = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        archive.selectDestination(destination)
        let receipt = try await archive.copyClassifiedFile(
            source: source, categoryID: "../escape", categoryLabel: "../private")
        guard case .moved(let path) = receipt else { return XCTFail("Expected safe filename") }
        XCTAssertTrue(path.hasPrefix(destination.path + "/"))
        XCTAssertFalse(path.contains("/../"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        archive.selectDestination(nil)
        XCTAssertNil(archive.destination)
        let disabled = try await archive.copyClassifiedFile(
            source: source, categoryID: "learning", categoryLabel: "学习")
        XCTAssertEqual(disabled, .notConfigured)
    }

    func testGeneratedScreenshotUsesMeaningfulAssignmentNameAndRemovesOriginal() async throws {
        let (root, archive, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("已粘贴 2026-11-02 下午7.12.01.png")
        let image = Data([137, 80, 78, 71, 0, 1, 2, 3])
        try image.write(to: original)
        let destination = root.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        archive.selectDestination(destination)
        let result = try await archive.copyClassifiedFile(
            source: original, categoryID: "learning", categoryLabel: "课程与学习",
            preferredName: "计算机网络 · 第四章作业")
        let newPath = destination.appendingPathComponent(
            "课程与学习/计算机网络 · 第四章作业.png")
        XCTAssertEqual(result, .moved(newPath.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(try Data(contentsOf: newPath), image)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(
            atPath: newPath.deletingLastPathComponent().path).count, 1)
    }

    func testSymlinkSourceNeverDeletesItsTarget() async throws {
        let (root, archive, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("protected-original.png")
        let data = Data([5, 6, 7, 8])
        try data.write(to: original)
        let shortcut = root.appendingPathComponent("shortcut.png")
        try FileManager.default.createSymbolicLink(at: shortcut, withDestinationURL: original)
        let output = root.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        archive.selectDestination(output)
        do {
            _ = try await archive.copyClassifiedFile(
                source: shortcut, categoryID: "learning", categoryLabel: "学习")
            XCTFail("A symlink must not trigger removal of the pointed-to file")
        } catch {
            XCTAssertEqual(try Data(contentsOf: original), data)
            XCTAssertTrue(FileManager.default.fileExists(atPath: shortcut.path))
        }
    }

    func testUnwritableOrMissingTargetDoesNotDeleteOriginal() async throws {
        let (root, archive, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("cannot-move.png")
        let contents = Data([12, 34, 56])
        try contents.write(to: original)
        archive.selectDestination(root.appendingPathComponent("does-not-exist"))
        do {
            _ = try await archive.copyClassifiedFile(
                source: original, categoryID: "learning", categoryLabel: "学习")
            XCTFail("Invalid destination must not be silently created")
        } catch {
            XCTAssertEqual(try Data(contentsOf: original), contents)
        }
    }

    func testAlreadyCategorizedFileIsNotRecopied() async throws {
        let (root, archive, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let subfolder = root.appendingPathComponent("学习")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let source = subfolder.appendingPathComponent("original.pdf")
        try Data("sample".utf8).write(to: source)
        archive.selectDestination(root)
        let preSorted = try await archive.copyClassifiedFile(
            source: source, categoryID: "learning", categoryLabel: "学习")
        XCTAssertEqual(preSorted, .alreadyStored(source.path))
    }

    private func fixture() throws -> (URL, ClassificationArchive, UserDefaults, String) {
        let name = "FilePetShell.ClassificationArchiveTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, ClassificationArchive(defaults: defaults), defaults, name)
    }
}
