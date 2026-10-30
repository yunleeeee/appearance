import AppKit
import ImageIO
import SwiftUI

/// Original animation pixels decoded once, with a fixed crop and source timing.
enum OriginalCharacterMedia {
    static let mouseSize = CGSize(width: CharacterAnimation.mouseSize.width, height: CharacterAnimation.mouseSize.height)
    static let frameDuration = CharacterAnimation.frameDuration
    static let frameCount = CharacterAnimation.frameCount

    private static func resourceURL(_ name: String, directory: String) -> URL {
        let subdirectory = directory == "Characters" ? nil : directory.replacingOccurrences(of: "Characters/", with: "")
        guard let url = CharacterAssets.url(for: name + ".png", subdirectory: subdirectory) else {
            preconditionFailure("Missing character resource: \(directory)/\(name).png")
        }
        return url
    }

    private static func image(_ name: String, directory: String = "Characters") -> CGImage {
        let url = resourceURL(name, directory: directory)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            preconditionFailure("Cannot decode original character: \(url.lastPathComponent)")
        }
        return image
    }

    static let jerry: [CGImage] = (0..<frameCount).map {
        image(String(format: "frame_%04d", $0), directory: "Characters/JerryRun")
    }

    static func frameIndex(at elapsed: TimeInterval) -> Int {
        CharacterAnimation.frameIndex(at: elapsed)
    }

    static func handPoint(at elapsed: TimeInterval, facingRight: Bool = true) -> CGPoint {
        let point = CharacterAnimation.handPoint(at: elapsed, facingRight: facingRight)
        return CGPoint(x: point.x, y: point.y)
    }

}

struct ThievingMouseView: View {
    var elapsed: TimeInterval
    var reducedMotion = false
    var facingRight = true

    var body: some View {
        let index = reducedMotion ? 0 : OriginalCharacterMedia.frameIndex(at: elapsed)
        Image(decorative: OriginalCharacterMedia.jerry[index], scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .scaleEffect(x: facingRight ? -1 : 1, y: 1)
            .allowsHitTesting(false)
            .accessibilityLabel("原片跑姿的杰瑞背着葡萄跑向屏幕右侧")
    }
}
