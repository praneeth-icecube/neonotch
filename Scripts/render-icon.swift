import AppKit

// Renders the NeoNotch app icon at 1024×1024 on the macOS icon grid:
// an 824 pt body with a 185 pt corner radius, centred, with a soft shadow.
//
//     swift Scripts/render-icon.swift /tmp/icon.png
//
// Then regenerate NeoNotch/Assets.xcassets/AppIcon.appiconset from it at
// 16, 32, 128, 256 and 512 pt, each at 1x and 2x (sips -z works), and
// docs/images/icon.png at 512 px for the README.
let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
               colors: stops.map { color($0.0, $0.2) } as CFArray,
               locations: stops.map { $0.1 })!
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
// Work top-down: y grows downwards.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = rounded(body, 185)

// Shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x000000, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(color(0x0B0B0F)); ctx.fillPath()
ctx.restoreGState()

// Wallpaper fills the body; the bezel sits across its top.
let bezelBottom: CGFloat = 340
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
ctx.drawLinearGradient(gradient([(0x2A1F6E, 0, 1), (0x5A2A8C, 0.4, 1), (0xB0388C, 0.75, 1), (0xF0567A, 1, 1)]),
                       start: CGPoint(x: 140, y: bezelBottom), end: CGPoint(x: 900, y: 924), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Cyan bloom low on the left, for depth.
ctx.drawRadialGradient(gradient([(0x37D7FF, 0, 0.6), (0x37D7FF, 1, 0)]),
                       startCenter: CGPoint(x: 230, y: 900), startRadius: 0,
                       endCenter: CGPoint(x: 230, y: 900), endRadius: 430, options: [])
// Neon glow spilling out under the island.
ctx.drawRadialGradient(gradient([(0xFF5FD2, 0, 0.75), (0x9B5BFF, 0.45, 0.32), (0x9B5BFF, 1, 0)]),
                       startCenter: CGPoint(x: 512, y: 520), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 520), endRadius: 400, options: [])
// Menu bar.
ctx.setFillColor(color(0xFFFFFF, 0.12))
ctx.fill(CGRect(x: 0, y: bezelBottom, width: size, height: 48))
// Bezel, with a faint sheen towards the top.
ctx.drawLinearGradient(gradient([(0x2B2B33, 0, 1), (0x0E0E12, 0.6, 1), (0x000000, 1, 1)]),
                       start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: bezelBottom), options: [])
// Camera.
ctx.setFillColor(color(0x15161C)); ctx.fillEllipse(in: CGRect(x: 512 - 22, y: 205, width: 44, height: 44))
ctx.setFillColor(color(0x0A1630)); ctx.fillEllipse(in: CGRect(x: 512 - 12, y: 215, width: 24, height: 24))
ctx.setFillColor(color(0x6FA8FF, 0.55)); ctx.fillEllipse(in: CGRect(x: 512 - 6, y: 219, width: 9, height: 9))

// The island, hanging from the bezel like a notch.
let cx: CGFloat = 512, top = bezelBottom
let w: CGFloat = 470, h: CGFloat = 190, ear: CGFloat = 40, r: CGFloat = 76
let island = CGMutablePath()
island.move(to: CGPoint(x: cx - w / 2 - ear, y: top - 1))
island.addLine(to: CGPoint(x: cx - w / 2 - ear, y: top))
island.addArc(tangent1End: CGPoint(x: cx - w / 2, y: top), tangent2End: CGPoint(x: cx - w / 2, y: top + ear), radius: ear)
island.addArc(tangent1End: CGPoint(x: cx - w / 2, y: top + h), tangent2End: CGPoint(x: cx, y: top + h), radius: r)
island.addArc(tangent1End: CGPoint(x: cx + w / 2, y: top + h), tangent2End: CGPoint(x: cx + w / 2, y: top), radius: r)
island.addArc(tangent1End: CGPoint(x: cx + w / 2, y: top), tangent2End: CGPoint(x: cx + w / 2 + ear, y: top), radius: ear)
island.addLine(to: CGPoint(x: cx + w / 2 + ear, y: top - 1))
island.closeSubpath()

// Neon rim: the island's outline glowing pink into violet, only below the bezel.
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: top, width: size, height: size))
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 46, color: color(0xFF4FD8, 0.95))
ctx.addPath(island); ctx.setFillColor(color(0x000000)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(island); ctx.setLineWidth(10); ctx.replacePathWithStrokedPath(); ctx.clip()
ctx.drawLinearGradient(gradient([(0x5EE6FF, 0, 1), (0xFF4FD8, 0.5, 1), (0xFFB25E, 1, 1)]),
                       start: CGPoint(x: cx - w / 2, y: 0), end: CGPoint(x: cx + w / 2, y: 0), options: [])
ctx.restoreGState()
ctx.restoreGState()
ctx.addPath(island); ctx.setFillColor(color(0x000000)); ctx.fillPath()

// Live activity inside: a cover on the left, level bars on the right.
let midY = top + h / 2 + 6
let art = CGRect(x: cx - w / 2 + 60, y: midY - 50, width: 100, height: 100)
ctx.saveGState()
ctx.addPath(rounded(art, 24)); ctx.clip()
ctx.drawLinearGradient(gradient([(0xFF7A59, 0, 1), (0xFF4FD8, 0.55, 1), (0x7B4DFF, 1, 1)]),
                       start: CGPoint(x: art.minX, y: art.minY), end: CGPoint(x: art.maxX, y: art.maxY), options: [])
ctx.setFillColor(color(0xFFE08A, 0.95))
ctx.fillEllipse(in: CGRect(x: art.midX - 23, y: art.midY - 28, width: 46, height: 46))
ctx.restoreGState()

let heights: [CGFloat] = [52, 100, 70, 116]
let barW: CGFloat = 24, gap: CGFloat = 16
var x = cx + w / 2 - 60 - (CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap)
for bh in heights {
    let bar = CGRect(x: x, y: midY - bh / 2, width: barW, height: bh)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18, color: color(0xFF4FD8, 0.9))
    ctx.addPath(rounded(bar, barW / 2)); ctx.setFillColor(color(0xFF4FD8)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(rounded(bar, barW / 2)); ctx.clip()
    ctx.drawLinearGradient(gradient([(0xFF6FE0, 0, 1), (0x6FE8FF, 1, 1)]),
                           start: CGPoint(x: 0, y: midY - 58), end: CGPoint(x: 0, y: midY + 58), options: [])
    ctx.restoreGState()
    x += barW + gap
}
ctx.restoreGState()  // body clip

// A thin highlight on the bezel's upper edge.
ctx.saveGState()
ctx.addPath(bodyPath); ctx.setLineWidth(3); ctx.setStrokeColor(color(0xFFFFFF, 0.14)); ctx.strokePath()
ctx.restoreGState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
