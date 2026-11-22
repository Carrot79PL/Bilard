import Cocoa
// Generuje AppIcon.iconset: bila „8” 3D na niebieskim suknie (BLUEROOT), styl macOS (squircle, gradienty, głębia)
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func c(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, a])!
}
func grad(_ cols: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: locs)! }

// Szum sukna (deterministyczny)
func feltNoise(_ px: Int) -> CGImage {
    var st: UInt64 = 0x5EED
    var bytes = [UInt8](repeating: 0, count: px * px * 4)
    for i in 0..<(px * px) {
        st = st &* 6364136223846793005 &+ 1442695040888963407
        let v = UInt8(truncatingIfNeeded: st >> 56)
        let a: UInt8 = 22
        let lum = UInt8((Int(v) * Int(a)) / 255)
        bytes[i * 4] = lum; bytes[i * 4 + 1] = lum; bytes[i * 4 + 2] = lum; bytes[i * 4 + 3] = a
    }
    let ctx = CGContext(data: &bytes, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

func render(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(px)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: s / 1024, y: s / 1024)          // rysujemy w siatce 1024 (szablon macOS)
    let box = CGRect(x: 100, y: 100, width: 824, height: 824)
    let sq = CGPath(roundedRect: box, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // cień całej ikony
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: c(0, 0.45))
    ctx.addPath(sq); ctx.setFillColor(c(0x0A2E66)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(sq); ctx.clip()
    // sukno: niebieskie (BLUEROOT), oświetlone lampą z góry
    ctx.drawRadialGradient(grad([c(0x3FA0F0), c(0x1B63C0), c(0x0B3577), c(0x061D45)], [0, 0.35, 0.75, 1]),
                           startCenter: CGPoint(x: 470, y: 720), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 560), endRadius: 640, options: .drawsAfterEndLocation)
    if px >= 64 {
        ctx.setBlendMode(.overlay)
        ctx.draw(feltNoise(px), in: box.insetBy(dx: -100, dy: -100))
        ctx.setBlendMode(.normal)
    }
    // stożek światła lampy
    ctx.drawRadialGradient(grad([c(0xFFFFFF, 0.22), c(0xFFFFFF, 0)], [0, 1]),
                           startCenter: CGPoint(x: 480, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 480, y: 980), endRadius: 560, options: [])
    // winieta przy krawędzi (głębia „bandy”)
    ctx.drawRadialGradient(grad([c(0, 0), c(0, 0), c(0, 0.42)], [0, 0.62, 1]),
                           startCenter: CGPoint(x: 512, y: 540), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 540), endRadius: 600, options: .drawsAfterEndLocation)

    // bila 8
    let r: CGFloat = 238, cx: CGFloat = 512, cy: CGFloat = 566
    // cień kontaktowy na suknie
    ctx.saveGState()
    ctx.translateBy(x: cx + 46, y: cy - r * 0.93)
    ctx.scaleBy(x: 1, y: 0.32)
    ctx.drawRadialGradient(grad([c(0x00081A, 0.85), c(0x00081A, 0.35), c(0x00081A, 0)], [0, 0.45, 1]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r * 1.18, options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)); ctx.clip()
    // bryła: lakierowana czerń
    ctx.drawRadialGradient(grad([c(0x5C6270), c(0x1E2128), c(0x08090C), c(0x020203)], [0, 0.28, 0.7, 1]),
                           startCenter: CGPoint(x: cx - r * 0.38, y: cy + r * 0.42), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: .drawsAfterEndLocation)
    // okienko z numerem (lekko w perspektywie)
    let wc = CGPoint(x: cx - r * 0.16, y: cy + r * 0.17)
    ctx.saveGState()
    ctx.translateBy(x: wc.x, y: wc.y)
    ctx.rotate(by: 0.32)
    ctx.scaleBy(x: 0.9, y: 1)
    let wr = r * 0.47
    ctx.addEllipse(in: CGRect(x: -wr, y: -wr, width: 2 * wr, height: 2 * wr)); ctx.clip()
    ctx.drawRadialGradient(grad([c(0xFFFFFF), c(0xF3F0E6), c(0xC9C4B6)], [0, 0.6, 1]),
                           startCenter: CGPoint(x: -wr * 0.3, y: wr * 0.35), startRadius: 0,
                           endCenter: .zero, endRadius: wr, options: .drawsAfterEndLocation)
    let f = NSFont.systemFont(ofSize: wr * 1.45, weight: .heavy)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "8", attributes: [.font: f, .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 1)]))
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: -b.midX, y: -b.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
    // odbicie niebieskiego sukna na dolnej krawędzi
    ctx.drawRadialGradient(grad([c(0x2F8BE6, 0), c(0x2F8BE6, 0), c(0x48A6FF, 0.55)], [0, 0.72, 1]),
                           startCenter: CGPoint(x: cx - r * 0.12, y: cy + r * 0.22), startRadius: 0,
                           endCenter: CGPoint(x: cx - r * 0.12, y: cy + r * 0.22), endRadius: r * 1.22, options: [])
    // główny refleks lampy
    ctx.saveGState()
    ctx.translateBy(x: cx - r * 0.42, y: cy + r * 0.5)
    ctx.rotate(by: 0.62)
    ctx.scaleBy(x: 1, y: 0.58)
    ctx.drawRadialGradient(grad([c(0xFFFFFF, 0.95), c(0xFFFFFF, 0.35), c(0xFFFFFF, 0)], [0, 0.35, 1]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r * 0.36, options: [])
    ctx.restoreGState()
    // drugi, mały refleks (okno sali)
    ctx.drawRadialGradient(grad([c(0xFFFFFF, 0.5), c(0xFFFFFF, 0)], [0, 1]),
                           startCenter: CGPoint(x: cx + r * 0.52, y: cy + r * 0.55), startRadius: 0,
                           endCenter: CGPoint(x: cx + r * 0.52, y: cy + r * 0.55), endRadius: r * 0.1, options: [])
    ctx.restoreGState()

    // znak studia BLUEROOT
    if px >= 128 {
        let wf = NSFont.systemFont(ofSize: 54, weight: .heavy)
        let attrs: [NSAttributedString.Key: Any] = [.font: wf, .kern: 14, .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.88)]
        let wl = CTLineCreateWithAttributedString(NSAttributedString(string: "BLUEROOT", attributes: attrs))
        let wb = CTLineGetBoundsWithOptions(wl, .useGlyphPathBounds)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 6, color: c(0x00102E, 0.7))
        ctx.textPosition = CGPoint(x: 512 - wb.midX + 7, y: 168)
        CTLineDraw(wl, ctx)
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // szklisty połysk krawędzi
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: box.insetBy(dx: 2, dy: 2), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setLineWidth(4); ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(grad([c(0xFFFFFF, 0.45), c(0xFFFFFF, 0.05), c(0xFFFFFF, 0.12)], [0, 0.5, 1]),
                           start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try? render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
