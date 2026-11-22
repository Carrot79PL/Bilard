import SceneKit
import Cocoa

/// Trójwymiarowy wskaźnik toru bili. Tor liczony symulacją tej samej fizyki co gra (kopia stołu),
/// więc linie są krzywe: masse, naciąg/ciąg po zderzeniu, gwint boczny na bandach. Bez strzałek – miękkie wstęgi.
/// Wszystko leży 3 mm nad suknem, bez zapisu do bufora głębi (brak z-fightingu), delikatny blask i wygaszanie na końcach.
final class AimIndicator {
    let root = SCNNode()
    private let cueLine: SCNNode          // biała do kontaktu (lub po bandach)
    private let tgtLine: SCNNode          // bila trafiona
    private let cueAfter: SCNNode         // biała po zderzeniu
    private let ghostBall: SCNNode, ring: SCNNode
    private let y: Float = 0.003
    private var t = 0.0
    private let sim = BilliardPhysics()
    private var lastKey: [Double] = []
    private var cached = Prediction()
    private var version = 0, drawnVersion = -1

    struct Prediction {
        var cue: [V2] = []
        var contact: V2? = nil
        var target: Int? = nil
        var tgt: [V2] = []
        var after: [V2] = []
    }

    private static func ribbonImage(arrow: Bool) -> NSImage {
        let w = 64, h = 128
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
        let cs = CGColorSpaceCreateDeviceRGB()
        // poprzeczny profil: miękkie krawędzie (blask) + jasny rdzeń; wzdłuż: wygaszanie ku końcowi (góra obrazu)
        for row in 0..<h {
            let f = Double(row) / Double(h - 1)               // 0 = początek, 1 = koniec
            let along = arrow ? (0.35 + 0.65 * (1 - f)) : (0.30 + 0.70 * pow(1 - f, 0.7))
            let endFade = f > 0.85 ? (1 - f) / 0.15 : 1.0
            for col in 0..<w {
                let c = abs((Double(col) + 0.5) / Double(w) * 2 - 1)   // 0 środek, 1 brzeg
                let glow = exp(-c * c * 5.0) * 0.55
                let core = c < 0.22 ? 0.95 : 0.0
                let a = min(1, glow + core) * along * endFade * (1 - pow(c, 6))
                ctx.setFillColor(CGColor(colorSpace: cs, components: [1, 1, 1, CGFloat(a)])!)
                ctx.fill(CGRect(x: col, y: row, width: 1, height: 1))
            }
        }
        img.unlockFocus()
        return img
    }

    private static func ringImage() -> NSImage {
        let s = 128
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        let c = CGFloat(s) / 2
        for (r, w, a) in [(CGFloat(52), CGFloat(10), 0.18), (CGFloat(52), CGFloat(5), 0.55), (CGFloat(52), CGFloat(2), 0.95)] {
            NSColor.white.withAlphaComponent(a).setStroke()
            let p = NSBezierPath(ovalIn: NSRect(x: c - r, y: c - r, width: 2 * r, height: 2 * r)); p.lineWidth = w; p.stroke()
        }
        img.unlockFocus()
        return img
    }

    private static func mat(_ img: NSImage, _ color: UInt32, _ alpha: CGFloat = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = nsc(color, 1)
        m.transparent.contents = img
        m.transparencyMode = .aOne
        m.transparency = alpha
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        m.blendMode = .add
        return m
    }

    private static func ribbonNode(_ root: SCNNode, _ color: UInt32, order: Int) -> SCNNode {
        let n = SCNNode()
        n.castsShadow = false
        n.renderingOrder = order
        n.isHidden = true
        n.geometry = nil
        n.setValue(Self.mat(Self.ribbonImage(arrow: false), color), forKey: "ribbonMat")
        root.addChildNode(n)
        return n
    }

    init() {
        cueLine = Self.ribbonNode(root, 0xBFEFFF, order: 100)
        tgtLine = Self.ribbonNode(root, 0xFFE9A8, order: 102)
        cueAfter = Self.ribbonNode(root, 0x7FD0FF, order: 101)
        let gs = SCNSphere(radius: Phys.R)
        let gm = SCNMaterial(); gm.lightingModel = .constant
        gm.diffuse.contents = nsc(0xDDF4FF, 1); gm.transparency = 0.22
        gm.writesToDepthBuffer = false; gm.blendMode = .add
        gs.materials = [gm]
        ghostBall = SCNNode(geometry: gs); ghostBall.castsShadow = false; ghostBall.renderingOrder = 104
        root.addChildNode(ghostBall)
        let pl = SCNPlane(width: 1, height: 1)
        pl.materials = [Self.mat(Self.ringImage(), 0xFFFFFF)]
        let inner = SCNNode(geometry: pl); inner.eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0); inner.castsShadow = false; inner.renderingOrder = 101
        ring = SCNNode(); ring.addChildNode(inner); root.addChildNode(ring)
        ghostBall.isHidden = true; ring.isHidden = true
        root.isHidden = true
    }

    /// precyzja kija: skala długości linii pomocniczych (1 = bazowa)
    var lineScale = 1.0

    func hide() { root.isHidden = true }

    /// uproszczenie łamanej: usuwa punkty prawie współliniowe (krok symulacji 1/240 s daje ich setki)
    private static func simplify(_ p: [V2]) -> [V2] {
        guard p.count > 2 else { return p }
        var out = [p[0]]
        var dir = simd_normalize(p[1] - p[0]), lastKept = p[0]
        for i in 1..<(p.count - 1) {
            let seg = p[i + 1] - p[i]; let l = simd_length(seg)
            if l < 1e-7 { continue }
            let d = seg / l
            let sharp = simd_dot(d, dir) < 0.9998           // > ~1,1°
            if sharp || simd_length(p[i] - lastKept) > 0.06 {
                out.append(p[i]); lastKept = p[i]; dir = d
            }
        }
        out.append(p[p.count - 1])
        return out
    }

    /// wstęga wzdłuż łamanej (szerokość w), v tekstury wzdłuż długości → wygaszanie ku końcowi.
    /// Na ostrych zakrętach (odbicia od bandy) każdy odcinek ma własną normalną – bez przewężeń i „motyla”.
    private func ribbon(_ n: SCNNode, _ raw: [V2], width: Double) {
        let pts = Self.simplify(raw)
        guard pts.count >= 2 else { n.isHidden = true; return }
        var total = 0.0
        for i in 1..<pts.count { total += simd_length(pts[i] - pts[i - 1]) }
        if total < 0.004 { n.isHidden = true; return }
        let hw = width / 2
        func dirAt(_ i: Int, _ j: Int) -> V2 { let d = pts[j] - pts[i]; let l = simd_length(d); return l > 1e-9 ? d / l : V2(1, 0) }
        var verts: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [UInt16] = []
        // dla każdego punktu: lista par (lewy, prawy); ostatnia para punktu łączy się z następnym odcinkiem
        var inPair = [Int](repeating: 0, count: pts.count), outPair = [Int](repeating: 0, count: pts.count)
        var acc = 0.0
        func push(_ p: V2, _ d: V2, _ v: Double) -> Int {
            let nr = V2(-d.y, d.x) * hw
            let L = p + nr, Rr = p - nr
            verts.append(SCNVector3(L.x, Double(y), L.y)); verts.append(SCNVector3(Rr.x, Double(y), Rr.y))
            uvs.append(CGPoint(x: 0, y: CGFloat(v))); uvs.append(CGPoint(x: 1, y: CGFloat(v)))
            return verts.count - 2
        }
        for i in 0..<pts.count {
            if i > 0 { acc += simd_length(pts[i] - pts[i - 1]) }
            let v = 1 - acc / total
            if i == 0 { let k = push(pts[0], dirAt(0, 1), v); inPair[0] = k; outPair[0] = k }
            else if i == pts.count - 1 { let k = push(pts[i], dirAt(i - 1, i), v); inPair[i] = k; outPair[i] = k }
            else {
                let d0 = dirAt(i - 1, i), d1 = dirAt(i, i + 1)
                if simd_dot(d0, d1) < 0.94 {                         // zakręt > ~20°: dwie pary
                    inPair[i] = push(pts[i], d0, v); outPair[i] = push(pts[i], d1, v)
                } else {
                    var m = d0 + d1; let l = simd_length(m); m = l > 1e-9 ? m / l : d0
                    // miter: poszerzenie, by szerokość poprzeczna była stała
                    let k = push(pts[i], m, v); inPair[i] = k; outPair[i] = k
                }
            }
        }
        for i in 0..<(pts.count - 1) {
            let a = UInt16(outPair[i]), b = UInt16(inPair[i + 1])
            idx += [a, a + 1, b, a + 1, b + 1, b]
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        if let m = n.value(forKey: "ribbonMat") as? SCNMaterial { g.materials = [m] }
        n.geometry = g
        n.isHidden = false
    }

    /// przycięcie łamanej do długości `len`
    private static func clip(_ p: [V2], _ len: Double) -> [V2] {
        guard p.count > 1 else { return p }
        var out = [p[0]], acc = 0.0
        for i in 1..<p.count {
            let s = simd_length(p[i] - p[i - 1])
            if acc + s >= len { let u = (len - acc) / max(1e-9, s); out.append(p[i - 1] + (p[i] - p[i - 1]) * u); return out }
            acc += s; out.append(p[i])
        }
        return out
    }

    /// Symulacja uderzenia na kopii stołu (ta sama fizyka co w grze, krok po kroku co 1/240 s).
    /// Łamana ma punkty w każdym kroku oraz DOKŁADNE punkty zdarzeń: odbicie od bandy i środek białej w chwili kontaktu,
    /// więc rykoszety i bila-duch leżą tam, gdzie fizyka je faktycznie liczy (bez ścinania rogów).
    func predict(balls: [Ball], aim: V2, power: Double, off: V2, elev: Double) -> Prediction {
        var key = [aim.x, aim.y, (power * 200).rounded(), off.x, off.y, elev, Phys.R]
        for b in balls where b.active { key.append(b.p.x); key.append(b.p.y) }
        if key == lastKey { return cached }
        lastKey = key
        let t0 = CACurrentMediaTime()
        sim.balls = balls
        for i in sim.balls.indices { sim.balls[i].v = V2(0, 0); sim.balls[i].w = V3(0, 0, 0); sim.balls[i].h = 0; sim.balls[i].vh = 0 }
        sim.events.removeAll(); sim.resetAccumulator()
        sim.strike(aim: aim, power: power, off: off, elev: elev)
        var pr = Prediction()
        pr.cue = [balls[0].p]
        let R = Phys.R
        let maxBefore = 3.2 * lineScale, maxAfterBand = 1.3 * lineScale
        var lenCue = 0.0, firstBand: Double? = nil
        var steps = 0
        func add(_ arr: inout [V2], _ p: V2) { if let l = arr.last, simd_length(p - l) < 1e-4 { return }; arr.append(p) }
        while steps < 1400 {
            sim.advance(Phys.dt); steps += 1
            var hitOther: Int? = nil, contactCenter: V2? = nil, pocketedCue = false
            var bandPts: [V2] = []
            for e in sim.events {
                switch e {
                case .ballHit(let a, let b, _, let pos) where pr.target == nil && (a == 0 || b == 0):
                    hitOther = a == 0 ? b : a
                    // środek białej w chwili kontaktu: punkt styku cofnięty o promień wzdłuż normalnej
                    let other = sim.balls[hitOther!].p, c = sim.balls[0].p
                    let nn = simd_normalize(other - c)
                    contactCenter = a == 0 ? pos - nn * R : pos + nn * R
                case .cushion(let bi, _, let pos) where bi == 0: bandPts.append(pos)
                case .pocket(let bi, _, _) where bi == 0: pocketedCue = true
                default: break
                }
            }
            sim.events.removeAll()
            let cb = sim.balls[0]
            if pr.target == nil {
                for bp in bandPts { if let l = pr.cue.last { lenCue += simd_length(bp - l) }; add(&pr.cue, bp); if firstBand == nil { firstBand = lenCue } }
                if let c = contactCenter, let h = hitOther {
                    if let l = pr.cue.last { lenCue += simd_length(c - l) }
                    add(&pr.cue, c)
                    pr.target = h; pr.contact = c
                    pr.tgt = [sim.balls[h].p]; pr.after = [c]
                    continue
                }
                if let l = pr.cue.last { lenCue += simd_length(cb.p - l) }
                add(&pr.cue, cb.p)
                if pocketedCue || !cb.active || lenCue > maxBefore { break }
                if let fb = firstBand, lenCue - fb > maxAfterBand { break }
                if !sim.anyMoving { break }
            } else if let h = pr.target {
                if sim.balls[h].active { add(&pr.tgt, sim.balls[h].p) }
                if cb.active { for bp in bandPts { add(&pr.after, bp) }; add(&pr.after, cb.p) }
                if !sim.anyMoving { break }
                let lt = Self.len(pr.tgt), la = Self.len(pr.after)
                if (lt > 0.9 * lineScale || !sim.balls[h].active) && (la > 0.6 * lineScale || !cb.active) { break }
            }
        }
        if pr.target != nil {
            pr.tgt = Self.clip(pr.tgt, 0.9 * lineScale)
            pr.after = Self.clip(pr.after, 0.6 * lineScale)
        }
        if ProcessInfo.processInfo.environment["BILARD_AIMLOG"] != nil {
            print("AIM tgt=\(pr.target ?? -1) cue=\(pr.cue.count)/\(Self.len(pr.cue)) tgt=\(pr.tgt.count)/\(Self.len(pr.tgt)) after=\(pr.after.count)/\(Self.len(pr.after)) steps=\(steps) ms=\((CACurrentMediaTime() - t0) * 1000)")
        }
        cached = pr
        version += 1
        return pr
    }

    /// test: przebieg toru dla rosnącej siły (ciągłość linii)
    func sweep(balls: [Ball], aim: V2, off: V2, elev: Double) {
        var prevEnd: V2? = nil
        for k in 1...20 {
            let pw = Double(k) / 20
            lastKey = []
            let pr = predict(balls: balls, aim: aim, power: pw, off: off, elev: elev)
            let end = pr.cue.last ?? V2(0, 0)
            let jump = prevEnd.map { simd_length(end - $0) } ?? 0
            print(String(format: "SWEEP p=%.2f  pkt=%3d  dlugosc=%.2f  kontakt=%d  koniec=(%.2f,%.2f)  skok_konca=%.2f m", pw, pr.cue.count, Self.len(pr.cue), pr.contact != nil ? 1 : 0, end.x, end.y, jump))
            prevEnd = end
        }
    }

    private static func len(_ p: [V2]) -> Double {
        var s = 0.0; if p.count > 1 { for i in 1..<p.count { s += simd_length(p[i] - p[i - 1]) } }; return s
    }

    /// aimRaw – kierunek kija (przed rzutem bocznym); off – punkt uderzenia; power 0…1; elev – nachylenie kija [rad]
    func update(dt: Double, balls: [Ball], aimRaw: V2, off: V2, power: Double, elev: Double) {
        t += dt
        root.isHidden = false
        let R = Phys.R
        if let gs = ghostBall.geometry as? SCNSphere, abs(Double(gs.radius) - R) > 1e-9 { gs.radius = CGFloat(R) }
        let pr = predict(balls: balls, aim: aimRaw, power: power, off: off, elev: elev)
        let redraw = version != drawnVersion
        drawnVersion = version
        if redraw {
            // wstęga białej zaczyna się tuż za krawędzią bili
            var cue = pr.cue
            if cue.count > 1 {
                let d = cue[1] - cue[0]; let l = simd_length(d)
                if l > 1e-6 { cue[0] = cue[0] + d / l * min(R * 1.05, l) }
            }
            ribbon(cueLine, cue, width: 0.032)
            if pr.contact != nil {
                ribbon(tgtLine, Self.trimStart(pr.tgt, R * 1.05), width: 0.02)
                ribbon(cueAfter, Self.trimStart(pr.after, R * 1.05), width: 0.016)
            } else { tgtLine.isHidden = true; cueAfter.isHidden = true }
        }
        if let c = pr.contact {
            ghostBall.isHidden = true   // sama obwódka, bez białej kuli
            ghostBall.simdPosition = SIMD3<Float>(Float(c.x), Float(R), Float(c.y))
            ring.isHidden = false
            let rs = CGFloat(2 * R * (1.12 + 0.03 * sin(t * 4)))
            (ring.childNodes[0].geometry as? SCNPlane)?.width = rs
            (ring.childNodes[0].geometry as? SCNPlane)?.height = rs
            ring.simdPosition = SIMD3<Float>(Float(c.x), y - 0.0005, Float(c.y))
        } else {
            ghostBall.isHidden = true; ring.isHidden = true
        }
    }

    /// pominięcie początku łamanej (wstęga zaczyna się przy krawędzi bili)
    private static func trimStart(_ p: [V2], _ d: Double) -> [V2] {
        guard p.count > 1 else { return p }
        var acc = 0.0
        for i in 1..<p.count {
            let s = simd_length(p[i] - p[i - 1])
            if acc + s > d { let u = (d - acc) / max(1e-9, s); return [p[i - 1] + (p[i] - p[i - 1]) * u] + Array(p[i...]) }
            acc += s
        }
        return []
    }
}
