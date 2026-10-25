import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the 1024×1024 app icon to match the launch animation: a glowing
// amber-to-ember ring around a dumbbell on deep navy.
// Usage: swift make_icon.swift <out-dir>

let size = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

struct Style {
    var background: (CGColor, CGColor)?   // nil = transparent
    var glow: CGColor?                    // warm light behind the ring
    var track: CGColor
    var ring: (top: CGColor, bottom: CGColor)
    var ringShadow: CGColor?
    var glyph: CGColor
}

func render(_ style: Style, to name: String) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // The App Store rejects a primary icon with an alpha channel; only the
    // transparent dark/tinted variants keep one.
    let alpha: CGImageAlphaInfo = style.background == nil ? .premultipliedLast : .noneSkipLast
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: alpha.rawValue)!
    let s = CGFloat(size)
    let center = CGPoint(x: s / 2, y: s / 2)

    if let (top, bottom) = style.background {
        let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
        // CG's y axis points up: top-left to bottom-right.
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }
    if let glow = style.glow {
        let clear = glow.copy(alpha: 0)!
        let gradient = CGGradient(colorsSpace: space, colors: [glow, clear] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 500, options: [])
    }

    let radius: CGFloat = 318
    let lineWidth: CGFloat = 58

    ctx.setLineWidth(lineWidth)
    ctx.setStrokeColor(style.track)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Glow first, as a blurred copy of the ring underneath the crisp gradient stroke.
    if let shadow = style.ringShadow {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 60, color: shadow)
        ctx.setStrokeColor(shadow)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // A full ring colored top-to-bottom, like the end of the launch animation: no seam.
    ctx.saveGState()
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let ringGradient = CGGradient(colorsSpace: space, colors: [style.ring.top, style.ring.bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(ringGradient, start: CGPoint(x: s / 2, y: center.y + radius + lineWidth),
                           end: CGPoint(x: s / 2, y: center.y - radius - lineWidth), options: [])
    ctx.restoreGState()

    // Dumbbell: bar, inner plates, outer plates, end caps, all rounded (same as DumbbellShape).
    ctx.setFillColor(style.glyph)
    func rounded(_ rect: CGRect, _ r: CGFloat) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.fillPath()
    }
    func centered(_ x: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: center.x + x - w / 2, y: center.y - h / 2, width: w, height: h)
    }
    rounded(centered(0, 300, 50), 25)
    for sign in [-1.0, 1.0] as [CGFloat] {
        rounded(centered(sign * 112, 62, 236), 22)
        rounded(centered(sign * 178, 50, 168), 20)
        rounded(centered(sign * 222, 34, 64), 14)
    }

    let image = ctx.makeImage()!
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote", url.path)
}

let amber = rgb(0xFFC26B)
let ember = rgb(0xFF6B1A)

// Light: deep navy with a warm center glow, like the launch animation.
render(Style(background: (rgb(0x1C2366), rgb(0x0A0C26)), glow: rgb(0xFF6B1A, 0.22),
             track: rgb(0xFFFFFF, 0.08), ring: (amber, ember), ringShadow: rgb(0xFF6B1A, 0.55), glyph: rgb(0xFFFFFF)),
       to: "AppIcon.png")
// Dark: transparent so iOS draws its dark backdrop; same ring and glyph.
render(Style(background: nil, glow: nil,
             track: rgb(0xFFFFFF, 0.10), ring: (amber, ember), ringShadow: rgb(0xFF6B1A, 0.45), glyph: rgb(0xFFFFFF)),
       to: "AppIcon-Dark.png")
// Tinted: grayscale on transparent; iOS applies the user's tint.
render(Style(background: nil, glow: nil,
             track: rgb(0xFFFFFF, 0.22), ring: (rgb(0xFFFFFF), rgb(0xCFCFCF)), ringShadow: nil, glyph: rgb(0xFFFFFF)),
       to: "AppIcon-Tinted.png")
