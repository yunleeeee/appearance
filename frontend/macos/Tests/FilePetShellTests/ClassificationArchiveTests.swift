import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class ClassificationArchiveTests: XCTestCase {
    func testUserChosenDestinationCopiesFileWithoutTouchingOriginalOrReplacingExistingFile() async throws {
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
        XCTAssertEqual(try await archive.copyClassifiedFile(
            source: file, categoryID: "learning", categoryLabel: "课程与学习"), .notConfigured)

        archive.selectDestination(output)
        let first = try await archive.copyClassifiedFile(
            source: file, categoryID: "learning", categoryLabel: "课程与学习")
        guard case .copied(let firstPath) = first else { return XCTFail("Expected a new copy") }
        XCTAssertEqual(URL(fileURLWithPath: firstPath).deletingLastPathComponent().lastPathComponent, "课程与学习")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: firstPath)), original)
        XCTAssertEqual(try Data(contentsOf: file), original)

        XCTAssertEqual(try await archive.copyClassifiedFile(
            source: file, categoryID: "learning", categoryLabel: "课程与学习"),
            .alreadyCopied(firstPath))

        // Another physical file with the same name must not overwrite it.
        let other = root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let colliding = other.appendingPathComponent("report.txt")
        try Data("independent".utf8).write(to: colliding)
        let second = try await archive.copyClassifiedFile(
            source: colliding, categoryID: "learning", categoryLabel: "课程与学习")
        guard case .copied(let secondPath) = second else { return XCTFail("Expected collision-safe copy") }
        XCTAssertNotEqual(firstPath, secondPath)
        XCTAssertTrue(secondPath.hasSuffix("report (2).txt"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: firstPath)), original)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: secondPath)), Data("independent".utf8))

        // A new ShellStore uses the persisted destination and copy receipts.
        let restored = ClassificationArchive(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.destination, output.standardizedFileURL)
        XCTAssertEqual(try await restored.copyClassifiedFile(
            source: file, categoryID: "learning", categoryLabel: "课程与学习"),
            .alreadyCopied(firstPath))
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
        guard case .copied(let path) = receipt else { return XCTFail("Expected safe filename") }
        XCTAssertTrue(path.hasPrefix(destination.path + "/"))
        XCTAssertFalse(path.contains("/../"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        archive.selectDestination(nil)
        XCTAssertNil(archive.destination)
        XCTAssertEqual(try await archive.copyClassifiedFile(
            source: source, categoryID: "learning", categoryLabel: "学习"), .notConfigured)
    }

    func testAlreadyCategorizedFileIsNotRecopied() async throws {
        let (root, archive, defaults, suite) = try fixture()
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let subfolder = root.appendingPathComponent("学习")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        let source = subfolder.appendingPathComponent("original.pdf")
        try Data("sample".utf8).write(to: source)
        archive.selectDestination(root)
        XCTAssertEqual(try await archive.copyClassifiedFile(
            source: source, categoryID: "learning", categoryLabel: "学习"),
            .alreadyCopied(source.path))
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
