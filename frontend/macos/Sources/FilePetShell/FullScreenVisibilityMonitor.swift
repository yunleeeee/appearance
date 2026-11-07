import AppKit
import OSLog

/// Follow the active application's native full-screen presentation without
/// reading other applications' windows or requesting accessibility permissions.
@MainActor
final class FullScreenVisibilityMonitor {
    private let isFullScreen: @MainActor () -> Bool
    private let onChange: (Bool) -> Void
    private let logger = Logger(subsystem: "com.filepet.GrapeShell", category: "presentation")
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var presentationObservation: NSKeyValueObservation?
    private var transitionChecks: [DispatchWorkItem] = []
    private var lastValue: Bool?
    private var stopped = false

    init(isFullScreen: @escaping @MainActor () -> Bool = {
        NSApp.currentSystemPresentationOptions.contains(.fullScreen)
    }, workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         applicationNotifications: NotificationCenter = .default,
         onChange: @escaping (Bool) -> Void) {
        self.isFullScreen = isFullScreen
        self.onChange = onChange
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            observers.append((workspaceNotifications, workspaceNotifications.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.presentationChanged() } }))
        }
        let name = NSApplication.didChangeScreenParametersNotification
        observers.append((applicationNotifications, applicationNotifications.addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.presentationChanged() } }))
        presentationObservation = NSApplication.shared.observe(
            \.currentSystemPresentationOptions, options: [.new]
        ) { [weak self] _, _ in
            DispatchQueue.main.async { self?.presentationChanged() }
        }
        presentationChanged()
    }

    func refresh() {
        guard !stopped else { return }
        let value = isFullScreen()
        guard lastValue != value else { return }
        lastValue = value
        logger.notice("Full-screen desktop suppression: \(value, privacy: .public)")
        onChange(value)
    }

    private func presentationChanged() {
        guard !stopped else { return }
        transitionChecks.forEach { $0.cancel() }
        refresh()
        // Space notifications can precede the end of the full-screen animation.
        // Recheck only around transitions; there is no continuous polling timer.
        transitionChecks = [0.25, 0.8].map { delay in
            let check = DispatchWorkItem { [weak self] in self?.refresh() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: check)
            return check
        }
    }

    func stop() {
        stopped = true
        presentationObservation?.invalidate()
        presentationObservation = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        transitionChecks.forEach { $0.cancel() }
        transitionChecks.removeAll()
    }
}
