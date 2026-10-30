import AppKit
import Combine
import SwiftUI

/// 应用入口：创建悬浮葡萄藤面板（NSPanel）与菜单栏（NSStatusItem）。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let store = ShellStore()
    private var vinePanel: NSPanel?
    private var statusItem: NSStatusItem?
    private var dropInteraction: VineDropInteractionController?
    private var theftOverlay: TheftOverlayController?
    private var petVisible = true
    private var cancellables = Set<AnyCancellable>()
    private weak var engineMenuItem: NSMenuItem?
    private weak var summaryMenuItem: NSMenuItem?
    private weak var classifyMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createVineWindow()
        createMenuBar()
        createApplicationMenu()
        theftOverlay = TheftOverlayController(model: store.vine)
        store.refreshConnection()
        store.$status.sink { [weak self] text in
            self?.statusItem?.button?.toolTip = text
        }.store(in: &cancellables)

        store.vine.$activeTheft
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self, let panel = self.vinePanel else { return }
                self.theftOverlay?.present(self.petVisible ? event : nil, attachedTo: panel)
            }
            .store(in: &cancellables)

        store.$petVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                self?.setPanelVisible(visible)
            }
            .store(in: &cancellables)
    }

    // MARK: - 悬浮葡萄藤面板

    private func createVineWindow() {
        let size = VineView.size
        let width = size.width
        let height = size.height

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        // 感应区域跟随横向葡萄藤面板尺寸，保留透明背景。
        let hosting = VineHostingView(rootView: VineView(model: store.vine))
        hosting.onTargeted = { [weak self] targeted in
            guard let self = self else { return }
            if targeted {
                self.store.vine.wake()      // 淡入 → swaying
            } else {
                self.store.vine.calmDown()  // 短暂停留后淡出
            }
        }
        hosting.onFiles = { [weak self] urls in
            guard let self = self else { return }
            // 立即切换到 receiving 状态（开始摆动/葡萄生长准备）
            self.store.classifyFiles(urls)
        }
        hosting.onDragSessionEnded = { [weak self] in
            self?.dropInteraction?.finishSession()
        }
        panel.contentView = hosting

        positionPanel(panel, width: width, height: height, force: true)
        panel.orderFrontRegardless()
        vinePanel = panel
        let interaction = VineDropInteractionController(panel: panel) { [weak hosting] in
            hosting?.endTargeting()
        }
        dropInteraction = interaction
        interaction.start()

        // 屏幕参数变化时把面板拉回可见区域
        NotificationCenter.default
            .addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let panel = self?.vinePanel else { return }
                    self?.theftOverlay?.dismiss()
                    self?.store.vine.setTheftPresentationEnabled(false)
                    self?.positionPanel(panel, width: width, height: height, force: false)
                    self?.store.vine.setTheftPresentationEnabled(self?.petVisible ?? false)
                }
            }
    }

    /// 主屏右上角，藤蔓从屏幕右缘伸出，位于菜单栏下方。
    private func positionPanel(_ panel: NSPanel, width: CGFloat, height: CGFloat, force: Bool) {
        let frame = panel.frame

        if !force {
            let onScreen = NSScreen.screens.contains { screen in
                screen.visibleFrame.intersects(frame)
            }
            if onScreen { return }
        }

        let area = NSScreen.main?.visibleFrame ?? NSRect(
            x: 0, y: 0, width: 1440, height: 900
        )
        panel.setFrameOrigin(NSPoint(
            x: area.maxX - width,
            y: area.maxY - height - 16
        ))
    }

    private func setPanelVisible(_ visible: Bool) {
        petVisible = visible
        store.vine.setTheftPresentationEnabled(visible)
        if visible {
            vinePanel?.orderFrontRegardless()
        } else {
            theftOverlay?.dismiss()
            dropInteraction?.finishSession()
            vinePanel?.orderOut(nil)
        }
    }

    // MARK: - 菜单栏

    private func createApplicationMenu() {
        let main = NSMenu()
        let item = NSMenuItem()
        let commands = NSMenu(title: "葡萄藤")
        let flowers = NSMenuItem(title: "六阶段花朵设计预览 · 常驻", action: nil, keyEquivalent: "")
        commands.addItem(flowers)
        let choose = NSMenuItem(title: "选择文件分类…", action: #selector(chooseFiles), keyEquivalent: "o")
        choose.target = self
        commands.addItem(choose)
        let results = NSMenuItem(title: "查看最近分类结果…", action: #selector(showResults), keyEquivalent: "")
        results.target = self
        commands.addItem(results)
        let preview = NSMenuItem(title: "预览杰瑞偷葡萄", action: #selector(previewTheft), keyEquivalent: "")
        preview.target = self
        commands.addItem(preview)
        commands.addItem(.separator())
        let quit = NSMenuItem(title: "退出葡萄藤", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        commands.addItem(quit)
        item.submenu = commands
        main.addItem(item)
        NSApp.mainMenu = main
    }

    private func createMenuBar() {
        let item = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        let menuIcon = NSImage(
            systemSymbolName: "archivebox.fill",
            accessibilityDescription: "葡萄藤"
        )?.withSymbolConfiguration(.init(pointSize: 18, weight: .regular, scale: .medium))
        menuIcon?.isTemplate = true
        item.button?.image = menuIcon

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let engine = NSMenuItem(title: store.connectionStatus, action: nil, keyEquivalent: "")
        engine.isEnabled = false
        menu.addItem(engine)
        engineMenuItem = engine
        let summary = NSMenuItem(title: store.status, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        summaryMenuItem = summary
        let flowers = NSMenuItem(title: "六阶段花朵设计预览 · 常驻", action: nil, keyEquivalent: "")
        flowers.isEnabled = false
        menu.addItem(flowers)
        menu.addItem(.separator())
        let choose = NSMenuItem(title: "选择文件分类…", action: #selector(chooseFiles), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)
        classifyMenuItem = choose
        let reconnect = NSMenuItem(title: "重新连接分类引擎", action: #selector(reconnectEngine), keyEquivalent: "")
        reconnect.target = self
        menu.addItem(reconnect)
        let detail = NSMenuItem(title: "查看最近分类结果…", action: #selector(showResults), keyEquivalent: "")
        detail.target = self
        menu.addItem(detail)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: "显示/隐藏葡萄藤",
            action: #selector(toggleVine),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let preview = NSMenuItem(
            title: "预览葡萄藤",
            action: #selector(previewVine),
            keyEquivalent: ""
        )
        preview.target = self
        menu.addItem(preview)

        let theftPreview = NSMenuItem(
            title: "预览杰瑞偷葡萄",
            action: #selector(previewTheft),
            keyEquivalent: ""
        )
        theftPreview.target = self
        menu.addItem(theftPreview)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出葡萄藤",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        engineMenuItem?.title = store.connectionStatus
        summaryMenuItem?.title = store.status
        classifyMenuItem?.isEnabled = !store.isBusy
    }

    @objc private func chooseFiles() { store.chooseFiles() }
    func chooseFilesFromMenu() { store.chooseFiles() }
    @objc private func reconnectEngine() { store.refreshConnection() }
    @objc private func showResults() { store.showResults() }

    @objc private func toggleVine() {
        store.petVisible.toggle()
    }

    @objc private func previewVine() {
        store.petVisible = true
        store.vine.preview()
    }

    @objc func previewTheft() {
        store.petVisible = true
        store.vine.setTheftPresentationEnabled(true)
        store.vine.previewTheft()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
        dropInteraction?.stop()
        theftOverlay?.dismiss()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool { false }
}
