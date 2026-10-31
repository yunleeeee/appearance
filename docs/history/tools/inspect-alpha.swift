import AppKit

for path in CommandLine.arguments.dropFirst() {
    let rep = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path)))!
    let w = rep.pixelsWide, h = rep.pixelsHigh
    let stride = rep.samplesPerPixel, alpha = rep.bitmapFormat.contains(.alphaFirst) ? 0 : stride - 1
    let bytes = rep.bitmapData!
    var mask = [UInt8](repeating: 0, count: w * h)
    for y in 0..<h { for x in 0..<w {
        if bytes[y * rep.bytesPerRow + x * stride + alpha] > 32 { mask[y * w + x] = 1 }
    }}
    var parts: [[String: Int]] = []
    for start in 0..<(w * h) where mask[start] == 1 {
        var queue = [start], cursor = 0
        mask[start] = 0
        var minX = w, minY = h, maxX = 0, maxY = 0
        while cursor < queue.count {
            let p = queue[cursor]; cursor += 1
            let x = p % w, y = p / w
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            for dy in -1...1 { for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                let n = ny * w + nx
                if mask[n] == 1 { mask[n] = 0; queue.append(n) }
            }}
        }
        if queue.count > 24 {
            parts.append(["x":minX,"y":minY,"w":maxX-minX+1,"h":maxY-minY+1,"pixels":queue.count])
        }
    }
    let output: [String: Any] = ["file":path,"width":w,"height":h,"components":parts]
    print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
}
