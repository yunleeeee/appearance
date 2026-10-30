import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 承载葡萄藤 UI 的 NSHostingView，同时是拖放目标。
/// 关键点：必须在 `registerForDraggedTypes` 注册 fileURL 等类型，
/// 否则 AppKit 不会把拖放会话路由到本视图（表现为拖上去毫无反应）。
/// 拖放感应区域随横向面板尺寸调整。
final class VineHostingView: NSHostingView<VineView> {

    var onFiles: (([URL]) -> Void)?
    var onTargeted: ((Bool) -> Void)?
    var onDragSessionEnded: (() -> Void)?
    private var isTargeted = false

    required init(rootView: VineView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    // MARK: - 拖放命中

    /// 仅在文件拖拽解锁窗口后使用此范围；普通点击由窗口级穿透处理。
    override func hitTest(_ point: NSPoint) -> NSView? {
        // 以实际 bounds 换算，不把旧面板高度写进命中区域。
        let contentTop = bounds.height - 20
        let contentBottom: CGFloat = 14
        let hitLateralMargin: CGFloat = 10

        guard point.y <= contentTop && point.y >= contentBottom else {
            return nil
        }
        // 左右留出边缘余量。
        if point.x < hitLateralMargin || point.x > bounds.width - hitLateralMargin {
            return nil
        }
        return self
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = Self.fileURLs(from: sender)
        if !urls.isEmpty {
            setTargeted(true)
            return .copy
        }
        setTargeted(false)
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // 仅在进入/离开时通知状态机，持续移动不重置淡入节奏。
        draggingEntered(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setTargeted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !Self.fileURLs(from: sender).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setTargeted(false)
        let urls = Self.fileURLs(from: sender)
        if urls.isEmpty { return false }
        onFiles?(urls)
        onDragSessionEnded?()
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        endTargeting()
        onDragSessionEnded?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        endTargeting()
        onDragSessionEnded?()
    }

    func endTargeting() { setTargeted(false) }

    private func setTargeted(_ targeted: Bool) {
        guard isTargeted != targeted else { return }
        isTargeted = targeted
        onTargeted?(targeted)
    }

    /// 从拖拽会话中提取所有文件 URL（同步读取，Finder 拖入时可用）。
    private static func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let pasteboard = sender.draggingPasteboard

        // 首选：Finder 常见的 fileURL 数组
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return urls
        }

        // 兜底：文件名列表再转 URL
        if let names = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String], !names.isEmpty {
            return names.map { URL(fileURLWithPath: $0) }
        }

        return []
    }
}
