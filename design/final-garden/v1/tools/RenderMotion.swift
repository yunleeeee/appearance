import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import JavaScriptCore

private struct AtlasManifest: Decodable {
    let images: [String: String]
    let sprites: [String: SpriteDefinition]
}

private struct SpriteDefinition: Decodable {
    let image: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
    let nativeW: Double
    let nativeH: Double
    let anchorX: Double
    let anchorY: Double
}

private struct RenderSprite {
    let image: CGImage
    let definition: SpriteDefinition
}

private enum ExportError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case let .message(message): return message }
    }
}

private final class SceneRenderer {
    static let logicalWidth = 384
    static let logicalHeight = 192
    static let scale = 3
    static let fps: Int32 = 24
    static let duration = 12.0
    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let context: JSContext
    private let sprites: [String: RenderSprite]
    private let background: CGColor
    private var lastJavaScriptError: String?

    init(root: URL, dark: Bool) throws {
        background = Self.color(dark ? "#202b30" : "#eef0e8")
        let manifest = try JSONDecoder().decode(AtlasManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("assets.json")))
        var images: [String: CGImage] = [:]
        for (key, name) in manifest.images {
            guard let source = CGImageSourceCreateWithURL(root.appendingPathComponent(name) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0,
                      [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                throw ExportError.message("Cannot decode atlas \(name)")
            }
            images[key] = image
        }
        var loaded: [String: RenderSprite] = [:]
        for (key, definition) in manifest.sprites {
            let rect = CGRect(x: definition.x, y: definition.y, width: definition.w, height: definition.h)
            guard let atlas = images[definition.image], let crop = atlas.cropping(to: rect) else {
                throw ExportError.message("Invalid sprite crop: \(key)")
            }
            loaded[key] = RenderSprite(image: crop, definition: definition)
        }
        sprites = loaded
        guard let js = JSContext() else { throw ExportError.message("Cannot create JavaScriptCore") }
        context = js
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastJavaScriptError = exception?.toString() ?? "Unknown JavaScript exception"
        }
        // The accepted flower engine is loaded byte-for-byte before the new
        // composition wrapper. The wrapper never changes its flower commands.
        for name in ["flower-engine.js", "scene.js"] {
            let url = root.appendingPathComponent(name)
            let code = try String(contentsOf: url, encoding: .utf8)
            context.evaluateScript(code, withSourceURL: url)
            if let error = lastJavaScriptError { throw ExportError.message(error) }
        }
        guard context.evaluateScript("typeof FarmMotion === 'object' && typeof FarmMotion.scene === 'function'")?.toBool() == true else {
            throw ExportError.message("scene.js must expose FarmMotion.scene")
        }
    }

    func scene(at time: Double, options: [String: Any] = [:]) throws -> [String: Any] {
        lastJavaScriptError = nil
        let data = try JSONSerialization.data(withJSONObject: options, options: [.sortedKeys])
        let optionsJSON = String(data: data, encoding: .utf8)!
        let expression = "JSON.stringify(FarmMotion.scene(\(time), \(optionsJSON)))"
        guard let json = context.evaluateScript(expression)?.toString(),
              let data = json.data(using: .utf8),
              let scene = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExportError.message(lastJavaScriptError ?? "Scene returned invalid JSON")
        }
        if let error = lastJavaScriptError { throw ExportError.message(error) }
        return scene
    }

    func frame(at time: Double, options: [String: Any] = [:]) throws -> (CGImage, [String: Any]) {
        let scene = try scene(at: time, options: options)
        guard let bitmap = CGContext(data: nil, width: Self.logicalWidth, height: Self.logicalHeight,
            bitsPerComponent: 8, bytesPerRow: Self.logicalWidth * 4,
            space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            throw ExportError.message("Cannot create logical frame")
        }
        bitmap.setFillColor(background)
        bitmap.fill(CGRect(x: 0, y: 0, width: Self.logicalWidth, height: Self.logicalHeight))
        bitmap.setShouldAntialias(false)
        bitmap.setAllowsAntialiasing(false)
        bitmap.interpolationQuality = .none
        bitmap.translateBy(x: 0, y: CGFloat(Self.logicalHeight))
        bitmap.scaleBy(x: 1, y: -1)
        for command in scene["commands"] as? [[String: Any]] ?? [] {
            try draw(command, in: bitmap)
        }
        guard let logical = bitmap.makeImage(),
              let output = CGContext(data: nil, width: Self.logicalWidth * Self.scale,
                  height: Self.logicalHeight * Self.scale, bitsPerComponent: 8,
                  bytesPerRow: Self.logicalWidth * Self.scale * 4,
                  space: Self.colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            throw ExportError.message("Cannot create enlarged frame")
        }
        output.interpolationQuality = .none
        output.setShouldAntialias(false)
        output.draw(logical, in: CGRect(x: 0, y: 0,
            width: Self.logicalWidth * Self.scale, height: Self.logicalHeight * Self.scale))
        return (output.makeImage()!, scene)
    }

    private func draw(_ command: [String: Any], in context: CGContext) throws {
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(CGFloat(max(0, min(1, Self.number(command, "opacity", default: 1)))))
        switch command["type"] as? String {
        case "sprite":
            guard let key = command["id"] as? String, let sprite = sprites[key] else {
                throw ExportError.message("Unknown sprite: \(command["id"] ?? "nil")")
            }
            let d = sprite.definition
            context.translateBy(x: Self.number(command, "x"), y: Self.number(command, "y"))
            context.rotate(by: Self.number(command, "rotation") * .pi / 180)
            context.scaleBy(x: Self.number(command, "scaleX", default: 1),
                            y: Self.number(command, "scaleY", default: 1))
            // Sector masks live in local native pixels relative to the anchor.
            // The current transform already contains sprite movement, rotation,
            // and scale, so the mask flexes with each petal layer.
            if let points = command["clipPolygon"] as? [[Double]],
               points.count >= 3, let first = points.first, first.count >= 2 {
                context.beginPath()
                context.move(to: CGPoint(x: first[0], y: first[1]))
                for point in points.dropFirst() where point.count >= 2 {
                    context.addLine(to: CGPoint(x: point[0], y: point[1]))
                }
                context.closePath()
                context.clip()
            }
            context.translateBy(x: -d.anchorX, y: -d.anchorY)
            // The scene uses browser-like top-left coordinates. Flip only the
            // image locally, preserving its orientation in the flipped scene.
            context.translateBy(x: 0, y: d.nativeH)
            context.scaleBy(x: 1, y: -1)
            context.draw(sprite.image, in: CGRect(x: 0, y: 0, width: d.nativeW, height: d.nativeH))
        case "rect":
            context.setFillColor(Self.color(command["color"] as? String ?? "#000000"))
            context.fill(CGRect(x: Self.number(command, "x"), y: Self.number(command, "y"),
                                width: Self.number(command, "w"), height: Self.number(command, "h")))
        case "line":
            guard let points = command["points"] as? [[Double]], let first = points.first, first.count >= 2 else { return }
            context.setStrokeColor(Self.color(command["color"] as? String ?? "#000000"))
            context.setLineWidth(Self.number(command, "width", default: 1))
            context.setLineCap(.butt)
            context.setLineJoin(.miter)
            context.beginPath()
            context.move(to: CGPoint(x: first[0], y: first[1]))
            for point in points.dropFirst() where point.count >= 2 {
                context.addLine(to: CGPoint(x: point[0], y: point[1]))
            }
            context.strokePath()
        default:
            throw ExportError.message("Unsupported drawing command: \(command["type"] ?? "nil")")
        }
    }

    private static func number(_ dictionary: [String: Any], _ key: String, default fallback: Double = 0) -> Double {
        (dictionary[key] as? NSNumber)?.doubleValue ?? fallback
    }

    static func color(_ hex: String) -> CGColor {
        var text = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if text.count == 3 { text = text.map { "\($0)\($0)" }.joined() }
        guard text.count == 6 || text.count == 8, let integer = UInt64(text, radix: 16) else {
            return CGColor(colorSpace: colorSpace, components: [0, 0, 0, 1])!
        }
        let rgba = text.count == 8 ? integer : (integer << 8) | 255
        return CGColor(colorSpace: colorSpace, components: [CGFloat((rgba >> 24) & 255) / 255,
                       CGFloat((rgba >> 16) & 255) / 255,
                       CGFloat((rgba >> 8) & 255) / 255,
                       CGFloat(rgba & 255) / 255])!
    }
}

private func savePNG(_ image: CGImage, at url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw ExportError.message("Cannot create PNG \(url.lastPathComponent)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ExportError.message("Cannot save PNG") }
}

private func nearestImage(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
    guard let context = CGContext(data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4, space: SceneRenderer.colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
        throw ExportError.message("Cannot create native-size proof")
    }
    context.interpolationQuality = .none
    context.setShouldAntialias(false)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func contactSheet(_ frames: [(Double, CGImage, String)], output: URL) throws {
    let width = 1200, columns = 3, cellWidth = 384, cellHeight = 224, gap = 12
    let rows = (frames.count + columns - 1) / columns
    let height = rows * (cellHeight + gap) + gap
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
    NSGraphicsContext.current?.imageInterpolation = .none
    for (index, item) in frames.enumerated() {
        let x = gap + (index % columns) * (cellWidth + gap)
        let y = height - gap - (index / columns + 1) * cellHeight - (index / columns) * gap
        NSImage(cgImage: item.1, size: NSSize(width: 1152, height: 576))
            .draw(in: CGRect(x: x, y: y, width: cellWidth, height: 192))
        String(format: "%.2fs · %@", item.0, item.2).draw(
            at: CGPoint(x: x + 8, y: y + 200), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.darkGray
            ])
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output)
}

private func writeMovie(renderer: SceneRenderer, output: URL, logicalCrop: CGRect? = nil,
                        start: Double = 0, duration: Double = SceneRenderer.duration,
                        options: [String: Any] = [:]) throws {
    let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    let sourceCrop = logicalCrop.map {
        CGRect(x: $0.minX * CGFloat(SceneRenderer.scale), y: $0.minY * CGFloat(SceneRenderer.scale),
               width: $0.width * CGFloat(SceneRenderer.scale), height: $0.height * CGFloat(SceneRenderer.scale))
    }
    let width = sourceCrop.map { Int($0.width) } ?? SceneRenderer.logicalWidth * SceneRenderer.scale
    let height = sourceCrop.map { Int($0.height) } ?? SceneRenderer.logicalHeight * SceneRenderer.scale
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000,
                                          AVVideoExpectedSourceFrameRateKey: SceneRenderer.fps]
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
        sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                     kCVPixelBufferWidthKey as String: width,
                                     kCVPixelBufferHeightKey as String: height])
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? ExportError.message("Cannot start movie") }
    writer.startSession(atSourceTime: .zero)
    let count = Int(duration * Double(SceneRenderer.fps))
    for index in 0..<count {
        while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
        let time = start + Double(index) / Double(SceneRenderer.fps)
        let wholeFrame = try renderer.frame(at: time, options: options).0
        let frame: CGImage
        if let sourceCrop {
            guard let cropped = wholeFrame.cropping(to: sourceCrop) else {
                throw ExportError.message("Invalid movie closeup crop")
            }
            frame = cropped
        } else { frame = wholeFrame }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        guard let pixelBuffer else { throw ExportError.message("Cannot create movie buffer") }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: SceneRenderer.colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        context.interpolationQuality = .none
        context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: SceneRenderer.fps)) else {
            throw writer.error ?? ExportError.message("Cannot append movie frame \(index)")
        }
    }
    input.markAsFinished()
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    finished.wait()
    guard writer.status == .completed else { throw writer.error ?? ExportError.message("Movie did not complete") }
}

private func comparisonImage(_ images: [(String, CGImage)], output: URL) throws {
    let gap = 24, cellWidth = 384, top = 34, bottom = 12, height = 190
    let width = images.count * cellWidth + (images.count + 1) * gap
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
    NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
    NSGraphicsContext.current?.imageInterpolation = .none
    for (index, item) in images.enumerated() {
        let x = gap + index * (cellWidth + gap)
        item.0.draw(at: CGPoint(x: x, y: height - top + 6), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.darkGray])
        NSImage(cgImage: item.1, size: NSSize(width: 384, height: 144))
            .draw(in: CGRect(x: x, y: bottom, width: cellWidth, height: 144))
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output)
}

@main
private struct RenderMotion {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let root = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath, isDirectory: true)
        let stillsOnly = arguments.contains("--stills-only")
        let dark = arguments.contains("--dark")
        let full = arguments.contains("--full")
        let outputRoot: URL
        if let index = arguments.firstIndex(of: "--output"), arguments.indices.contains(index + 1) {
            outputRoot = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else { outputRoot = root }
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let renderer = try SceneRenderer(root: root, dark: dark)
        let times = [0.0, 2.0, 3.9, 4.0, 4.5, 5.0, 5.5, 6.0, 8.0, 10.0, 11.8]
        let suffix = dark ? "-dark" : ""
        let keyframes = outputRoot.appendingPathComponent("keyframes" + suffix, isDirectory: true)
        let closeups = outputRoot.appendingPathComponent("closeups" + suffix, isDirectory: true)
        let nativeProofs = outputRoot.appendingPathComponent("native-proofs" + suffix, isDirectory: true)
        for directory in [keyframes, closeups, nativeProofs] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var frames: [(Double, CGImage, String)] = []
        var states: [[String: Any]] = []
        let logicalCrop = CGRect(x: 0, y: 48, width: 384, height: 144)
        let sourceCrop = CGRect(x: 0, y: 144, width: 1152, height: 432)
        for time in times {
            let (image, scene) = try renderer.frame(at: time)
            let name = String(format: "frame-%05.2f.png", time)
            try savePNG(image, at: keyframes.appendingPathComponent(name))
            if let closeup = image.cropping(to: sourceCrop) {
                try savePNG(closeup, at: closeups.appendingPathComponent(name))
                try savePNG(nearestImage(closeup, width: 384, height: 144),
                            at: nativeProofs.appendingPathComponent(name))
            }
            let opacity = (scene["gardenOpacity"] as? NSNumber)?.doubleValue ?? -1
            let label = opacity >= 0.999 ? "完整组合" : (opacity <= 0.001 ? "仅花朵常驻" : "藤蔓淡出")
            frames.append((time, image, label))
            states.append(["time": time, "gardenOpacity": opacity,
                           "commandCount": (scene["commands"] as? [Any])?.count ?? 0])
        }
        try contactSheet(frames, output: outputRoot.appendingPathComponent("contact-sheet" + suffix + ".png"))
        try JSONSerialization.data(withJSONObject: states, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputRoot.appendingPathComponent("state-checks" + suffix + ".json"))

        // Compare visibility at the identical clock time. Only the garden layer
        // changes; the accepted flower position and movement remain continuous.
        var comparison: [(String, CGImage)] = []
        for (mode, label) in [("all", "完整组合 · 常驻大小"), ("flowers", "仅花朵常驻 · 相同时间") ] {
            let (image, _) = try renderer.frame(at: 8, options: ["visibility": mode])
            guard let crop = image.cropping(to: sourceCrop) else { throw ExportError.message("Invalid state crop") }
            let native = try nearestImage(crop, width: 384, height: 144)
            try savePNG(crop, at: outputRoot.appendingPathComponent("state-" + mode + suffix + ".png"))
            try savePNG(native, at: outputRoot.appendingPathComponent("state-" + mode + "-native" + suffix + ".png"))
            comparison.append((label, native))
        }
        try comparisonImage(comparison, output: outputRoot.appendingPathComponent("comparison-native" + suffix + ".png"))

        if !stillsOnly {
            var versions: [(String, CGRect?)] = [("final-garden-transition" + suffix, logicalCrop)]
            if full { versions.append(("final-garden-full" + suffix, nil)) }
            for (name, crop) in versions {
                let movie = outputRoot.appendingPathComponent(name + ".mp4")
                if FileManager.default.fileExists(atPath: movie.path) { try FileManager.default.removeItem(at: movie) }
                try writeMovie(renderer: renderer, output: movie, logicalCrop: crop)
                let asset = AVURLAsset(url: movie)
                let duration = try await asset.load(.duration)
                let video = try await asset.loadTracks(withMediaType: .video)
                let audio = try await asset.loadTracks(withMediaType: .audio)
                let naturalSize = try await video.first!.load(.naturalSize)
                let frameRate = try await video.first!.load(.nominalFrameRate)
                let visible = crop ?? CGRect(x: 0, y: 0, width: 384, height: 192)
                let metadata: [String: Any] = ["duration": CMTimeGetSeconds(duration),
                    "width": naturalSize.width, "height": naturalSize.height,
                    "fps": frameRate, "audioTracks": audio.count,
                    "sourceStartTime": 0, "sourceEndTime": SceneRenderer.duration,
                    "sourceLogicalWidth": 384, "sourceLogicalHeight": 192,
                    "visibleLogicalRect": ["x": visible.minX, "y": visible.minY,
                                           "width": visible.width, "height": visible.height],
                    "renderer": "Frozen flower engine + combined garden wrapper, CoreGraphics nearest-neighbor pixels"]
                let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                let metadataName = name.replacingOccurrences(of: "final-garden-transition", with: "metadata") + ".json"
                try data.write(to: outputRoot.appendingPathComponent(metadataName))
                print(String(data: data, encoding: .utf8)!)
                print("Movie: \(movie.path)")
                let mediaChecks = outputRoot.appendingPathComponent("media-checks", isDirectory: true)
                try FileManager.default.createDirectory(at: mediaChecks, withIntermediateDirectories: true)
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                for sample in [0.0, 2.0, 4.0, 5.0, 6.0, 8.0, 10.0, 11.8] {
                    let frameIndex = Int64((sample * Double(SceneRenderer.fps)).rounded())
                    let time = CMTime(value: frameIndex, timescale: SceneRenderer.fps)
                    let image = try generator.copyCGImage(at: time, actualTime: nil)
                    try savePNG(image, at: mediaChecks.appendingPathComponent(
                        String(format: "%@-%05.2fs.png", name, CMTimeGetSeconds(time))))
                }
            }
        }
        print("Contact sheet: \(outputRoot.path)")
    }
}
