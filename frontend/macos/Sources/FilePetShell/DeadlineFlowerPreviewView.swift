import AppKit
import ImageIO
import SwiftUI

/// Six design samples, independent of classification and real deadline data.
/// Their stems remain anchored when the vine sways, but never auto-fade.
struct DeadlineFlowerPreviewView: View {
    var time: TimeInterval = 0

    var body: some View {
        Canvas { context, _ in
            for (index, flower) in FlowerPreviewArtwork.samples.enumerated() {
                let x = CGFloat(62 + index * 80)
                let anchor = CGPoint(x: x, y: VineGeometry.height(at: x, time: time))
                let scale: CGFloat = 0.10
                let rect = CGRect(
                    x: anchor.x - flower.stemAnchor.x * scale,
                    y: anchor.y - flower.stemAnchor.y * scale,
                    width: CGFloat(flower.image.width) * scale,
                    height: CGFloat(flower.image.height) * scale
                )
                context.draw(Image(decorative: flower.image, scale: 1).interpolation(.high), in: rect)
            }
        }
        .frame(width: VineView.size.width, height: VineView.size.height)
        .allowsHitTesting(false)
    }
}

private enum FlowerPreviewArtwork {
    struct Sample {
        let image: CGImage
        let stemAnchor: CGPoint
    }

    static let samples: [Sample] = {
        let bundle: Bundle
        if let url = Bundle.main.url(forResource: "FilePetShell_FilePetShell", withExtension: "bundle"),
           let installed = Bundle(url: url) {
            bundle = installed
        } else {
            bundle = Bundle.module
        }
        guard let url = bundle.url(forResource: "Lifecycle", withExtension: "png", subdirectory: "Flowers"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0,
                  [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            preconditionFailure("Missing flower preview artwork")
        }

        // Runtime atlas windows preserve the original PNG and its alpha. These
        // are measured plant bounds; equal grid cells would clip the full bloom.
        let placements: [(CGRect, CGPoint)] = [
            (CGRect(x: 115, y: 118, width: 327, height: 347), CGPoint(x: 72, y: 337)),
            (CGRect(x: 578, y: 51, width: 349, height: 413), CGPoint(x: 67, y: 404)),
            (CGRect(x: 1030, y: 54, width: 464, height: 410), CGPoint(x: 90, y: 401)),
            (CGRect(x: 27, y: 509, width: 546, height: 450), CGPoint(x: 124, y: 416)),
            (CGRect(x: 578, y: 569, width: 457, height: 366), CGPoint(x: 49, y: 356)),
            (CGRect(x: 1044, y: 578, width: 482, height: 358), CGPoint(x: 55, y: 347)),
        ]
        return placements.map { rect, anchor in
            guard let image = sheet.cropping(to: rect) else {
                preconditionFailure("Invalid flower preview window")
            }
            return Sample(image: image, stemAnchor: anchor)
        }
    }()
}
