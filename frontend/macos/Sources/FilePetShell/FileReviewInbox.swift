import Combine
import CryptoKit
import Foundation

struct PendingFileReview: Identifiable, Codable, Equatable {
    let id: String
    let path: String
    let fileName: String
    let reason: String
    var candidates: [EngineDeadline]
    let createdAt: Date
}

@MainActor
final class FileReviewInbox: ObservableObject {
    @Published private(set) var items: [PendingFileReview] = []
    @Published private(set) var persistenceError: String?
    private let defaults: UserDefaults
    private let key = "filepet.shell.reviewInbox.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key) else { return }
        do { items = try JSONDecoder().decode([PendingFileReview].self, from: data) }
        catch { persistenceError = "读取待确认事项失败：\(error.localizedDescription)" }
    }

    func enqueue(result: EngineClassificationResult, candidates: [EngineDeadline]? = nil) {
        let path = URL(fileURLWithPath: result.path).standardizedFileURL.path
        let previous = items.first { $0.id == path }
        let proposed = candidates ?? result.deadlines
        let reason = proposed.contains(where: \.requiresConfirmation)
            ? "图片中的截止日期需要核对，请确认内容、时间和项目。" : result.reason
        let review = PendingFileReview(id: path, path: path, fileName: result.fileName,
            reason: reason, candidates: proposed,
            createdAt: previous?.createdAt ?? Date())
        var updated = items
        if let index = updated.firstIndex(where: { $0.id == path }) { updated[index] = review }
        else { updated.append(review) }
        save(updated)
    }

    func remove(id: String) { save(items.filter { $0.id != id }) }

    func resolveCandidate(reviewID: String, candidateID: String?) {
        guard let index = items.firstIndex(where: { $0.id == reviewID }) else { return }
        guard let candidateID else { remove(id: reviewID); return }
        var updated = items
        updated[index].candidates.removeAll { $0.id == candidateID }
        if updated[index].candidates.isEmpty { updated.remove(at: index) }
        save(updated)
    }

    private func save(_ updated: [PendingFileReview]) {
        do {
            defaults.set(try JSONEncoder().encode(updated), forKey: key)
            items = updated
            persistenceError = nil
        } catch { persistenceError = "保存待确认事项失败：\(error.localizedDescription)" }
    }
}

enum DeadlineInput {
    static func validationError(title: String, project: String, dueDate: String, dueTime: String?) -> String? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "请填写主要内容。" }
        guard !project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "请填写项目。" }
        guard dueDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return "请按 YYYY-MM-DD 填写截止日期，例如 2026-11-03。"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: dueDate), formatter.string(from: date) == dueDate else {
            return "截止日期无效，请核对月份和日期。"
        }
        if let time = dueTime?.trimmingCharacters(in: .whitespacesAndNewlines), !time.isEmpty,
           time.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) == nil {
            return "请按 HH:mm 填写截止时间，例如 23:59；也可以留空。"
        }
        return nil
    }

    static func manualID(path: String, title: String, dueDate: String, dueTime: String?) -> String {
        let value = [path, title, dueDate, dueTime ?? ""].joined(separator: "\u{0}")
        return "manual-" + SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
