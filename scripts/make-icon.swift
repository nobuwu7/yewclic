// Draws the Yewclic app icon and writes Resources/AppIcon.icns.
// Run from the repo root:  swift scripts/make-icon.swift
//
// Design: a deep yew-green squircle, a white cursor arrow, and a red yew
// berry at the cursor tip with "click" ripples around it.
import AppKit

let canvasSize: CGFloat = 1024

func drawIcon(in context: CGContext) {
    // Flip so we can think in top-left coordinates like a design tool.
    context.translateBy(x: 0, y: canvasSize)
    context.scaleBy(x: 1, y: -1)

    // macOS icon grid: 824pt squircle centred on a 1024 canvas.
    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tileRect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addPath(tilePath)
    context.setFillColor(NSColor.black.cgColor)
    context.fillPath()
    context.restoreGState()

    // Green gradient background.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let backgroundGradient = CGGradient(colorsSpace: colorSpace, colors: [
        NSColor(srgbRed: 0.20, green: 0.52, blue: 0.34, alpha: 1).cgColor,
        NSColor(srgbRed: 0.05, green: 0.22, blue: 0.15, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(backgroundGradient, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 824, y: 924), options: [])

    // Subtle top highlight for depth.
    let highlightGradient = CGGradient(colorsSpace: colorSpace, colors: [
        NSColor.white.withAlphaComponent(0.16).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor,
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(highlightGradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 520), options: [])
    context.restoreGState()

    // Berry position: where the cursor "clicks".
    let berryCenter = CGPoint(x: 395, y: 355)

    // Click ripples.
    for (index, radius) in [150.0, 228.0].enumerated() {
        context.setStrokeColor(NSColor.white.withAlphaComponent(index == 0 ? 0.22 : 0.11).cgColor)
        context.setLineWidth(14)
        context.addArc(center: berryCenter, radius: radius, startAngle: .pi * 0.95, endAngle: .pi * 1.8, clockwise: false)
        context.strokePath()
    }

    // Red yew berry with a glossy highlight.
    let berryRadius: CGFloat = 70
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.addEllipse(in: CGRect(x: berryCenter.x - berryRadius, y: berryCenter.y - berryRadius, width: berryRadius * 2, height: berryRadius * 2))
    context.setFillColor(NSColor(srgbRed: 0.90, green: 0.18, blue: 0.22, alpha: 1).cgColor)
    context.fillPath()
    context.restoreGState()
    context.addEllipse(in: CGRect(x: berryCenter.x - 38, y: berryCenter.y - 46, width: 34, height: 26))
    context.setFillColor(NSColor.white.withAlphaComponent(0.55).cgColor)
    context.fillPath()

    // Cursor arrow, tip on the berry. Classic arrow shape in unit space.
    let arrowUnitPoints: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.74), CGPoint(x: 0.17, y: 0.58),
        CGPoint(x: 0.30, y: 0.86), CGPoint(x: 0.42, y: 0.81), CGPoint(x: 0.29, y: 0.53),
        CGPoint(x: 0.52, y: 0.53),
    ]
    let arrowScale: CGFloat = 470
    let arrowOrigin = CGPoint(x: berryCenter.x + 10, y: berryCenter.y + 10)
    let arrowPath = CGMutablePath()
    arrowPath.addLines(between: arrowUnitPoints.map {
        CGPoint(x: arrowOrigin.x + $0.x * arrowScale, y: arrowOrigin.y + $0.y * arrowScale)
    })
    arrowPath.closeSubpath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 16), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    context.addPath(arrowPath)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    context.addPath(arrowPath)
    context.setStrokeColor(NSColor(srgbRed: 0.05, green: 0.22, blue: 0.15, alpha: 1).cgColor)
    context.setLineWidth(18)
    context.setLineJoin(.round)
    context.strokePath()
}

func renderPNG(pixelSize: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)!
    let context = graphicsContext.cgContext
    let scale = CGFloat(pixelSize) / canvasSize
    context.scaleBy(x: scale, y: scale)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    drawIcon(in: context)
    return bitmap.representation(using: .png, properties: [:])!
}

let fileManager = FileManager.default
let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for pointSize in [16, 32, 128, 256, 512] {
    try renderPNG(pixelSize: pointSize).write(to: iconsetURL.appendingPathComponent("icon_\(pointSize)x\(pointSize).png"))
    try renderPNG(pixelSize: pointSize * 2).write(to: iconsetURL.appendingPathComponent("icon_\(pointSize)x\(pointSize)@2x.png"))
}
try renderPNG(pixelSize: 1024).write(to: URL(fileURLWithPath: "Resources/AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
