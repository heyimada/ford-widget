import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Bitmap {
    let width: Int, height: Int
    var data: [UInt8]

    init(width: Int, height: Int) {
        self.width = width; self.height = height
        data = [UInt8](repeating: 0, count: width * height * 4)
    }

    init(path: String) {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("cannot read \(path)") }
        self.init(width: image.width, height: image.height)
        draw { $0.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)) }
    }

    mutating func draw(_ body: (CGContext) -> Void) {
        let (w, h) = (width, height)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high
            body(context)
        }
    }

    var cgImage: CGImage {
        var copy = data
        return copy.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        }
    }

    func write(to path: String) {
        let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("cannot write \(path)") }
    }

    func isCard(_ x: Int, _ y: Int) -> Bool {
        let i = (y * width + x) * 4
        return min(data[i], data[i + 1], data[i + 2]) >= 190
    }
}

/// The card is the near-white block on the red wallpaper; the caption below it is too sparse to pass the row/column counts.
func cardBounds(_ image: Bitmap) -> CGRect {
    let rows = (0..<image.height).filter { y in (0..<image.width).reduce(0) { $0 + (image.isCard($1, y) ? 1 : 0) } > image.width / 4 }
    let top = rows.first!, bottom = rows.last!
    let columns = (0..<image.width).filter { x in (top...bottom).reduce(0) { $0 + (image.isCard(x, $1) ? 1 : 0) } > (bottom - top) / 3 }
    return CGRect(x: columns.first!, y: top, width: columns.last! - columns.first! + 1, height: bottom - top + 1)
}

let args = CommandLine.arguments
guard args.count == 6, let width = Int(args[4]), let height = Int(args[5]) else {
    fatalError("usage: parity reference.png render.png <out-dir> <width-px> <height-px>")
}
let outDir = args[3]
let reference = Bitmap(path: args[1])
let render = Bitmap(path: args[2])
precondition(render.width == width && render.height == height, "render is \(render.width)x\(render.height), expected \(width)x\(height)")

let bounds = cardBounds(reference)
print("card bounds in reference px: x \(Int(bounds.minX))…\(Int(bounds.maxX)) y \(Int(bounds.minY))…\(Int(bounds.maxY))")

var cropped = Bitmap(width: width, height: height)
let source = reference.cgImage.cropping(to: bounds)!
cropped.draw { $0.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height)) }

// Pixels inside the rounded rect inset by 6 px; the screenshot's corners show the wallpaper.
let inset = 6.0, radius = 22.0 * 3 - inset
let rect = CGRect(x: inset, y: inset, width: Double(width) - 2 * inset, height: Double(height) - 2 * inset)
func inside(_ x: Int, _ y: Int) -> Bool {
    let p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
    let cx = min(max(p.x, rect.minX + radius), rect.maxX - radius)
    let cy = min(max(p.y, rect.minY + radius), rect.maxY - radius)
    return rect.contains(p) && hypot(p.x - cx, p.y - cy) <= radius
}

var total = 0, count = 0
var overlay = Bitmap(width: width, height: height)
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        for c in 0..<3 {
            overlay.data[i + c] = UInt8((Int(cropped.data[i + c]) + Int(render.data[i + c])) / 2)
            if inside(x, y) { total += abs(Int(cropped.data[i + c]) - Int(render.data[i + c])) }
        }
        overlay.data[i + 3] = 255
        if inside(x, y) { count += 3 }
    }
}

var sideBySide = Bitmap(width: width, height: height * 2 + 6)
sideBySide.draw { context in
    context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height * 2 + 6))
    context.draw(cropped.cgImage, in: CGRect(x: 0, y: height + 6, width: width, height: height))
    context.draw(render.cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
}
cropped.write(to: "\(outDir)/reference-card.png")
sideBySide.write(to: "\(outDir)/side-by-side.png")
overlay.write(to: "\(outDir)/overlay.png")
print(String(format: "%.3f", Double(total) / Double(count)))
