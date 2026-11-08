#!/usr/bin/env swift
// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
// Renders Nera's app icon (and the README logo) with CoreGraphics, so it's crisp at every size and lives in
// the repo as code. Usage: swift scripts/brand/render-icon.swift <output-dir>
// Writes icon_<size>.png for the macOS AppIcon set and logo.png (512 px).
import AppKit
import CoreGraphics

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha)
}

/// The icon at `size` px: Apple's macOS grid (824/1024 rounded square with a soft shadow), a night-blue field,
/// an aurora ring (pink → violet → blue → teal → gold) around a white-hot core: light, in Nera's colors.
func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.displayP3)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)  // y down, like design tools

    let inset = s * 100 / 1024
    let box = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = box.width * 0.225
    let shape = CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s * 0.012), blur: s * 0.035, color: color(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x1b1446))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    // Field: deep night blue, slightly lighter at the top.
    let field = CGGradient(colorsSpace: space, colors: [color(0x23205a), color(0x110f2e), color(0x07061a)] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(field, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.maxY), options: [])

    let center = CGPoint(x: box.midX, y: box.midY)
    // Soft colored bloom behind the ring.
    let bloom = CGGradient(colorsSpace: space, colors: [color(0x8f6bff, 0.55), color(0xff5fa2, 0.18), color(0x000000, 0)] as CFArray, locations: [0, 0.45, 1])!
    ctx.drawRadialGradient(bloom, startCenter: center, startRadius: 0, endCenter: center, endRadius: box.width * 0.62, options: [])

    // Aurora ring: a conic gradient clipped to a thick ring.
    let outer = box.width * 0.33, inner = box.width * 0.215
    let ring = CGMutablePath()
    ring.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
    ring.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
    ctx.saveGState()
    ctx.addPath(ring)
    ctx.clip(using: .evenOdd)
    // Conic sweep, drawn as thin wedges with interpolated colors (CoreGraphics has no conic gradient).
    let stops: [(CGFloat, UInt32)] = [(0, 0xff5fa2), (0.22, 0xa66bff), (0.45, 0x5b8cff), (0.65, 0x3ee0d0), (0.85, 0xffd36e), (1, 0xff5fa2)]
    func mix(_ t: CGFloat) -> CGColor {
        let i = max(0, (stops.firstIndex { $0.0 >= t } ?? 1) - 1)
        let (t0, c0) = stops[i], (t1, c1) = stops[min(i + 1, stops.count - 1)]
        let f = t1 > t0 ? (t - t0) / (t1 - t0) : 0
        func channel(_ c: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((c >> shift) & 0xff) / 255 }
        return CGColor(
            red: channel(c0, 16) + (channel(c1, 16) - channel(c0, 16)) * f, green: channel(c0, 8) + (channel(c1, 8) - channel(c0, 8)) * f,
            blue: channel(c0, 0) + (channel(c1, 0) - channel(c0, 0)) * f, alpha: 1)
    }
    let wedges = 720
    ctx.setShouldAntialias(false)  // no seams between wedges; the ring's clip keeps the edges smooth
    for k in 0..<wedges {
        let a0 = -CGFloat.pi / 2 + CGFloat(k) / CGFloat(wedges) * 2 * .pi
        let a1 = -CGFloat.pi / 2 + CGFloat(k + 1) / CGFloat(wedges) * 2 * .pi + 0.004
        let wedge = CGMutablePath()
        wedge.move(to: center)
        wedge.addArc(center: center, radius: outer + 2, startAngle: a0, endAngle: a1, clockwise: false)
        wedge.closeSubpath()
        ctx.addPath(wedge)
        ctx.setFillColor(mix(CGFloat(k) / CGFloat(wedges)))
        ctx.fillPath()
    }
    ctx.setShouldAntialias(true)
    // Inner shading for a glassy, 3D ring.
    let depth = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.35), color(0xffffff, 0), color(0x000000, 0.25)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(depth, start: CGPoint(x: center.x, y: center.y - outer), end: CGPoint(x: center.x, y: center.y + outer), options: [])
    ctx.restoreGState()

    // The light at the center: white-hot core with a warm halo.
    let halo = CGGradient(colorsSpace: space, colors: [color(0xffffff), color(0xfff1cf, 0.9), color(0xffd27a, 0)] as CFArray, locations: [0, 0.4, 1])!
    ctx.drawRadialGradient(halo, startCenter: center, startRadius: 0, endCenter: center, endRadius: inner * 0.95, options: [])

    // Subtle top sheen for depth.
    let sheen = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.12), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: box.midX, y: box.minY), end: CGPoint(x: box.midX, y: box.minY + box.height * 0.4), options: [])
    ctx.restoreGState()

    // Hairline edge.
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0xffffff, 0.12))
    ctx.setLineWidth(max(1, s / 512))
    ctx.strokePath()

    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try render(size).write(to: out.appending(path: "icon_\(size).png"))
}
try render(512).write(to: out.appending(path: "logo.png"))
print("✔ rendered icons into \(out.path)")
