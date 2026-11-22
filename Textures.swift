import Cocoa

// MARK: - Pomocnicze (kolory, obrazy)

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, a])!
}
func nsc(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
func makeImage(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}
func gradient(_ c: [CGColor], _ l: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: srgb, colors: c as CFArray, locations: l)! }

// MARK: - Proceduralne tekstury

enum Tex {
    /// obraz z funkcji piksela (RGBA 0…255)
    static func pixels(_ w: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
        var data = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let c = f(x, y), i = (y * w + x) * 4
            data[i] = c.0; data[i + 1] = c.1; data[i + 2] = c.2; data[i + 3] = c.3
        } }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: srgb,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }

    // szum wartości z okresowością (kafelkowanie bez szwów)
    static func hash(_ x: Int, _ y: Int, _ s: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ s &* 2147483647)
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Double(h & 0xFFFFFF) / Double(0xFFFFFF)
    }
    static func vnoise(_ x: Double, _ y: Double, period: Int, seed: Int) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func h(_ a: Int, _ b: Int) -> Double { hash(((a % period) + period) % period, ((b % period) + period) % period, seed) }
        let a = h(xi, yi), b = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }
    static func fbm(_ x: Double, _ y: Double, base: Int, octaves: Int, seed: Int) -> Double {
        var v = 0.0, amp = 0.5, f = 1.0, per = base
        for o in 0..<octaves {
            v += amp * vnoise(x * f, y * f, period: per, seed: seed + o)
            amp *= 0.5; f *= 2; per *= 2
        }
        return v
    }

    // MARK: Sukno: mapa wysokości włókien → kolor (szary), normalna, chropowatość
    static let clothSize = 512
    static let clothHeight: [Double] = {
        let n = clothSize
        var hgt = [Double](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            let fx = Double(x) / Double(n), fy = Double(y) / Double(n)
            // włókna: drobny szum biały + średnioskalowy szum + lekka anizotropia
            let fine = hash(x, y, 7)
            let mid = fbm(fx * 64, fy * 64, base: 64, octaves: 2, seed: 3)
            let low = fbm(fx * 8, fy * 8, base: 8, octaves: 3, seed: 11)
            hgt[y * n + x] = 0.55 * fine + 0.3 * mid + 0.15 * low
        } }
        return hgt
    }()

    static func clothDiffuse() -> CGImage {
        let n = clothSize
        return pixels(n, n) { x, y in
            let h = clothHeight[y * n + x]
            let v = UInt8(max(0, min(255, 150 + (h - 0.5) * 210)))
            return (v, v, v, 255)
        }
    }
    static func clothNormal() -> CGImage {
        let n = clothSize
        return pixels(n, n) { x, y in
            func H(_ a: Int, _ b: Int) -> Double { clothHeight[((b + n) % n) * n + ((a + n) % n)] }
            let dx = (H(x + 1, y) - H(x - 1, y)) * 3.2
            let dy = (H(x, y + 1) - H(x, y - 1)) * 3.2
            let l = sqrt(dx * dx + dy * dy + 1)
            return (UInt8((-dx / l * 0.5 + 0.5) * 255), UInt8((-dy / l * 0.5 + 0.5) * 255), UInt8((1 / l * 0.5 + 0.5) * 255), 255)
        }
    }
    static func clothRoughness() -> CGImage {
        let n = clothSize
        return pixels(n, n) { x, y in
            let v = UInt8(max(0, min(255, 232 + (clothHeight[y * n + x] - 0.5) * 50)))
            return (v, v, v, 255)
        }
    }

    // MARK: Mahoń
    static func wood(_ light: Bool = false) -> CGImage {
        let w = 1024, h = 512
        return pixels(w, h) { x, y in
            let fx = Double(x) / Double(w), fy = Double(y) / Double(h)
            let warp = fbm(fx * 4, fy * 6, base: 4, octaves: 3, seed: 21) * 6
            let ring = sin((fy * 38 + warp * 2.2) * .pi) * 0.5 + 0.5
            let streak = fbm(fx * 90, fy * 6, base: 90, octaves: 2, seed: 33)
            let t = 0.3 * ring + 0.7 * streak
            let r = 0.20 + 0.20 * t, g = 0.075 + 0.075 * t, b = 0.04 + 0.035 * t
            let k = light ? 1.25 : 1.0
            return (UInt8(min(255, r * k * 255)), UInt8(min(255, g * k * 255)), UInt8(min(255, b * k * 255)), 255)
        }
    }

    // MARK: Siatka łuzy (alfa)
    static func net() -> CGImage {
        let w = 256, h = 128
        return makeImage(w, h) { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setStrokeColor(rgb(0xD8D2C0, 0.95))
            ctx.setLineWidth(2.2)
            for i in 0...16 { let x = CGFloat(i) * CGFloat(w) / 16; ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: CGFloat(h))) }
            for j in 0...8 { let y = CGFloat(j) * CGFloat(h) / 8; ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: CGFloat(w), y: y)) }
            ctx.strokePath()
        }
    }

    // MARK: Mapa otoczenia (klub bilardowy: ciemne ściany, jasne lampy nad stołem)
    static func environment() -> CGImage {
        let w = 1024, h = 512
        return makeImage(w, h) { ctx in
            ctx.drawLinearGradient(gradient([rgb(0x6A6256), rgb(0x2B2620), rgb(0x1A1613), rgb(0x0C0A09)], [0, 0.45, 0.6, 1]),
                                   start: CGPoint(x: 0, y: CGFloat(h)), end: CGPoint(x: 0, y: 0), options: [])
            // lampy (miękkie prostokąty) w górnej półsferze
            for (cx, w0, h0, a) in [(0.25, 0.14, 0.05, 1.0), (0.5, 0.2, 0.06, 1.0), (0.75, 0.14, 0.05, 1.0), (0.0, 0.1, 0.04, 0.6), (1.0, 0.1, 0.04, 0.6)] as [(Double, Double, Double, Double)] {
                let rect = CGRect(x: (cx - w0 / 2) * Double(w), y: Double(h) * 0.80, width: w0 * Double(w), height: h0 * Double(h))
                ctx.setShadow(offset: .zero, blur: 40, color: rgb(0xFFF1D8, a))
                ctx.setFillColor(rgb(0xFFF6E8, a))
                ctx.fill(rect)
            }
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            // okna / panele na horyzoncie
            ctx.setFillColor(rgb(0x3A4A60, 0.55))
            for i in 0..<6 { ctx.fill(CGRect(x: CGFloat(i) * 170 + 30, y: CGFloat(h) * 0.52, width: 90, height: 40)) }
        }
    }

    // MARK: Bile
    static let ballColors: [UInt32] = [0xF5F1E6, 0xF2C31A, 0x1F4FC9, 0xD8281E, 0x4B2A8C, 0xF0701A, 0x1C8A3A, 0x8E1F1F, 0x101010]

    static func ball(_ n: Int) -> CGImage {
        let w = 1024, h = 512
        let color = ballColors[n <= 8 ? n : n - 8]
        let numFont = NSFont(name: "HelveticaNeue-Bold", size: 84) ?? NSFont.boldSystemFont(ofSize: 84)
        return makeImage(w, h) { ctx in
            ctx.setFillColor(rgb(n == 0 ? 0xF7F4EA : (n >= 9 ? 0xF7F4EA : color)))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            if n >= 9 {
                // pas w kolorze: |szerokość| < 0.62 rad
                let band = CGFloat(h) * 0.5 * 0.40
                ctx.setFillColor(rgb(color))
                ctx.fill(CGRect(x: 0, y: CGFloat(h) / 2 - band, width: CGFloat(w), height: band * 2))
            }
            if n == 0 {
                // biała bila: kilka drobnych kropek orientacyjnych
                ctx.setFillColor(rgb(0xC9362B))
                for u in [0.25, 0.75] { ctx.fillEllipse(in: CGRect(x: u * Double(w) - 9, y: Double(h) / 2 - 9, width: 18, height: 18)) }
            } else {
                for u in [0.25, 0.75] {
                    let cx = CGFloat(u) * CGFloat(w), cy = CGFloat(h) / 2, r: CGFloat = 66
                    ctx.setFillColor(rgb(0xFBF8EE))
                    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                    let str = NSAttributedString(string: "\(n)", attributes: [.font: numFont, .foregroundColor: NSColor(white: 0.05, alpha: 1)])
                    let line = CTLineCreateWithAttributedString(str)
                    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                    ctx.saveGState()
                    ctx.textPosition = CGPoint(x: cx - b.midX, y: cy - b.midY)
                    CTLineDraw(line, ctx)
                    ctx.restoreGState()
                }
            }
        }
    }
}
typealias SeededRNG = SeededGen
