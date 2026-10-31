import AppKit
import Combine
import ImageIO
import SwiftUI

/// Small independent windows keep the flower layer present while the vine sleeps.
/// Only opaque artwork accepts clicks; every transparent gap passes through.
@MainActor
final class DeadlineFlowerController {
    private let garden: DeadlineGarden
    private let onFiles: ([URL]) -> Void
    private let screenFrame: () -> NSRect
    private var flowers: [(deadline: GardenDeadline, panel: NSPanel, view: DeadlineFlowerView)] = []
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var popover: NSPopover?
    private var hoveredID: String?
    private var visible = true

    init(garden: DeadlineGarden,
         screenFrame: @escaping () -> NSRect = { NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900) },
         onFiles: @escaping ([URL]) -> Void) {
        self.garden = garden
        self.onFiles = onFiles
        self.screenFrame = screenFrame
        observation = garden.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.synchronize() }
        }
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        synchronize()
    }

    func setVisible(_ value: Bool) {
        visible = value
        if value { synchronize() }
        else {
            closeDetails()
            flowers.forEach { $0.panel.orderOut(nil) }
        }
    }

    func reposition() {
        let area = screenFrame()
        for (index, flower) in flowers.enumerated() {
            let artwork = CompactFlowerArtwork.plants[index]
            flower.panel.setFrameOrigin(NSPoint(
                x: area.maxX - 300 + artwork.rootX - artwork.stemX,
                y: area.minY
            ))
        }
        closeDetails()
    }

    func stop() {
        observation?.cancel()
        observation = nil
        timer?.invalidate()
        timer = nil
        closeDetails()
        flowers.forEach { $0.panel.orderOut(nil) }
        flowers = []
    }

    private func synchronize() {
        closeDetails()
        flowers.forEach { $0.panel.orderOut(nil) }
        flowers = garden.visibleDeadlines.enumerated().map { index, deadline in
            let artwork = CompactFlowerArtwork.plants[index]
            let view = DeadlineFlowerView(artwork: artwork)
            view.onHarvest = { [weak self] in self?.garden.harvest(id: deadline.id) }
            view.onFiles = onFiles
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.button)
            view.setAccessibilityLabel("\(deadline.title)，\(deadline.dueDate)，项目：\(deadline.project)；点击收获并完成")
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: artwork.size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = true
            panel.contentView = view
            if visible { panel.orderFrontRegardless() }
            return (deadline, panel, view)
        }
        reposition()
        updatePointer()
    }

    private func updatePointer() {
        guard visible else { return }
        let mouse = NSEvent.mouseLocation
        var hovered: (deadline: GardenDeadline, panel: NSPanel, view: DeadlineFlowerView)?
        for flower in flowers {
            let local = NSPoint(x: mouse.x - flower.panel.frame.minX,
                                y: mouse.y - flower.panel.frame.minY)
            let hit = flower.view.containsArtwork(local)
            flower.panel.ignoresMouseEvents = !hit && !flower.view.isPressed
            if hit { hovered = flower }
        }
        // The details remain readable when the pointer crosses from flower to card.
        if hovered == nil, let frame = popover?.contentViewController?.view.window?.frame,
           frame.insetBy(dx: -8, dy: -8).contains(mouse) { return }
        guard let flower = hovered else { closeDetails(); return }
        guard NSEvent.pressedMouseButtons == 0 else { return }
        guard hoveredID != flower.deadline.id else { return }
        closeDetails()
        hoveredID = flower.deadline.id
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView:
            DeadlineFlowerDetailsView(deadline: flower.deadline, queuedCount: garden.queuedCount))
        self.popover = popover
        // Anchor to the stem's side so the card never covers the flower head.
        popover.show(relativeTo: NSRect(x: 0, y: flower.view.bounds.midY, width: 1, height: 1),
                     of: flower.view, preferredEdge: .minX)
    }

    private func closeDetails() {
        popover?.close()
        popover = nil
        hoveredID = nil
    }
}

struct CompactFlowerArtwork {
    let image: CGImage
    let size: CGSize
    let rootX: CGFloat
    let stemX: CGFloat
    let alpha: [UInt8]

    static let plants: [CompactFlowerArtwork] = {
        let bundle: Bundle
        if let url = Bundle.main.url(forResource: "FilePetShell_FilePetShell", withExtension: "bundle"),
           let installed = Bundle(url: url) { bundle = installed }
        else { bundle = Bundle.module }
        guard let url = bundle.url(forResource: "Compact", withExtension: "png", subdirectory: "Flowers"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            preconditionFailure("Missing compact garden artwork")
        }
        let placements: [(CGRect, CGFloat, CGFloat, CGFloat, Int)] = [
            (CGRect(x: 187, y: 350, width: 399, height: 501), 0.165, 34, 395 - 187, 566),
            (CGRect(x: 677, y: 72, width: 485, height: 779), 0.187, 131, 873 - 677, 448),
            (CGRect(x: 1296, y: 340, width: 401, height: 511), 0.175, 246, 1493 - 1296, 660),
        ]
        return placements.map { crop, scale, rootX, stemX, foliageStart in
            guard let image = sheet.cropping(to: crop) else { preconditionFailure("Invalid compact flower crop") }
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            pixels.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            // Match the confirmed preview's foliage treatment while keeping
            // every petal and the exact alpha/hit mask unchanged.
            for y in max(0, foliageStart - Int(crop.minY))..<image.height {
                for x in 0..<image.width {
                    let offset = (y * image.width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let red = Double(pixels[offset]) / 255 / alpha
                    let green = Double(pixels[offset + 1]) / 255 / alpha
                    let blue = Double(pixels[offset + 2]) / 255 / alpha
                    let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
                    for (channel, value) in [red, green, blue].enumerated() {
                        let saturated = luminance + (value - luminance) * 0.55
                        let treated = ((saturated * 0.98 - 0.5) * 0.92 + 0.5)
                        pixels[offset + channel] = UInt8((min(1, max(0, treated)) * alpha * 255).rounded())
                    }
                }
            }
            let provider = CGDataProvider(data: Data(pixels) as CFData)!
            let displayImage = CGImage(width: image.width, height: image.height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            return CompactFlowerArtwork(image: displayImage,
                size: CGSize(width: crop.width * scale, height: crop.height * scale),
                rootX: rootX, stemX: stemX * scale, alpha: pixels)
        }
    }()
}

final class DeadlineFlowerView: NSView {
    let artwork: CompactFlowerArtwork
    var onHarvest: (() -> Void)?
    var onFiles: (([URL]) -> Void)?
    private var press: NSPoint?
    var isPressed: Bool { press != nil }

    init(artwork: CompactFlowerArtwork) {
        self.artwork = artwork
        super.init(frame: NSRect(origin: .zero, size: artwork.size))
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: artwork.image, size: artwork.size).draw(in: bounds)
    }

    func containsArtwork(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        let x = min(artwork.image.width - 1, Int(point.x / bounds.width * CGFloat(artwork.image.width)))
        let y = min(artwork.image.height - 1, Int((bounds.height - point.y) / bounds.height * CGFloat(artwork.image.height)))
        return artwork.alpha[(y * artwork.image.width + x) * 4 + 3] > 32
    }

    override func hitTest(_ point: NSPoint) -> NSView? { containsArtwork(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { press = convert(event.locationInWindow, from: nil) }
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let origin = press
        press = nil
        guard let origin, hypot(point.x - origin.x, point.y - origin.y) < 6, containsArtwork(point) else { return }
        onHarvest?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onHarvest else { return false }
        onHarvest()
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.fileURLs(sender).isEmpty ? [] : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { !Self.fileURLs(sender).isEmpty }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        press = nil
        let files = Self.fileURLs(sender)
        guard !files.isEmpty else { return false }
        onFiles?(files)
        return true
    }

    private static func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty { return urls }
        let names = sender.draggingPasteboard.propertyList(forType:
            NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []
        return names.map { URL(fileURLWithPath: $0) }
    }
}
