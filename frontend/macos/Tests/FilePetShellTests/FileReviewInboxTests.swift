import Foundation
import XCTest
@testable import FilePetShell

@MainActor
final class FileReviewInboxTests: XCTestCase {
    func testPendingCandidatesSurviveRestartAndResolveOneAtATime() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let result = pendingResult(path: "/tmp/review-notice.png", candidates: [candidate("first"), candidate("second")])
        let inbox = FileReviewInbox(defaults: defaults)
        inbox.enqueue(result: result)
        inbox.enqueue(result: result)
        XCTAssertEqual(inbox.items.count, 1, "Refeeding one file must not duplicate its pending review")
        XCTAssertEqual(inbox.items[0].candidates.map(\.id), ["first", "second"])

        let restored = FileReviewInbox(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(restored.items, inbox.items)
        let reviewID = try XCTUnwrap(restored.items.first?.id)
        restored.resolveCandidate(reviewID: reviewID, candidateID: "first")
        XCTAssertEqual(restored.items.count, 1)
        XCTAssertEqual(restored.items[0].candidates.map(\.id), ["second"])
        XCTAssertEqual(FileReviewInbox(defaults: defaults).items, restored.items)
        restored.resolveCandidate(reviewID: reviewID, candidateID: "second")
        XCTAssertTrue(restored.items.isEmpty)
        XCTAssertTrue(FileReviewInbox(defaults: defaults).items.isEmpty)
    }

    func testUnknownFileCanBeRemovedWithoutInventingADate() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let inbox = FileReviewInbox(defaults: defaults)
        inbox.enqueue(result: pendingResult(path: "/tmp/unknown.txt", candidates: []))
        XCTAssertEqual(inbox.items.count, 1)
        XCTAssertTrue(inbox.items[0].candidates.isEmpty)
        XCTAssertEqual(inbox.items[0].fileName, "unknown.txt")
        inbox.remove(id: inbox.items[0].id)
        XCTAssertTrue(inbox.items.isEmpty)
    }

    func testDeadlineInputRejectsInvalidDatesAndTimesButAllowsPastDatesAndNoTime() {
        XCTAssertNil(DeadlineInput.validationError(title: "提交作业", project: "软件工程",
                                                  dueDate: "2026-10-18", dueTime: nil))
        XCTAssertNil(DeadlineInput.validationError(title: "提交作业", project: "软件工程",
                                                  dueDate: "2024-02-29", dueTime: "23:59"))
        for (title, project, date, time) in [
            ("", "软件工程", "2026-11-03", Optional("23:59")),
            ("作业", "", "2026-11-03", Optional("23:59")),
            ("作业", "软件工程", "", Optional("23:59")),
            ("作业", "软件工程", "2026-02-29", Optional("23:59")),
            ("作业", "软件工程", "2026-11-31", Optional("23:59")),
            ("作业", "软件工程", "2026-11-03", Optional("24:00")),
            ("作业", "软件工程", "2026-11-03", Optional("12:60")),
        ] {
            XCTAssertNotNil(DeadlineInput.validationError(title: title, project: project, dueDate: date, dueTime: time),
                            "Invalid entries must not become persisted flowers")
        }
    }

    private func candidate(_ id: String) -> EngineDeadline {
        EngineDeadline(id: id, title: "请提交作业", project: "软件工程", dueDate: "2026-10-18",
                       dueTime: "23:59", yearInferred: false, evidence: "dd|为2026年10月18日23:59", signal: "ocr_deadline")
    }

    private func pendingResult(path: String, candidates: [EngineDeadline]) -> EngineClassificationResult {
        EngineClassificationResult(path: path, fileName: URL(fileURLWithPath: path).lastPathComponent,
            status: "needs_review", categoryID: nil, categoryLabel: nil, confidence: 0.5,
            matchedKeywords: ["作业"], reason: "有效内容线索不足，建议人工指定类别",
            extractionChars: 70, deadlines: candidates)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "FilePetShell.FileReviewInboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
