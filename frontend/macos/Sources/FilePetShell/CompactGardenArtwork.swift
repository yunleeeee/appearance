import AppKit
import ImageIO

/// The approved compact garden source is the only trellis/berry artwork used by
/// the desktop renderer. Fruit is separated at load time so the decorative
/// source's three full bunches never become phantom file counts.
enum CompactGardenArtwork {
    static let crop = CGRect(x: 29, y: 38, width: 1401, height: 1022)

    static let source: CGImage = {
        // SwiftPM's test runner can expose an older installed resource bundle
        // through Bundle.main. Prefer the package bundle and verify the exact
        // resource before using any installed fallback.
        var bundles = [Bundle.module]
        if let url = Bundle.main.url(forResource: "FilePetShell_FilePetShell", withExtension: "bundle"),
           let installed = Bundle(url: url) { bundles.append(installed) }
        let host = Bundle(for: CompactGardenBundleLocator.self)
        let nearby = host.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("FilePetShell_FilePetShell.bundle")
        if let adjacent = Bundle(url: nearby) { bundles.append(adjacent) }
        for bundle in bundles {
            let candidates = [
                bundle.url(forResource: "CompactTrellis", withExtension: "png", subdirectory: "Garden"),
                bundle.resourceURL?.appendingPathComponent("Garden/CompactTrellis.png"),
            ]
            for case let url? in candidates where FileManager.default.fileExists(atPath: url.path) {
                if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) { return image }
            }
        }
        preconditionFailure("Missing approved compact trellis artwork in " + bundles.map(\.bundlePath).joined(separator: ", "))
    }()

    /// Keep source dimensions: all runtime crop and contact coordinates refer
    /// to the same top-left pixel space as the approved artwork.
    static let trellis: CGImage = {
        var pixels = rgba(source)
        let width = source.width
        for (index, polygon) in fruitSilhouettes.enumerated() {
            let bounds = polygon.boundingBoxOfPath.integral
            for y in max(0, Int(bounds.minY))..<min(source.height, Int(bounds.maxY)) {
                for x in max(0, Int(bounds.minX))..<min(source.width, Int(bounds.maxX)) {
                    guard polygon.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) else { continue }
                    let offset = (y * width + x) * 4
                    let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
                    // Purple/gold fruit overlap a little surrounding foliage.
                    // Preserve the green leaf pixels rather than cutting a box
                    // out of the branch. The green bunch uses its measured
                    // silhouette because its fruit and leaves share a hue.
                    let foliageBottom = index == 0 ? 370 : 345
                    let isLeaf = y < foliageBottom && g > r * 6 / 5 && g > b * 6 / 5
                    if index != 1 && isLeaf { continue }
                    pixels[offset] = 0
                    pixels[offset + 1] = 0
                    pixels[offset + 2] = 0
                    pixels[offset + 3] = 0
                }
            }
        }
        // Below each surrounding leaf, only baked fruit/its antialiased
        // outline remains. Clear this measured region too so pale desktops do
        // not show tiny orphan pixels from the decorative source bunches.
        for (index, polygon) in fruitSilhouettes.enumerated() {
            let bounds = polygon.boundingBoxOfPath.insetBy(dx: -6, dy: -6).integral
            let foliageBottom = [370, 350, 360][index]
            for y in foliageBottom..<min(source.height, Int(bounds.maxY)) {
                for x in max(0, Int(bounds.minX))..<min(source.width, Int(bounds.maxX)) {
                    let offset = (y * width + x) * 4
                    pixels[offset] = 0; pixels[offset + 1] = 0
                    pixels[offset + 2] = 0; pixels[offset + 3] = 0
                }
            }
        }
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0 else { continue }
            let channels = (0..<3).map { min(1, Double(pixels[offset + $0]) / 255 / alpha) }
            let gray = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
            // Restore just a little of the approved foliage's green and
            // midtone detail so the v2 flower leaves and living grape crowns
            // belong to the same garden. Keep the wooden frame muted.
            let foliage = channels[1] > channels[0] * 1.08 && channels[1] > channels[2] * 1.04
            let chroma = foliage ? 0.60 : 0.48
            let light = foliage ? 0.93 : 0.89
            for channel in 0..<3 {
                let muted = ((gray + (channels[channel] - gray) * chroma) * light - 0.5) * 0.85 + 0.5
                pixels[offset + channel] = UInt8(max(0, min(255, (muted * alpha * 255).rounded())))
            }
        }
        return image(pixels, width: source.width, height: source.height)
    }()

    static let croppedTrellis: CGImage = {
        guard let cropped = trellis.cropping(to: crop) else { preconditionFailure("Invalid compact trellis crop") }
        return cropped
    }()

    static let berrySprites: [CGImage] = [
        singleBerry(in: CGRect(x: 209, y: 320, width: 49, height: 51)),
        singleBerry(in: CGRect(x: 618, y: 339, width: 51, height: 53)),
        singleBerry(in: CGRect(x: 1020, y: 314, width: 51, height: 53)),
    ]

    static func berry(for category: String) -> CGImage {
        let slot: Int
        switch category {
        case "finance", "travel", "entertainment": slot = 2
        case "learning", "daily": slot = 1
        case "research", "recruitment", "engineering": slot = 0
        default:
            slot = category.utf8.reduce(0) { ($0 + Int($1)) % 3 }
        }
        return berrySprites[slot]
    }

    private static func singleBerry(in rect: CGRect) -> CGImage {
        guard let cropped = source.cropping(to: rect) else { preconditionFailure("Invalid berry crop") }
        var pixels = rgba(cropped)
        let w = cropped.width, h = cropped.height
        for y in 0..<h {
            for x in 0..<w {
                // A stepped silhouette preserves hard pixel edges and excludes
                // the adjacent berries/leaf corners in the original crop.
                let nx = (Double(x) + 0.5 - Double(w) / 2) / (Double(w) * 0.47)
                let ny = (Double(y) + 0.5 - Double(h) / 2) / (Double(h) * 0.47)
                let offset = (y * w + x) * 4
                if nx * nx + ny * ny > 1 {
                    pixels[offset] = 0; pixels[offset + 1] = 0
                    pixels[offset + 2] = 0; pixels[offset + 3] = 0
                }
            }
        }
        return image(pixels, width: w, height: h)
    }

    private static let fruitSilhouettes: [CGPath] = [
        polygon([(205,334),(214,322),(249,319),(275,319),(296,321),(306,309),(337,308),
                 (349,322),(355,349),(347,364),(357,377),(347,399),(333,409),(323,431),
                 (310,446),(302,464),(283,475),(263,465),(252,449),(242,430),(225,413),
                 (221,392),(205,377),(203,353)]),
        polygon([(616,351),(628,340),(652,339),(665,329),(696,328),(715,337),(739,338),
                 (751,356),(751,379),(757,397),(747,419),(730,426),(723,446),(710,460),
                 (702,480),(684,493),(664,484),(659,467),(642,459),(636,440),(623,427),
                 (613,402),(613,376)]),
        polygon([(1017,331),(1028,316),(1056,312),(1076,315),(1096,310),(1113,314),
                 (1137,313),(1154,328),(1158,351),(1162,370),(1158,392),(1141,405),
                 (1134,425),(1119,438),(1112,458),(1094,471),(1075,467),(1066,449),
                 (1051,441),(1041,419),(1027,405),(1023,384),(1014,366)])
    ]

    private static func polygon(_ points: [(Int, Int)]) -> CGPath {
        let path = CGMutablePath()
        for (index, point) in points.enumerated() {
            let value = CGPoint(x: point.0, y: point.1)
            if index == 0 { path.move(to: value) } else { path.addLine(to: value) }
        }
        path.closeSubpath()
        return path
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                preconditionFailure("Cannot decode compact garden pixels")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    private static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage {
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            preconditionFailure("Cannot compose compact garden pixels")
        }
        return image
    }
}

private final class CompactGardenBundleLocator {}
