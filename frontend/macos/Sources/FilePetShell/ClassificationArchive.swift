import CryptoKit
import Foundation

/// Opt-in local move into the user-selected category folder.
/// Never deletes the original before byte-for-byte verification of the copy.
/// A failed copy or verification leaves the original untouched.
@MainActor
final class ClassificationArchive {
    enum Receipt: Equatable {
        case notConfigured
        case moved(String)
        case alreadyStored(String)
    }

    private struct Record: Codable, Sendable {
        let output: String
        let size: UInt64
        let modified: TimeInterval
    }

    private let defaults: UserDefaults
    private let destinationKey = "filepet.shell.archive.destination.v1"
    // Keep existing receipt schema/key compatible with earlier copy-only builds.
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

    func selectDestination(_ url: URL?) {
        defaults.set(url?.standardizedFileURL.resolvingSymlinksInPath().path,
                     forKey: destinationKey)
    }

    func copyClassifiedFile(source: URL, categoryID: String, categoryLabel: String,
                            preferredName: String? = nil) async throws -> Receipt {
        guard let root = destination else { return .notConfigured }
        let normalized = source.standardizedFileURL.resolvingSymlinksInPath()
        let folder = Self.categoryFolder(categoryID: categoryID, label: categoryLabel)
        let key = root.path + "\u{0}" + normalized.path + "\u{0}" + folder
        let old = records[key]
        let result = try await Task.detached(priority: .utility) {
            try Self.moveVerified(source: normalized, root: root, category: folder,
                                  previous: old, preferredName: preferredName)
        }.value
        switch result {
        case .saved(let path, let record):
            records[key] = record
            defaults.set(try JSONEncoder().encode(records), forKey: recordsKey)
            return .moved(path)
        case .unchanged(let path):
            return .alreadyStored(path)
        }
    }

    private enum MoveResult: Sendable {
        case saved(String, Record)
        case unchanged(String)
    }

    private nonisolated static func categoryFolder(categoryID: String, label: String) -> String {
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

    /// Stream hashes so moving large documents does not duplicate them in RAM.
    private nonisolated static func digest(_ url: URL) throws -> SHA256.Digest {
        let stream = try FileHandle(forReadingFrom: url)
        defer { try? stream.close() }
        var hasher = SHA256()
        while true {
            guard let block = try stream.read(upToCount: 1024 * 1024), !block.isEmpty else { break }
            hasher.update(data: block)
        }
        return hasher.finalize()
    }

    private nonisolated static func moveVerified(
        source: URL, root: URL, category: String, previous: Record?,
        preferredName: String?
    ) throws -> MoveResult {
        let fm = FileManager.default
        var rootIsDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &rootIsDirectory),
              rootIsDirectory.boolValue else { throw CocoaError(.fileNoSuchFile) }
        let directory = root.appendingPathComponent(category, isDirectory: true)
        // Prevent following a pre-created category symlink to an unchosen folder.
        if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw CocoaError(.fileWriteNoPermission)
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: source.path) {
            if let previous, fm.fileExists(atPath: previous.output) {
                return .unchanged(previous.output)
            }
            throw CocoaError(.fileNoSuchFile)
        }
        let attrs = try fm.attributesOfItem(atPath: source.path)
        guard (attrs[.type] as? FileAttributeType) == .typeRegular else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        if source.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path {
            return .unchanged(source.path)
        }

        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let sourceDigest = try digest(source)
        if let previous, previous.size == size,
           fm.fileExists(atPath: previous.output),
           try digest(URL(fileURLWithPath: previous.output)) == sourceDigest {
            // An earlier copy-only build may have left an identical original.
            // Remove it only after verifying the already-saved copy.
            try fm.removeItem(at: source)
            return .saved(previous.output, Record(output: previous.output,
                                                   size: size, modified: modified))
        }

        // Meaningful OCR titles can rename generated screenshots, but only
        // when the caller explicitly supplied a verified task title.
        let baseStem = source.deletingPathExtension().lastPathComponent
        let safe = preferredName?.unicodeScalars.map { char -> String in
            CharacterSet.controlCharacters.contains(char) ||
                "/\\:".unicodeScalars.contains(char) ? "_" : String(char)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = String((safe ?? "").prefix(80))
        let stem = chosen.isEmpty || chosen == "." || chosen == ".." ? baseStem : chosen
        let ext = source.pathExtension
        for index in 1...10000 {
            let filename = index == 1 ? source.lastPathComponent :
                stem + " (" + String(index) + ")" + (ext.isEmpty ? "" : "." + ext)
            let target = directory.appendingPathComponent(filename)
            if fm.fileExists(atPath: target.path) { continue }
            let staging = directory.appendingPathComponent(".filepet-stage-" + UUID().uuidString)
            defer { if fm.fileExists(atPath: staging.path) { try? fm.removeItem(at: staging) } }
            try fm.copyItem(at: source, to: staging)
            guard try digest(staging) == sourceDigest else {
                throw CocoaError(.fileReadCorruptFile)
            }
            // The staged copy and destination share the same filesystem.
            // Renaming into place avoids exposing a partial destination.
            try fm.moveItem(at: staging, to: target)
            guard try digest(target) == sourceDigest else {
                try? fm.removeItem(at: target)
                throw CocoaError(.fileReadCorruptFile)
            }
            do {
                try fm.removeItem(at: source)
            } catch {
                // Never destroy the verified destination if the source
                // unexpectedly disappeared during a deletion error.
                if fm.fileExists(atPath: source.path) {
                    try? fm.removeItem(at: target)
                    throw error
                }
            }
            return .saved(target.path, Record(output: target.path,
                                              size: size, modified: modified))
        }
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
