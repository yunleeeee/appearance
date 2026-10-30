import Foundation

/// Original PNG frames and attribution files owned by the Mac appearance.
public enum CharacterAssets {
    private static let resourceBundle: Bundle = {
        // The Mac app installer puts SwiftPM resources in Contents/Resources.
        // Prefer that copy so the installed app never depends on a development path.
        if let url = Bundle.main.url(forResource: "FilePetShell_FilePetShell", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()

    public static var charactersDirectoryURL: URL? {
        resourceBundle.url(forResource: "Characters", withExtension: nil)
    }

    /// Pass the full file name, e.g. "TomWatch.png" or "frame_0000.png" in "JerryRun".
    public static func url(for fileName: String, subdirectory: String? = nil) -> URL? {
        let directory = subdirectory.map { "Characters/\($0)" } ?? "Characters"
        return resourceBundle.url(forResource: fileName, withExtension: nil, subdirectory: directory)
    }
}
