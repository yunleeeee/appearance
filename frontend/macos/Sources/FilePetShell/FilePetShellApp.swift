import AppKit

/// A menu-bar host for the reusable animation views. No empty Settings window.
@main
@MainActor
struct FilePetShellApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
