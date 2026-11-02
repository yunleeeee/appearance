import Combine
import CryptoKit
import Foundation

struct PendingFileReview: Identifiable, Codable, Equatable {
    let id: String
    var path: String
    let fileName: String
    let reason: String
    var candidates: [EngineDeadline]
    let createdAt: Date
    var needsCategoryReview: Bool? = nil
    var contentFingerprint: String? = nil
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

    var pendingSemanticKeys: Set<String> {
        Set(items.flatMap { $0.candidates.compactMap(\.semanticKey) })
    }

    func enqueue(result: EngineClassificationResult, candidates: [EngineDeadline]? = nil, needsCategoryReview: Bool? = nil) {
        let path = URL(fileURLWithPath: result.path).standardizedFileURL.path
        let previous = items.first { $0.id == path }
        let incoming = candidates ?? result.deadlines
        // Refeeding the same source must never erase earlier unresolved OCR
        // candidates when another DDL becomes recognizable on a later pass.
        var known = Set<String>()
        let proposed = ((previous?.candidates ?? []) + incoming).filter { candidate in
            let key = candidate.semanticKey ?? candidate.id
            return known.insert(key).inserted
        }
        let reason = proposed.contains(where: \.requiresConfirmation)
            ? "图片中的截止日期需要核对，请确认内容、时间和项目。" : result.reason
        let review = PendingFileReview(id: path, path: path, fileName: result.fileName,
            reason: reason, candidates: proposed,
            createdAt: previous?.createdAt ?? Date(),
            needsCategoryReview: needsCategoryReview ?? (result.status != "classified"),
            contentFingerprint: result.contentFingerprint ?? previous?.contentFingerprint)
        var updated = items
        if let index = updated.firstIndex(where: { $0.id == path }) { updated[index] = review }
        else { updated.append(review) }
        save(updated)
    }

    /// Remove an older OCR review when the same semantic task has now been
    /// accepted automatically. Keep unrelated candidates and category reviews.
    /// Never discards the original image or any stored completed garden item.
    func removeAutomaticallyAccepted(_ accepted: [EngineDeadline]) {
        guard !accepted.isEmpty else { return }
        let ids = Set(accepted.map(\.id))
        let keys = Set(accepted.compactMap(\.semanticKey))
        var changed = false
        let updated = items.compactMap { review -> PendingFileReview? in
            var next = review
            let count = next.candidates.count
            next.candidates.removeAll { candidate in
                ids.contains(candidate.id) ||
                    (candidate.semanticKey.map { keys.contains($0) } ?? false)
            }
            if next.candidates.count != count { changed = true }
            if next.candidates.isEmpty && next.needsCategoryReview != true {
                changed = true
                return nil
            }
            return next
        }
        if changed { save(updated) }
    }

    /// Keep pending candidates and their Open Source actions valid when
    /// their image was safely moved after classification.
    func relinkSource(from oldPath: String, to newPath: String) {
        guard oldPath != newPath else { return }
        var updated = items
        var changed = false
        for index in updated.indices where updated[index].path == oldPath {
            updated[index].path = newPath
            for candidateIndex in updated[index].candidates.indices {
                if updated[index].candidates[candidateIndex].sourcePath == oldPath {
                    updated[index].candidates[candidateIndex].sourcePath = newPath
                }
            }
            changed = true
        }
        if changed { save(updated) }
    }

    func remove(id: String) { save(items.filter { $0.id != id }) }

    func resolveCandidate(reviewID: String, candidateID: String?) {
        guard let index = items.firstIndex(where: { $0.id == reviewID }) else { return }
        guard let candidateID else {
            if items[index].needsCategoryReview != true { remove(id: reviewID) }
            return
        }
        var updated = items
        updated[index].candidates.removeAll { $0.id == candidateID }
        if updated[index].candidates.isEmpty && updated[index].needsCategoryReview != true {
            updated.remove(at: index)
        }
        save(updated)
    }

    func resolveCategory(reviewID: String) {
        guard let index = items.firstIndex(where: { $0.id == reviewID }) else { return }
        var updated = items
        updated[index].needsCategoryReview = false
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
