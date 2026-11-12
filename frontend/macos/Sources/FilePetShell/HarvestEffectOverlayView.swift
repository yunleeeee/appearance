import AppKit

/// Click-through canvas wider than the flower's own compact NSPanel.
/// The original flower panel keeps its identity, position and input geometry.
@MainActor
final class HarvestEffectOverlayView: NSView {
    static let bleed: CGFloat = 120

    private weak var source: DeadlineFlowerView?
    private let sourceSize: CGSize
    private let frozenStage: DeadlineStage?
    private let plantSnapshot: HarvestSlashEffect.PlantSnapshot?
    private var frames: Timer?

    init(flower: DeadlineFlowerView) {
        source = flower
        sourceSize = flower.bounds.size
        frozenStage = flower.deadlineStage
        // Freeze the full native sprite before the source view enters harvest
        // mode. The cached image includes crown, leaves, stem and ground root.
        if let stage = flower.deadlineStage {
            plantSnapshot = HarvestSlashEffect.makeSnapshot(
                in: flower.bounds, stage: stage,
                artwork: flower.artwork, crownScale: flower.crownScale,
                pose: flower.plantPose)
        } else {
            plantSnapshot = nil
        }
        super.init(frame: CGRect(x: 0, y: 0,
            width: flower.bounds.width + Self.bleed * 2,
            height: flower.bounds.height + 28))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { false }

    func start() {
        guard frames == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.source?.isHarvesting == true else {
                    timer.invalidate()
                    self?.frames = nil
                    return
                }
                self.needsDisplay = true
            }
        }
        timer.tolerance = 0.003
        frames = timer
        RunLoop.main.add(timer, forMode: .common)
        needsDisplay = true
    }

    func stop() {
        frames?.invalidate()
        frames = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let flower = source, let stage = frozenStage,
              let age = flower.previewHarvestAge ?? flower.harvestAge,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        // Geometry and the original atlas remain in the flower's local space.
        // Only the sword-light canvas is extended horizontally.
        ctx.translateBy(x: Self.bleed, y: 0)
        HarvestSlashEffect.draw(in: CGRect(origin: .zero, size: sourceSize),
            stage: stage, artwork: flower.artwork,
            crownScale: flower.crownScale, pose: flower.plantPose,
            age: age, reduceMotion: false, snapshot: plantSnapshot)
        ctx.restoreGState()
    }
}
