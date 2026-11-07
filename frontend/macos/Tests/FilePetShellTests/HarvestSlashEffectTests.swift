import AppKit
import XCTest
@testable import FilePetShell

@MainActor
final class HarvestSlashEffectTests: XCTestCase {
    func testOnlyActualDoubleClickOnArtworkHarvests() {
        XCTAssertFalse(HarvestGesturePolicy.accepts(
            clickCount: 1, displacement: 0, onArtwork: true))
        XCTAssertTrue(HarvestGesturePolicy.accepts(
            clickCount: 2, displacement: 2.4, onArtwork: true))
        XCTAssertFalse(HarvestGesturePolicy.accepts(
            clickCount: 2, displacement: 7, onArtwork: true),
            "Drag-like gestures must not complete a task")
        XCTAssertFalse(HarvestGesturePolicy.accepts(
            clickCount: 2, displacement: 0, onArtwork: false),
            "Transparent desktop pixels must remain click-through")
    }

    func testNativeMouseUpRequiresTwoClicksAndRejectsRepeatDuringAnimation() throws {
        _ = NSApplication.shared
        let art = CompactFlowerArtwork.plants[1]
        let view = DeadlineFlowerView(artwork: art)
        view.deadlineStage = .bloom
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: art.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = view
        defer { panel.orderOut(nil) }
        let sprite = try XCTUnwrap(DeadlineFlowerMotion.heads.last.map { _ in
            DeadlineFlowerMotion.heads[DeadlineStage.bloom.rawValue]
        })
        let geometry = try XCTUnwrap(DeadlineFlowerMotion.geometry(
            bounds: view.bounds, artwork: art, stage: .bloom, stem: 0, head: 0))
        let idx = try XCTUnwrap(sprite.alpha.firstIndex(where: { $0 > 200 }))
        let point = CGPoint(
            x: geometry.rect.minX +
                (CGFloat(idx % sprite.pixelsWide) + 0.5) /
                CGFloat(sprite.pixelsWide) * geometry.rect.width,
            y: geometry.rect.maxY -
                (CGFloat(idx / sprite.pixelsWide) + 0.5) /
                CGFloat(sprite.pixelsHigh) * geometry.rect.height)
        XCTAssertTrue(view.containsArtwork(point))
        func event(_ type: NSEvent.EventType, count: Int) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: TimeInterval(count), windowNumber: panel.windowNumber,
                context: nil, eventNumber: count,
                clickCount: count, pressure: 1))
        }
        var harvestCalls = 0
        view.onHarvest = {
            harvestCalls += 1
            view.beginHarvestEffect(completion: {})
        }
        view.mouseDown(with: try event(.leftMouseDown, count: 1))
        view.mouseUp(with: try event(.leftMouseUp, count: 1))
        XCTAssertEqual(harvestCalls, 0, "A single click must never finish a task")
        view.mouseDown(with: try event(.leftMouseDown, count: 2))
        view.mouseUp(with: try event(.leftMouseUp, count: 2))
        XCTAssertEqual(harvestCalls, 1)
        XCTAssertTrue(view.isHarvesting)
        XCTAssertFalse(view.containsArtwork(point),
                       "During the animation the flower must be click-through")
        view.mouseDown(with: try event(.leftMouseDown, count: 2))
        view.mouseUp(with: try event(.leftMouseUp, count: 2))
        XCTAssertEqual(harvestCalls, 1, "Repeat clicks cannot re-trigger harvest")
    }

    func testSwordCutsThenShatteringThenGravityAndCompleteDisappear() {
        let fresh = HarvestSlashEffect.sample(at: 0, reduceMotion: false)
        XCTAssertTrue(fresh.showHead)
        XCTAssertEqual(fresh.stemOpacity, 1)
        XCTAssertEqual(fresh.shardOpacity, 0)

        let cuts = HarvestSlashEffect.sample(at: 0.21, reduceMotion: false)
        XCTAssertTrue(cuts.showHead)
        XCTAssertFalse(cuts.finished)
        let shatter = HarvestSlashEffect.sample(at: 0.42, reduceMotion: false)
        XCTAssertFalse(shatter.showHead)
        XCTAssertGreaterThan(shatter.shardOpacity, 0)
        XCTAssertGreaterThan(shatter.stemOpacity, 0)
        let falling = HarvestSlashEffect.sample(at: 0.82, reduceMotion: false)
        XCTAssertEqual(falling.stemOpacity, 0)
        XCTAssertGreaterThan(falling.shardOpacity, 0)
        XCTAssertLessThan(falling.shardOpacity, 1)
        let end = HarvestSlashEffect.sample(at: HarvestSlashEffect.duration, reduceMotion: false)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(end.stemOpacity, 0)
        XCTAssertEqual(end.shardOpacity, 0)
        XCTAssertFalse(end.showHead)
    }

    func testFullScreenAndUserHideCancelHarvestWithoutCompletingTask() async throws {
        _ = NSApplication.shared
        let suite = "FilePetShell.HarvestVisibility.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let garden = DeadlineGarden(defaults: defaults)
        garden.feed([EngineDeadline(id: "active", title: "提交报告", project: "课程",
            dueDate: "2099-11-08", dueTime: "23:59", yearInferred: false,
            evidence: "2099年11月8日23:59前提交报告")])
        let controller = DeadlineFlowerController(garden: garden,
            screenFrame: { NSRect(x: 0, y: 0, width: 1440, height: 900) },
            onFiles: { _ in })
        defer { controller.stop() }
        let identity = try XCTUnwrap(controller.panelIdentities["active"])
        let panel = try XCTUnwrap(NSApp.windows.first { ObjectIdentifier($0) == identity })
        let view = try XCTUnwrap(panel.contentView as? DeadlineFlowerView)
        view.reduceMotionOverride = false

        for fullScreen in [true, false] {
            XCTAssertTrue(view.accessibilityPerformPress())
            XCTAssertTrue(view.isHarvesting)
            XCTAssertNil(garden.deadlines.first?.completedAt,
                         "The task completes after the cinematic, not on activation")
            if fullScreen { controller.setFullScreenSuppressed(true) }
            else { controller.setVisible(false) }
            XCTAssertTrue(controller.visiblePanelIDs.isEmpty)
            XCTAssertFalse(view.isHarvesting)
            _ = view.accessibilityPerformPress()
            XCTAssertFalse(view.isHarvesting, "A hidden task cannot start a cinematic")
            try await Task.sleep(nanoseconds: UInt64((HarvestSlashEffect.duration + 0.10) * 1_000_000_000))
            XCTAssertNil(garden.deadlines.first?.completedAt,
                         "Cancelled animation callbacks must not finish a hidden task")
            if fullScreen { controller.setFullScreenSuppressed(false) }
            else { controller.setVisible(true) }
            XCTAssertEqual(controller.visiblePanelIDs, ["active"])
            XCTAssertEqual(controller.panelIdentities["active"], identity)
            XCTAssertFalse(view.isHarvesting)
        }
    }

    func testReduceMotionPreservesRecognitionAndDisablesSwordFlight() {
        let first = HarvestSlashEffect.sample(at: 0, reduceMotion: true)
        XCTAssertTrue(first.showHead)
        XCTAssertEqual(first.shardOpacity, 0)
        let middle = HarvestSlashEffect.sample(at: 0.11, reduceMotion: true)
        XCTAssertFalse(middle.showHead)
        XCTAssertEqual(middle.shardOpacity, 0)
        XCTAssertFalse(middle.finished)
        let end = HarvestSlashEffect.sample(
            at: HarvestSlashEffect.reducedDuration, reduceMotion: true)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(end.stemOpacity, 0)
        XCTAssertEqual(end.shardOpacity, 0)
        XCTAssertLessThan(HarvestSlashEffect.reducedDuration, HarvestSlashEffect.duration)
    }

    func testRenderedHarvestFramesChangeAndEndTransparent() throws {
        let flower = DeadlineFlowerView(artwork: CompactFlowerArtwork.plants[1])
        flower.deadlineStage = .bloom
        flower.reduceMotionOverride = false
        flower.previewHarvestAge = 0.16
        let slash = try bitmap(for: flower)
        flower.previewHarvestAge = 0.50
        let breakApart = try bitmap(for: flower)
        flower.previewHarvestAge = 0.80
        let falling = try bitmap(for: flower)
        flower.previewHarvestAge = HarvestSlashEffect.duration
        let final = try bitmap(for: flower)
        XCTAssertNotEqual(slash, breakApart)
        XCTAssertNotEqual(breakApart, falling)
        XCTAssertNotEqual(falling, final)
        XCTAssertTrue(final.allSatisfy { $0 == 0 },
                      "After falling there should be no lingering flower, beam or spark")

        flower.reduceMotionOverride = true
        flower.previewHarvestAge = HarvestSlashEffect.reducedDuration
        XCTAssertTrue(try bitmap(for: flower).allSatisfy { $0 == 0 })
    }

    private func bitmap(for flower: DeadlineFlowerView) throws -> [UInt8] {
        let width = Int(ceil(flower.bounds.width))
        let height = Int(ceil(flower.bounds.height))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        flower.draw(flower.bounds)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let raw = try XCTUnwrap(bitmap.bitmapData)
        return Array(UnsafeBufferPointer(start: raw, count: width * height * 4))
    }
}
