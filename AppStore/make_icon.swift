import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the 1024×1024 app icon: a rest-timer ring around a dumbbell.
// Usage: swift make_icon.swift <out-dir>

let size = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

struct Style {
    var background: (CGColor, CGColor)?   // nil = transparent
    var track: CGColor
    var arc: (CGColor, CGColor)
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
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }

    // Timer ring: faint full track, then a 3/4 arc starting at 12 o'clock, clockwise.
    let radius: CGFloat = 318
    let lineWidth: CGFloat = 70
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(style.track)
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    let start = CGFloat.pi / 2              // 12 o'clock (CG's y axis points up)
    let end = start - .pi * 1.5             // clockwise 270°
    ctx.saveGState()
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let arcGradient = CGGradient(colorsSpace: space, colors: [style.arc.0, style.arc.1] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(arcGradient, start: CGPoint(x: s / 2, y: s - 150), end: CGPoint(x: 150, y: s / 2), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Dumbbell: bar, inner plates, outer plates, end caps — all rounded.
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

// Light: blue→indigo, white glyph, orange arc echoing the rest alarm.
render(Style(background: (rgb(0x2F7BF5), rgb(0x4338CA)),
             track: rgb(0xFFFFFF, 0.22), arc: (rgb(0xFFB347), rgb(0xFF7A1A)), glyph: rgb(0xFFFFFF)),
       to: "AppIcon.png")
// Dark: transparent so iOS draws its dark backdrop; colored glyph.
render(Style(background: nil,
             track: rgb(0xFFFFFF, 0.14), arc: (rgb(0xFFB347), rgb(0xFF7A1A)), glyph: rgb(0x6EA8FF)),
       to: "AppIcon-Dark.png")
// Tinted: grayscale on transparent; iOS applies the user's tint.
render(Style(background: nil,
             track: rgb(0xFFFFFF, 0.25), arc: (rgb(0xFFFFFF), rgb(0xD0D0D0)), glyph: rgb(0xFFFFFF)),
       to: "AppIcon-Tinted.png")
