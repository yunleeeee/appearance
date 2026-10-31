import AppKit
import XCTest
@testable import FilePetShell

/// Reproducible native AppKit renderer proofs, NOT a capture of a logged-in desktop.
/// CI encodes the frame sequences to two MP4s with ffmpeg when available.
@MainActor
final class DeadlineVisualProofTests: XCTestCase {
    func testStageScreenshotsAndMotionSequences() throws {
        guard let destination = ProcessInfo.processInfo.environment["FILEPET_VISUAL_PROOFS"] else {
            return // Only capture when CI explicitly requests proof artifacts.
        }
        XCTAssertEqual(DeadlineFlowerMotion.heads.count, 6,
                       "Frozen v2 atlas must be available in the runtime bundle")
        let root = URL(fileURLWithPath: destination, isDirectory: true)
        let snapshots = root.appendingPathComponent("six-stages", isDirectory: true)
        let transitions = root.appendingPathComponent("stage-change-frames", isDirectory: true)
        let breeze = root.appendingPathComponent("resident-breeze-frames", isDirectory: true)
        for folder in [snapshots, transitions, breeze] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let artwork = CompactFlowerArtwork.plants[1]
        for (index, stage) in DeadlineStage.allCases.enumerated() {
            let view = DeadlineFlowerView(artwork: artwork)
            view.deadlineStage = stage
            let file = snapshots.appendingPathComponent(String(format: "%d-%@.png", index, stage.label))
            try imageData(view).write(to: file)
        }

        let stageView = DeadlineFlowerView(artwork: artwork)
        stageView.previewTransition = (.bud, 1)
        stageView.deadlineStage = .bud
        for i in 0..<144 {
            let index = min(5, i / 24)
            let current = DeadlineStage.allCases[index]
            let previous = DeadlineStage.allCases[max(0, index - 1)]
            let position = i % 24
            stageView.previewTransition = (previous, CGFloat(min(1, Double(position) / 12)))
            stageView.deadlineStage = current
            let file = transitions.appendingPathComponent(String(format: "frame-%03d.png", i))
            try imageData(stageView).write(to: file)
        }

        let windView = DeadlineFlowerView(artwork: artwork)
        windView.reduceMotionOverride = false // CI host accessibility settings must not hide the motion proof.
        windView.deadlineStage = .bloom
        for i in 0..<120 {
            windView.previewWindAge = Double(i) / 24 - 0.5
            let file = breeze.appendingPathComponent(String(format: "frame-%03d.png", i))
            try imageData(windView).write(to: file)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: snapshots.path).count, 6)
    }

    func testReduceMotionDisablesContinuousBreezeButKeepsStageDifference() throws {
        let artwork = CompactFlowerArtwork.plants[1]
        let view = DeadlineFlowerView(artwork: artwork)
        view.reduceMotionOverride = true
        view.deadlineStage = .bloom
        view.previewWindAge = 0.4
        let first = try imageData(view)
        view.previewWindAge = 1.4
        let second = try imageData(view)
        XCTAssertEqual(first, second, "Reduce Motion must suppress ongoing wind")
        view.deadlineStage = .withered
        XCTAssertNotEqual(first, try imageData(view), "Distinct deadlines must remain visually legible")
    }

    func testBreezeProofHasRealDifferentialMotion() throws {
        let view = DeadlineFlowerView(artwork: CompactFlowerArtwork.plants[1])
        view.reduceMotionOverride = false
        view.deadlineStage = .bloom
        view.previewWindAge = 0.52
        let pushed = try imageData(view)
        view.previewWindAge = 1.27
        let recovery = try imageData(view)
        XCTAssertNotEqual(pushed, recovery, "Preview movie must contain real rendered motion")
    }

    private func imageData(_ view: DeadlineFlowerView) throws -> Data {
        let width = 384, height = 384
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.setFillColor(NSColor(calibratedRed: 0.975, green: 0.969, blue: 0.955, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: (CGFloat(width) - view.bounds.width * 2) / 2,
                            y: (CGFloat(height) - view.bounds.height * 2) / 2)
        context.scaleBy(x: 2, y: 2)
        view.draw(view.bounds)
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
