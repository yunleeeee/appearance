import AppKit
import SwiftUI

/// 全屏剧情层永远不参与鼠标命中，也不注册任何拖放目标。
private final class TheftPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct LiveTheftScene: View {
    let event: VineTheft
    let origin: CGPoint
    let grapeVisualScale: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Sample source frame boundaries at display rate; the sprite itself
        // remains at the GIF's original 40 ms exposure per frame.
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 12 : 1.0 / 60)) { timeline in
            TheftScene(category: event.category, origin: origin,
                       elapsed: timeline.date.timeIntervalSince(event.startedAt),
                       reducedMotion: reduceMotion, grapeVisualScale: grapeVisualScale)
        }
    }
}

@MainActor
final class TheftOverlayController {
    private let model: VineModel
    private var panel: NSPanel?
    private var completionTimer: Timer?
    private var eventID: UUID?

    init(model: VineModel) { self.model = model }

    func present(_ event: VineTheft?, attachedTo vinePanel: NSPanel) {
        guard let event else {
            dismiss()
            return
        }
        guard eventID != event.id else { return }
        dismiss()
        guard let screen = vinePanel.screen ?? NSScreen.screens.first else {
            model.completeTheft(id: event.id)
            return
        }
        let area = screen.visibleFrame
        let time = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? 0 : event.startedAt.timeIntervalSinceReferenceDate
        let categoryCount = max(1, model.branches.count)
        let anchor = CompactGardenLayout.branchAnchor(index: event.branchIndex, total: categoryCount, time: time)
        let localGrape = CGPoint(x: anchor.x, y: anchor.y)
        let grapeVisualScale = CompactGardenLayout.branchScale(total: categoryCount)
        let screenGrape = CGPoint(x: vinePanel.frame.minX + localGrape.x,
                                  y: vinePanel.frame.maxY - localGrape.y)
        let origin = CGPoint(x: screenGrape.x - area.minX, y: area.maxY - screenGrape.y)
        let overlay = TheftPanel(contentRect: area,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        overlay.hidesOnDeactivate = false
        overlay.isReleasedWhenClosed = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.ignoresMouseEvents = true
        let hosting = NSHostingView(rootView: LiveTheftScene(event: event, origin: origin, grapeVisualScale: grapeVisualScale))
        hosting.frame = CGRect(origin: .zero, size: area.size)
        overlay.contentView = hosting
        overlay.orderFrontRegardless()
        panel = overlay
        eventID = event.id

        let remaining = max(0.05, VineModel.theftDuration - Date().timeIntervalSince(event.startedAt))
        let timer = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.eventID == event.id else { return }
                self.dismiss()
                self.model.completeTheft(id: event.id)
            }
        }
        completionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func dismiss() {
        completionTimer?.invalidate()
        completionTimer = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        eventID = nil
    }
}
