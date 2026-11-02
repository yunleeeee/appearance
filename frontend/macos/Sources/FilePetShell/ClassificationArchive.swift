import Foundation

/// Opt-in, local-only copy of classified files to a user-chosen directory.
/// Originals are never renamed, moved, modified or removed. No network access.
@MainActor
final class ClassificationArchive {
    enum Receipt: Equatable {
        case notConfigured
        case copied(String)
        case alreadyCopied(String)
    }

    private struct Record: Codable, Sendable {
        let output: String
        let size: UInt64
        let modified: TimeInterval
    }

    private let defaults: UserDefaults
    private let destinationKey = "filepet.shell.archive.destination.v1"
    private let recordsKey = "filepet.shell.archive.records.v1"
    private var records: [String: Record]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        records = (defaults.data(forKey: recordsKey))
            .flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
    }

    var destination: URL? {
        guard let raw = defaults.string(forKey: destinationKey), !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true)
    }

    /// Call only after the user explicitly chooses a folder in NSOpenPanel.
    func selectDestination(_ url: URL?) {
        defaults.set(url?.standardizedFileURL.resolvingSymlinksInPath().path,
                     forKey: destinationKey)
    }

    func copyClassifiedFile(source: URL, categoryID: String, categoryLabel: String) async throws -> Receipt {
        guard let root = destination else { return .notConfigured }
        let normalized = source.standardizedFileURL.resolvingSymlinksInPath()
        let folder = Self.categoryFolder(categoryID: categoryID, label: categoryLabel)
        let key = root.path + "\u{0}" + normalized.path + "\u{0}" + folder
        let old = records[key]
        let result = try await Task.detached(priority: .utility) {
            try Self.copy(source: normalized, root: root, category: folder, previous: old)
        }.value
        switch result {
        case .saved(let path, let record):
            records[key] = record
            defaults.set(try JSONEncoder().encode(records), forKey: recordsKey)
            return .copied(path)
        case .unchanged(let path):
            return .alreadyCopied(path)
        }
    }

    private enum CopyResult: Sendable {
        case saved(String, Record)
        case unchanged(String)
    }

    private nonisolated static func categoryFolder(categoryID: String, label: String) -> String {
        // Category label comes from the engine, never trust it as a path.
        let requested = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = categoryID.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = requested.isEmpty ? fallback : requested
        let cleaned = text.unicodeScalars.map { scalar -> String in
            if CharacterSet.controlCharacters.contains(scalar) ||
                "/\\:".unicodeScalars.contains(scalar) { return "_" }
            return String(scalar)
        }.joined()
        let limited = String(cleaned.prefix(64)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty || limited == "." || limited == ".." ? "未分类" : limited
    }

    private nonisolated static func copy(source: URL, root: URL, category: String,
                                         previous: Record?) throws -> CopyResult {
        let fm = FileManager.default
        var rootIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &rootIsDirectory),
              rootIsDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        let attrs = try fm.attributesOfItem(atPath: source.path)
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        if let previous, previous.size == size, previous.modified == modified,
           fm.fileExists(atPath: previous.output) {
            return .unchanged(previous.output)
        }
        let directory = root.appendingPathComponent(category, isDirectory: true)
        if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw CocoaError(.fileWriteNoPermission)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if source.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path {
            // An already-sorted file must not be copied onto itself.
            return .unchanged(source.path)
        }
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        for index in 1...10000 {
            let filename = index == 1 ? source.lastPathComponent :
                stem + " (" + String(index) + ")" + (ext.isEmpty ? "" : "." + ext)
            let target = directory.appendingPathComponent(filename)
            if fm.fileExists(atPath: target.path) { continue }
            // copyItem fails rather than replacing an existing target; the
            // source is never touched, including when a copy fails.
            try fm.copyItem(at: source, to: target)
            return .saved(target.path, Record(output: target.path,
                                             size: size, modified: modified))
        }
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
