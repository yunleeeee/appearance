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
    private var flowerController: DeadlineFlowerController?
    private var fullScreenMonitor: FullScreenVisibilityMonitor?
    private var fullScreenSuppressed = false
    private var reviewWindowController: ReviewWindowController?
    private var petVisible = true
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store.onShowPendingReviews = { [weak self] in self?.showPendingReviews() }
        createVineWindow()
        flowerController = DeadlineFlowerController(garden: store.garden, screenFrame: { [weak self] in
            // DDL confirmation may occur on another display. Keep flowers with
            // the trellis instead of following the current main window.
            self?.vinePanel?.screen?.frame ?? NSScreen.screens.first?.frame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        }) { [weak self] files in
            self?.store.classifyFiles(files)
        }
        fullScreenMonitor = FullScreenVisibilityMonitor(isFullScreen: { [weak self] in
            // A desktop-only panel joins ordinary Spaces, but not another
            // application's native full-screen Space. This remains meaningful
            // while the panel is ordered out, so restoration cannot self-lock.
            NSApp.currentSystemPresentationOptions.contains(.fullScreen) ||
                self?.vinePanel?.isOnActiveSpace == false
        }) { [weak self] suppressed in
            guard let self else { return }
            self.fullScreenSuppressed = suppressed
            self.flowerController?.setFullScreenSuppressed(suppressed)
            self.setPanelVisible(self.petVisible)
        }
        createMenuBar()
        createApplicationMenu()
        store.startConnectionMonitoring()
        store.$status.sink { [weak self] text in
            self?.statusItem?.button?.toolTip = text
        }.store(in: &cancellables)

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
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary]
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
                    self?.positionPanel(panel, width: width, height: height, force: true)
                    self?.flowerController?.reposition()
                }
            }
    }

    /// 主屏右下角；花层留在屏幕底部，葡萄层位于它上方。
    private func positionPanel(_ panel: NSPanel, width: CGFloat, height: CGFloat, force: Bool) {
        let frame = panel.frame

        if !force {
            let onScreen = NSScreen.screens.contains { screen in
                screen.visibleFrame.intersects(frame)
            }
            if onScreen { return }
        }

        let area = NSScreen.main?.frame ?? NSRect(
            x: 0, y: 0, width: 1440, height: 900
        )
        panel.setFrameOrigin(NSPoint(
            x: area.maxX - width - CGFloat(CompactGardenLayout.rightInset),
            y: area.minY + CGFloat(CompactGardenLayout.bottomInset)
        ))
    }

    private func setPanelVisible(_ visible: Bool) {
        petVisible = visible
        // The trellis may sleep or hide while deadline flowers remain present.
        if visible && !fullScreenSuppressed {
            vinePanel?.orderFrontRegardless()
        } else {
            dropInteraction?.finishSession()
            vinePanel?.orderOut(nil)
        }
    }

    // MARK: - 菜单栏

    private func createApplicationMenu() {
        let main = NSMenu()
        let app = NSMenuItem(title: "FilePet", action: nil, keyEquivalent: "")
        app.submenu = makeCompactMenu()
        main.addItem(app)
        NSApp.mainMenu = main
    }

    private func createMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(
            systemSymbolName: "archivebox.fill", accessibilityDescription: "FilePet"
        )?.withSymbolConfiguration(.init(pointSize: 18, weight: .regular, scale: .medium))
        icon?.isTemplate = true
        item.button?.image = icon
        item.menu = makeCompactMenu()
        statusItem = item
    }

    private func makeCompactMenu() -> NSMenu {
        let menu = NSMenu(title: "FilePet")
        menu.autoenablesItems = false
        menu.delegate = self
        populateCompactMenu(menu)
        return menu
    }

    private func item(_ title: String, action: Selector,
                      key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private var pendingReviewCount: Int {
        store.reviewInbox.items.reduce(0) { $0 + max(1, $1.candidates.count) }
    }

    private func populateCompactMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // A single short status line replaces three independent engine/DDL
        // counters. The status tooltip retains detailed progress information.
        let connected = store.connectionStatus.hasPrefix("分类引擎：已连接")
        let status = NSMenuItem(title: connected ? "FilePet · 已连接" : "FilePet · 未连接",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let open = item("导入文件…", action: #selector(chooseFiles), key: "o")
        open.isEnabled = !store.isBusy
        menu.addItem(open)

        let tasks = NSMenuItem(
            title: "DDL 任务（\(store.garden.activeDeadlines.count)）",
            action: nil, keyEquivalent: ""
        )
        let taskMenu = NSMenu(title: "DDL 任务")
        populateDeadlineMenu(taskMenu)
        tasks.submenu = taskMenu
        menu.addItem(tasks)

        if pendingReviewCount > 0 {
            menu.addItem(item("待确认（\(pendingReviewCount)）…",
                              action: #selector(showPendingReviews)))
        }

        let folderName = store.archive.destination?.lastPathComponent
        let archiveLabel = folderName.map { "归档位置：\($0)…" } ?? "选择归档位置…"
        let archive = item(archiveLabel, action: #selector(chooseArchiveFolder), key: "s")
        archive.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(archive)

        let countItem = NSMenuItem(title: "显示花朵：\(store.garden.visibleLimit) 朵",
                                   action: nil, keyEquivalent: "")
        let countMenu = NSMenu(title: "显示花朵")
        for count in 1...3 {
            let choice = item("\(count) 朵", action: #selector(changeFlowerCount(_:)))
            choice.representedObject = count
            choice.state = store.garden.visibleLimit == count ? .on : .off
            countMenu.addItem(choice)
        }
        countItem.submenu = countMenu
        menu.addItem(countItem)

        menu.addItem(.separator())
        let more = NSMenuItem(title: "更多操作", action: nil, keyEquivalent: "")
        let moreMenu = NSMenu(title: "更多操作")

        let autoOCR = item("自动识别图片 DDL", action: #selector(toggleAutomaticOCR))
        autoOCR.state = store.autoAcceptImageDeadlines ? .on : .off
        moreMenu.addItem(autoOCR)

        let showVine = item("显示葡萄藤", action: #selector(toggleVine))
        showVine.state = store.petVisible ? .on : .off
        moreMenu.addItem(showVine)
        moreMenu.addItem(item("查看最近结果…", action: #selector(showResults)))
        if pendingReviewCount == 0 {
            moreMenu.addItem(item("待确认事项…", action: #selector(showPendingReviews)))
        }
        let undo = item("撤销上次采摘", action: #selector(undoHarvest))
        undo.isEnabled = store.garden.deadlines.contains { $0.completedAt != nil }
        moreMenu.addItem(undo)
        moreMenu.addItem(.separator())
        moreMenu.addItem(item("重新连接引擎", action: #selector(reconnectEngine)))
        if store.archive.destination != nil {
            moreMenu.addItem(item("停止自动移动归档", action: #selector(disableArchive)))
        }
        more.submenu = moreMenu
        menu.addItem(more)

        menu.addItem(.separator())
        menu.addItem(item("退出 FilePet", action: #selector(quitApp), key: "q"))
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateCompactMenu(menu)
    }

    private func populateDeadlineMenu(_ submenu: NSMenu) {
        let tasks = store.garden.activeDeadlines.sorted {
            if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
            if $0.dueTime != $1.dueTime { return ($0.dueTime ?? "zz") < ($1.dueTime ?? "zz") }
            return $0.id < $1.id
        }
        if tasks.isEmpty {
            let empty = NSMenuItem(title: "暂无未完成任务", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        let visible = Set(store.garden.visibleDeadlines.map(\.id))
        for deadline in tasks.prefix(40) {
            let mark = visible.contains(deadline.id) ? "✿ " : ""
            let item = self.item(mark + deadline.title + " · " + deadline.dueDate,
                                 action: #selector(showDeadlineFromMenu(_:)))
            item.representedObject = deadline.id
            submenu.addItem(item)
        }
        if tasks.count > 40 {
            let extra = NSMenuItem(title: "另有 \(tasks.count - 40) 项未展示",
                                   action: nil, keyEquivalent: "")
            extra.isEnabled = false
            submenu.addItem(extra)
        }
    }

    @objc private func changeFlowerCount(_ sender: NSMenuItem) {
        guard let count = sender.representedObject as? Int else { return }
        store.garden.setVisibleLimit(count)
    }

    @objc private func showDeadlineFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let deadline = store.garden.deadlines.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = deadline.title
        alert.informativeText = """
            项目：\(deadline.project)
            截止：\(deadline.dueDate) \(deadline.dueTime ?? "（时间未注明）")
            状态：\(store.garden.stage(for: deadline)?.label ?? "待确认")
            \(deadline.yearInferred ? "年份曾由系统推断，需要核实。\\n" : "")来源：\(deadline.sourcePath.map { FileDisplayName.label(URL(fileURLWithPath: $0).lastPathComponent) } ?? "未知")
            证据：\(deadline.evidence)
            """
        alert.addButton(withTitle: "关闭")
        alert.addButton(withTitle: "编辑截止日期…")
        if deadline.sourcePath != nil { alert.addButton(withTitle: "查看来源") }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            editDeadline(deadline)
        } else if response == .alertThirdButtonReturn, let path = deadline.sourcePath {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private func editDeadline(_ deadline: GardenDeadline) {
        let alert = NSAlert()
        alert.messageText = "编辑 \(deadline.title) 的截止时间"
        alert.informativeText = "输入 YYYY-MM-DD；时间可空，格式 HH:mm。编辑将保留花朵和完成记录。"
        let content = NSStackView()
        content.orientation = .vertical
        content.spacing = 8
        let dateField = NSTextField(string: deadline.dueDate)
        dateField.placeholderString = "YYYY-MM-DD"
        let timeField = NSTextField(string: deadline.dueTime ?? "")
        timeField.placeholderString = "HH:mm（可留空）"
        content.addArrangedSubview(dateField)
        content.addArrangedSubview(timeField)
        content.frame = NSRect(x: 0, y: 0, width: 290, height: 58)
        alert.accessoryView = content
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            let time = timeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let error = store.garden.edit(id: deadline.id, title: deadline.title,
                project: deadline.project, dueDate: dateField.stringValue,
                dueTime: time.isEmpty ? nil : time) {
                let failure = NSAlert()
                failure.messageText = "无法更新 DDL"
                failure.informativeText = error
                failure.runModal()
            }
        }
    }

    /// One quick folder picker controls future classification copies.
    /// Existing files remain untouched; users can disable the copy at any time.
    @objc private func chooseArchiveFolder() {
        let panel = NSOpenPanel()
        panel.title = "分类文件保存位置"
        panel.message = "分类成功后将文件移动至类别文件夹。仅在写入并校验成功后才删除原位置的文件。"
        panel.prompt = "使用此文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let current = store.archive.destination { panel.directoryURL = current }
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let chosen = panel.url {
            store.archive.selectDestination(chosen)
        }
    }

    @objc private func disableArchive() {
        store.archive.selectDestination(nil)
    }

    @objc private func chooseFiles() { store.chooseFiles() }
    func chooseFilesFromMenu() { store.chooseFiles() }
    @objc private func reconnectEngine() { store.refreshConnection() }
    @objc private func showResults() { store.showResults() }
    @objc private func showPendingReviews() {
        if reviewWindowController == nil { reviewWindowController = ReviewWindowController(store: store) }
        reviewWindowController?.show()
    }

    @objc private func toggleAutomaticOCR() {
        store.setAutoAcceptImageDeadlines(!store.autoAcceptImageDeadlines)
    }

    @objc private func undoHarvest() {
        if store.garden.undoLastHarvest() != nil { store.garden.refreshTime() }
    }

    @objc private func toggleVine() {
        store.petVisible.toggle()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        fullScreenMonitor?.stop()
        store.stop()
        dropInteraction?.stop()
        flowerController?.stop()
        reviewWindowController?.close()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool { false }
}
