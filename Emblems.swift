import Cocoa
import SceneKit

// MARK: - Emblematy na suknie (biały nadruk na środku stołu, wybierany w menu Wygląd)

struct EmblemDef: Identifiable, Equatable {
    let id: String, name: String
    static let all: [EmblemDef] = [
        EmblemDef(id: "blueroot", name: "BLUEROOT"),
        EmblemDef(id: "none", name: "Brak"),
        EmblemDef(id: "star", name: "Gwiazda"),
        EmblemDef(id: "crown", name: "Korona"),
        EmblemDef(id: "eight", name: "Ósemka"),
        EmblemDef(id: "compass", name: "Róża wiatrów"),
        EmblemDef(id: "ornament", name: "Ornament"),
        EmblemDef(id: "custom", name: "Własny obraz"),
    ]
    static func find(_ id: String) -> EmblemDef { all.first { $0.id == id } ?? all[0] }
}

enum Emblems {
    static let size = 1024
    /// plik z własnym emblematem (kopia wybranego obrazu)
    static var customURL: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bilard", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.appendingPathComponent("emblem.png")
    }
    static var hasCustom: Bool { FileManager.default.fileExists(atPath: customURL.path) }

    /// Otwiera panel wyboru pliku; obraz jest zamieniany na biały nadruk (jasność × przezroczystość)
    static func pickCustom(done: @escaping (Bool) -> Void) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        p.allowsMultipleSelection = false
        p.message = "Wybierz obraz logo (najlepiej biały lub jasny na ciemnym albo przezroczystym tle)"
        guard p.runModal() == .OK, let url = p.url, let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { done(false); return }
        let n = 512
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { done(false); return }
        let sc = min(CGFloat(n) / CGFloat(cg.width), CGFloat(n) / CGFloat(cg.height))
        let w = CGFloat(cg.width) * sc, h = CGFloat(cg.height) * sc
        ctx.draw(cg, in: CGRect(x: (CGFloat(n) - w) / 2, y: (CGFloat(n) - h) / 2, width: w, height: h))
        guard let d = ctx.data else { done(false); return }
        let px = d.bindMemory(to: UInt8.self, capacity: n * n * 4)
        // tło: jeśli obraz nieprzezroczysty, jasność liczona względem narożnika (odwraca czarne logo na jasnym tle)
        var opaque = true
        for i in 0..<(n * n) where px[i * 4 + 3] < 250 { opaque = false; break }
        let c0 = (Int(px[0]) + Int(px[1]) + Int(px[2])) / 3
        let invert = opaque && c0 > 128
        for i in 0..<(n * n) {
            let a = Double(px[i * 4 + 3]) / 255
            var l = (0.299 * Double(px[i * 4]) + 0.587 * Double(px[i * 4 + 1]) + 0.114 * Double(px[i * 4 + 2])) / 255
            if a > 0 { l /= a }     // wartości premultiplied
            if invert { l = 1 - l }
            let v = UInt8(max(0, min(1, opaque ? l : a * (l * 0.7 + 0.3))) * 255)
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = 255
        }
        guard let out = ctx.makeImage(), let dst = CGImageDestinationCreateWithURL(customURL as CFURL, "public.png" as CFString, 1, nil) else { done(false); return }
        CGImageDestinationAddImage(dst, out, nil)
        done(CGImageDestinationFinalize(dst))
    }

    /// Obraz do mieszania addytywnego: czarne tło, biały nadruk.
    static func image(_ id: String) -> CGImage? {
        if id == "none" { return nil }
        if id == "custom" {
            guard let s = CGImageSourceCreateWithURL(customURL as CFURL, nil), let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { return nil }
            return i
        }
        let n = size
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        let c = CGPoint(x: n / 2, y: n / 2), R = CGFloat(n) * 0.42
        let white = CGColor(gray: 1, alpha: 1)
        ctx.setFillColor(white); ctx.setStrokeColor(white); ctx.setLineJoin(.round); ctx.setLineCap(.round)
        func polar(_ r: CGFloat, _ a: CGFloat) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
        switch id {
        case "blueroot": drawBlueroot(ctx, n)
        case "star":
            ctx.setLineWidth(R * 0.05); ctx.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)); ctx.strokePath()
            ctx.setLineWidth(R * 0.02); ctx.addEllipse(in: CGRect(x: c.x - R * 0.93, y: c.y - R * 0.93, width: R * 1.86, height: R * 1.86)); ctx.strokePath()
            for i in 0..<10 {
                let p = polar(i % 2 == 0 ? R * 0.78 : R * 0.32, .pi / 2 + CGFloat(i) * .pi / 5)
                i == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
            }
            ctx.closePath(); ctx.fillPath()
        case "crown":
            let w = R * 1.7, x0 = c.x - w / 2, y0 = c.y - R * 0.45, hh = R * 0.9
            ctx.move(to: CGPoint(x: x0, y: y0))
            ctx.addLine(to: CGPoint(x: x0 - R * 0.06, y: y0 + hh))
            ctx.addLine(to: CGPoint(x: x0 + w * 0.25, y: y0 + hh * 0.42))
            ctx.addLine(to: CGPoint(x: c.x, y: y0 + hh * 1.12))
            ctx.addLine(to: CGPoint(x: x0 + w * 0.75, y: y0 + hh * 0.42))
            ctx.addLine(to: CGPoint(x: x0 + w + R * 0.06, y: y0 + hh))
            ctx.addLine(to: CGPoint(x: x0 + w, y: y0)); ctx.closePath(); ctx.fillPath()
            ctx.fill(CGRect(x: x0, y: y0 - R * 0.2, width: w, height: R * 0.13))
            for p in [CGPoint(x: x0 - R * 0.06, y: y0 + hh), CGPoint(x: x0 + w * 0.25, y: y0 + hh * 0.42), CGPoint(x: c.x, y: y0 + hh * 1.12),
                      CGPoint(x: x0 + w * 0.75, y: y0 + hh * 0.42), CGPoint(x: x0 + w + R * 0.06, y: y0 + hh)] {
                ctx.fillEllipse(in: CGRect(x: p.x - R * 0.07, y: p.y + R * 0.02, width: R * 0.14, height: R * 0.14))
            }
        case "eight":
            ctx.setLineWidth(R * 0.07); ctx.addEllipse(in: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R)); ctx.strokePath()
            ctx.setLineWidth(R * 0.025); ctx.addEllipse(in: CGRect(x: c.x - R * 0.9, y: c.y - R * 0.9, width: R * 1.8, height: R * 1.8)); ctx.strokePath()
            let f = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, R * 1.25, nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "8", attributes: [.font: f, .foregroundColor: NSColor.white]))
            let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            ctx.textPosition = CGPoint(x: c.x - b.midX, y: c.y - b.midY); CTLineDraw(line, ctx)
        case "compass":
            ctx.setLineWidth(R * 0.04); ctx.addEllipse(in: CGRect(x: c.x - R * 0.9, y: c.y - R * 0.9, width: R * 1.8, height: R * 1.8)); ctx.strokePath()
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4, long = i % 2 == 0
                let tip = polar(long ? R : R * 0.62, a)
                ctx.move(to: tip); ctx.addLine(to: polar(R * 0.12, a + .pi / 8)); ctx.addLine(to: c); ctx.addLine(to: polar(R * 0.12, a - .pi / 8)); ctx.closePath(); ctx.fillPath()
            }
            ctx.setBlendMode(.clear); ctx.fillEllipse(in: CGRect(x: c.x - R * 0.06, y: c.y - R * 0.06, width: R * 0.12, height: R * 0.12))
            ctx.setBlendMode(.normal); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillEllipse(in: CGRect(x: c.x - R * 0.06, y: c.y - R * 0.06, width: R * 0.12, height: R * 0.12))
        case "ornament":
            ctx.setLineWidth(R * 0.04)
            for k in [1.0, 0.82, 0.64] as [CGFloat] {
                ctx.move(to: CGPoint(x: c.x, y: c.y + R * k)); ctx.addLine(to: CGPoint(x: c.x + R * k * 0.62, y: c.y))
                ctx.addLine(to: CGPoint(x: c.x, y: c.y - R * k)); ctx.addLine(to: CGPoint(x: c.x - R * k * 0.62, y: c.y)); ctx.closePath(); ctx.strokePath()
            }
            ctx.fillEllipse(in: CGRect(x: c.x - R * 0.12, y: c.y - R * 0.12, width: R * 0.24, height: R * 0.24))
            for s in [-1.0, 1.0] as [CGFloat] {
                ctx.move(to: CGPoint(x: c.x + s * R * 0.7, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + s * R * 1.15, y: c.y)); ctx.strokePath()
                ctx.fillEllipse(in: CGRect(x: c.x + s * R * 1.2 - R * 0.05, y: c.y - R * 0.05, width: R * 0.1, height: R * 0.1))
            }
        default: return nil
        }
        return ctx.makeImage()
    }

    /// Logo BLUEROOT (znak + napis) z wektorów intra, wpasowane w środek obrazu
    private static func drawBlueroot(_ ctx: CGContext, _ n: Int) {
        let m = BluerootIntro.markPaths
        var paths: [CGPath] = m.bands + m.leaves
        if let w = BluerootIntro.wordPaths { paths += [w.0, w.1] }
        var box = CGRect.null
        for p in paths { box = box.union(p.boundingBoxOfPath) }
        guard !box.isNull else { return }
        let s = CGFloat(n) * 0.9 / max(box.width, box.height)
        var tr = CGAffineTransform(translationX: CGFloat(n) / 2, y: CGFloat(n) / 2).scaledBy(x: s, y: -s).translatedBy(x: -box.midX, y: -box.midY)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        for p in paths { if let q = p.copy(using: &tr) { ctx.addPath(q) } }
        ctx.fillPath(using: .winding)
    }
}
