import Foundation

/// A deadline's visual stage is derived from its due time and explicit completion,
/// never from time since feeding or from elapsed animation frames.
enum DeadlineStage: Int, CaseIterable, Sendable {
    case bud, swelling, opening, bloom, drooping, withered

    var label: String {
        switch self {
        case .bud: "含苞"
        case .swelling: "待放"
        case .opening: "初绽"
        case .bloom: "盛放"
        case .drooping: "萎垂"
        case .withered: "凋零"
        }
    }
}

struct DeadlineStageResolver: Sendable {
    struct Thresholds: Sendable {
        var bud: TimeInterval = 7 * 86_400
        var swelling: TimeInterval = 3 * 86_400
        var opening: TimeInterval = 24 * 3_600
        var bloom: TimeInterval = 3 * 3_600
    }

    let thresholds: Thresholds
    let calendar: Calendar

    init(thresholds: Thresholds = Thresholds(), calendar: Calendar = .current) {
        self.thresholds = thresholds
        self.calendar = calendar
    }

    /// nil means completed or invalid data. Date-only deadlines use calendar
    /// days: they never invent 23:59 or enter a false <3h urgency state.
    func resolve(dueDate: String, dueTime: String?, completedAt: Date? = nil,
                 now: Date) -> DeadlineStage? {
        guard completedAt == nil, let day = parsedDay(dueDate) else { return nil }
        guard let time = dueTime, !time.isEmpty else {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                              to: day).day ?? 0
            if days < 0 { return .withered }
            if days == 0 { return .bloom }
            if days <= 3 { return .opening }
            if days <= 7 { return .swelling }
            return .bud
        }
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), let hour = Int(parts[0]),
              let minute = Int(parts[1]), (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        let second = parts.count == 3 ? Int(parts[2]) : 0
        guard let second, (0...59).contains(second),
              let due = calendar.date(bySettingHour: hour, minute: minute,
                                      second: second, of: day) else { return nil }
        let remaining = due.timeIntervalSince(now)
        if remaining <= 0 { return .withered }
        if remaining <= thresholds.bloom { return .drooping }
        if remaining <= thresholds.opening { return .bloom }
        if remaining <= thresholds.swelling { return .opening }
        if remaining <= thresholds.bud { return .swelling }
        return .bud
    }

    func parsedDay(_ value: String) -> Date? {
        let p = value.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2,
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]),
              let day = calendar.date(from: DateComponents(year: y, month: m, day: d)) else {
            return nil
        }
        let readback = calendar.dateComponents([.year, .month, .day], from: day)
        guard readback.year == y && readback.month == m && readback.day == d else { return nil }
        return calendar.startOfDay(for: day)
    }

    /// Small next-boundary hint permits sleeping until the next threshold rather
    /// than redrawing all flowers at a fixed animation cadence.
    func nextChange(dueDate: String, dueTime: String?, now: Date) -> Date? {
        guard let day = parsedDay(dueDate) else { return nil }
        if let time = dueTime {
            let p = time.split(separator: ":")
            guard p.count >= 2, let hour = Int(p[0]), let minute = Int(p[1]),
                  let second = p.count > 2 ? Int(p[2]) : 0,
                  let due = calendar.date(bySettingHour: hour, minute: minute,
                                          second: second, of: day) else { return nil }
            return [thresholds.bud, thresholds.swelling, thresholds.opening,
                    thresholds.bloom, 0].map { due.addingTimeInterval(-$0) }
                   .first { $0 > now }
        }
        return calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                 matchingPolicy: .nextTime)
    }
}
