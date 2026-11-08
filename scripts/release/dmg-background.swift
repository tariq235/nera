// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Draws the DMG window background: Nera's soft aurora light, an install hint, and an arrow from the app to
// Applications. Usage: swift scripts/release/dmg-background.swift <out-dir>  (writes background.png and @2x)
import AppKit

let size = CGSize(width: 640, height: 420)
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func render(scale: CGFloat) -> Data {
    let w = Int(size.width * scale)
    let h = Int(size.height * scale)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)

    // Canvas.
    ctx.setFillColor(color(0xFAF9FB))
    ctx.fill(CGRect(origin: .zero, size: size))

    // Soft light along the bottom (y is up in Core Graphics).
    let glows: [(CGPoint, CGFloat, UInt32, CGFloat)] = [
        (CGPoint(x: 60, y: 10), 260, 0x7FE3F0, 0.55),  // cyan
        (CGPoint(x: 250, y: -20), 240, 0xB9A6FF, 0.45),  // violet
        (CGPoint(x: 450, y: 0), 250, 0xFFB3D9, 0.5),  // pink
        (CGPoint(x: 640, y: 30), 230, 0xFFD2A8, 0.5),  // peach
        (CGPoint(x: 330, y: 470), 260, 0xC9B8FF, 0.22),  // faint glow at the top
    ]
    for (center, radius, hex, alpha) in glows {
        let gradient = CGGradient(colorsSpace: space, colors: [color(hex, alpha), color(hex, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    // Arrow between the two icons (icons are centered at x 170 and 470, y 180 from the top).
    let arrowY = size.height - 180
    let stops: [UInt32] = [0x5BC8E8, 0x9A7BFF, 0xF27BC0]
    for (i, hex) in stops.enumerated() {
        let x = 293 + CGFloat(i) * 22
        ctx.setStrokeColor(color(hex, 0.45 + 0.25 * CGFloat(i)))
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: x, y: arrowY + 13))
        ctx.addLine(to: CGPoint(x: x + 13, y: arrowY))
        ctx.addLine(to: CGPoint(x: x, y: arrowY - 13))
        ctx.strokePath()
    }

    // Install hint at the top.
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = NSMutableAttributedString(
        string: "Drag ", attributes: [.font: NSFont.systemFont(ofSize: 19, weight: .regular), .foregroundColor: NSColor(white: 0.42, alpha: 1)])
    let bold: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 19, weight: .semibold), .foregroundColor: NSColor(white: 0.1, alpha: 1)]
    let light: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 19, weight: .regular), .foregroundColor: NSColor(white: 0.42, alpha: 1)]
    title.append(NSAttributedString(string: "Nera", attributes: bold))
    title.append(NSAttributedString(string: " into ", attributes: light))
    title.append(NSAttributedString(string: "Applications", attributes: bold))
    title.append(NSAttributedString(string: " to install", attributes: light))
    title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
    title.draw(in: CGRect(x: 0, y: size.height - 74, width: size.width, height: 30))

    NSGraphicsContext.current = nil

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = size  // 72 dpi at 1x, 144 dpi at 2x, so Finder pairs them
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
print("✔ DMG background written to \(out.path)")
