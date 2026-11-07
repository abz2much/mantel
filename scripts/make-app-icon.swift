// Draws Mantel's app icon and writes Resources/AppIcon.icns.
//   swift scripts/make-app-icon.swift            (from the repo root)
// The artwork: a warm brass shelf with the notch resting on it, glowing like the app's compact view
// (a song dot and a waveform). Drawn on Apple's icon grid: an 824-pt rounded square in a 1024 canvas.
import AppKit

func drawIcon(in ctx: CGContext, size s: CGFloat) {
    let u = s / 1024   // design units: 1024 per side
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * u, y: (1024 - y - h) * u, width: w * u, height: h * u)   // top-left design coords
    }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }
    func linear(_ colors: [CGColor], from: CGPoint, to: CGPoint) {
        let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: from, end: to, options: [])
    }

    // Body: the rounded square, with a soft drop shadow.
    let body = r(100, 100, 824, 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185 * u, cornerHeight: 185 * u, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * u), blur: 28 * u, color: rgb(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x1a1a1f)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    linear([rgb(0x3b3b45), rgb(0x16161b)], from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.minY))

    // Warm glow behind the notch, like firelight on a wall.
    let glowCentre = CGPoint(x: 512 * u, y: (1024 - 470) * u)
    let glow = CGGradient(colorsSpace: space, colors: [rgb(0xffa24a, 0.55), rgb(0xff7a2f, 0.18), rgb(0xff7a2f, 0)] as CFArray,
                          locations: [0, 0.45, 1])!
    ctx.saveGState()
    ctx.translateBy(x: glowCentre.x, y: glowCentre.y)
    ctx.scaleBy(x: 1.7, y: 1)
    ctx.drawRadialGradient(glow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 230 * u, options: [])
    ctx.restoreGState()

    // The notch: a black pill resting on the shelf, with a faint top edge.
    let pill = r(322, 402, 380, 132)
    let pillPath = CGPath(roundedRect: pill, cornerWidth: 66 * u, cornerHeight: 66 * u, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6 * u), blur: 18 * u, color: rgb(0x000000, 0.6))
    ctx.addPath(pillPath); ctx.setFillColor(rgb(0x050506)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(pillPath); ctx.clip()
    linear([rgb(0xffffff, 0.10), rgb(0xffffff, 0)], from: CGPoint(x: 0, y: pill.maxY), to: CGPoint(x: 0, y: pill.maxY - 40 * u))
    ctx.restoreGState()

    // Inside the notch: the glowing song dot and waveform.
    let amber = rgb(0xff9d3c)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 22 * u, color: rgb(0xff8a2a, 0.9))
    ctx.setFillColor(amber)
    ctx.fillEllipse(in: r(384, 444, 48, 48))
    for (x, h) in [(568.0, 34.0), (600.0, 64.0), (632.0, 46.0)] {
        ctx.addPath(CGPath(roundedRect: r(x, 468 - h / 2, 18, h), cornerWidth: 9 * u, cornerHeight: 9 * u, transform: nil))
    }
    ctx.fillPath()
    ctx.restoreGState()

    // The shelf: brass, with a highlight on top and a shadow underneath.
    let shelf = r(214, 552, 596, 64)
    let shelfPath = CGPath(roundedRect: shelf, cornerWidth: 32 * u, cornerHeight: 32 * u, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -26 * u), blur: 40 * u, color: rgb(0x000000, 0.55))
    ctx.addPath(shelfPath); ctx.setFillColor(rgb(0xb8783a)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shelfPath); ctx.clip()
    linear([rgb(0xf3c787), rgb(0xd29a52), rgb(0x9a5d24)], from: CGPoint(x: 0, y: shelf.maxY), to: CGPoint(x: 0, y: shelf.minY))
    ctx.setFillColor(rgb(0xffffff, 0.35))
    ctx.fill(r(240, 556, 544, 6))
    ctx.restoreGState()

    // Edge: a hairline so it holds up on dark backgrounds.
    ctx.addPath(bodyPath); ctx.setStrokeColor(rgb(0xffffff, 0.08)); ctx.setLineWidth(3 * u); ctx.strokePath()
    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    drawIcon(in: gc.cgContext, size: CGFloat(size))
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
guard fm.fileExists(atPath: "Resources/Info.plist") else { print("Run this from the repo root"); exit(1) }
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let out = URL(fileURLWithPath: "Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try iconutil.run(); iconutil.waitUntilExit()
// A preview for the README and for checking by eye.
try png(size: 512).write(to: URL(fileURLWithPath: "docs/images/app-icon.png"))
try? fm.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
print("Wrote \(out.path) and docs/images/app-icon.png")
