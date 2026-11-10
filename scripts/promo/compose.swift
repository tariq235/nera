// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was
// not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Builds Nera's promo video, "Your Spaces don't have to die.", from scenes recorded in the app
// (Debug `--promo <scene> --record <dir>`, see make-promo.sh): real footage under a moving camera, keycaps for the
// shortcuts pressed, a background that takes each Space's colors, and type in Fraunces (SIL OFL). Silent, cut on
// a 120 BPM grid so any track fits; H.264, 60 fps.
//
//   swift compose.swift <raw dir> <assets dir> <out.mp4> <wide|tall|teaser> [from s] [to s]
//   assets: logo.png, Fraunces.ttf
import AVFoundation
import AppKit
import CoreText
import Foundation

let args = CommandLine.arguments
guard args.count >= 5 else {
    print("usage: compose.swift <raw dir> <assets dir> <out.mp4> <wide|tall|teaser> [from s] [to s]")
    exit(2)
}
let rawDir = URL(fileURLWithPath: args[1])
let assets = URL(fileURLWithPath: args[2])
let outURL = URL(fileURLWithPath: args[3])
let cut = args[4]
let tall = cut == "tall"
let W = tall ? 1080 : 1920
let H = tall ? 1920 : 1080
let fps = 60.0
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let logo = NSImage(contentsOf: assets.appending(path: "logo.png"))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
CTFontManagerRegisterFontsForURL(assets.appending(path: "Fraunces.ttf") as CFURL, .process, nil)

// MARK: Basics

func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(max(x, a), b) }
func easeOut(_ t: Double) -> Double { 1 - pow(1 - clamp(t), 3) }
func easeInOut(_ t: Double) -> Double { let t = clamp(t); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func backOut(_ t: Double) -> Double { let t = clamp(t), c = 1.4; return 1 + (c + 1) * pow(t - 1, 3) + c * pow(t - 1, 2) }
func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func rgb(_ hex: UInt32, _ a: Double = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255,
        alpha: CGFloat(a))
}
func hsb(_ h: Double, _ s: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    NSColor(hue: CGFloat(h.truncatingRemainder(dividingBy: 1)), saturation: CGFloat(s), brightness: CGFloat(b), alpha: CGFloat(a)).cgColor
}
/// Sizes are designed for 1080 high (wide); the tall cut scales type up for phones.
let U = tall ? 1.32 : 1.0

func serif(_ size: Double, weight: Double = 520) -> CTFont {
    let variations: [NSNumber: NSNumber] = [
        NSNumber(value: 0x7767_6874): NSNumber(value: weight),  // wght
        NSNumber(value: 0x6F70_737A): NSNumber(value: 144),  // opsz: display
        NSNumber(value: 0x534F_4654): NSNumber(value: 30),  // SOFT
    ]
    let descriptor = CTFontDescriptorCreateWithAttributes(
        [kCTFontFamilyNameAttribute: "Fraunces", kCTFontVariationAttribute: variations] as CFDictionary)
    return CTFontCreateWithFontDescriptor(descriptor, CGFloat(size * U), nil)
}
func sans(_ size: Double, _ weight: NSFont.Weight = .medium) -> CTFont { NSFont.systemFont(ofSize: CGFloat(size * U), weight: weight) }

// MARK: Footage

struct Event {
    let ms: Int
    let type: String
    let keys: [String]
    let hue: Double, saturation: Double, secondaryHue: Double
}

/// One recorded scene: frames timed in milliseconds from the recording's start, and its event log.
final class Clip {
    let name: String
    let frames: [(ms: Int, url: URL)]
    let events: [Event]
    private var cache: (URL, CGImage)?
    init(_ name: String) {
        self.name = name
        let dir = rawDir.appending(path: name)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        frames = files.filter { $0.pathExtension == "jpg" }.compactMap { url in
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "_")
            return parts.count == 2 ? (Int(parts[1]) ?? 0, url) : nil
        }.sorted { $0.ms < $1.ms }
        let log = (try? String(contentsOf: dir.appending(path: "events.jsonl"), encoding: .utf8)) ?? ""
        events = log.split(separator: "\n").compactMap { line in
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
            return Event(
                ms: o["ms"] as? Int ?? 0, type: o["type"] as? String ?? "", keys: o["keys"] as? [String] ?? [],
                hue: o["hue"] as? Double ?? 0, saturation: o["saturation"] as? Double ?? 0,
                secondaryHue: o["secondaryHue"] as? Double ?? 0)
        }
        if frames.isEmpty { print("✘ no frames for \(name)") }
    }
    var duration: Double { Double(frames.last?.ms ?? 0) / 1000 }
    func image(at t: Double) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        let ms = Int(t * 1000)
        var lo = 0, hi = frames.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if frames[mid].ms <= ms { lo = mid } else { hi = mid - 1 }
        }
        let url = frames[lo].url
        if let cache, cache.0 == url { return cache.1 }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        cache = (url, image)
        return image
    }
    func event(_ type: String) -> Double? { events.first { $0.type == type }.map { Double($0.ms) / 1000 } }
}

/// The camera on the window: `zoom` 1 shows the whole window at its base size; `x`, `y` is the window point (0…1
/// from its top left) at the frame's focus point.
struct Cam {
    var at: Double  // clip time
    var zoom: Double
    var x: Double
    var y: Double
}

/// A stretch of the clip played at `speed`.
struct Run {
    var from: Double
    var to: Double
    var speed: Double = 1
}

struct Footage {
    let clip: Clip
    var runs: [Run]
    var cams: [Cam]
    /// (clip time, text): the caption under the window from that moment on.
    var captions: [(Double, String)] = []
    /// The window sits left of center, leaving room for a checklist on the right.
    var side = false
    var duration: Double { runs.reduce(0) { $0 + ($1.to - $1.from) / $1.speed } }

    func clipTime(_ t: Double) -> Double {
        var left = t
        for run in runs {
            let length = (run.to - run.from) / run.speed
            if left <= length { return run.from + left * run.speed }
            left -= length
        }
        return runs.last?.to ?? 0
    }
    func beatTime(ofClip c: Double) -> Double? {
        var acc = 0.0
        for run in runs {
            if c >= run.from && c <= run.to { return acc + (c - run.from) / run.speed }
            acc += (run.to - run.from) / run.speed
        }
        return nil
    }
    func camera(_ c: Double) -> Cam {
        guard let first = cams.first else { return Cam(at: 0, zoom: 1, x: 0.5, y: 0.5) }
        if c <= first.at { return first }
        for (a, b) in zip(cams, cams.dropFirst()) where c <= b.at {
            let p = easeInOut((c - a.at) / max(b.at - a.at, 0.001))
            return Cam(at: c, zoom: mix(a.zoom, b.zoom, p), x: mix(a.x, b.x, p), y: mix(a.y, b.y, p))
        }
        return cams.last!
    }
}

// MARK: Beats

enum Content {
    /// Lines of type, revealed word by word.
    case words([String], size: Double)
    /// The logo with a burst of light, then a line.
    case logo(String)
    case footage(Footage)
    /// Footage with a checklist beside it.
    case checklist(Footage, [String])
    /// A list of facts, checked off one by one (the first one counts up).
    case facts([String])
    /// One line after another, each for an equal share of the beat.
    case stamps([String])
    case end
}

struct Beat {
    var duration: Double
    var content: Content
}

func timeline() -> [Beat] {
    let importClip = Clip("import"), hero = Clip("hero"), work = Clip("work"), spaces = Clip("spaces"), theme = Clip("theme")
    // The import: Arc's Spaces picked, the counts going up, the sidebar rebuilt.
    let reveal = importClip.event("reveal") ?? 3.8
    let importFootage = Footage(
        clip: importClip, runs: [Run(from: 0.6, to: reveal + 1.6)],
        cams: [
            Cam(at: 0.6, zoom: 1.0, x: 0.5, y: 0.5), Cam(at: reveal - 0.3, zoom: 1.06, x: 0.5, y: 0.5),
            // The welcome gives way to your sidebar, rebuilt: the camera goes to it.
            Cam(at: reveal + 0.5, zoom: 1.75, x: 0.13, y: 0.42), Cam(at: reveal + 1.6, zoom: 1.85, x: 0.13, y: 0.42),
        ], side: true)
    // The README, built in public.
    let heroFootage = Footage(
        clip: hero, runs: [Run(from: 0.5, to: min(hero.duration, 3.4), speed: 1.45)],
        cams: [Cam(at: 0.5, zoom: 1.0, x: 0.5, y: 0.5), Cam(at: 3.6, zoom: 1.1, x: 0.56, y: 0.42)],
        captions: [(0, "Built after everything Arc got right —")])
    // Real work on Nera: the pull request, ⌘T to the CI run, Split View, Peek, a Little Window.
    let t = { (type: String, fallback: Double) in work.event(type) ?? fallback }
    let cmdT = t("keys", 2.34), switched = t("switched", 4.05), split2 = t("split2", 6.9), peek = t("peek", 12.2)
    let little = t("little", 15.2)
    let splitKeys = (work.events.filter { $0.type == "keys" && $0.keys.contains("⌃") }.first.map { Double($0.ms) / 1000 }) ?? 5.6
    let workFootage = Footage(
        clip: work,
        runs: [
            Run(from: 0.4, to: cmdT - 0.1, speed: 1.8), Run(from: cmdT - 0.1, to: switched + 0.5, speed: 1.2),
            Run(from: switched + 0.5, to: splitKeys - 0.1, speed: 2.4), Run(from: splitKeys - 0.1, to: split2 + 0.4, speed: 1.2),
            Run(from: split2 + 0.4, to: split2 + 2.6, speed: 1.5), Run(from: split2 + 2.6, to: peek - 0.1, speed: 4),
            Run(from: peek - 0.1, to: peek + 2.3, speed: 1.4), Run(from: peek + 2.3, to: little - 0.1, speed: 3.5),
            Run(from: little - 0.1, to: min(little + 2.2, work.duration), speed: 1.25),
        ],
        cams: [
            Cam(at: 0.4, zoom: 1.0, x: 0.5, y: 0.5), Cam(at: cmdT - 0.2, zoom: 1.06, x: 0.55, y: 0.42),
            Cam(at: cmdT + 0.3, zoom: 1.45, x: 0.58, y: 0.3), Cam(at: switched - 0.1, zoom: 1.45, x: 0.58, y: 0.3),
            Cam(at: switched + 0.5, zoom: 1.0, x: 0.5, y: 0.5), Cam(at: splitKeys, zoom: 1.0, x: 0.5, y: 0.5),
            Cam(at: splitKeys + 0.4, zoom: 1.4, x: 0.62, y: 0.3), Cam(at: split2 - 0.1, zoom: 1.4, x: 0.62, y: 0.3),
            Cam(at: split2 + 0.5, zoom: 1.0, x: 0.5, y: 0.5), Cam(at: split2 + 2.6, zoom: 1.04, x: 0.55, y: 0.5),
            Cam(at: peek, zoom: 1.0, x: 0.5, y: 0.5), Cam(at: peek + 1.0, zoom: 1.12, x: 0.6, y: 0.5),
            Cam(at: little - 0.2, zoom: 1.0, x: 0.5, y: 0.5), Cam(at: little + 1.0, zoom: 1.1, x: 0.62, y: 0.5),
        ],
        captions: [
            (0, "— and everything it got wrong."), (cmdT - 0.1, "Jump to anything."), (splitKeys - 0.1, "Split View, up to four."),
            (peek - 0.1, "Peek at a link. Stay where you are."), (little - 0.1, "Little Windows for links from other apps."),
        ])
    let spacesFootage = Footage(
        clip: spaces, runs: [Run(from: 0.4, to: spaces.duration - 0.2, speed: 1.45)],
        cams: [Cam(at: 0.4, zoom: 1.0, x: 0.5, y: 0.5), Cam(at: spaces.duration, zoom: 1.08, x: 0.35, y: 0.5)],
        captions: [(0, "Spaces. Each in its own light.")])
    let themeFootage = Footage(
        clip: theme, runs: [Run(from: 0.9, to: theme.duration - 0.2, speed: 1.5)],
        cams: [Cam(at: 0.9, zoom: 1.08, x: 0.45, y: 0.45), Cam(at: theme.duration, zoom: 1.16, x: 0.45, y: 0.45)],
        captions: [(0, "Make it yours.")])
    return [
        Beat(duration: 1.8, content: .words(["You trusted your browser."], size: 92)),
        Beat(duration: 1.6, content: .words(["Now it’s disappearing."], size: 92)),
        Beat(duration: 1.8, content: .words(["Don’t let it happen again."], size: 92)),
        Beat(duration: 2.2, content: .logo("Meet Nera.")),
        Beat(
            duration: importFootage.duration,
            content: .checklist(
                importFootage, ["Import everything", "Your data stays on your Mac", "No account", "Open source", "Yours forever"])),
        Beat(duration: heroFootage.duration, content: .footage(heroFootage)),
        Beat(duration: workFootage.duration, content: .footage(workFootage)),
        Beat(duration: spacesFootage.duration, content: .footage(spacesFootage)),
        Beat(duration: themeFootage.duration, content: .footage(themeFootage)),
        Beat(
            duration: 3.2,
            content: .facts([
                "380+ automated tests", "Chromium security updates", "Native Swift", "Open source", "Privacy first",
            ])),
        Beat(duration: 2.4, content: .stamps(["Built in public.", "Open source.", "No telemetry.", "No accounts."])),
        Beat(duration: 2.0, content: .words(["Your browser.", "Not ours."], size: 100)),
        Beat(duration: 3.6, content: .end),
    ]
}

// MARK: Drawing

var spaceTint: (Double, Double, Double)?  // hue, saturation, second hue of the Space on screen

func background(_ ctx: CGContext, t: Double) {
    ctx.setFillColor(rgb(0x07060f))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    // The aurora: the logo's ring colors, or the colors of the Space on screen.
    var glows: [(CGColor, Double, Double, Double)] = [
        (rgb(0xf5a3d7, 0.42), 0.15, 0.85, 0.0), (rgb(0xa78bfa, 0.46), 0.85, 0.75, 2.1), (rgb(0x7ee7c9, 0.36), 0.55, 0.08, 4.2),
    ]
    if let (h, s, h2) = spaceTint {
        let sat = max(0.45, min(0.85, s + 0.25))
        glows = [
            (hsb(h, sat, 0.95, 0.55), 0.15, 0.85, 0.0), (hsb(h2, sat, 0.95, 0.5), 0.85, 0.75, 2.1),
            (hsb(h + 0.08, sat * 0.8, 0.9, 0.38), 0.55, 0.08, 4.2),
        ]
    }
    for (color, x, y, phase) in glows {
        let cx = (x + 0.05 * sin(t * 0.4 + phase)) * Double(W)
        let cy = (y + 0.05 * cos(t * 0.33 + phase)) * Double(H)
        let r = Double(max(W, H)) * 0.6
        let g = CGGradient(colorsSpace: sRGB, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
    }
}

/// A line of type, centered on `x` (fraction of the width) at `y` pixels from the top; `appear` 0…1 fades and
/// lifts it in. `words`: reveal word by word over `appear`.
func line(
    _ ctx: CGContext, _ text: String, font: CTFont, y: Double, x: Double = 0.5, appear: Double, alpha: Double = 1,
    color: UInt32 = 0xffffff, gradient: Bool = false, words: Bool = false, align: CTTextAlignment = .center
) {
    guard appear > 0.001 else { return }
    let pieces = words ? text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) : [text]
    func attributed(_ s: String, _ a: Double) -> NSAttributedString {
        NSAttributedString(
            string: s,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(color, alpha * a),
                .kern: -CTFontGetSize(font) * 0.015,
            ])
    }
    let whole = CTLineCreateWithAttributedString(attributed(text, 1))
    let bounds = CTLineGetBoundsWithOptions(whole, .useOpticalBounds)
    let startX: Double
    switch align {
    case .left: startX = x * Double(W)
    default: startX = x * Double(W) - bounds.width / 2 - bounds.minX
    }
    let baseline = Double(H) - y - (bounds.midY)
    var penX = startX
    for (i, piece) in pieces.enumerated() {
        let local = words ? clamp(appear * Double(pieces.count + 2) - Double(i)) / 1.0 : appear
        let a = easeOut(local)
        let word = piece + (words && i < pieces.count - 1 ? " " : "")
        let l = CTLineCreateWithAttributedString(attributed(word, a))
        let rise = (1 - a) * 22 * U
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: penX, y: baseline - rise)
        if gradient {
            ctx.setTextDrawingMode(.clip)
            CTLineDraw(l, ctx)
            let g = CGGradient(
                colorsSpace: sRGB, colors: [rgb(0x7ee7c9, a), rgb(0xa78bfa, a), rgb(0xf5a3d7, a)] as CFArray, locations: [0, 0.5, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: penX, y: 0), end: CGPoint(x: penX + bounds.width, y: 0), options: [])
        } else {
            CTLineDraw(l, ctx)
        }
        ctx.restoreGState()
        penX += CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed(word, 1)), nil, nil, nil)
    }
}

/// The window's base size and place in the frame.
func baseRect(side: Bool, aspect: Double) -> CGRect {
    if tall {
        let w = Double(W) * 0.96
        return CGRect(x: (Double(W) - w) / 2, y: Double(H) * 0.48 - w / aspect / 2, width: w, height: w / aspect)
    }
    let w = Double(W) * (side ? 0.6 : 0.69)
    let h = w / aspect
    let cx = side ? Double(W) * 0.355 : Double(W) / 2
    let cy = side ? Double(H) * 0.5 : Double(H) * 0.45
    return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)  // y from the top
}

/// Draws the window under the camera. `presence` 0…1 brings it in (a short zoom), and past 1 takes it out.
func window(_ ctx: CGContext, _ image: CGImage, footage: Footage, clipTime: Double, enter: Double, exit: Double) {
    let aspect = Double(image.width) / Double(image.height)
    let base = baseRect(side: footage.side, aspect: aspect)
    var cam = footage.camera(clipTime)
    if tall {
        // A phone is narrow: the camera is closer, on the sidebar and the start of the page unless a shot aims
        // elsewhere.
        cam.zoom = min(cam.zoom * 1.75, 2.9)
        if abs(cam.x - 0.5) < 0.001 { cam.x = 0.36 }
    }
    let inScale = mix(0.93, 1, easeOut(enter)) * mix(1.05, 1, easeOut(exit))
    let zoom = cam.zoom * inScale
    let w = base.width * zoom, h = base.height * zoom
    let focusX = base.midX, focusY = base.midY
    // The camera's point of the window goes to the base's center: at zoom 1 that's the window's center.
    let px = mix(0.5, cam.x, clamp((cam.zoom - 1) / 0.3))
    let py = mix(0.5, cam.y, clamp((cam.zoom - 1) / 0.3))
    let left = focusX - px * w, top = focusY - py * h
    let rect = CGRect(x: left, y: Double(H) - top - h, width: w, height: h)
    let alpha = min(easeOut(enter * 1.6), easeOut(exit * 1.6))
    let radius = w * 0.0105
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setShadow(offset: CGSize(width: 0, height: -30 * U), blur: 110 * U, color: rgb(0x000000, 0.7))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0x000000))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.addPath(path)
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(image, in: rect)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setAlpha(alpha * 0.9)
    ctx.addPath(path)
    ctx.setStrokeColor(rgb(0xffffff, 0.16))
    ctx.setLineWidth(1.5)
    ctx.strokePath()
    ctx.restoreGState()
}

/// A shortcut's keys as keycaps, pressed in on the beat.
func keycaps(_ ctx: CGContext, _ keys: [String], age: Double, y: Double) {
    let life = 1.1
    guard age >= 0, age < life else { return }
    let a = min(easeOut(age / 0.12), easeOut((life - age) / 0.25))
    let size = 54 * U
    let gap = 12 * U
    let font = sans(30, .semibold)
    let widths = keys.map { max(size, Double(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])), nil, nil, nil)) + 30 * U) }
    let total = widths.reduce(0, +) + gap * Double(keys.count - 1)
    var x = (Double(W) - total) / 2
    for (i, key) in keys.enumerated() {
        let local = age - Double(i) * 0.05
        let press = local < 0 ? 0 : (local < 0.12 ? 1 - local / 0.12 * 0.3 : mix(0.7, 1, easeOut((local - 0.12) / 0.2)))
        let down = (1 - press) * 6 * U
        let rect = CGRect(x: x, y: Double(H) - y - size / 2 - down, width: widths[i], height: size)
        let path = CGPath(roundedRect: rect, cornerWidth: 12 * U, cornerHeight: 12 * U, transform: nil)
        ctx.saveGState()
        ctx.setAlpha(a)
        ctx.setShadow(offset: CGSize(width: 0, height: -6 * U * press), blur: 18 * U, color: rgb(0x000000, 0.5))
        ctx.addPath(path)
        ctx.setFillColor(rgb(0xffffff, 0.14))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setAlpha(a)
        ctx.addPath(path)
        ctx.setStrokeColor(rgb(0xffffff, 0.35))
        ctx.setLineWidth(1.5)
        ctx.strokePath()
        let l = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: key,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): rgb(0xffffff),
                ]))
        let b = CTLineGetBoundsWithOptions(l, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: rect.midX - b.width / 2 - b.minX, y: rect.midY - b.midY)
        CTLineDraw(l, ctx)
        ctx.restoreGState()
        x += widths[i] + gap
    }
}

/// A check mark drawn in a circle; `p` 0…1 draws it.
func check(_ ctx: CGContext, center: CGPoint, radius: Double, p: Double) {
    guard p > 0 else { return }
    ctx.saveGState()
    ctx.setAlpha(easeOut(p * 2))
    let g = CGGradient(colorsSpace: sRGB, colors: [rgb(0x7ee7c9), rgb(0xa78bfa)] as CFArray, locations: [0, 1])!
    ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ctx.clip()
    ctx.drawLinearGradient(
        g, start: CGPoint(x: center.x - radius, y: center.y + radius), end: CGPoint(x: center.x + radius, y: center.y - radius), options: [])
    ctx.restoreGState()
    let pts = [
        CGPoint(x: center.x - radius * 0.42, y: center.y), CGPoint(x: center.x - radius * 0.1, y: center.y - radius * 0.32),
        CGPoint(x: center.x + radius * 0.45, y: center.y + radius * 0.35),
    ]
    let q = clamp((p - 0.25) / 0.75)
    guard q > 0 else { return }
    ctx.saveGState()
    ctx.setStrokeColor(rgb(0x0b0820))
    ctx.setLineWidth(radius * 0.22)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: pts[0])
    let first = min(q / 0.4, 1)
    ctx.addLine(to: CGPoint(x: mix(pts[0].x, pts[1].x, first), y: mix(pts[0].y, pts[1].y, first)))
    if q > 0.4 {
        let second = (q - 0.4) / 0.6
        ctx.addLine(to: CGPoint(x: mix(pts[1].x, pts[2].x, second), y: mix(pts[1].y, pts[2].y, second)))
    }
    ctx.strokePath()
    ctx.restoreGState()
}

func footageLayer(_ ctx: CGContext, _ footage: Footage, local: Double, duration: Double, first: Bool, last: Bool) {
    let c = footage.clipTime(local)
    // The Space on screen tints the background.
    if let e = footage.clip.events.last(where: { $0.type == "space" && Double($0.ms) / 1000 <= c }) {
        spaceTint = (e.hue, e.saturation, e.secondaryHue)
    }
    if let image = footage.clip.image(at: c) {
        window(ctx, image, footage: footage, clipTime: c, enter: first ? local / 0.45 : 1, exit: last ? (duration - local) / 0.3 : 1)
    }
    // Caption under the window (above it in the tall cut), on a soft dark band so it reads over anything.
    let captionY = tall ? 205.0 : 1004.0
    let band = CGGradient(colorsSpace: sRGB, colors: [rgb(0x07060f, 0), rgb(0x07060f, 0.82)] as CFArray, locations: [0, 1])!
    if tall {
        ctx.drawLinearGradient(band, start: CGPoint(x: 0, y: Double(H) - 380), end: CGPoint(x: 0, y: Double(H) - 150), options: [.drawsAfterEndLocation])
    } else {
        ctx.drawLinearGradient(band, start: CGPoint(x: 0, y: 190), end: CGPoint(x: 0, y: 40), options: [.drawsAfterEndLocation])
    }
    if let index = footage.captions.lastIndex(where: { $0.0 <= c + 0.0001 }) {
        let (start, text) = footage.captions[index]
        let since = local - (footage.beatTime(ofClip: max(start, footage.runs.first?.from ?? 0)) ?? 0)
        let next = index + 1 < footage.captions.count ? footage.beatTime(ofClip: footage.captions[index + 1].0) : nil
        let fade = min(clamp(since / 0.35), next.map { clamp(($0 - local) / 0.2) } ?? clamp((duration - local) / 0.25))
        line(ctx, text, font: serif(54, weight: 480), y: captionY, appear: fade, words: since < 0.6)
    }
    // Keycaps for shortcuts pressed, just above the caption.
    for e in footage.clip.events where e.type == "keys" {
        guard let at = footage.beatTime(ofClip: Double(e.ms) / 1000) else { continue }
        keycaps(ctx, e.keys, age: local - at, y: tall ? 1590 : 918)
    }
}

func draw(_ ctx: CGContext, beat: Beat, local: Double, global: Double) {
    let fadeIn = clamp(local / 0.3), fadeOut = clamp((beat.duration - local) / 0.25)
    switch beat.content {
    case .words(let lines, let size):
        spaceTint = nil
        background(ctx, t: global)
        let lh = size * U * 1.18
        let top = Double(H) / 2 - lh * Double(lines.count - 1) / 2
        for (i, text) in lines.enumerated() {
            let appear = clamp((local - 0.1 - Double(i) * 0.45) / 0.7) * fadeOut
            line(ctx, text, font: serif(size, weight: 460), y: top + Double(i) * lh, appear: appear, words: true)
        }
    case .logo(let text):
        background(ctx, t: global)
        // A ring of light grows out of the logo.
        let cx = Double(W) / 2, cy = Double(H) / 2 + 70 * U
        let burst = easeOut(local / 1.0)
        for (i, hex) in [UInt32(0x7ee7c9), 0xa78bfa, 0xf5a3d7].enumerated() {
            let r = mix(60, Double(max(W, H)) * 0.7, burst) * (1 + Double(i) * 0.12)
            ctx.saveGState()
            ctx.setStrokeColor(rgb(hex, (1 - burst) * 0.55 * fadeOut))
            ctx.setLineWidth(CGFloat(mix(26, 2, burst) * U))
            ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            ctx.strokePath()
            ctx.restoreGState()
        }
        if let logo {
            let s = 190 * U * backOut(local / 0.55)
            ctx.saveGState()
            ctx.setAlpha(clamp(local / 0.25) * fadeOut)
            ctx.setShadow(offset: .zero, blur: 80 * U, color: rgb(0xa78bfa, 0.7))
            ctx.draw(logo, in: CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s))
            ctx.restoreGState()
        }
        line(ctx, text, font: serif(92, weight: 500), y: Double(H) / 2 + 120 * U, appear: clamp((local - 0.45) / 0.6) * fadeOut, words: true)
    case .footage(let footage):
        background(ctx, t: global)
        footageLayer(ctx, footage, local: local, duration: beat.duration, first: true, last: true)
    case .checklist(let footage, let items):
        background(ctx, t: global)
        footageLayer(ctx, footage, local: local, duration: beat.duration, first: true, last: true)
        let x = tall ? 0.14 : 0.705
        let top = tall ? 1450.0 : Double(H) / 2 - 2 * 74
        let step = tall ? 84.0 : 74.0
        for (i, item) in items.enumerated() {
            let at = 0.35 + Double(i) * 0.42
            let p = clamp((local - at) / 0.45) * fadeOut
            let y = top + Double(i) * step
            check(ctx, center: CGPoint(x: x * Double(W), y: Double(H) - y), radius: 19 * U, p: p)
            line(
                ctx, item, font: serif(42, weight: 470), y: y, x: x + 34 * U / Double(W) + 0.012, appear: p, align: .left)
        }
    case .facts(let items):
        spaceTint = nil
        background(ctx, t: global)
        let step = 82.0 * U
        let top = Double(H) / 2 - step * Double(items.count - 1) / 2
        let x = tall ? 0.16 : 0.33
        for (i, item) in items.enumerated() {
            let at = 0.15 + Double(i) * 0.3
            let p = clamp((local - at) / 0.4) * fadeOut
            var text = item
            if i == 0, let number = item.split(separator: "+").first.flatMap({ Int($0) }) {
                let shown = Int(Double(number) * easeOut((local - at) / 1.1))
                text = "\(shown)+" + item.dropFirst(item.split(separator: "+").first!.count + 1)
            }
            let y = top + Double(i) * step
            check(ctx, center: CGPoint(x: x * Double(W), y: Double(H) - y), radius: 22 * U, p: p)
            line(ctx, text, font: serif(56, weight: 480), y: y, x: x + 40 * U / Double(W) + 0.012, appear: p, align: .left)
        }
    case .stamps(let items):
        spaceTint = nil
        background(ctx, t: global)
        let share = beat.duration / Double(items.count)
        let i = min(Int(local / share), items.count - 1)
        let l = local - Double(i) * share
        let a = min(clamp(l / 0.12), clamp((share - l) / 0.1))
        let punch = mix(1.12, 1, easeOut(l / 0.25))
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(W) / 2, y: CGFloat(H) / 2)
        ctx.scaleBy(x: CGFloat(punch), y: CGFloat(punch))
        ctx.translateBy(x: -CGFloat(W) / 2, y: -CGFloat(H) / 2)
        line(ctx, items[i], font: serif(110, weight: 560), y: Double(H) / 2, appear: a)
        ctx.restoreGState()
    case .end:
        spaceTint = nil
        background(ctx, t: global)
        let cx = Double(W) / 2, cy = Double(H) / 2 + 150 * U
        if let logo {
            let s = 150 * U * mix(0.85, 1, easeOut(local / 0.6))
            ctx.saveGState()
            ctx.setAlpha(clamp(local / 0.35))
            ctx.setShadow(offset: .zero, blur: 70 * U, color: rgb(0xa78bfa, 0.6))
            ctx.draw(logo, in: CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s))
            ctx.restoreGState()
        }
        line(ctx, "Nera", font: serif(150, weight: 560), y: Double(H) / 2 + 30 * U, appear: clamp((local - 0.2) / 0.6), gradient: true)
        line(ctx, "Free for macOS · Open source", font: sans(30, .medium), y: Double(H) / 2 + 130 * U, appear: clamp((local - 0.5) / 0.6), alpha: 0.78)
        // The download pill.
        let pa = clamp((local - 0.8) / 0.5)
        let label = "Download · github.com/tariq235/nera"
        let font = sans(26, .semibold)
        let lw = CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])),
            nil, nil, nil)
        let pill = CGRect(x: cx - (lw + 64 * U) / 2, y: Double(H) - (Double(H) / 2 + 210 * U) - 32 * U, width: lw + 64 * U, height: 64 * U)
        ctx.saveGState()
        ctx.setAlpha(pa)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 32 * U, cornerHeight: 32 * U, transform: nil))
        ctx.setFillColor(rgb(0xffffff))
        ctx.fillPath()
        ctx.restoreGState()
        line(ctx, label, font: font, y: Double(H) / 2 + 210 * U, appear: pa, color: 0x0b0820)
    }
    _ = fadeIn
}

// MARK: Render

var beats = timeline()
if cut == "teaser" {
    // 15 s: the hook, the import, a taste of the work, the close.
    beats = [beats[0], beats[1], beats[2], beats[3], beats[4], beats[11], beats[12]]
}
let total = beats.reduce(0) { $0 + $1.duration }
let from = args.count > 5 ? Double(args[5]) ?? 0 : 0
let to = args.count > 6 ? Double(args[6]) ?? total : total
print(String(format: "%@: %.1f s, %d beats", cut, total, beats.count))
try? FileManager.default.removeItem(at: outURL)
let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
let input = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 24_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoExpectedSourceFrameRateKey: 60, AVVideoMaxKeyFrameIntervalKey: 120,
        ],
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2, AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W,
        kCVPixelBufferHeightKey as String: H,
    ])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
let count = Int((to - from) * fps)
for i in 0..<count {
    let t = from + Double(i) / fps
    var acc = 0.0, index = 0
    while index < beats.count - 1 && t >= acc + beats[index].duration {
        acc += beats[index].duration
        index += 1
    }
    while !input.isReadyForMoreMediaData { usleep(2000) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    guard let buffer else { fatalError("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer), width: W, height: H, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    draw(ctx, beat: beats[index], local: t - acc, global: t)
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 60))
    if i % 600 == 0 { print(String(format: "  %.0f%%", Double(i) / Double(count) * 100)) }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "✔ \(outURL.path) (\(String(format: "%.1f", to - from)) s, \(W)x\(H))" : "✘ \(writer.error.map { "\($0)" } ?? "failed")")
