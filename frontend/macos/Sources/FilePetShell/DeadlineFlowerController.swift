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
    private var flowers: [(deadline: GardenDeadline, panel: NSPanel, view: DeadlineFlowerView, slot: Int)] = []
    private var observation: AnyCancellable?
    private var timer: Timer?
    private var stageTimer: Timer?
    private var windTimer: Timer?
    private var clockObservers: [(NotificationCenter, NSObjectProtocol)] = []
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
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        self.timer = timer
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        let stageTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.garden.refreshTime() }
        }
        stageTimer.tolerance = 2
        self.stageTimer = stageTimer
        RunLoop.main.add(stageTimer, forMode: .common)
        let workspace = NSWorkspace.shared.notificationCenter
        clockObservers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.garden.refreshTime() } }))
        for name in ["NSSystemClockDidChangeNotification", "NSSystemTimeZoneDidChangeNotification",
                     "NSCalendarDayChangedNotification"] {
            clockObservers.append((.default, NotificationCenter.default.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.garden.refreshTime() } }))
        }
        garden.refreshTime()
        synchronize()
        scheduleWind()
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
        for flower in flowers {
            let artwork = CompactFlowerArtwork.plants[flower.slot]
            flower.panel.setFrameOrigin(NSPoint(
                x: area.maxX - 300 + artwork.rootX - artwork.stemX,
                y: area.minY
            ))
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
        timer?.invalidate()
        timer = nil
        stageTimer?.invalidate()
        stageTimer = nil
        windTimer?.invalidate()
        windTimer = nil
        clockObservers.forEach { $0.0.removeObserver($0.1) }
        clockObservers.removeAll()
        closeDetails()
        flowers.forEach { $0.panel.orderOut(nil) }
        flowers = []
    }

    private func synchronize() {
        let desired = garden.visibleDeadlines
        let desiredIDs = Set(desired.map(\.id))
        let existing = Dictionary(uniqueKeysWithValues: flowers.map { ($0.deadline.id, $0) })
        var next: [(deadline: GardenDeadline, panel: NSPanel, view: DeadlineFlowerView, slot: Int)] = []
        var reserved = Set<Int>()
        // Keep slots and NSPanel instances for unchanged deadline IDs.
        for deadline in desired {
            if let previous = existing[deadline.id] {
                previous.view.deadlineStage = garden.stage(for: deadline)
                previous.view.setAccessibilityLabel("\(deadline.title)，\(deadline.dueDate)")
                reserved.insert(previous.slot)
                next.append((deadline, previous.panel, previous.view, previous.slot))
            }
        }
        for deadline in desired where existing[deadline.id] == nil {
            guard let slot = (0..<3).first(where: { !reserved.contains($0) }) else { continue }
            reserved.insert(slot)
            let artwork = CompactFlowerArtwork.plants[slot]
            let view = DeadlineFlowerView(artwork: artwork)
            view.deadlineStage = garden.stage(for: deadline)
            view.onHarvest = { [weak self] in self?.requestHarvest(id: deadline.id) }
            view.onFiles = onFiles
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.button)
            view.setAccessibilityLabel("\(deadline.title)，\(deadline.dueDate)，点击确认完成")
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
            next.append((deadline, panel, view, slot))
        }
        let removed = flowers.filter { !desiredIDs.contains($0.deadline.id) }
        if let id = hoveredID, !desiredIDs.contains(id) { closeDetails() }
        flowers = next
        reposition()
        for flower in next where existing[flower.deadline.id] == nil {
            guard visible else { continue }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { flower.panel.alphaValue = 0 }
            flower.panel.orderFrontRegardless()
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { continue }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                flower.panel.animator().alphaValue = 1
            }
        }
        for flower in removed {
            flower.view.stopGust()
            flower.panel.ignoresMouseEvents = true
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                flower.panel.orderOut(nil)
            } else {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.20
                    flower.panel.animator().alphaValue = 0
                }, completionHandler: {
                    flower.panel.orderOut(nil)
                })
            }
        }
        updatePointer()
    }

    private func scheduleWind() {
        windTimer?.invalidate()
        let interval = Double.random(in: 7...15)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.visible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    for flower in self.flowers {
                        let phase = Double(flower.slot) * 0.13
                        DispatchQueue.main.asyncAfter(deadline: .now() + phase) { [weak self] in
                            MainActor.assumeIsolated {
                                guard let self, self.flowers.contains(where: { $0.deadline.id == flower.deadline.id }) else { return }
                                flower.view.startGust(strength: CGFloat.random(in: -0.85...0.85))
                            }
                        }
                    }
                }
                self.scheduleWind()
            }
        }
        timer.tolerance = 0.8
        windTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func requestHarvest(id: String) {
        guard garden.visibleDeadlines.contains(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "确认任务已完成并采摘花朵？"
        alert.informativeText = "逾期不会自动完成。误操作可通过菜单撤销最近一次采摘。"
        alert.addButton(withTitle: "确认完成")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { garden.harvest(id: id) }
    }

    private func updatePointer() {
        guard visible else { return }
        let mouse = NSEvent.mouseLocation
        var hovered: (deadline: GardenDeadline, panel: NSPanel, view: DeadlineFlowerView, slot: Int)?
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
        flower.view.startGust(strength: 0.18)
        hoveredID = flower.deadline.id
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView:
            DeadlineFlowerDetailsView(deadline: flower.deadline, queuedCount: garden.queuedCount,
                stage: garden.stage(for: flower.deadline), now: garden.currentTime,
                onOpenSource: { [path = flower.deadline.sourcePath] in
                    guard let path else { return }
                    NSWorkspace.shared.open(URL(fileURLWithPath: path))
                }))
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
    var deadlineStage: DeadlineStage? {
        didSet {
            guard oldValue != deadlineStage else { return }
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, oldValue != nil {
                previousStage = oldValue
                transitionStart = Date()
                startFrames(duration: 0.34)
            } else { previousStage = nil }
            needsDisplay = true
        }
    }
    private var previousStage: DeadlineStage?
    private var transitionStart: Date?
    private var gustStart: Date?
    private var gustStrength: CGFloat = 0
    private var frames: Timer?

    func startGust(strength: CGFloat) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        gustStrength = strength
        gustStart = Date()
        startFrames(duration: 2.5)
    }

    func stopGust() {
        gustStart = nil
        frames?.invalidate()
        frames = nil
    }

    private func startFrames(duration: TimeInterval) {
        if frames != nil { return }
        let timer = Timer(timeInterval: 1.0 / 24.0, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let now = Date()
                let gusting = self.gustStart.map { now.timeIntervalSince($0) < 2.5 } ?? false
                let changing = self.transitionStart.map { now.timeIntervalSince($0) < 0.34 } ?? false
                if !gusting { self.gustStart = nil }
                if !changing { self.previousStage = nil; self.transitionStart = nil }
                self.needsDisplay = true
                if !gusting && !changing { timer.invalidate(); self.frames = nil }
            }
        }
        timer.tolerance = 0.004
        frames = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func force(lag: TimeInterval) -> CGFloat {
        guard let started = gustStart,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return 0 }
        let t = Date().timeIntervalSince(started) - lag
        if t < 0 || t >= 2.35 { return 0 }
        let shape: Double
        if t < 0.23 {
            let v = t / 0.23
            shape = v * v * (3 - 2 * v)
        } else if t < 1.45 {
            let v = (t - 0.23) / 1.22
            shape = 1 - v * v * (3 - 2 * v)
        } else {
            let v = t - 1.45
            shape = -0.22 * sin(v * 12.5) * exp(-v * 6)
        }
        return gustStrength * CGFloat(shape)
    }

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
        if let stage = deadlineStage, DeadlineFlowerMotion.heads.count == 6 {
            let stem = force(lag: 0), head = force(lag: 0.115)
            let petals = (force(lag: 0.17), force(lag: 0.20), force(lag: 0.235))
            if let previousStage, let start = transitionStart {
                let elapsed = Date().timeIntervalSince(start)
                // Calyx-anchored upward reveal, no blurry full-flower crossfade.
                _ = DeadlineFlowerMotion.draw(bounds: bounds, artwork: artwork, stage: previousStage,
                    stem: stem, head: head, petals: petals)
                let portion = min(1, max(0, elapsed / 0.34))
                let context = NSGraphicsContext.current?.cgContext
                context?.saveGState()
                context?.clip(to: CGRect(x: 0, y: bounds.height * (0.35 + 0.65 * (1 - portion)),
                                         width: bounds.width, height: bounds.height * portion))
                _ = DeadlineFlowerMotion.draw(bounds: bounds, artwork: artwork, stage: stage,
                    stem: stem, head: head, petals: petals)
                context?.restoreGState()
            } else {
                _ = DeadlineFlowerMotion.draw(bounds: bounds, artwork: artwork, stage: stage,
                    stem: stem, head: head, petals: petals)
            }
            return
        }
        NSImage(cgImage: artwork.image, size: artwork.size).draw(in: bounds)
    }

    func containsArtwork(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        if let stage = deadlineStage, DeadlineFlowerMotion.heads.count == 6 {
            return DeadlineFlowerMotion.hit(point, bounds: bounds, artwork: artwork,
                stage: stage, stem: force(lag: 0), head: force(lag: 0.115))
        }
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
