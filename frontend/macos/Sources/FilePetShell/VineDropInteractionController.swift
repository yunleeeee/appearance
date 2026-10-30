import AppKit

/// 只在本轮按下后确实拖动时解锁；普通点击与轻微手抖保持穿透。
struct VineDragGate {
    private var pressOrigin: CGPoint?
    private var waitsForRelease = false
    private(set) var acceptsDrops = false

    mutating func update(leftMouseDown: Bool, location: CGPoint) {
        guard leftMouseDown else {
            pressOrigin = nil
            waitsForRelease = false
            acceptsDrops = false
            return
        }
        guard !waitsForRelease else { return }
        guard let pressOrigin else {
            self.pressOrigin = location
            return
        }
        if hypot(location.x - pressOrigin.x, location.y - pressOrigin.y) >= 6 {
            acceptsDrops = true
        }
    }

    mutating func finish() {
        pressOrigin = nil
        waitsForRelease = true
        acceptsDrops = false
    }

    mutating func beginDragging() {
        guard !waitsForRelease else { return }
        acceptsDrops = true
    }
}

/// 普通点击交给下层窗口，拖动期间才开启 AppKit 拖放目标。
/// 文件类型由真实拖拽会话判断；不读取剪贴板或监听键盘。
@MainActor
final class VineDropInteractionController {
    private weak var panel: NSPanel?
    private var gate = VineDragGate()
    private var timer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private let onSessionEnded: (() -> Void)?
    private var eventPressLocation: CGPoint?
    private var lastPointerEventTime = Date.distantPast
    private var releaseTimer: Timer?

    init(panel: NSPanel, onSessionEnded: (() -> Void)? = nil) {
        self.panel = panel
        self.onSessionEnded = onSessionEnded
        panel.ignoresMouseEvents = true
    }

    func start() {
        guard timer == nil else { return }
        finishSession()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        timer.tolerance = 0.01
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)

        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointerEvent(event, local: false) }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            MainActor.assumeIsolated { self?.handlePointerEvent(event, local: true) }
            return event
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        finishSession()
    }

    /// 成功投放、取消、隐藏挂件及松手时均可立即恢复穿透。
    func finishSession() {
        let wasAccepting = gate.acceptsDrops
        releaseTimer?.invalidate()
        releaseTimer = nil
        eventPressLocation = nil
        gate.finish()
        panel?.ignoresMouseEvents = true
        if wasAccepting { onSessionEnded?() }
    }

    private func update() {
        guard let panel, panel.isVisible else {
            finishSession()
            return
        }
        let wasAccepting = gate.acceptsDrops
        let physicallyPressed = NSEvent.pressedMouseButtons & 1 != 0
        // 松手到原生投放消息之间留一个短暂窗口；成功/取消回调会提前释放。
        if !physicallyPressed && releaseTimer != nil { return }
        // 事件流补足瞬时状态采样；短暂容差也支持系统合成的拖拽事件。
        let recentEventPress = eventPressLocation != nil && Date().timeIntervalSince(lastPointerEventTime) < 0.25
        let location = physicallyPressed ? NSEvent.mouseLocation : (eventPressLocation ?? NSEvent.mouseLocation)
        gate.update(leftMouseDown: physicallyPressed || recentEventPress, location: location)
        panel.ignoresMouseEvents = !gate.acceptsDrops
        if wasAccepting && !gate.acceptsDrops { onSessionEnded?() }
    }

    private func handlePointerEvent(_ event: NSEvent, local: Bool) {
        guard let panel, panel.isVisible else { return }
        if event.type == .leftMouseUp {
            eventPressLocation = nil
            if gate.acceptsDrops {
                releaseTimer?.invalidate()
                let timer = Timer(timeInterval: 0.08, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finishSession() }
                }
                releaseTimer = timer
                RunLoop.main.add(timer, forMode: .common)
            } else {
                finishSession()
            }
            return
        }
        let location = local
            ? (event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation)
            : NSEvent.mouseLocation
        eventPressLocation = location
        lastPointerEventTime = Date()
        if event.type == .leftMouseDown {
            releaseTimer?.invalidate()
            releaseTimer = nil
            gate.update(leftMouseDown: false, location: location)
        }
        gate.update(leftMouseDown: true, location: location)
        if event.type == .leftMouseDragged { gate.beginDragging() }
        panel.ignoresMouseEvents = !gate.acceptsDrops
    }
}
