import Foundation

/// Presentation only. Never changes the original file name or source URL.
/// Exclude OS timestamp labels from user-visible task/review summaries.
enum FileDisplayName {
    private static let generated = #"^(?:已粘贴|粘贴|屏幕快照|屏幕截图|截屏|截图|Screenshot|Screen[ _-]*Shot|CleanShot|Pasted[ _-]*Image)[ _-]*\d{4}[-.年_]\d{1,2}[-.月_]\d{1,2}日?[ _-]*(?:at[ _-]*|上午|下午|晚上|中午|凌晨)?[ _-]*\d{1,2}[:.：时]\d{2}(?:[:.：分]\d{2})?(?:秒)?[ _-]*(?:AM|PM)?(?:[ _-]*\(\d+\))?$"#

    static func label(_ original: String) -> String {
        let stem = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
        if stem.range(of: generated, options: [.regularExpression, .caseInsensitive]) != nil {
            return "截图"
        }
        if ["screen", "image", "photo", "picture", "screenshot", "screencapture",
            "clipboard", "capture", "untitled", "无标题", "截图", "图片", "屏幕快照"]
            .contains(stem.lowercased()) {
            return "图片"
        }
        if stem.range(of: #"^(?:IMG|DSC|PXL)[_-]\d{4,}(?:[_-]\d+)*$"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return "图片"
        }
        return original
    }
}
