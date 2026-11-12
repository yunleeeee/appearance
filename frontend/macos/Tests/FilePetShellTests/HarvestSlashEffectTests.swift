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
        let shatter = HarvestSlashEffect.sample(at: 0.78, reduceMotion: false)
        XCTAssertFalse(shatter.showHead)
        XCTAssertGreaterThan(shatter.shardOpacity, 0)
        XCTAssertEqual(shatter.stemOpacity, 0, "The whole plant, including roots, shatters together")
        let falling = HarvestSlashEffect.sample(at: 1.20, reduceMotion: false)
        XCTAssertEqual(falling.stemOpacity, 0)
        XCTAssertGreaterThan(falling.shardOpacity, 0)
        XCTAssertLessThan(falling.shardOpacity, 1)
        let end = HarvestSlashEffect.sample(at: HarvestSlashEffect.duration, reduceMotion: false)
        XCTAssertTrue(end.finished)
        XCTAssertEqual(end.stemOpacity, 0)
        XCTAssertEqual(end.shardOpacity, 0)
        XCTAssertFalse(end.showHead)
    }

    func testNineCutsCoverWholeRectangleIncludingRootAndCrown() {
        let rectangle = CGRect(x: 0, y: 0, width: 160, height: 220)
        XCTAssertEqual(HarvestSlashEffect.cuttingRect(in: rectangle), rectangle)
        let segments = HarvestSlashEffect.slashSegments(in: rectangle)
        XCTAssertEqual(segments.count, 7)
        XCTAssertTrue(segments.contains { min($0.0.y, $0.1.y) < rectangle.height * 0.05 },
                      "Sword streaks must strike the rooted bottom of the target area")
        XCTAssertTrue(segments.contains { max($0.0.y, $0.1.y) > rectangle.height * 0.95 },
                      "Sword streaks must also traverse the upper blossom")
        XCTAssertTrue(segments.contains {
            abs($0.0.y - $0.1.y) > rectangle.height * 0.8
        }, "At least one blade must cross almost the entire height")
    }

    func testWholePlantSnapshotContainsPaintedRootAndStemFragments() throws {
        let artwork = CompactFlowerArtwork.plants[1]
        let bounds = CGRect(origin: .zero,
            size: DeadlineFlowerArrangement.canvasSize(for: artwork.size, count: 1))
        let snapshot = try XCTUnwrap(HarvestSlashEffect.makeSnapshot(
            in: bounds, stage: .bloom, artwork: artwork,
            crownScale: 0.72, pose: .solo))
        XCTAssertEqual(snapshot.cutRect, bounds)
        XCTAssertGreaterThan(snapshot.fragments.count, 30,
                             "The entire planted image should fracture into many pieces")
        XCTAssertTrue(snapshot.fragments.contains { $0.center.y < bounds.height * 0.10 },
                      "The root and ground-level stem must become independent fragments")
        XCTAssertTrue(snapshot.fragments.contains { $0.center.y > bounds.height * 0.67 },
                      "The bloom must also fracture")
        XCTAssertTrue(snapshot.fragments.contains {
            $0.center.y > bounds.height * 0.23 && $0.center.y < bounds.height * 0.56
        }, "The middle stem and leaves must not remain as an intact prop")

        let rootPixels = (max(0, snapshot.pixelHeight - 28)..<snapshot.pixelHeight).reduce(0) {
            sum, y in sum + snapshot.alpha[(y * snapshot.pixelWidth)..<((y + 1) * snapshot.pixelWidth)]
                .filter { $0 > 22 }.count
        }
        XCTAssertGreaterThan(rootPixels, 0, "The original root/soil must be present in the raster")
        let velocities = snapshot.fragments.map { $0.speedX }
        XCTAssertGreaterThan(Set(velocities.map { Int($0 / 10) }).count, 12,
            "Fragment velocities must vary rather than form two uniform columns")
        XCTAssertTrue(velocities.contains(where: { $0 < -60 }))
        XCTAssertTrue(velocities.contains(where: { $0 > 60 }))
        let sides = Set(snapshot.fragments.map { Int($0.side) })
        XCTAssertEqual(sides, Set([-1, 1]), "Every piece belongs to one side of the real cut")
        let cut = HarvestSlashEffect.executionLine(
            in: snapshot.cutRect, rootX: artwork.stemX)
        for piece in snapshot.fragments {
            let pieces = HarvestSlashEffect.splitBySword(
                piece.points, start: cut.start, end: cut.end)
            let expected = piece.side > 0 ? pieces.positive : pieces.negative
            XCTAssertEqual(HarvestSlashEffect.polygonArea(expected),
                           HarvestSlashEffect.polygonArea(piece.points),
                           accuracy: 0.005, "Fragments cannot straddle the finisher")
        }
    }

    func testCinematicSequenceHasHitStopAndDecisiveFinisher() {
        XCTAssertGreaterThan(HarvestSlashEffect.finisherAt, 0.35)
        XCTAssertLessThan(HarvestSlashEffect.finisherAt, HarvestSlashEffect.shatterAt)
        XCTAssertGreaterThan(HarvestSlashEffect.shatterAt - HarvestSlashEffect.finisherAt, 0.08,
            "The execution strike must be visibly distinct from the breakup")
        let before = HarvestSlashEffect.sample(
            at: HarvestSlashEffect.finisherAt - 0.03, reduceMotion: false)
        XCTAssertTrue(before.showHead)
        let atImpact = HarvestSlashEffect.sample(
            at: HarvestSlashEffect.shatterAt, reduceMotion: false)
        XCTAssertFalse(atImpact.showHead)
        XCTAssertEqual(atImpact.stemOpacity, 0)
        XCTAssertEqual(atImpact.shardOpacity, 0,
            "The primary cut must form two slabs before any micro-fragments")
        let debris = HarvestSlashEffect.sample(
            at: HarvestSlashEffect.secondaryAt, reduceMotion: false)
        XCTAssertGreaterThan(debris.shardOpacity, 0)
        let battle = HarvestSlashEffect.combatRect(
            in: CGRect(x: 0, y: 0, width: 80, height: 180), rootX: 40)
        XCTAssertGreaterThanOrEqual(battle.width, 154)
        XCTAssertEqual(battle.minY, 1.5)
    }

    func testInksteelPaletteHasSteelHighlightsAndNeutralFinisher() {
        let p = HarvestSlashEffect.Palette.self
        let ink = p.ink.usingColorSpace(.deviceRGB)!
        let steel = p.steel.usingColorSpace(.deviceRGB)!
        let silver = p.silver.usingColorSpace(.deviceRGB)!
        let pearl = p.pearl.usingColorSpace(.deviceRGB)!
        let charcoal = p.charcoal.usingColorSpace(.deviceRGB)!
        let ash = p.ash.usingColorSpace(.deviceRGB)!
        let white = p.white.usingColorSpace(.deviceRGB)!
        XCTAssertLessThan(ink.brightnessComponent, steel.brightnessComponent)
        XCTAssertLessThan(steel.brightnessComponent, silver.brightnessComponent)
        XCTAssertLessThan(silver.brightnessComponent, pearl.brightnessComponent)
        for neutral in [charcoal, ash, white] {
            XCTAssertEqual(neutral.redComponent, neutral.greenComponent, accuracy: 0.001)
            XCTAssertEqual(neutral.greenComponent, neutral.blueComponent, accuracy: 0.001)
        }
    }

    func testWholePlantLosesColorAtFinisherAndKeepsAlpha() throws {
        XCTAssertEqual(HarvestSlashEffect.monochromeProgress(
            at: HarvestSlashEffect.finisherAt - 0.01, reduceMotion: false), 0)
        XCTAssertGreaterThan(HarvestSlashEffect.monochromeProgress(
            at: HarvestSlashEffect.finisherAt + 0.05, reduceMotion: false), 0)
        XCTAssertEqual(HarvestSlashEffect.monochromeProgress(
            at: HarvestSlashEffect.shatterAt, reduceMotion: false), 1)
        XCTAssertEqual(HarvestSlashEffect.monochromeProgress(
            at: HarvestSlashEffect.shatterAt, reduceMotion: true), 0)

        let artwork = CompactFlowerArtwork.plants[1]
        let bounds = CGRect(origin: .zero, size: artwork.size)
        let snapshot = try XCTUnwrap(HarvestSlashEffect.makeSnapshot(
            in: bounds, stage: .bloom, artwork: artwork,
            crownScale: 0.72, pose: .solo))
        XCTAssertEqual(snapshot.monochromeRGBA.count,
                       snapshot.pixelWidth * snapshot.pixelHeight * 4)
        var opaque = 0
        for i in stride(from: 0, to: snapshot.monochromeRGBA.count, by: 4) {
            let rgb = snapshot.monochromeRGBA
            XCTAssertEqual(rgb[i], rgb[i + 1], "Red/green channel must match")
            XCTAssertEqual(rgb[i + 1], rgb[i + 2], "Green/blue channel must match")
            XCTAssertEqual(rgb[i + 3], snapshot.alpha[i / 4],
                           "Black-white conversion must preserve pixel alpha")
            if rgb[i + 3] > 180 { opaque += 1 }
        }
        XCTAssertGreaterThan(opaque, 250, "The complete monochrome flower must be present")
        let actual = HarvestSlashEffect.makeMonochromeRGBA([
            180, 50, 30, 255,
            0, 80, 110, 128,
            0, 0, 0, 0
        ])
        XCTAssertEqual(actual.count, 12)
        XCTAssertEqual(actual[0], actual[1])
        XCTAssertEqual(actual[1], actual[2])
        XCTAssertEqual(actual[4], actual[5])
        XCTAssertEqual(actual[5], actual[6])
        XCTAssertEqual(actual[7], 128)
        XCTAssertEqual(Array(actual[8...11]), [0, 0, 0, 0])
    }

    func testExecutionLineSplitsPolygonWithoutLosingArea() {
        let rect = CGRect(x: 0, y: 0, width: 110, height: 190)
        let execution = HarvestSlashEffect.executionLine(in: rect, rootX: 56)
        XCTAssertLessThan(abs(execution.start.x - 56), 20)
        XCTAssertLessThan(abs(execution.end.x - 56), 20)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        let halves = HarvestSlashEffect.splitBySword(
            corners, start: execution.start, end: execution.end)
        XCTAssertGreaterThanOrEqual(halves.positive.count, 3)
        XCTAssertGreaterThanOrEqual(halves.negative.count, 3)
        let area = HarvestSlashEffect.polygonArea(halves.positive)
            + HarvestSlashEffect.polygonArea(halves.negative)
        XCTAssertEqual(area, rect.width * rect.height, accuracy: 0.1,
                       "The sword's real geometry must partition the full image")
        let crossing = HarvestSlashEffect.splitBySword([
            CGPoint(x: 25, y: 80), CGPoint(x: 80, y: 80),
            CGPoint(x: 80, y: 110), CGPoint(x: 25, y: 110)
        ], start: execution.start, end: execution.end)
        XCTAssertGreaterThan(HarvestSlashEffect.polygonArea(crossing.positive), 0)
        XCTAssertGreaterThan(HarvestSlashEffect.polygonArea(crossing.negative), 0)
    }

    func testTwoStageSplitPreservesCutSeamAndNoDebrisBeforeRelease() {
        XCTAssertEqual(HarvestSlashEffect.monochromeProgress(
            at: HarvestSlashEffect.shatterAt, reduceMotion: false), 1)
        XCTAssertGreaterThan(HarvestSlashEffect.secondaryAt, HarvestSlashEffect.shatterAt)
        XCTAssertEqual(HarvestSlashEffect.primarySeparation(
            at: HarvestSlashEffect.shatterAt), 0)
        let middle = (HarvestSlashEffect.shatterAt + HarvestSlashEffect.secondaryAt) / 2
        XCTAssertGreaterThan(HarvestSlashEffect.primarySeparation(at: middle), 0)
        XCTAssertEqual(HarvestSlashEffect.primarySeparation(
            at: HarvestSlashEffect.secondaryAt), 13, accuracy: 0.001)
        let slab = HarvestSlashEffect.sample(at: middle, reduceMotion: false)
        XCTAssertFalse(slab.showHead)
        XCTAssertEqual(slab.stemOpacity, 0)
        XCTAssertEqual(slab.shardOpacity, 0,
                       "Two recognizable halves must be visible before micro-debris")
        let shard = HarvestSlashEffect.sample(
            at: HarvestSlashEffect.secondaryAt, reduceMotion: false)
        XCTAssertGreaterThan(shard.shardOpacity, 0)
        XCTAssertEqual(HarvestSlashEffect.sample(
            at: HarvestSlashEffect.duration, reduceMotion: false).shardOpacity, 0)
    }

    func testOneFrameMonochromeNegativeIsConfinedToExecutionWindow() {
        XCTAssertGreaterThan(HarvestSlashEffect.impactFrameAt,
                             HarvestSlashEffect.finisherAt)
        XCTAssertLessThan(HarvestSlashEffect.impactFrameAt
                          + HarvestSlashEffect.impactFrameDuration,
                          HarvestSlashEffect.shatterAt + 0.001)
        let src: [UInt8] = [40, 100, 145, 255, 0, 0, 0, 0]
        let normal = HarvestSlashEffect.makeMonochromeRGBA(src)
        let negative = HarvestSlashEffect.makeMonochromeRGBA(src, inverted: true)
        XCTAssertNotEqual(normal[0], negative[0])
        XCTAssertEqual(negative[0], negative[1])
        XCTAssertEqual(negative[1], negative[2])
        XCTAssertEqual(negative[3], normal[3])
        XCTAssertEqual(negative[7], 0)
    }

    func testPetalPhysicsNeverFallsThroughDesktopGround() {
        for centerY in [CGFloat(10), 25, 54, 91, 130] {
            for launch in [CGFloat(40), 74, 129, 175] {
                for sample in stride(from: 0.0, through: 1.6, by: 0.04) {
                    let dy = HarvestSlashEffect.verticalOffset(
                        time: CGFloat(sample), launch: launch, centerY: centerY)
                    XCTAssertGreaterThanOrEqual(centerY + dy,
                        HarvestSlashEffect.floorY - 0.001)
                }
            }
        }
    }

    func testExpandedOverlayCanvasDoesNotChangeOriginalFlowerGeometry() {
        let flower = DeadlineFlowerView(artwork: CompactFlowerArtwork.plants[1])
        let originalFrame = flower.frame
        let overlay = HarvestEffectOverlayView(flower: flower)
        XCTAssertGreaterThan(overlay.frame.width, originalFrame.width + 200)
        XCTAssertGreaterThan(overlay.frame.height, originalFrame.height)
        XCTAssertEqual(flower.frame, originalFrame)
        XCTAssertFalse(overlay.isOpaque)
    }

    func testExpandedSwordBeamIsVisibleOutsideTheFlowerPanel() throws {
        let flower = DeadlineFlowerView(artwork: CompactFlowerArtwork.plants[1])
        flower.deadlineStage = .bloom
        flower.previewHarvestAge = 0.205
        let overlay = HarvestEffectOverlayView(flower: flower)
        let wide = try bitmap(for: overlay)
        let pixelWidth = Int(ceil(overlay.bounds.width))
        let pixelHeight = Int(ceil(overlay.bounds.height))
        let leftLimit = Int(HarvestEffectOverlayView.bleed)
        let rightLimit = leftLimit + Int(ceil(flower.bounds.width))
        var paintedOutsideOriginalPanel = 0
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth where x < leftLimit || x >= rightLimit {
                if wide[(y * pixelWidth + x) * 4 + 3] > 0 {
                    paintedOutsideOriginalPanel += 1
                }
            }
        }
        XCTAssertGreaterThan(paintedOutsideOriginalPanel, 0,
            "A long sword-light trail must not be clipped by the original flower panel")

        flower.previewHarvestAge = nil
        flower.renderHarvestInOverlay = true
        XCTAssertTrue(try bitmap(for: flower).allSatisfy { $0 == 0 },
                      "The spent sprite must not flash back while awaiting queue sync")
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

    func testFinisherHasDistinctFrameFromTheHitStop() throws {
        let flower = DeadlineFlowerView(artwork: CompactFlowerArtwork.plants[1])
        flower.deadlineStage = .bloom
        flower.reduceMotionOverride = false
        flower.previewHarvestAge = 0.35
        let still = try bitmap(for: flower)
        flower.previewHarvestAge = 0.525
        let finisher = try bitmap(for: flower)
        XCTAssertNotEqual(still, finisher,
            "The execution slash should be its own recognizable visual beat")
    }

    func testRenderedHarvestFramesChangeAndEndTransparent() throws {
        let flower = DeadlineFlowerView(artwork: CompactFlowerArtwork.plants[1])
        flower.deadlineStage = .bloom
        flower.reduceMotionOverride = false
        flower.previewHarvestAge = 0.16
        let slash = try bitmap(for: flower)
        flower.previewHarvestAge = 0.65
        let breakApart = try bitmap(for: flower)
        flower.previewHarvestAge = 1.11
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

    private func bitmap(for view: NSView) throws -> [UInt8] {
        let width = Int(ceil(view.bounds.width))
        let height = Int(ceil(view.bounds.height))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        view.draw(view.bounds)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let raw = try XCTUnwrap(bitmap.bitmapData)
        return Array(UnsafeBufferPointer(start: raw, count: width * height * 4))
    }
}
