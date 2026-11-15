import AppKit

// Renders the app icon (light, dark, tinted) into Shared/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift
let size = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("Shared/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func bitmap() -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func render(_ name: String, background: [NSColor]?, car: NSColor) throws {
    // The car is drawn on its own transparent layer: its window and wheel cut-outs clear pixels, which must show the
    // background, not punch holes in it (iOS renders transparent icon pixels black).
    let layer = bitmap()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: layer)
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)

    // An original hatchback side profile (SF Symbols may not be used in app icons). AppKit's y axis points up.
    let body = NSBezierPath()
    body.move(to: NSPoint(x: 232, y: 400))
    body.line(to: NSPoint(x: 800, y: 400))
    body.curve(to: NSPoint(x: 840, y: 470), controlPoint1: NSPoint(x: 828, y: 400), controlPoint2: NSPoint(x: 842, y: 430))
    body.curve(to: NSPoint(x: 700, y: 552), controlPoint1: NSPoint(x: 838, y: 520), controlPoint2: NSPoint(x: 780, y: 540))
    body.curve(to: NSPoint(x: 560, y: 650), controlPoint1: NSPoint(x: 650, y: 590), controlPoint2: NSPoint(x: 610, y: 640))
    body.line(to: NSPoint(x: 360, y: 650))
    body.curve(to: NSPoint(x: 236, y: 560), controlPoint1: NSPoint(x: 300, y: 648), controlPoint2: NSPoint(x: 252, y: 610))
    body.curve(to: NSPoint(x: 232, y: 400), controlPoint1: NSPoint(x: 218, y: 510), controlPoint2: NSPoint(x: 210, y: 400))
    body.close()
    car.setFill()
    body.fill()

    let context = NSGraphicsContext.current!
    context.compositingOperation = .clear
    let rearWindow = NSBezierPath()
    rearWindow.move(to: NSPoint(x: 274, y: 566))
    rearWindow.curve(to: NSPoint(x: 370, y: 624), controlPoint1: NSPoint(x: 296, y: 604), controlPoint2: NSPoint(x: 330, y: 622))
    rearWindow.line(to: NSPoint(x: 452, y: 624))
    rearWindow.line(to: NSPoint(x: 452, y: 566))
    rearWindow.close()
    rearWindow.fill()
    let frontWindow = NSBezierPath()
    frontWindow.move(to: NSPoint(x: 480, y: 566))
    frontWindow.line(to: NSPoint(x: 480, y: 624))
    frontWindow.line(to: NSPoint(x: 548, y: 624))
    frontWindow.curve(to: NSPoint(x: 650, y: 566), controlPoint1: NSPoint(x: 590, y: 616), controlPoint2: NSPoint(x: 624, y: 590))
    frontWindow.close()
    frontWindow.fill()
    let wheels = [NSPoint(x: 352, y: 404), NSPoint(x: 696, y: 404)]
    for center in wheels {
        NSBezierPath(ovalIn: NSRect(x: center.x - 82, y: center.y - 82, width: 164, height: 164)).fill()
    }
    context.compositingOperation = .sourceOver
    car.setFill()
    for center in wheels {
        NSBezierPath(ovalIn: NSRect(x: center.x - 64, y: center.y - 64, width: 128, height: 128)).fill()
    }

    // A thin road line under the wheels.
    car.withAlphaComponent(0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: 232, y: 300, width: 560, height: 14), xRadius: 7, yRadius: 7).fill()

    NSGraphicsContext.restoreGraphicsState()

    let rep = bitmap()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    if let background {
        NSGradient(colors: background)!.draw(in: canvas, angle: -90)
    }
    layer.draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: iconSet.appendingPathComponent(name))
    print("wrote \(name)")
}

try render("AppIcon.png", background: [color(0x2A5BA8), color(0x0B2552)], car: .white)
try render("AppIcon-Dark.png", background: [color(0x14213A), color(0x05080F)], car: color(0x8DB4F0))
// Tinted icons are grayscale on transparent; the system applies the user's tint.
try render("AppIcon-Tinted.png", background: nil, car: .white)

let contents = """
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "AppIcon-Dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
      "filename" : "AppIcon-Tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try contents.write(to: iconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
