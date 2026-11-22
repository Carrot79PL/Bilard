import Cocoa
import ImageIO

// MARK: - Asynchroniczna synteza tekstur PBR (równolegle na wszystkich rdzeniach CPU, pamięć współdzielona Apple Silicon)

struct TexturePack {
    var clothDiffuse: CGImage, clothNormal: CGImage, clothRough: CGImage
    var balls: [CGImage]
    var ballRough: CGImage, ballNormal: CGImage
    var woodAlbedo: CGImage, woodNormal: CGImage, woodRough: CGImage
    var mapleAlbedo: CGImage, mapleNormal: CGImage, mapleRough: CGImage
    var buttAlbedo: CGImage, buttNormal: CGImage, buttRough: CGImage
    var brassAlbedo: CGImage, brassNormal: CGImage, brassRough: CGImage
    var leatherAlbedo: CGImage, leatherNormal: CGImage
    var tip: CGImage, tipNormal: CGImage
    var decalAdd: CGImage, decalMul: CGImage, dot: CGImage, env: CGImage, net: CGImage
    var chalk: CGImage, glare: CGImage, shaft: CGImage, contact: CGImage
}

/// bufor wysokości z zawijaniem (kafelkowanie)
final class HeightBuf {
    let w: Int, h: Int
    let p: UnsafeMutablePointer<Float>
    init(_ w: Int, _ h: Int, _ f: (Int, Int) -> Float) {
        self.w = w; self.h = h
        p = UnsafeMutablePointer<Float>.allocate(capacity: w * h)
        let buf = p
        DispatchQueue.concurrentPerform(iterations: h) { y in
            for x in 0..<w { buf[y * w + x] = f(x, y) }
        }
    }
    deinit { p.deallocate() }
    @inline(__always) func at(_ x: Int, _ y: Int) -> Float { p[((y + h) % h) * w + ((x + w) % w)] }
    /// mapa normalnych (styczna), strength – siła
    func normalMap(_ strength: Float) -> CGImage {
        Par.image(w, h) { x, y in
            let dx = (self.at(x + 1, y) - self.at(x - 1, y)) * strength
            let dy = (self.at(x, y + 1) - self.at(x, y - 1)) * strength
            let l = sqrt(dx * dx + dy * dy + 1)
            return (UInt8((-dx / l * 0.5 + 0.5) * 255), UInt8((-dy / l * 0.5 + 0.5) * 255), UInt8((1 / l * 0.5 + 0.5) * 255), 255)
        }
    }
}

enum Par {
    /// obraz RGBA generowany równolegle po wierszach
    static func image(_ w: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> CGImage {
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        DispatchQueue.concurrentPerform(iterations: h) { y in
            for x in 0..<w {
                let c = f(x, y), i = (y * w + x) * 4
                buf[i] = c.0; buf[i + 1] = c.1; buf[i + 2] = c.2; buf[i + 3] = c.3
            }
        }
        let data = Data(bytesNoCopy: buf, count: w * h * 4, deallocator: .free)
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: srgb,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    }
}

enum TextureFactory {
    @inline(__always) static func b(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v))) }

    // szum okresowy o niezależnych okresach w x i y (kafelkowanie bez szwów)
    static func pn(_ x: Double, _ y: Double, _ px: Int, _ py: Int, _ s: Int) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func h(_ a: Int, _ c: Int) -> Double { Tex.hash(((a % px) + px) % px, ((c % py) + py) % py, s) }
        let a = h(xi, yi), bb = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1)
        let top = a + (bb - a) * sx, bot = c + (d - c) * sx
        return top + (bot - top) * sy
    }
    static func pf(_ x: Double, _ y: Double, _ px: Int, _ py: Int, _ oct: Int, _ s: Int) -> Double {
        var v = 0.0, amp = 0.5, f = 1.0
        for o in 0..<oct { v += amp * pn(x * f, y * f, px * Int(f), py * Int(f), s + o); amp *= 0.5; f *= 2 }
        return v
    }

    // MARK: Główna funkcja
    static func generate(progress: @escaping (Double, String) -> Void) -> TexturePack {
        let t0 = Date()
        var step = 0.0
        let total = 12.0
        func tick(_ s: String) { step += 1; progress(step / total, s) }
        progress(0, "Sukno 4K…")

        // --- sukno 4096²: splot (twill), włókna, kępki
        let N = 4096
        let hb = HeightBuf(N, N) { x, y in
            let fx = Double(x), fy = Double(y)
            let fine = Tex.hash(x, y, 7)
            let fib = pn(fx / 4, fy / 4, N / 4, N / 4, 3)
            let mid = pn(fx / 32, fy / 32, N / 32, N / 32, 5)
            let low = pn(fx / 256, fy / 256, 16, 16, 9)
            let tw = 0.5 + 0.5 * sin(2 * .pi * (fx + fy) / 16)
            let tw2 = 0.5 + 0.5 * sin(2 * .pi * (fx - fy) / 32)
            return Float(0.32 * fine + 0.26 * fib + 0.14 * mid + 0.1 * low + 0.12 * tw + 0.06 * tw2)
        }
        let clothDiffuse = Par.image(N, N) { x, y in
            let h = Double(hb.at(x, y))
            let v = b(150 + (h - 0.5) * 230)
            return (v, v, v, 255)
        }
        tick("Sukno: normalne…")
        let clothNormal = hb.normalMap(3.4)
        let clothRough = Par.image(N, N) { x, y in
            let v = b(236 + (Double(hb.at(x, y)) - 0.5) * 55)
            return (v, v, v, 255)
        }
        tick("Bile (żywica)…")

        // --- bile: albedo 2048×1024 + wspólne mapy roughness/normal (polerowana żywica)
        let balls = (0..<16).map { ballAlbedo($0) }
        let bw = 2048, bh = 1024
        let bhb = HeightBuf(bw, bh) { x, y in
            let fx = Double(x), fy = Double(y)
            return Float(0.6 * pn(fx / 3, fy / 3, bw / 3 + 1, bh / 3 + 1, 31) + 0.4 * pf(fx / 64, fy / 64, 32, 16, 3, 40))
        }
        let ballNormal = bhb.normalMap(0.55)
        let ballRough = Par.image(bw, bh) { x, y in
            // roughness 0.03–0.08: drobne wahania polerowanej żywicy
            let r = 0.03 + 0.05 * (0.6 * Double(bhb.at(x, y)) + 0.4 * pn(Double(x) / 90, Double(y) / 90, 23, 12, 77))
            let v = b(r * 255)
            return (v, v, v, 255)
        }
        tick("Drewno (mahoń)…")

        // --- drewno
        let mah = woodSet(w: 2048, h: 1024, alongY: false, light: (0.20, 0.07, 0.04), dark: (0.07, 0.025, 0.015), seed: 21, rings: 38, rough: 0.34)
        tick("Kij: klon…")
        let maple = woodSet(w: 512, h: 2048, alongY: true, light: (0.93, 0.78, 0.55), dark: (0.74, 0.55, 0.33), seed: 51, rings: 10, rough: 0.28)
        let walnut = woodSet(w: 512, h: 2048, alongY: true, light: (0.24, 0.12, 0.07), dark: (0.08, 0.035, 0.02), seed: 61, rings: 12, rough: 0.30)
        let butt = inlays(walnut.0)
        tick("Mosiądz i skóra…")

        // --- mosiądz szczotkowany z patyną i rysami
        let M = 1024
        let brhb = HeightBuf(M, M) { x, y in
            let fx = Double(x), fy = Double(y)
            let brush = pn(fx / 80, fy / 1.2, M / 80, M, 91)            // smugi wzdłuż x
            let scr = Tex.hash(x / 24, y, 93) > 0.985 ? 0.5 : 0.0
            return Float(0.7 * brush + scr + 0.3 * Tex.hash(x, y, 95))
        }
        let brassAlbedo = Par.image(M, M) { x, y in
            let fx = Double(x), fy = Double(y)
            let patina = pf(fx / 120, fy / 120, 9, 9, 3, 97)
            let wear = Double(brhb.at(x, y))
            var r = 0.80, g = 0.62, bl = 0.27
            let p = max(0, patina - 0.55) * 2.2      // zielonkawa patyna w zagłębieniach
            r = r * (1 - 0.35 * p) + 0.18 * p; g = g * (1 - 0.1 * p) + 0.45 * p * 0.4; bl = bl * (1 - 0.2 * p) + 0.22 * p * 0.4
            let k = 0.85 + 0.25 * wear
            return (b(r * k * 255), b(g * k * 255), b(bl * k * 255), 255)
        }
        let brassNormal = brhb.normalMap(1.6)
        let brassRough = Par.image(M, M) { x, y in
            let v = b((0.26 + 0.22 * Double(brhb.at(x, y)) + 0.2 * max(0, pf(Double(x) / 120, Double(y) / 120, 9, 9, 3, 97) - 0.55)) * 255)
            return (v, v, v, 255)
        }
        // --- skóra: komórkowy (Voronoi) wzór ziarna
        let cells = 40
        let leh = HeightBuf(M, M) { x, y in
            let u = Double(x) / Double(M) * Double(cells), v = Double(y) / Double(M) * Double(cells)
            let cx = Int(floor(u)), cy = Int(floor(v))
            var f1 = 9.0, f2 = 9.0
            for j in -1...1 { for i in -1...1 {
                let gx = cx + i, gy = cy + j
                let wx = ((gx % cells) + cells) % cells, wy = ((gy % cells) + cells) % cells
                let px = Double(gx) + Tex.hash(wx, wy, 111), py = Double(gy) + Tex.hash(wx, wy, 113)
                let d = sqrt((u - px) * (u - px) + (v - py) * (v - py))
                if d < f1 { f2 = f1; f1 = d } else if d < f2 { f2 = d }
            } }
            let edge = min(1, (f2 - f1) * 3.5)
            return Float(edge * 0.8 + 0.2 * Tex.hash(x, y, 115))
        }
        let leatherNormal = leh.normalMap(2.4)
        let leatherAlbedo = Par.image(M, M) { x, y in
            let h = Double(leh.at(x, y))
            let k = 0.55 + 0.45 * h
            return (b(0.20 * k * 255), b(0.115 * k * 255), b(0.075 * k * 255), 255)
        }
        tick("Detale…")

        // --- końcówka kija: niebieska skóra z kredą
        let tipH = HeightBuf(256, 256) { x, y in Float(0.6 * Tex.hash(x, y, 121) + 0.4 * Tex.hash(x / 3, y / 3, 123)) }
        let tip = Par.image(256, 256) { x, y in
            let h = Double(tipH.at(x, y))
            let chalk = Tex.hash(x / 2, y / 2, 125) > 0.55 ? 0.35 : 0.0
            return (b((0.10 + 0.5 * chalk + 0.05 * h) * 255), b((0.28 + 0.45 * chalk + 0.06 * h) * 255), b((0.62 + 0.3 * chalk + 0.08 * h) * 255), 255)
        }
        let tipNormal = tipH.normalMap(1.2)

        let (decalAdd, decalMul) = tableDecals()
        let dot = softDot()
        tick("Optyka i oświetlenie…")
        let env = environment()
        let net = netImage()
        let chalk = chalkDecal()
        let glare = glareSprite()
        let shaft = shaftGradient()
        let contact = contactShadow()
        tick("Gotowe")
        print(String(format: "TEXTURES generated in %.2f s", Date().timeIntervalSince(t0)))
        progress(1, "Gotowe")
        return TexturePack(clothDiffuse: clothDiffuse, clothNormal: clothNormal, clothRough: clothRough, balls: balls,
                           ballRough: ballRough, ballNormal: ballNormal,
                           woodAlbedo: mah.0, woodNormal: mah.1, woodRough: mah.2,
                           mapleAlbedo: maple.0, mapleNormal: maple.1, mapleRough: maple.2,
                           buttAlbedo: butt, buttNormal: walnut.1, buttRough: walnut.2,
                           brassAlbedo: brassAlbedo, brassNormal: brassNormal, brassRough: brassRough,
                           leatherAlbedo: leatherAlbedo, leatherNormal: leatherNormal, tip: tip, tipNormal: tipNormal,
                           decalAdd: decalAdd, decalMul: decalMul, dot: dot, env: env, net: net, chalk: chalk, glare: glare, shaft: shaft, contact: contact)
    }

    // MARK: Drewno (albedo, normal, roughness) z porami i usłojeniem
    static func woodSet(w: Int, h: Int, alongY: Bool, light: (Double, Double, Double), dark: (Double, Double, Double),
                        seed: Int, rings: Int, rough: Double) -> (CGImage, CGImage, CGImage) {
        func parts(_ x: Int, _ y: Int) -> (grain: Double, pore: Double, t: Double) {
            let a = alongY ? y : x, c = alongY ? x : y
            let la = alongY ? h : w, lc = alongY ? w : h
            let fa = Double(a) / Double(la), fc = Double(c) / Double(lc)
            let warp = pf(fa * 4, fc * 6, 4, 6, 3, seed) * 6
            let ring = 0.5 + 0.5 * sin((fc * Double(rings) + warp * 0.35) * 2 * .pi)
            let streak = pf(fa * 24, fc * Double(lc / 4), 24, lc / 4, 2, seed + 7)
            let fine = pn(fa * 6, fc * Double(lc / 2), 6, lc / 2, seed + 13)
            let poreHash = Tex.hash(a / 7, c, seed + 3)
            let pore = poreHash > 0.992 ? (poreHash - 0.992) / 0.008 : 0.0
            let t = 0.28 * ring + 0.5 * streak + 0.22 * fine
            return (0.4 * ring + 0.35 * streak + 0.25 * fine, pore, t)
        }
        let hh = HeightBuf(w, h) { x, y in let p = parts(x, y); return Float(p.grain * 0.5 - p.pore * 0.9) }
        let albedo = Par.image(w, h) { x, y in
            let p = parts(x, y)
            let t = p.t, k = 1 - 0.55 * p.pore
            return (b((dark.0 + (light.0 - dark.0) * t) * k * 255), b((dark.1 + (light.1 - dark.1) * t) * k * 255),
                    b((dark.2 + (light.2 - dark.2) * t) * k * 255), 255)
        }
        let normal = hh.normalMap(2.2)
        let rg = Par.image(w, h) { x, y in
            let p = parts(x, y)
            let v = b((rough + 0.05 * p.grain + 0.35 * p.pore) * 255)
            return (v, v, v, 255)
        }
        return (albedo, normal, rg)
    }

    /// zdobienia (inlays) na części chwytowej kija: rombowe wstawki z kości słoniowej, pierścienie, owijka
    static func inlays(_ base: CGImage) -> CGImage {
        let w = base.width, h = base.height
        return makeImage(w, h) { ctx in
            ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
            let ivory = rgb(0xF1E8D2), maple = rgb(0xE8C48A), brass = rgb(0xC9A24A)
            // pierścienie (górna część = bliżej ferruli)
            for (y, hgt, col) in [(0.82, 0.012, ivory), (0.80, 0.006, maple), (0.52, 0.006, maple), (0.50, 0.012, ivory), (0.18, 0.02, brass)] as [(Double, Double, CGColor)] {
                ctx.setFillColor(col)
                ctx.fill(CGRect(x: 0, y: y * Double(h), width: Double(w), height: hgt * Double(h)))
            }
            // rombowe wstawki (4 wokół obwodu)
            for k in 0..<4 {
                let cx = (Double(k) + 0.5) / 4 * Double(w)
                for (cy, sz, col) in [(0.68, 0.12, ivory), (0.66, 0.05, maple), (0.34, 0.09, ivory)] as [(Double, Double, CGColor)] {
                    let cyy = cy * Double(h), hw = sz * Double(w) * 0.4, hh2 = sz * Double(h) * 1.0
                    ctx.setFillColor(col)
                    ctx.move(to: CGPoint(x: cx, y: cyy + hh2)); ctx.addLine(to: CGPoint(x: cx + hw, y: cyy))
                    ctx.addLine(to: CGPoint(x: cx, y: cyy - hh2)); ctx.addLine(to: CGPoint(x: cx - hw, y: cyy)); ctx.closePath()
                    ctx.fillPath()
                }
            }
            // owijka (dolna część): drobna kratka lnu
            ctx.setFillColor(rgb(0x1A1210))
            ctx.fill(CGRect(x: 0, y: 0, width: Double(w), height: Double(h) * 0.17))
            ctx.setStrokeColor(rgb(0x3A2E26, 0.8)); ctx.setLineWidth(1)
            var yy = 0.0
            while yy < Double(h) * 0.17 { ctx.move(to: CGPoint(x: 0, y: yy)); ctx.addLine(to: CGPoint(x: Double(w), y: yy)); yy += 5 }
            var xx = 0.0
            while xx < Double(w) { ctx.move(to: CGPoint(x: xx, y: 0)); ctx.addLine(to: CGPoint(x: xx, y: Double(h) * 0.17)); xx += 5 }
            ctx.strokePath()
        }
    }

    // MARK: Oznaczenia i zużycie sukna (dwie nakładki na pole gry 2,54 × 1,27 m)
    // add – linie, punkty i pyłki kredy (mieszanie addytywne, czarne tło); mul – przyciemnienie toru rozbicia i zabrudzenia (białe tło)
    static func tableDecals() -> (CGImage, CGImage) {
        let w = 2048, h = 1024
        let px = Double(w) / (2 * Phys.halfL)   // px na metr
        func X(_ m: Double) -> Double { (m + Phys.halfL) * px }
        func Z(_ m: Double) -> Double { (m + Phys.halfW) * px }
        var rng = SeededGen(s: 4242)
        func r01() -> Double { Double(rng.next() % 100000) / 100000 }
        let add = makeImage(w, h) { ctx in
            ctx.setFillColor(rgb(0x000000)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setStrokeColor(rgb(0xFFFFFF, 0.5)); ctx.setLineWidth(0.004 * px)
            if Phys.snooker {
                // linia baulk (737 mm od bandy dolnej), półkole „D” (R 292 mm) i punkty kolorowych
                let bx = SnookerLayout.baulkX
                ctx.move(to: CGPoint(x: X(bx), y: Z(-Phys.halfW))); ctx.addLine(to: CGPoint(x: X(bx), y: Z(Phys.halfW)))
                ctx.strokePath()
                ctx.addArc(center: CGPoint(x: X(bx), y: Z(0)), radius: 0.292 * px, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
                ctx.strokePath()
                ctx.setFillColor(rgb(0xFFFFFF, 0.6))
                for sp in SnookerLayout.spots.values {
                    ctx.fillEllipse(in: CGRect(x: X(sp.x) - 0.0045 * px, y: Z(sp.y) - 0.0045 * px, width: 0.009 * px, height: 0.009 * px))
                }
            } else {
            ctx.move(to: CGPoint(x: X(-Phys.halfL / 2), y: Z(-Phys.halfW))); ctx.addLine(to: CGPoint(x: X(-Phys.halfL / 2), y: Z(Phys.halfW)))
            ctx.strokePath()
            ctx.setFillColor(rgb(0xFFFFFF, 0.6))
            for sx in [-Phys.halfL / 2, 0, Phys.halfL / 2] {
                ctx.fillEllipse(in: CGRect(x: X(sx) - 0.0045 * px, y: Z(0) - 0.0045 * px, width: 0.009 * px, height: 0.009 * px))
            }
            }
            for (cx, n) in [(-Phys.halfL / 2, 900), (Phys.halfL / 2, 600)] {
                for _ in 0..<n {
                    let a = r01() * 2 * .pi, d = pow(r01(), 1.6) * 0.16
                    let s = (0.0005 + r01() * 0.0013) * px
                    ctx.setFillColor(rgb(r01() < 0.6 ? 0x9CC4FF : 0xE8F0FF, 0.10 + r01() * 0.22))
                    ctx.fillEllipse(in: CGRect(x: X(cx + cos(a) * d), y: Z(sin(a) * d), width: s, height: s))
                }
            }
        }
        let mul = makeImage(w, h) { ctx in
            ctx.setFillColor(rgb(0xFFFFFF)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.saveGState()
            ctx.clip(to: CGRect(x: X(-Phys.halfL * 0.9), y: Z(-0.13), width: (Phys.halfL * 1.8) * px, height: 0.26 * px))
            ctx.drawLinearGradient(gradient([rgb(0x000000, 0), rgb(0x000000, 0.07), rgb(0x000000, 0)], [0, 0.5, 1]),
                                   start: CGPoint(x: 0, y: Z(-0.13)), end: CGPoint(x: 0, y: Z(0.13)), options: [])
            ctx.restoreGState()
            for _ in 0..<80 {
                let x = (r01() * 2 - 1) * Phys.halfL * 0.9, z = (r01() * 2 - 1) * Phys.halfW * 0.9
                let s = (0.02 + r01() * 0.05) * px
                ctx.drawRadialGradient(gradient([rgb(0x000000, 0.035), rgb(0x000000, 0)], [0, 1]), startCenter: CGPoint(x: X(x), y: Z(z)), startRadius: 0,
                                       endCenter: CGPoint(x: X(x), y: Z(z)), endRadius: s, options: [])
            }
        }
        return (add, mul)
    }

    static func softDot() -> CGImage {
        makeImage(64, 64) { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
            ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 1), rgb(0xFFFFFF, 0.35), rgb(0xFFFFFF, 0)], [0, 0.4, 1]), startCenter: CGPoint(x: 32, y: 32),
                                   startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
    }

    // MARK: Zestawy specjalne (chrom, złoto, perła, szkło, onyks)
    static let exoticSets: Set<String> = ["chrome", "gold", "pearl", "glass", "onyx"]
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func c(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 255) }
        func m(_ s: UInt32) -> UInt32 { UInt32(max(0, min(255, c(a, s) + (c(b, s) - c(a, s)) * t))) }
        return (m(16) << 16) | (m(8) << 8) | m(0)
    }
    /// barwy zestawu: (tło kuli, pas bili połówkowej, krycie tła, krycie pasa)
    static func exoticColors(_ n: Int, set: String) -> (base: UInt32, band: UInt32, aBase: Double, aBand: Double) {
        let col = Tex.ballColors[n <= 8 ? n : n - 8]
        let striped = n >= 9
        switch set {
        case "chrome":
            let silver: UInt32 = 0xF2F3F6
            if n == 0 { return (silver, 0, 1, 1) }
            if n == 8 { return (0x34363C, 0, 1, 1) }               // czarny chrom
            return striped ? (silver, col, 1, 1) : (mix(col, 0xFFFFFF, 0.18), 0, 1, 1)   // barwiony chrom / emaliowany pas
        case "gold":
            let gold: UInt32 = 0xE6B65C
            if n == 0 { return (0xE29A6E, 0, 1, 1) }               // biała = szczotkowana miedź
            if n == 8 { return (0x4A3A2A, 0, 1, 1) }               // ciemny brąz
            return striped ? (gold, col, 1, 1) : (mix(col, gold, 0.35), 0, 1, 1)
        case "pearl":
            let pearl: UInt32 = 0xF5EFE6
            if n == 0 { return (pearl, 0, 1, 1) }
            if n == 8 { return (0x26242C, 0, 1, 1) }               // czarna perła
            return striped ? (pearl, mix(col, 0xFFFFFF, 0.22), 1, 1) : (mix(col, 0xFFFFFF, 0.28), 0, 1, 1)
        case "glass":
            if n == 0 { return (0xEAF3FF, 0, 0.16, 1) }
            if n == 8 { return (0x1A1A1E, 0, 0.62, 1) }            // dymione szkło
            return striped ? (0xEEF4FA, col, 0.16, 0.62) : (col, 0, 0.42, 1)
        default:   // onyx: czarny kamień z żyłkami, kolor tylko w pasie / pierścieniu numeru
            if n == 0 { return (0xEDEAE4, 0, 1, 1) }               // biały marmur
            return (0x111114, col, 1, 1)
        }
    }

    static func exoticBall(_ n: Int, set: String, outW: Int) -> CGImage {
        let w = 2048, h = 1024
        let (base, band, aBase, aBand) = exoticColors(n, set: set)
        let col = Tex.ballColors[n <= 8 ? n : n - 8]
        let numFont = NSFont(name: "HelveticaNeue-Bold", size: 176) ?? NSFont.boldSystemFont(ofSize: 176)
        var rng = SeededGen(s: UInt64(1900 + n))
        func r01() -> Double { Double(rng.next() % 100000) / 100000 }
        return makeImage(outW, outW / 2) { ctx in
            ctx.scaleBy(x: CGFloat(outW) / CGFloat(w), y: CGFloat(outW) / CGFloat(w))
            ctx.setFillColor(rgb(base, aBase)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            if set == "gold" {           // szczotkowanie: cienkie poziome rysy wzdłuż równoleżników
                for _ in 0..<900 {
                    let y = r01() * Double(h), x = r01() * Double(w), l = 200 + r01() * 900
                    ctx.setFillColor(rgb(r01() < 0.5 ? 0xFFFFFF : 0x000000, 0.012 + r01() * 0.022))
                    ctx.fill(CGRect(x: x, y: y, width: l, height: 1 + r01() * 1.5))
                }
            }
            if set == "onyx" {           // żyłki kamienia
                let vein: UInt32 = n == 0 ? 0x8A8478 : 0xC9C2B4
                for _ in 0..<14 {
                    var x = r01() * Double(w), y = r01() * Double(h)
                    ctx.setStrokeColor(rgb(vein, 0.10 + r01() * 0.25)); ctx.setLineWidth(1 + r01() * 3)
                    ctx.move(to: CGPoint(x: x, y: y))
                    for _ in 0..<12 { x += (r01() - 0.3) * 160; y += (r01() - 0.5) * 120; ctx.addLine(to: CGPoint(x: x, y: y)) }
                    ctx.strokePath()
                }
            }
            if n >= 9 {
                let bw = Double(h) * 0.5 * 0.40
                ctx.clear(CGRect(x: 0, y: Double(h) / 2 - bw, width: Double(w), height: bw * 2))
                ctx.setFillColor(rgb(band, aBand))
                ctx.fill(CGRect(x: 0, y: Double(h) / 2 - bw, width: Double(w), height: bw * 2))
            }
            if n == 0 {
                ctx.setFillColor(rgb(set == "chrome" || set == "gold" ? 0x1A1A1A : 0xC9362B))
                for u in [0.25, 0.75] { ctx.fillEllipse(in: CGRect(x: u * Double(w) - 14, y: Double(h) / 2 - 14, width: 28, height: 28)) }
                return
            }
            for u in [0.25, 0.75] {
                let cx = u * Double(w), cy = Double(h) / 2, r = 132.0
                // emaliowane (niemetaliczne, kryjące) kółko z numerem – czytelne w każdym zestawie
                ctx.clear(CGRect(x: cx - r - 10, y: cy - r - 10, width: 2 * r + 20, height: 2 * r + 20))
                ctx.setFillColor(rgb(base, aBase)); ctx.fill(CGRect(x: cx - r - 10, y: cy - r - 10, width: 2 * r + 20, height: 2 * r + 20))
                if n >= 9 { ctx.setFillColor(rgb(band, aBand)); ctx.fill(CGRect(x: cx - r - 10, y: cy - r - 10, width: 2 * r + 20, height: 2 * r + 20)) }
                let ring: UInt32 = set == "onyx" ? col : (set == "gold" ? 0xB8862E : 0x2A2A2E)
                ctx.setFillColor(rgb(ring)); ctx.fillEllipse(in: CGRect(x: cx - r - 6, y: cy - r - 6, width: 2 * r + 12, height: 2 * r + 12))
                ctx.setFillColor(rgb(0xFBF8EE)); ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                let str = NSAttributedString(string: "\(n)", attributes: [.font: numFont, .foregroundColor: NSColor(white: 0.04, alpha: 1)])
                let line = CTLineCreateWithAttributedString(str)
                let bb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                ctx.textPosition = CGPoint(x: cx - bb.midX, y: cy - bb.midY)
                CTLineDraw(line, ctx)
                if n == 6 || n == 9 { ctx.setFillColor(rgb(0x0A0A0A)); ctx.fill(CGRect(x: cx - 34, y: cy - bb.height / 2 - 20, width: 68, height: 9)) }
            }
        }
    }

    /// mapa metaliczności (biel = metal) i chropowatości dla chromu/złota: pas i kółka numerów to emalia
    static func exoticMaps(_ n: Int, set: String) -> (metal: CGImage, rough: CGImage) {
        let w = 512, h = 256
        var rng = SeededGen(s: UInt64(2900 + n))
        func r01() -> Double { Double(rng.next() % 100000) / 100000 }
        let gold = set == "gold"
        func enamel(_ ctx: CGContext, _ v: Double) {
            ctx.setFillColor(CGColor(gray: v, alpha: 1))
            if n >= 9 { let bw = Double(h) * 0.2; ctx.fill(CGRect(x: 0, y: Double(h) / 2 - bw, width: Double(w), height: bw * 2)) }
            if n != 0 { for u in [0.25, 0.75] { let r = 132.0 / 4 + 2.5; ctx.fillEllipse(in: CGRect(x: u * Double(w) - r, y: Double(h) / 2 - r, width: 2 * r, height: 2 * r)) } }
        }
        let metal = makeImage(w, h) { ctx in
            // chrom: 80 % metalu – w ciemnej sali czyste lustro wychodziło niemal czarne; 20 % srebrnej warstwy łapie światło
            ctx.setFillColor(CGColor(gray: gold ? 1 : 0.8, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            enamel(ctx, 0)
        }
        let rough = makeImage(w, h) { ctx in
            ctx.setFillColor(CGColor(gray: gold ? 0.30 : 0.06, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            if gold { for _ in 0..<500 {
                ctx.setFillColor(CGColor(gray: 0.18 + r01() * 0.28, alpha: 1))
                ctx.fill(CGRect(x: r01() * Double(w), y: r01() * Double(h), width: 40 + r01() * 300, height: 1))
            } }
            enamel(ctx, 0.08)
        }
        return (metal, rough)
    }

    // MARK: Pozostałe
    static func ballAlbedo(_ n: Int, set: String = "classic", outW: Int = 2048) -> CGImage {
        if exoticSets.contains(set) { return exoticBall(n, set: set, outW: outW) }
        let w = 2048, h = 1024
        var palette = Tex.ballColors
        if set == "tv" { palette[4] = 0xE8749A; palette[7] = 0x7A4A22 }       // różowa 4, brązowa 7 (transmisje TV)
        if set == "snooker" { palette = [0xF3EBD0, 0xE8C21A, 0x1F8A3A, 0x6B3A1E, 0x1F4FC9, 0xE8749A, 0xC4161C, 0x8A2F1A, 0x0E0E10] }
        let dark = set == "dark", snk = set == "snooker"
        func scaled(_ c: UInt32, _ k: Double) -> UInt32 {
            let r = Double((c >> 16) & 255) * k, g = Double((c >> 8) & 255) * k, b = Double(c & 255) * k
            return (UInt32(min(255, r)) << 16) | (UInt32(min(255, g)) << 8) | UInt32(min(255, b))
        }
        let color = palette[n <= 8 ? n : n - 8]
        let neon: UInt32 = n == 0 ? 0x35E0FF : scaled(color, 1.0 / max(0.45, Double(max((color >> 16) & 255, (color >> 8) & 255, color & 255)) / 255))
        let numFont = NSFont(name: "HelveticaNeue-Bold", size: 176) ?? NSFont.boldSystemFont(ofSize: 176)
        var rng = SeededGen(s: UInt64(900 + n))
        func r01() -> Double { Double(rng.next() % 100000) / 100000 }
        return makeImage(outW, outW / 2) { ctx in
            ctx.scaleBy(x: CGFloat(outW) / CGFloat(w), y: CGFloat(outW) / CGFloat(w))
            let base: UInt32 = dark ? (n == 0 ? 0xE6EEF4 : (n >= 9 ? 0x16171B : scaled(color, 0.2)))
                                    : ((n == 0 || n >= 9) ? (snk && n == 0 ? 0xF3EBD0 : 0xF6F2E6) : color)
            ctx.setFillColor(rgb(base)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            // miękkie wahania pigmentu w żywicy
            for _ in 0..<26 {
                let r = 120 + r01() * 360, x = r01() * Double(w), y = r01() * Double(h)
                ctx.drawRadialGradient(gradient([rgb(r01() < 0.5 ? 0xFFFFFF : 0x000000, 0.045), rgb(0x000000, 0)], [0, 1]),
                                       startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: r, options: [])
            }
            if n >= 9 {
                let band = Double(h) * 0.5 * 0.40
                ctx.setFillColor(rgb(dark ? scaled(color, 0.5) : color))
                ctx.fill(CGRect(x: 0, y: Double(h) / 2 - band, width: Double(w), height: band * 2))
                // wtopiony brzeg pasa: cienka ciemniejsza obwódka
                ctx.setFillColor(rgb(0x000000, 0.12))
                ctx.fill(CGRect(x: 0, y: Double(h) / 2 - band - 1.5, width: Double(w), height: 3))
                ctx.fill(CGRect(x: 0, y: Double(h) / 2 + band - 1.5, width: Double(w), height: 3))
            }
            if n == 0 {
                ctx.setFillColor(rgb(dark ? 0x35E0FF : (snk ? 0xF3EBD0 : 0xC9362B)))
                for u in [0.25, 0.75] { ctx.fillEllipse(in: CGRect(x: u * Double(w) - 14, y: Double(h) / 2 - 14, width: 28, height: 28)) }
                // mikro-rysy użytkowe
                ctx.setLineWidth(1.3)
                for _ in 0..<70 {
                    let x = r01() * Double(w), y = r01() * Double(h), l = 12 + r01() * 70, a = r01() * .pi
                    ctx.setStrokeColor(rgb(r01() < 0.5 ? 0x7A7A7A : 0xFFFFFF, 0.05 + r01() * 0.08))
                    ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l)); ctx.strokePath()
                }
            } else {
                for u in [0.25, 0.75] {
                    let cx = u * Double(w), cy = Double(h) / 2, r = 132.0
                    // kółko „zatopione” pod lakierem: cień wewnątrz i ostre krawędzie
                    ctx.setFillColor(rgb(0x000000, 0.22))
                    ctx.fillEllipse(in: CGRect(x: cx - r - 2.5, y: cy - r - 2.5, width: 2 * r + 5, height: 2 * r + 5))
                    ctx.setFillColor(rgb(dark ? 0x07080A : 0xFBF8EE))
                    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
                    if dark {
                        ctx.setStrokeColor(rgb(neon)); ctx.setLineWidth(9)
                        ctx.strokeEllipse(in: CGRect(x: cx - r + 6, y: cy - r + 6, width: 2 * r - 12, height: 2 * r - 12))
                    }
                    let str = NSAttributedString(string: "\(n)", attributes: [.font: numFont, .foregroundColor: dark ? nsc(neon) : NSColor(white: 0.04, alpha: 1)])
                    let line = CTLineCreateWithAttributedString(str)
                    let bb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                    ctx.textPosition = CGPoint(x: cx - bb.midX, y: cy - bb.midY)
                    CTLineDraw(line, ctx)
                    if n == 6 || n == 9 {   // podkreślenie 6/9
                        ctx.setFillColor(rgb(0x0A0A0A)); ctx.fill(CGRect(x: cx - 34, y: cy - bb.height / 2 - 20, width: 68, height: 9))
                    }
                }
            }
            // drobne mikro-rysy na wszystkich bilach
            ctx.setLineWidth(1)
            for _ in 0..<(n == 0 ? 0 : 25) {
                let x = r01() * Double(w), y = r01() * Double(h), l = 8 + r01() * 40, a = r01() * .pi
                ctx.setStrokeColor(rgb(0xFFFFFF, 0.04 + r01() * 0.05))
                ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l)); ctx.strokePath()
            }
        }
    }

    static func environment() -> CGImage {
        let w = 2048, h = 1024
        return makeImage(w, h) { ctx in
            ctx.drawLinearGradient(gradient([rgb(0x8A8072), rgb(0x302A24), rgb(0x1C1713), rgb(0x0A0807)], [0, 0.45, 0.6, 1]),
                                   start: CGPoint(x: 0, y: Double(h)), end: CGPoint(x: 0, y: 0), options: [])
            // długa lampa turniejowa nad stołem (wąski, jasny prostokąt) + miękkie softboksy
            func box(_ cx: Double, _ cy: Double, _ bw: Double, _ bh: Double, _ a: Double, _ blur: Double) {
                let rect = CGRect(x: (cx - bw / 2) * Double(w), y: (cy - bh / 2) * Double(h), width: bw * Double(w), height: bh * Double(h))
                ctx.setShadow(offset: .zero, blur: blur, color: rgb(0xFFF1D8, a))
                ctx.setFillColor(rgb(0xFFF8EC, a)); ctx.fill(rect)
            }
            box(0.5, 0.90, 0.42, 0.022, 1.0, 36)      // główna lampa: długa listwa
            box(0.5, 0.86, 0.46, 0.05, 0.35, 70)
            box(0.18, 0.80, 0.10, 0.04, 0.5, 40)
            box(0.82, 0.80, 0.10, 0.04, 0.5, 40)
            box(0.0, 0.78, 0.07, 0.05, 0.45, 40); box(1.0, 0.78, 0.07, 0.05, 0.45, 40)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setFillColor(rgb(0x3A4A60, 0.5))
            for i in 0..<9 { ctx.fill(CGRect(x: Double(i) * 230 + 40, y: Double(h) * 0.52, width: 120, height: 70)) }
        }
    }

    static func netImage() -> CGImage {
        let w = 512, h = 256
        return makeImage(w, h) { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setStrokeColor(rgb(0xCFC7B2, 0.95)); ctx.setLineWidth(3)
            for i in 0...20 { let x = Double(i) * Double(w) / 20; ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: Double(h))) }
            for j in 0...10 { let y = Double(j) * Double(h) / 10; ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: Double(w), y: y)) }
            ctx.strokePath()
        }
    }

    static func chalkDecal() -> CGImage {
        var rng = SeededGen(s: 31337)
        return makeImage(128, 128) { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: 128, height: 128))
            ctx.drawRadialGradient(gradient([rgb(0x6FA8FF, 0.55), rgb(0x6FA8FF, 0)], [0, 1]), startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                   endCenter: CGPoint(x: 64, y: 64), endRadius: 62, options: [])
            for _ in 0..<260 {
                let a = Double(rng.next() % 6283) / 1000, d = pow(Double(rng.next() % 1000) / 1000, 0.7) * 58
                ctx.setFillColor(rgb(0xBBD6FF, 0.25 + Double(rng.next() % 40) / 100))
                ctx.fillEllipse(in: CGRect(x: 64 + cos(a) * d, y: 64 + sin(a) * d, width: 2.2, height: 2.2))
            }
        }
    }

    /// anamorficzny blask: pozioma smuga + słaby krzyż
    static func glareSprite() -> CGImage {
        let w = 512, h = 128
        return makeImage(w, h) { ctx in
            ctx.setFillColor(rgb(0x000000)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.saveGState()
            ctx.translateBy(x: Double(w) / 2, y: Double(h) / 2)
            ctx.scaleBy(x: 1, y: 0.06)
            ctx.drawRadialGradient(gradient([rgb(0xBFD8FF, 0.9), rgb(0x5F8FFF, 0.25), rgb(0x000000, 0)], [0, 0.35, 1]),
                                   startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: Double(w) / 2, options: [])
            ctx.restoreGState()
            ctx.saveGState()
            ctx.translateBy(x: Double(w) / 2, y: Double(h) / 2)
            ctx.scaleBy(x: 0.1, y: 1)
            ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.35), rgb(0x000000, 0)], [0, 1]), startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: Double(h) / 2, options: [])
            ctx.restoreGState()
            ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 1), rgb(0xFFEFD0, 0.3), rgb(0x000000, 0)], [0, 0.3, 1]),
                                   startCenter: CGPoint(x: Double(w) / 2, y: Double(h) / 2), startRadius: 0,
                                   endCenter: CGPoint(x: Double(w) / 2, y: Double(h) / 2), endRadius: 26, options: [])
        }
    }

    /// pionowy gradient stożka światła (jasno przy lampie)
    static func shaftGradient() -> CGImage {
        makeImage(8, 256) { ctx in
            ctx.drawLinearGradient(gradient([rgb(0x000000), rgb(0x3A3428), rgb(0xFFF0D0)], [0, 0.5, 1]),
                                   start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 256), options: [])
        }
    }

    static func contactShadow() -> CGImage {
        makeImage(128, 128) { ctx in
            ctx.clear(CGRect(x: 0, y: 0, width: 128, height: 128))
            ctx.drawRadialGradient(gradient([rgb(0x000000, 0.97), rgb(0x000000, 0.85), rgb(0x000000, 0.42), rgb(0x000000, 0.12), rgb(0x000000, 0)], [0, 0.30, 0.48, 0.72, 1]),
                                   startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
    }
}

// MARK: - Cache tekstur na dysku (~/Library/Caches/pl.marchewka.bilard/tex-v1)

extension TexturePack {
    static var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("pl.marchewka.bilard/tex-v1")
    }
    static func loadCached() -> TexturePack? {
        let dir = cacheDir
        let okURL = dir.appendingPathComponent("ok")
        guard let okDate = (try? okURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        // nowa kompilacja programu lub zasobów unieważnia cache
        if let exe = Bundle.main.executableURL, let d = (try? exe.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, d > okDate { return nil }
        var failed = false
        func L(_ n: String) -> CGImage {
            guard let s = CGImageSourceCreateWithURL(dir.appendingPathComponent(n + ".png") as CFURL, nil),
                  let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { failed = true; return placeholder }
            return i
        }
        let balls = (0..<16).map { L("ball\($0)") }
        let p = TexturePack(
            clothDiffuse: L("clothDiffuse"),
            clothNormal: L("clothNormal"),
            clothRough: L("clothRough"), balls: balls,
            ballRough: L("ballRough"),
            ballNormal: L("ballNormal"),
            woodAlbedo: L("woodAlbedo"),
            woodNormal: L("woodNormal"),
            woodRough: L("woodRough"),
            mapleAlbedo: L("mapleAlbedo"),
            mapleNormal: L("mapleNormal"),
            mapleRough: L("mapleRough"),
            buttAlbedo: L("buttAlbedo"),
            buttNormal: L("buttNormal"),
            buttRough: L("buttRough"),
            brassAlbedo: L("brassAlbedo"),
            brassNormal: L("brassNormal"),
            brassRough: L("brassRough"),
            leatherAlbedo: L("leatherAlbedo"),
            leatherNormal: L("leatherNormal"),
            tip: L("tip"),
            tipNormal: L("tipNormal"),
            decalAdd: L("decalAdd"),
            decalMul: L("decalMul"),
            dot: L("dot"),
            env: L("env"),
            net: L("net"),
            chalk: L("chalk"),
            glare: L("glare"),
            shaft: L("shaft"),
            contact: L("contact"))
        return failed ? nil : p
    }
    static let placeholder: CGImage = makeImage(1, 1) { _ in }
    func saveCache() {
        DispatchQueue.global(qos: .utility).async {
            let dir = Self.cacheDir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            func S(_ n: String, _ i: CGImage) {
                guard let d = CGImageDestinationCreateWithURL(dir.appendingPathComponent(n + ".png") as CFURL, "public.png" as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(d, i, nil); CGImageDestinationFinalize(d)
            }
            for (i, b) in self.balls.enumerated() { S("ball\(i)", b) }
            S("clothDiffuse", clothDiffuse)
        S("clothNormal", clothNormal)
        S("clothRough", clothRough)
        S("ballRough", ballRough)
        S("ballNormal", ballNormal)
        S("woodAlbedo", woodAlbedo)
        S("woodNormal", woodNormal)
        S("woodRough", woodRough)
        S("mapleAlbedo", mapleAlbedo)
        S("mapleNormal", mapleNormal)
        S("mapleRough", mapleRough)
        S("buttAlbedo", buttAlbedo)
        S("buttNormal", buttNormal)
        S("buttRough", buttRough)
        S("brassAlbedo", brassAlbedo)
        S("brassNormal", brassNormal)
        S("brassRough", brassRough)
        S("leatherAlbedo", leatherAlbedo)
        S("leatherNormal", leatherNormal)
        S("tip", tip)
        S("tipNormal", tipNormal)
        S("decalAdd", decalAdd)
        S("decalMul", decalMul)
        S("dot", dot)
        S("env", env)
        S("net", net)
        S("chalk", chalk)
        S("glare", glare)
        S("shaft", shaft)
        S("contact", contact)
            FileManager.default.createFile(atPath: dir.appendingPathComponent("ok").path, contents: Data())
        }
    }
}
