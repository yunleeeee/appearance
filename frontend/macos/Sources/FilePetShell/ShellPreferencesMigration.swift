import Foundation

/// Preserve the prior sandboxed App's garden and grape records when this local
/// build starts managing the external Python core without App Sandbox.
enum ShellPreferencesMigration {
    static let markerKey = "filepet.shell.migration.legacySandbox.v1"

    static func restoreLegacySandboxValues(into defaults: UserDefaults, legacyFileURL: URL? = nil) {
        guard defaults.object(forKey: markerKey) == nil else { return }
        let source = legacyFileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.filepet.GrapeShell/Data/Library/Preferences/com.filepet.GrapeShell.plist")
        do {
            let data = try Data(contentsOf: source)
            guard let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any] else { return }
            for (key, value) in values where key.hasPrefix("filepet.shell.") {
                // Current records win, including completed DDLs and deliberately
                // empty values. Never replace them with an older sandbox copy.
                if defaults.object(forKey: key) == nil { defaults.set(value, forKey: key) }
            }
            defaults.set(true, forKey: markerKey)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
               [CocoaError.Code.fileNoSuchFile.rawValue,
                CocoaError.Code.fileReadNoSuchFile.rawValue].contains(failure.code) {
                defaults.set(true, forKey: markerKey)
            }
            // An unreadable or malformed source remains untouched and unmarked,
            // so the next App launch can retry after the underlying issue clears.
        }
    }
}
