import Foundation

/// Called synchronously on the engine's host thread.
/// Values retain the original Mac app's JSON encoding and keys.
public protocol VineStorage: AnyObject {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
}

public final class MemoryVineStorage: VineStorage {
    public private(set) var values: [String: Data]
    public init(values: [String: Data] = [:]) { self.values = values }
    public func data(forKey key: String) throws -> Data? { values[key] }
    public func set(_ data: Data, forKey key: String) throws { values[key] = data }
}

/// A readable, atomic JSON archive for appearance state.
/// Use one writer per archive; different processes must coordinate externally.
public final class JSONFileVineStorage: VineStorage {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func data(forKey key: String) throws -> Data? {
        guard let value = try readValues()[key] else { return nil }
        return try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
    }

    public func set(_ data: Data, forKey key: String) throws {
        var values = try readValues()
        values[key] = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let encoded = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoded.write(to: fileURL, options: .atomic)
    }

    private func readValues() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        guard let values = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return values
    }
}
