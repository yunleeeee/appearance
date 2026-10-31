import Foundation
import XCTest
@testable import FilePetShell

final class DeadlineStageResolverTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    func testAllStageBoundaryInstants() throws {
        let resolver = DeadlineStageResolver(calendar: utc)
        let due = try XCTUnwrap(utc.date(from: DateComponents(
            year: 2026, month: 11, day: 20, hour: 12)))
        for (seconds, expected) in [
            (7 * 86400 + 1, DeadlineStage.bud),
            (7 * 86400, .swelling), (3 * 86400, .opening),
            (86400, .bloom), (10800, .drooping),
            (0, .withered), (-1, .withered)
        ] {
            XCTAssertEqual(resolver.resolve(dueDate: "2026-11-20", dueTime: "12:00",
                                            now: due.addingTimeInterval(-Double(seconds))),
                           expected, "Boundary \(seconds)s")
        }
    }

    func testDateOnlyNeverUsesFalseThreeHourCountdown() throws {
        let resolver = DeadlineStageResolver(calendar: utc)
        let day = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 11, day: 20)))
        XCTAssertEqual(resolver.resolve(dueDate: "2026-11-20", dueTime: nil,
                                        now: day.addingTimeInterval(23 * 3600 + 59 * 60)), .bloom)
        XCTAssertEqual(resolver.resolve(dueDate: "2026-11-20", dueTime: nil,
                                        now: day.addingTimeInterval(86400)), .withered)
        XCTAssertNil(resolver.resolve(dueDate: "2026-11-20", dueTime: nil,
                                      completedAt: day, now: day))
        XCTAssertNil(resolver.resolve(dueDate: "2026-02-30", dueTime: nil, now: day))
        XCTAssertNil(resolver.resolve(dueDate: "2026-11-20", dueTime: "25:00", now: day))
    }

    func testNextThresholdCanBeScheduledAndCompletedIsIndependent() throws {
        let resolver = DeadlineStageResolver(calendar: utc)
        let now = try XCTUnwrap(utc.date(from: DateComponents(
            year: 2026, month: 11, day: 12, hour: 12)))
        let boundary = try XCTUnwrap(resolver.nextChange(
            dueDate: "2026-11-20", dueTime: "12:00", now: now))
        XCTAssertEqual(boundary.timeIntervalSince(now), 86400, accuracy: 0.001)
    }
}
