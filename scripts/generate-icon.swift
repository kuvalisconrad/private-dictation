// First-party vector app icon, matching SetupWindow's PrivacyMark and palette.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let background = NSColor(calibratedRed: 0.055, green: 0.069, blue: 0.064, alpha: 1)
let card = NSColor(calibratedRed: 0.096, green: 0.112, blue: 0.103, alpha: 1)
let border = NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.19, alpha: 1)
let mint = NSColor(calibratedRed: 0.67, green: 0.89, blue: 0.73, alpha: 1)

func png(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = graphics
    graphics.shouldAntialias = true
    graphics.imageInterpolation = .high
    graphics.cgContext.scaleBy(x: CGFloat(pixels) / 64, y: CGFloat(pixels) / 64)
    let tile = NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 56, height: 56), xRadius: 13, yRadius: 13)
    NSGradient(starting: card, ending: background)!.draw(in: tile, angle: -75)
    border.withAlphaComponent(0.7).setStroke(); tile.lineWidth = 0.35; tile.stroke()

    let shield = NSBezierPath()
    shield.move(to: NSPoint(x: 32, y: 49)); shield.line(to: NSPoint(x: 47, y: 43))
    shield.line(to: NSPoint(x: 46, y: 28))
    shield.curve(to: NSPoint(x: 32, y: 14), controlPoint1: NSPoint(x: 44, y: 21), controlPoint2: NSPoint(x: 36, y: 16))
    shield.curve(to: NSPoint(x: 18, y: 28), controlPoint1: NSPoint(x: 28, y: 16), controlPoint2: NSPoint(x: 20, y: 21))
    shield.line(to: NSPoint(x: 17, y: 43)); shield.close()
    mint.withAlphaComponent(0.075).setFill(); shield.fill()
    mint.setStroke(); shield.lineWidth = 1.3; shield.lineJoinStyle = .round; shield.stroke()
    for (x, height) in [(24.0, 6.0), (28.0, 12.0), (32.0, 18.0), (36.0, 12.0), (40.0, 6.0)] {
        let wave = NSBezierPath(roundedRect: NSRect(x: x - 1, y: 32 - height / 2, width: 2, height: height),
                               xRadius: 1, yRadius: 1)
        mint.setFill(); wave.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try png(points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
