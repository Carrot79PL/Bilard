import Cocoa
import SceneKit
import simd
import ModelIO
import SceneKit.ModelIO

// MARK: - Budowa sceny 3D: stół turniejowy 9 ft, bile, kij, oświetlenie

struct TableNodes {
    var root = SCNNode()
    var ballMaterials: [SCNMaterial] = []
    var glare: [SCNNode] = []
    var contact: [SCNNode] = []
    var decals: [SCNNode] = []
    var emblem: SCNNode? = nil       // biały emblemat na środku sukna
    var probe: SCNLight? = nil
    var probeNode: SCNNode? = nil
    var probeLight: SCNLight? = nil
    var lampLights: [SCNLight] = []
    var shafts = SCNNode()          // stożek światła + pył
    var chalkMarks: [SCNNode] = []
    var balls: [SCNNode] = []
    var cue = SCNNode()
    var clothMaterials: [SCNMaterial] = []
    var cushionMaterial: SCNMaterial? = nil
    var railMaterials: [SCNMaterial] = []
    var fitting: SCNMaterial? = nil
    var lamp = SCNNode()
    var lampFixtures = SCNNode()     // 3 widoczne lampy nad stołem
}

/// Siatka z płaskimi normalnymi (wygodna do budowy band i metalowych obrzeży)
final class MeshBuilder {
    var verts: [SCNVector3] = [], norms: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [Int32] = []
    var uvScale = 8.0

    /// wypukły wielokąt; center – punkt wewnątrz bryły (do orientacji normalnej na zewnątrz)
    func face(_ p: [V3], center: V3) {
        guard p.count >= 3 else { return }
        var n = V3(0, 0, 0)
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        }
        let len = simd_length(n)
        if len < 1e-12 { return }
        n /= len
        var pts = p
        let cen = p.reduce(V3(0, 0, 0), +) / Double(p.count)
        if simd_dot(n, cen - center) < 0 { pts.reverse(); n = -n }
        let base = Int32(verts.count)
        for q in pts {
            verts.append(SCNVector3(q.x, q.y, q.z))
            norms.append(SCNVector3(n.x, n.y, n.z))
            uvs.append(CGPoint(x: q.x * uvScale, y: (q.z + q.y) * uvScale))
        }
        for k in 1..<(pts.count - 1) { idx += [base, base + Int32(k), base + Int32(k + 1)] }
    }

    func geometry() -> SCNGeometry {
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                      SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        return g
    }
}

enum TableBuilder {
    static var pack: TexturePack!
    // Wymiary
    static var L: Double { Phys.halfL }
    static var W: Double { Phys.halfW }
    static let railIn = 0.07          // głębokość bandy (od noska do drewna)
    static let railW = 0.15           // szerokość drewnianej ramy
    static let railTop = 0.05
    static var X: Double { Phys.halfL + railIn }
    static var Y: Double { Phys.halfW + railIn }   // wewnętrzny prostokąt ramy
    static let floorY = -0.80

    // MARK: Shadery z pliku Shaders.metal
    static let shaders: [String: String] = {
        var out: [String: String] = [:]
        guard let url = Bundle.main.url(forResource: "Shaders", withExtension: "metal"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return out }
        var name: String? = nil, buf: [String] = []
        func flush() { if let n = name { out[n] = buf.joined(separator: "\n") } }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("// ==== ") { flush(); name = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces); buf = [] }
            else if name != nil { buf.append(line) }
        }
        flush()
        return out
    }()

    // MARK: Materiały
    static func pbr(_ color: Any, rough: Double, metal: Double) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    static func cushionColor(blue: Bool = true) -> NSColor { clothColor().blended(withFraction: 0.18, of: .black) ?? clothColor() }

    static func clothMaterial(blue: Bool, normalMap: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = pack.clothDiffuse
        m.multiply.contents = clothColor(blue: blue)
        if normalMap { m.normal.contents = pack.clothNormal }
        m.normal.intensity = 0.55 * CGFloat(Settings.shared.cloth.weave)
        m.roughness.contents = pack.clothRough
        m.metalness.contents = 0.0
        for p in [m.diffuse, m.normal, m.roughness] {
            p.wrapS = .repeat; p.wrapT = .repeat
            p.mipFilter = .linear
            p.maxAnisotropy = 16
        }
        if !normalMap { m.multiply.contents = cushionColor(blue: blue) }
        if let s = shaders["cloth_surface"] { m.shaderModifiers = [.surface: s] }
        return m
    }
    static func clothColor(blue: Bool = true) -> NSColor { nsc(Settings.shared.cloth.color) }

    static func woodMaterial(light: Bool = false) -> SCNMaterial {
        let m = pbr(pack.woodAlbedo, rough: 0.34, metal: 0)
        m.normal.contents = pack.woodNormal
        m.normal.intensity = 0.8
        m.roughness.contents = pack.woodRough
        for p in [m.diffuse, m.normal, m.roughness] { p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear; p.maxAnisotropy = 16 }
        m.clearCoat.contents = 0.6
        m.clearCoatRoughness.contents = 0.12
        if let s = shaders["wood_surface"] { m.shaderModifiers = [.surface: s] }
        return m
    }
    /// czarny lakier fortepianowy na skanie orzecha (słoje prześwitują lekko spod lakieru)
    static func blackLacquer() -> SCNMaterial {
        let m = woodMaterial()
        styleRail(m, Settings.shared.finish)
        return m
    }
    static func styleRail(_ m: SCNMaterial, _ f: FinishDef) {
        if f.solid {
            m.diffuse.contents = nsc(f.railTint); m.multiply.contents = nil
            m.normal.contents = nil; m.roughness.contents = 0.25
            m.emission.contents = nsc(f.railTint); m.emission.intensity = 0.22    // światła sceny są słabe – lekka własna jasność
        } else {
            m.diffuse.contents = pack.woodAlbedo; m.normal.contents = pack.woodNormal
            m.emission.contents = nil; m.emission.intensity = 0
            m.multiply.contents = nsc(f.railTint)
            m.roughness.contents = f.natural ? pack.woodRough : 0.22
            m.normal.intensity = f.natural ? 0.8 : 0.25
        }
        m.clearCoat.contents = 1.0
        m.clearCoatRoughness.contents = f.natural ? 0.1 : 0.06
    }

    // MARK: Pomocnicze geometrii
    /// nadaje wierzchołkom SCNShape współrzędne UV z położenia (x,y)·scale
    static func remapUV(_ g: SCNGeometry, scale: Double, zMix: Double = 0) -> SCNGeometry {
        guard let vs = g.sources(for: .vertex).first else { return g }
        let n = vs.vectorCount, stride = vs.dataStride, off = vs.dataOffset, bpc = vs.bytesPerComponent
        var uv: [CGPoint] = []
        uv.reserveCapacity(n)
        vs.data.withUnsafeBytes { raw in
            for i in 0..<n {
                let base = raw.baseAddress!.advanced(by: i * stride + off)
                var x = 0.0, y = 0.0, z = 0.0
                if bpc == 4 { x = Double(base.load(as: Float.self)); y = Double(base.advanced(by: 4).load(as: Float.self))
                    if zMix != 0 { z = Double(base.advanced(by: 8).load(as: Float.self)) } }
                else { x = base.load(as: Double.self); y = base.advanced(by: 8).load(as: Double.self)
                    if zMix != 0 { z = base.advanced(by: 16).load(as: Double.self) } }
                uv.append(CGPoint(x: x * scale, y: (y - zMix * z) * scale))
            }
        }
        let srcs = g.sources.filter { $0.semantic != .texcoord } + [SCNGeometrySource(textureCoordinates: uv)]
        return SCNGeometry(sources: srcs, elements: g.elements)
    }

    static func poly(_ path: NSBezierPath, _ pts: [CGPoint]) {
        guard let f = pts.first else { return }
        path.move(to: f)
        for q in pts.dropFirst() { path.line(to: q) }
        path.close()
    }

    /// łuk okręgu (próbkowany) od p1 do p2 po stronie zewnętrznej względem wewnętrznego prostokąta ramy
    static func arcPoints(c: V2, r: Double, p1: V2, p2: V2, n: Int = 40) -> [V2] {
        let (a1, sweep) = arcSweep(c: c, r: r, p1: p1, p2: p2)
        return (0...n).map { k in
            let a = a1 + sweep * Double(k) / Double(n)
            return c + r * V2(cos(a), sin(a))
        }
    }
    /// kąt początkowy i rozwartość łuku p1→p2 po stronie zewnętrznej ramy
    static func arcSweep(c: V2, r: Double, p1: V2, p2: V2) -> (Double, Double) {
        let a1 = atan2(p1.y - c.y, p1.x - c.x), a2 = atan2(p2.y - c.y, p2.x - c.x)
        var d1 = a2 - a1
        while d1 <= 0 { d1 += 2 * .pi }
        let d2 = d1 - 2 * .pi
        func outside(_ a: Double) -> Bool {
            let p = c + r * V2(cos(a), sin(a))
            return abs(p.x) > X + 1e-6 || abs(p.y) > Y + 1e-6
        }
        return (a1, outside(a1 + d1 / 2) ? d1 : d2)
    }
    /// prawdziwy łuk Béziera (SCNShape wygładza normalne na krzywych – brak fasetek); sx/sy – odbicie lustrzane
    static func addArc(_ path: NSBezierPath, c: V2, r: Double, a1: Double, sweep: Double, sx: Double = 1, sy: Double = 1) {
        let s = V2((c.x + r * cos(a1)) * sx, (c.y + r * sin(a1)) * sy), cm = V2(c.x * sx, c.y * sy)
        let am = atan2(s.y - cm.y, s.x - cm.x), sw = sweep * sx * sy
        path.appendArc(withCenter: CGPoint(x: cm.x, y: cm.y), radius: CGFloat(r), startAngle: CGFloat(am * 180 / .pi),
                       endAngle: CGFloat((am + sw) * 180 / .pi), clockwise: sw < 0)
    }
    /// kontur otworu w ramie (6 łuków łuz) jako krzywe
    static func holePath(_ path: NSBezierPath, reversed: Bool) {
        let specs = reversed ? pocketArcSpecs().reversed().map { ($0.0, $0.2, $0.1) } : pocketArcSpecs()
        for (k, (p, a, b)) in specs.enumerated() {
            if k == 0 { path.move(to: CGPoint(x: a.x, y: a.y)) }
            let (a1, sw) = arcSweep(c: p.c, r: p.r, p1: a, p2: b)
            addArc(path, c: p.c, r: p.r, a1: a1, sweep: sw)
        }
        path.close()
    }
    static func pocketArcs() -> [(pocket: Pocket, pts: [V2])] {
        pocketArcSpecs().map { ($0.0, arcPoints(c: $0.0.c, r: $0.0.r, p1: $0.1, p2: $0.2)) }
    }

    /// Wszystkie 6 łuków (otwory łuz w ramie) w kolejności obchodzenia konturu
    static func pocketArcSpecs() -> [(Pocket, V2, V2)] {
        var out: [(Pocket, V2, V2)] = []
        let pk = BilliardPhysics.pockets
        func corner(_ sx: Double, _ sy: Double) -> Pocket { pk.first { !$0.side && $0.c.x * sx > 0 && $0.c.y * sy > 0 }! }
        func side(_ sy: Double) -> Pocket { pk.first { $0.side && $0.c.y * sy > 0 }! }
        func cornerArc(_ sx: Double, _ sy: Double, enterAtH: Bool) -> (Pocket, V2, V2) {
            let p = corner(sx, sy), c = p.c
            let h1 = sqrt(max(0, p.r * p.r - pow(X - abs(c.x), 2))), h2 = sqrt(max(0, p.r * p.r - pow(Y - abs(c.y), 2)))
            let v = V2(sx * X, c.y - sy * h1), h = V2(c.x - sx * h2, sy * Y)
            return (p, enterAtH ? h : v, enterAtH ? v : h)
        }
        func sideArc(_ sy: Double, ltr: Bool) -> (Pocket, V2, V2) {
            let p = side(sy)
            let h3 = sqrt(p.r * p.r - pow(Y - abs(p.c.y), 2))
            let a = V2(-h3, sy * Y), b = V2(h3, sy * Y)
            return (p, ltr ? a : b, ltr ? b : a)
        }
        out.append(sideArc(-1, ltr: true))
        out.append(cornerArc(1, -1, enterAtH: true))
        out.append(cornerArc(1, 1, enterAtH: false))
        out.append(sideArc(1, ltr: false))
        out.append(cornerArc(-1, 1, enterAtH: true))
        out.append(cornerArc(-1, -1, enterAtH: false))
        return out
    }

    // MARK: Budowa
    static var holeExtra: Double { Phys.modelTable && !Phys.snooker ? 0.004 : 0 }
    static func build(blueCloth: Bool, pack texPack: TexturePack, applied: Bool = false) -> TableNodes {
        pack = applied ? texPack : Scans.apply(texPack)
        let sc = Phys.halfL / 1.27           // skala stołu względem 9 ft (lampy, oświetlenie)
        let rScale = Phys.R / 0.028575
        var t = TableNodes()
        let root = t.root
        root.name = "table"
        let cloth = clothMaterial(blue: blueCloth, normalMap: false)   // bandy: bez mapy normalnych (brak tangentów w siatce)
        t.cushionMaterial = cloth
        for p in [cloth.diffuse, cloth.roughness] { p.contentsTransform = SCNMatrix4MakeScale(10, 1, 1) }
        let wood = blackLacquer()
        let brass = chromeMaterial()     // okucia łuz wg wykończenia stołu
        t.railMaterials.append(wood); t.fitting = brass

        // --- sukno (płaszczyzna gry y = 0) z 6 otworami
        // kontur zewnętrzny przeciwnie do ruchu wskazówek, otwory zgodnie (SCNShape używa reguły niezerowej)
        // margines sukna poza polem gry: pod ramą proceduralną 13 cm; model 3D ma węższą ramę i boki (±1,364 × ±0,735 m),
        // więc 9 cm – sukno chowa się pod ramą modelu, a otwory łuz (najdalej 1,33 / 0,72 m) dalej mieszczą się w konturze
        let ce = holeExtra > 0 ? 0.09 : 0.13
        let clothPath = NSBezierPath()
        poly(clothPath, [CGPoint(x: -(L + ce), y: -(W + ce)), CGPoint(x: L + ce, y: -(W + ce)),
                         CGPoint(x: L + ce, y: W + ce), CGPoint(x: -(L + ce), y: W + ce)])
        for p in BilliardPhysics.pockets {       // otwory zgodnie z ruchem wskazówek, jako prawdziwe okręgi
            let hr = p.r + holeExtra      // model 3D: otwór sukna chowa się pod kubkiem łuzy modelu
            clothPath.move(to: CGPoint(x: p.c.x + hr, y: p.c.y))
            clothPath.appendArc(withCenter: CGPoint(x: p.c.x, y: p.c.y), radius: CGFloat(hr), startAngle: 360, endAngle: 0, clockwise: true)
            clothPath.close()
        }
        clothPath.flatness = CGFloat(Double(ProcessInfo.processInfo.environment["BILARD_FLAT"] ?? "") ?? 0.0002)
        // model 3D: sukno 1 cm (spód nad dolną krawędzią ramy modelu y = −1,24 cm – niewidoczne z boku ani spod stołu)
        let clothShape = SCNShape(path: clothPath, extrusionDepth: holeExtra > 0 ? 0.01 : 0.02)
        clothShape.chamferRadius = ProcessInfo.processInfo.environment["BILARD_NOCC"] != nil ? 0 : 0.004        // zaokrąglony brzeg sukna wpadający w otwór łuzy
        clothShape.chamferMode = .front
        clothShape.chamferProfile = roundProfile()
        // SCNShape mapuje UV na obwiednię kształtu (0…1) – skalujemy teksturę do ~8 włókien/m
        let clothTop = clothMaterial(blue: blueCloth)
        t.clothMaterials = [clothTop]
        let cw = 2 * (L + ce), ch = 2 * (W + ce)
        for p in [clothTop.diffuse, clothTop.normal, clothTop.roughness] { p.contentsTransform = SCNMatrix4MakeScale(CGFloat(cw * 8), CGFloat(ch * 8), 1) }
        clothShape.materials = [clothTop]
        let clothNode = SCNNode(geometry: clothShape)
        clothNode.eulerAngles.x = -.pi / 2
        clothNode.position.y = -CGFloat(clothShape.boundingBox.max.z)
        clothNode.name = "cloth"
        root.addChildNode(clothNode)

        // --- płyta łupkowa pod suknem (ciemna), żeby nie prześwitywało
        let slate = SCNBox(width: 2 * (L + 0.13), height: 0.04, length: 2 * (W + 0.13), chamferRadius: 0)
        slate.materials = [pbr(nsc(0x151515), rough: 0.9, metal: 0)]
        let slateNode = SCNNode(geometry: slate)
        slateNode.position = SCNVector3(0, -0.032, 0)
        // prosta płyta zasłaniałaby łuzy – wycinamy ją od spodu przez głęboką czerń rur łuz
        // (płyta pomijana: sukno ma grubość 2 cm i pod nim jest otwarta przestrzeń)
        _ = slateNode

        // --- drewniana rama z otworami łuz
        let railPath = NSBezierPath()
        let ox = X + railW, oy = Y + railW, rr = 0.09
        railPath.move(to: CGPoint(x: ox - rr, y: -oy))
        for (cx, cy, a0) in [(ox - rr, -oy + rr, -90.0), (ox - rr, oy - rr, 0.0), (-ox + rr, oy - rr, 90.0), (-ox + rr, -oy + rr, 180.0)] {
            addArc(railPath, c: V2(cx, cy), r: rr, a1: a0 * .pi / 180, sweep: .pi / 2)
        }
        railPath.close()
        holePath(railPath, reversed: true)
        railPath.flatness = CGFloat(Double(ProcessInfo.processInfo.environment["BILARD_FLAT"] ?? "") ?? 0.0002)
        let railShape = SCNShape(path: railPath, extrusionDepth: 0.09)
        railShape.chamferRadius = 0.022
        railShape.chamferMode = .front
        railShape.chamferProfile = roundProfile()   // ćwierćokrąg: zaokrąglony brzeg ramy jak w prawdziwych stołach
        wood.diffuse.contentsTransform = SCNMatrix4MakeScale(CGFloat(2 * (X + railW) * 2.2), CGFloat(2 * (Y + railW) * 2.2), 1)
        railShape.materials = [wood]
        let railNode = SCNNode(geometry: railShape)
        railNode.eulerAngles.x = -.pi / 2
        railNode.position.y = railTop - CGFloat(railShape.boundingBox.max.z)
        railNode.name = "rail"
        root.addChildNode(railNode)

        // --- bandy K-66 (4 rzędy z 45° ściętymi końcami przy łuzach)
        let lx = L - Phys.tipGap, sz = W - Phys.tipGap
        let longRanges: [(Double, Double)] = [(Phys.sideTip, lx), (-lx, -Phys.sideTip)]
        let shortRanges: [(Double, Double)] = [(-sz, sz)]
        let rails: [(V3, Double, [(Double, Double)])] = [
            (V3(0, 0, W), 0, longRanges), (V3(0, 0, -W), .pi, longRanges),
            (V3(L, 0, 0), .pi / 2, shortRanges), (V3(-L, 0, 0), -.pi / 2, shortRanges)]
        for (pos, rot, ranges) in rails {
            let n = SCNNode()
            n.position = SCNVector3(pos.x, pos.y, pos.z)
            n.eulerAngles.y = CGFloat(rot)
            n.name = "cushion"
            for (a, b) in ranges { n.addChildNode(cushionNode(a: a, b: b, mat: cloth)) }
            root.addChildNode(n)
        }

        // --- metalowe obrzeża łuz (łuki mosiądzu) + wnętrze łuzy z siatką
        let net = SCNMaterial()
        net.lightingModel = .lambert
        net.diffuse.contents = pack.net
        net.diffuse.wrapS = .repeat; net.diffuse.wrapT = .repeat
        net.isDoubleSided = true
        net.transparencyMode = .aOne
        let black = pbr(pack.leatherAlbedo, rough: 0.55, metal: 0)     // skórzany kosz łuzy
        black.normal.contents = pack.leatherNormal; black.normal.intensity = 1.2
        for p in [black.diffuse, black.normal] { p.wrapS = .repeat; p.wrapT = .repeat; p.contentsTransform = SCNMatrix4MakeScale(4, 2, 1); p.mipFilter = .linear }
        black.isDoubleSided = true
        black.multiply.contents = NSColor(white: 0.10, alpha: 1)
        let liner = pbr(nsc(0x030303), rough: 0.9, metal: 0)        // gumowa wykładzina łuzy
        liner.isDoubleSided = true
        liner.lightingModel = .constant; liner.diffuse.contents = NSColor.black   // wnętrze łuzy: głęboka czerń bez odbić
        for (pocket, pts) in pocketArcs() {
            let mb = MeshBuilder()
            let w = 0.042
            for k in 0..<(pts.count - 1) {
                func inner(_ p: V2) -> V2 { pocket.c + (p - pocket.c) * ((pocket.r - 0.0008) / pocket.r) }
                func outer(_ p: V2) -> V2 { pocket.c + (p - pocket.c) * ((pocket.r + w) / pocket.r) }
                let a = inner(pts[k]), b = inner(pts[k + 1]), c = outer(pts[k + 1]), d = outer(pts[k])
                let top = railTop + 0.0025
                let mid = (a + c) / 2
                let ctr = V3(mid.x, 0.02, mid.y)
                _ = (c, d, top)
                mb.face([V3(a.x, railTop, a.y), V3(b.x, railTop, b.y), V3(b.x, -0.006, b.y), V3(a.x, -0.006, a.y)], center: ctr)
            }
            let g = mb.geometry()
            g.materials = [liner]
            let ln = SCNNode(geometry: g)
            ln.name = "liner"
            root.addChildNode(ln)
            root.addChildNode(pocketCasting(pocket, chrome: brass))

            // kosz łuzy: jedna gładka rura (bez stopni i szczelin) od spodu zaokrąglonego sukna do czarnego dna
            let tube = SCNTube(innerRadius: CGFloat(pocket.r + holeExtra - 0.0012), outerRadius: CGFloat(pocket.r + holeExtra - 0.0004), height: 0.032)
            tube.radialSegmentCount = 96
            tube.materials = [liner]
            let tn = SCNNode(geometry: tube)
            tn.position = SCNVector3(pocket.c.x, -0.003 - 0.016, pocket.c.y)
            root.addChildNode(tn)
            let bottom = SCNCylinder(radius: CGFloat(pocket.r + holeExtra), height: 0.004)
            bottom.radialSegmentCount = 48
            bottom.materials = [liner]
            let bnode = SCNNode(geometry: bottom)
            bnode.position = SCNVector3(pocket.c.x, -0.034, pocket.c.y)   // dno nad korpusem (góra korpusu y = −0,04)
            root.addChildNode(bnode)
        }

        // --- „diamenty” na ramie
        let pearl = pbr(nsc(0xF4F2EC), rough: 0.2, metal: 0)
        let dRail = railIn + railW / 2
        for s in [-1.0, 1.0] {
            for k in [-0.75, -0.5, -0.25, 0.25, 0.5, 0.75] {
                addDiamond(root, pearl, x: k * L, z: s * (W + dRail))
            }
            for k in [-0.5, 0, 0.5] { addDiamond(root, pearl, x: s * (L + dRail), z: k * W) }
        }

        // --- korpus i nogi
        let body = SCNBox(width: 2 * (X + railW) - 0.03, height: 0.26, length: 2 * (Y + railW) - 0.03, chamferRadius: 0.015)
        let bodyMat = blackLacquer(); t.railMaterials.append(bodyMat)
        body.chamferSegmentCount = 10
        body.materials = [bodyMat]
        let bn = SCNNode(geometry: body)
        bn.name = "body"
        bn.position = SCNVector3(0, -0.04 - 0.13, 0)
        root.addChildNode(bn)
        let legMat = blackLacquer(); t.railMaterials.append(legMat)
        for sx in [-1.0, 1.0] { for sz2 in [-1.0, 1.0] {
            let leg = SCNBox(width: 0.17, height: CGFloat(-0.17 - floorY), length: 0.17, chamferRadius: 0.012)
            leg.chamferSegmentCount = 8
            leg.materials = [legMat]
            let ln = SCNNode(geometry: leg)
            ln.name = "leg"
            ln.position = SCNVector3(sx * (X + railW - 0.20), (-0.17 + floorY) / 2, sz2 * (Y + railW - 0.20))
            root.addChildNode(ln)
        } }

        // --- podłoga
        // podłoga: ciemne deski (tło HDRI z góry pokazywało drugi, olbrzymi stół i ucinało salę w połowie)
        let floor = SCNFloor()
        floor.reflectivity = 0.03
        floor.reflectionFalloffEnd = 0.5
        let fm = pbr(pack.woodAlbedo, rough: 0.6, metal: 0)
        fm.multiply.contents = nsc(0x5A4A40)
        fm.diffuse.wrapS = .repeat; fm.diffuse.wrapT = .repeat; fm.diffuse.mipFilter = .linear; fm.diffuse.maxAnisotropy = 16
        fm.diffuse.contentsTransform = SCNMatrix4MakeScale(2.2, 2.2, 1)
        floor.materials = [fm]
        // miękki cień stołu i nóg na podłodze (reflektory są zbyt słabe, by rzucić go same)
        let fsW = 2 * (X + railW) + 0.9, fsH = 2 * (Y + railW) + 0.9
        let fsImg = makeImage(512, 320) { ctx in
            let iw = 512 * (2 * (X + railW)) / fsW, ih = 320 * (2 * (Y + railW)) / fsH
            let r = CGRect(x: 256 - iw / 2, y: 160 - ih / 2, width: iw, height: ih)
            ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 60, color: rgb(0x000000, 0.9))
            ctx.setFillColor(rgb(0x000000, 0.55)); ctx.fill(r.insetBy(dx: 14, dy: 14))
            ctx.setShadow(offset: .zero, blur: 10, color: rgb(0x000000, 1))
            ctx.setFillColor(rgb(0x000000, 0.85))
            for sx in [-1.0, 1.0] { for sy in [-1.0, 1.0] {
                let cx = 256 + sx * 512 * (X + railW - 0.20) / fsW, cy = 160 + sy * 320 * (Y + railW - 0.20) / fsH
                ctx.fill(CGRect(x: cx - 14, y: cy - 14, width: 28, height: 28))
            } }
        }
        let fsm = SCNMaterial()
        fsm.lightingModel = .constant
        fsm.diffuse.contents = fsImg
        fsm.writesToDepthBuffer = false
        let fsn = SCNNode(geometry: SCNPlane(width: fsW, height: fsH))
        fsn.geometry!.materials = [fsm]
        fsn.eulerAngles.x = -.pi / 2
        fsn.position = SCNVector3(0, floorY + 0.002, 0)
        fsn.castsShadow = false
        root.addChildNode(fsn)
        let fn = SCNNode(geometry: floor)
        fn.position = SCNVector3(0, floorY, 0)
        root.addChildNode(fn)

        // --- bile
        let ballShader = shaders["ball_surface"]
        let snookerColors: [UInt32] = [0xE8C21A, 0x1F8A3A, 0x6B3A1E, 0x1F4FC9, 0xE8749A, 0x0E0E10]
        for i in 0..<Phys.nBalls {
            // LOD: gęsta kula w zbliżeniach (brak widocznych krawędzi), lżejsze z daleka
            func sphere(_ n: Int) -> SCNSphere { let g = SCNSphere(radius: Phys.R); g.segmentCount = n; return g }
            let s = sphere(Int(ProcessInfo.processInfo.environment["BILARD_BALLSEG"] ?? "") ?? 128)
            var tex: Any = i < 16 ? pack.balls[i] : nsc(snookerColors[i - 16])
            if Phys.snooker && i >= 1 && i <= 15 { tex = nsc(0xC4161C) }      // snooker: czerwone bez numerów
            if !Phys.snooker && i >= 16 { tex = nsc(0x808080) }
            let m = pbr(tex, rough: 0.05, metal: 0)
            m.roughness.contents = pack.ballRough            // 0,03–0,08: polerowana żywica fenolowa
            m.normal.contents = pack.ballNormal; m.normal.intensity = 0.25
            for p in [m.diffuse, m.normal, m.roughness] { p.mipFilter = .linear; p.maxAnisotropy = 16 }
            m.clearCoat.contents = Double(ProcessInfo.processInfo.environment["BILARD_CC"] ?? "") ?? 1.0
            m.clearCoatRoughness.contents = 0.015
            if let sh = ballShader, ProcessInfo.processInfo.environment["BILARD_NOBALLSH"] == nil { m.shaderModifiers = [.surface: sh] }
            m.setValue(SCNVector3(0, 1, 0), forKey: "lampDirV")
            t.ballMaterials.append(m)
            s.materials = [m]
            let mid = sphere(56), low = sphere(28)
            mid.materials = [m]; low.materials = [m]
            if ProcessInfo.processInfo.environment["BILARD_NOLOD"] == nil { s.levelsOfDetail = [SCNLevelOfDetail(geometry: mid, screenSpaceRadius: 70),
                                SCNLevelOfDetail(geometry: low, screenSpaceRadius: 16)] }
            let n = SCNNode(geometry: s)
            n.name = "ball\(i)"
            n.position = SCNVector3(0, Phys.R, 0)
            root.addChildNode(n)
            t.balls.append(n)
        }

        // --- nakładka z oznaczeniami sukna (baza, punkty, tor rozbicia, kreda)
        let envv = ProcessInfo.processInfo.environment
        var decAdd = pack.decalAdd, decMul = pack.decalMul
        if Phys.snooker { (decAdd, decMul) = TextureFactory.tableDecals() }
        for (img, blend, order) in envv["BILARD_NODECAL"] != nil ? [] : [(decMul, SCNBlendMode.multiply, 2), (decAdd, SCNBlendMode.add, 3)] {
            let dm = SCNMaterial()
            dm.lightingModel = .constant
            dm.diffuse.contents = img
            dm.blendMode = blend
            dm.diffuse.mipFilter = .linear; dm.diffuse.minificationFilter = .linear; dm.diffuse.maxAnisotropy = 16   // cienkie linie i kreda bez migotania z daleka
            dm.writesToDepthBuffer = false
            let dp = SCNPlane(width: 2 * L, height: 2 * W)
            dp.materials = [dm]
            let dn = SCNNode(geometry: dp)
            dn.eulerAngles.x = -.pi / 2
            dn.position.y = 0.0014
            dn.renderingOrder = order
            t.decals.append(dn)
            dn.castsShadow = false
            root.addChildNode(dn)
        }

        // --- emblemat na środku sukna (wybierany w menu Wygląd)
        if envv["BILARD_NODECAL"] == nil {
            let em = SCNMaterial()
            em.lightingModel = .constant
            em.blendMode = .add
            em.diffuse.mipFilter = .linear; em.diffuse.minificationFilter = .linear; em.diffuse.maxAnisotropy = 16
            em.diffuse.contents = Emblems.image(Settings.shared.emblemId)
            em.writesToDepthBuffer = false
            let ep = SCNPlane(width: 1.15 * W, height: 1.15 * W)
            ep.materials = [em]
            let en = SCNNode(geometry: ep)
            en.eulerAngles.x = -.pi / 2
            en.position.y = 0.0014
            en.renderingOrder = 4
            en.castsShadow = false
            en.isHidden = Settings.shared.emblemId == "none"
            t.decals.append(en); t.emblem = en
            root.addChildNode(en)
        }

        // --- miękkie cienie kontaktowe pod bilami + anamorficzny blask na refleksach
        for _ in 0..<Phys.nBalls {
            let cm = SCNMaterial()
            cm.lightingModel = .constant
            cm.diffuse.contents = pack.contact
            cm.diffuse.mipFilter = .linear; cm.diffuse.maxAnisotropy = 16
            cm.writesToDepthBuffer = false
            let cp = SCNPlane(width: 0.125 * rScale, height: 0.125 * rScale)
            cp.materials = [cm]
            let cn = SCNNode(geometry: cp)
            cn.eulerAngles.x = -.pi / 2
            cn.position.y = 0.0020
            cn.renderingOrder = 3
            cn.castsShadow = false
            root.addChildNode(cn)
            t.contact.append(cn)

            let gm = SCNMaterial()
            gm.lightingModel = .constant
            gm.diffuse.contents = pack.glare
            gm.blendMode = .add
            gm.writesToDepthBuffer = false
            gm.readsFromDepthBuffer = false
            let gp = SCNPlane(width: 0.20 * rScale, height: 0.05 * rScale)
            gp.materials = [gm]
            let gn = SCNNode(geometry: gp)
            gn.constraints = [SCNBillboardConstraint()]
            gn.renderingOrder = 200
            gn.opacity = 0          // sztuczny blask wyłączony: na zdjęciach go nie ma
            gn.castsShadow = false
            root.addChildNode(gn)
            t.glare.append(gn)
        }

        // --- stożek światła lampy + drobiny pyłu (subtelne „god rays”)
        let sm = SCNMaterial()
        sm.lightingModel = .constant
        sm.diffuse.contents = pack.shaft
        sm.blendMode = .add
        sm.transparency = 0.0035
        sm.writesToDepthBuffer = false
        sm.isDoubleSided = true
        let cone = SCNCone(topRadius: 0.08, bottomRadius: 1.9, height: 2.3)
        cone.radialSegmentCount = 48
        cone.materials = [sm]
        let coneNode = SCNNode(geometry: cone)
        coneNode.position = SCNVector3(0, 2.4 - 1.15, 0)
        coneNode.renderingOrder = 50
        coneNode.castsShadow = false; coneNode.opacity = 0   // sam stożek wyłączony, zostaje pył
        t.shafts.addChildNode(coneNode)
        let ps = SCNParticleSystem()
        ps.birthRate = 4
        ps.particleLifeSpan = 20
        ps.particleLifeSpanVariation = 6
        let eshape = SCNCylinder(radius: 1.2, height: 2.0)
        ps.emitterShape = eshape
        ps.birthLocation = .volume
        ps.particleVelocity = 0.025
        ps.particleVelocityVariation = 0.03
        ps.spreadingAngle = 180
        ps.emittingDirection = SCNVector3(0, 1, 0)
        ps.particleImage = pack.dot
        ps.particleSize = 0.0028
        ps.particleSizeVariation = 0.0015
        ps.particleColor = NSColor(white: 1, alpha: 0.32)
        ps.blendMode = .additive
        ps.isLightingEnabled = false
        ps.warmupDuration = 15
        let pn = SCNNode()
        pn.position = SCNVector3(0, 1.1, 0)
        pn.addParticleSystem(ps)
        t.shafts.addChildNode(pn)
        if envv["BILARD_NOCONE"] == nil { root.addChildNode(t.shafts) }

        // --- kij
        t.cue = makeCue()
        root.addChildNode(t.cue)

        // --- oświetlenie: długa lampa turniejowa = 3 reflektory (miękkie, nakładające się cienie) + IBL + sonda odbić
        for (k, x0) in [-0.78, 0.0, 0.78].enumerated() {
            let x = x0 * sc
            let lampNode = SCNNode()
            let light = SCNLight()
            light.type = .spot
            light.color = nsc(0xFFF8F0)
            light.temperature = 5600
            light.intensity = CGFloat((k == 1 ? 1500.0 : 1300.0) * lightMul)
            light.spotInnerAngle = 70
            light.spotOuterAngle = 125
            light.castsShadow = true
            light.shadowMapSize = CGSize(width: 1024, height: 1024)
            light.shadowSampleCount = 4
            light.shadowRadius = 4
            light.shadowColor = NSColor(white: 0, alpha: 1.0)
            light.shadowBias = 0.5
            light.zNear = 0.3
            light.zFar = 4
            lampNode.light = light
            t.lampLights.append(light)
            lampNode.position = SCNVector3(x, 0.93, 0)
            lampNode.eulerAngles.x = -.pi / 2
            root.addChildNode(lampNode)
            if k == 1 { t.lamp = lampNode }
            t.lampFixtures.addChildNode(pendantLamp(x: x))
        }
        root.addChildNode(t.lampFixtures)
        // widoczna lampa (tylko dla sondy odbić; kamera główna jej nie renderuje)
        let lm = SCNMaterial()
        lm.lightingModel = .constant
        lm.diffuse.contents = NSColor.white
        lm.emission.contents = NSColor.white
        lm.emission.intensity = 6
        let lbox = SCNBox(width: 2.3 * sc, height: 0.05, length: 0.30, chamferRadius: 0.02)
        lbox.materials = [lm]
        let lampGeo = SCNNode(geometry: lbox)
        lampGeo.position = SCNVector3(0, 2.34, 0)
        lampGeo.categoryBitMask = 4
        lampGeo.castsShadow = false
        root.addChildNode(lampGeo)
        // sonda światła: odbicia pobliskich bil, band i lampy w bilach (color bleeding)
        let probe = SCNLight()
        probe.type = .probe
        probe.probeType = .radiance
        probe.probeUpdateType = .never
        probe.probeExtents = SIMD3<Float>(Float(3.4 * sc), 2.6, Float(2.2 * sc))
        probe.parallaxCorrectionEnabled = true
        let probeNode = SCNNode()
        probeNode.light = probe
        probeNode.position = SCNVector3(0, 0.30, 0)
        probeNode.name = "probe"
        t.probeNode = probeNode; t.probeLight = probe
        t.probe = probe
        // sonda wyłączona: zasłaniała odbicia HDRI i przepalała bile odbiciem lampy (włącz: BILARD_PROBE=1)
        if ProcessInfo.processInfo.environment["BILARD_PROBE"] != nil { root.addChildNode(probeNode) } else { t.probe = nil }
        // stół z modelu 3D: części proceduralne zastąpione siatką modelu (sukno, rury łuz, bile, lampy zostają)
        if Phys.modelTable && !Phys.snooker {
            let lac = blackLacquer()      // UV modelu w metrach (rzut sześcienny) – własna skala słojów
            for p in [lac.diffuse, lac.normal, lac.roughness] { p.contentsTransform = SCNMatrix4MakeScale(1.4, 1.4, 1) }
            if let m = modelTable(t, lacquer: lac) {
                for c in root.childNodes where proceduralParts.contains(c.name ?? "") { c.removeFromParentNode() }
                root.addChildNode(m)
                t.railMaterials.append(lac)
            }
        }
        if ProcessInfo.processInfo.environment["BILARD_TRIS"] != nil {     // diagnostyka: trójkąty wg węzła
            var rows: [(String, Int)] = []
            root.enumerateHierarchy { n, _ in
                guard let g = n.geometry else { return }
                let c = g.elements.reduce(0) { $0 + $1.primitiveCount }
                rows.append(("\(n.name ?? n.parent?.name ?? "?") \(type(of: g))", c))
            }
            var agg: [String: (Int, Int)] = [:]
            for (k, c) in rows { let o = agg[k] ?? (0, 0); agg[k] = (o.0 + 1, o.1 + c) }
            for (k, v) in agg.sorted(by: { $0.value.1 > $1.value.1 }).prefix(14) { print("TRIS \(k): \(v.0)× \(v.1)") }
        }

        let fill = SCNNode()
        let fl = SCNLight()
        fl.type = .ambient
        fl.intensity = 0     // płaskie wypełnienie wyłączone: przepalało bile
        fl.color = nsc(0xE8ECF4)
        fill.light = fl
        root.addChildNode(fill)
        return t
    }

    /// chromowany odlew łuzy: płyta na ramie wokół otworu (narożna obejmuje róg stołu)
    static var lightMul: Double { Double(ProcessInfo.processInfo.environment["BILARD_LIGHT"] ?? "") ?? 0.015 }
    /// wisząca lampa: ciemnozielony metalowy klosz, biała świecąca dyfuzja od spodu, przewód do sufitu
    static func pendantLamp(x: Double) -> SCNNode {
        let n = SCNNode()
        n.position = SCNVector3(x, 1.0, 0)
        let shell = pbr(nsc(0x16392A), rough: 0.25, metal: 0.6)
        shell.clearCoat.contents = 0.8; shell.clearCoatRoughness.contents = 0.05
        let inner = pbr(nsc(0xF2F0EA), rough: 0.6, metal: 0)
        inner.emission.contents = nsc(0xFFF6E8); inner.emission.intensity = 0.6
        let shade = SCNCone(topRadius: 0.045, bottomRadius: 0.21, height: 0.15)
        shade.radialSegmentCount = 48
        shade.materials = [shell, shell, inner]
        let sn = SCNNode(geometry: shade); sn.position.y = 0.075
        n.addChildNode(sn)
        let glow = pbr(NSColor.white, rough: 1, metal: 0)
        glow.lightingModel = .constant
        glow.emission.contents = nsc(0xFFF8EE); glow.emission.intensity = 9
        let disc = SCNCylinder(radius: 0.19, height: 0.003)
        disc.radialSegmentCount = 48
        disc.materials = [glow]
        let dn = SCNNode(geometry: disc); dn.position.y = 0.004
        n.addChildNode(dn)
        let rod = SCNCylinder(radius: 0.004, height: 2.0)
        rod.materials = [pbr(nsc(0x111111), rough: 0.4, metal: 0.8)]
        let rn = SCNNode(geometry: rod); rn.position.y = 0.15 + 1.0
        n.addChildNode(rn)
        n.enumerateHierarchy { c, _ in c.castsShadow = false; c.categoryBitMask = 8 }
        return n
    }

    /// lustrzany chrom: model Blinna + jasna mapa „studia” (lampy, sufit, ciemna podłoga),
    /// bo ciemna sala z HDRI dawała w PBR matową, brązowoszarą blachę
    /// szczotkowane aluminium: jasnoszary metal z drobnymi poziomymi rysami, szeroki miękki połysk, słabe odbicie otoczenia
    static func chromeMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
        styleFitting(m, Settings.shared.pocketFinish)
        return m
    }
    static func styleFitting(_ m: SCNMaterial, _ f: FinishDef) {
        if f.mirror {
            m.diffuse.contents = NSColor(white: 0.02, alpha: 1)
            m.multiply.contents = f.fittingTint == 0xFFFFFF ? nil : nsc(f.fittingTint)
            m.emission.contents = nil; m.emission.intensity = 0
            m.specular.contents = NSColor.white
            m.shininess = CGFloat(f.fittingGloss)
            m.reflective.contents = chromeEnv
            m.reflective.intensity = 1.25
            m.fresnelExponent = 0
        } else {
            m.diffuse.contents = brushedTex
            m.multiply.contents = nsc(f.fittingTint)
            m.emission.contents = brushedTex      // światła sceny są bardzo słabe – własna jasność daje czytelny metal
            m.emission.intensity = 0.5
            m.specular.contents = NSColor(white: 0.62, alpha: 1)
            m.shininess = CGFloat(f.fittingGloss)
            m.reflective.contents = chromeEnv
            m.reflective.intensity = 0.06
            m.fresnelExponent = 1.5
        }
    }
    static let brushedTex: CGImage = makeImage(512, 512) { ctx in
        ctx.setFillColor(rgb(0x8B8E93)); ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        var g = SeededGen(s: 4242)
        func r() -> Double { Double(g.next() % 10000) / 10000 }
        for _ in 0..<2600 {
            let y = r() * 512, x = r() * 512, l = 40 + r() * 300
            ctx.setStrokeColor(rgb(r() < 0.5 ? 0xFFFFFF : 0x30323A, 0.05 + r() * 0.12))
            ctx.setLineWidth(0.6 + r() * 0.8)
            ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + l, y: y + (r() - 0.5) * 0.8)); ctx.strokePath()
        }
    }
    /// mapa odbić chromu. SceneKit traktuje pojedynczy obraz `reflective` jak sferyczną mapę w przestrzeni widoku
    /// (środek = kierunek do kamery, brzeg = odbicia ślizgowe), a tablica 6 obrazów jako cube map renderowała się na czarno.
    /// Wzór symetryczny góra/dół: ciemne tło, jasne pasy „softboksów” przez środek i jasny pierścień przy brzegu.
    static let chromeEnv: CGImage = makeImage(512, 512) { ctx in
        let c = CGPoint(x: 256, y: 256)
        ctx.drawRadialGradient(gradient([rgb(0x3A3C41), rgb(0x16171A), rgb(0x0C0C0E), rgb(0x2E3034), rgb(0xC9CCD1), rgb(0xF4F5F7)], [0, 0.40, 0.62, 0.84, 0.94, 1]),
                               startCenter: c, startRadius: 0, endCenter: c, endRadius: 256, options: [.drawsAfterEndLocation])
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fill(CGRect(x: 120, y: 268, width: 272, height: 20))        // lampy odbite tuż nad środkiem
        ctx.fill(CGRect(x: 120, y: 224, width: 272, height: 20))
        ctx.setFillColor(rgb(0x9A9DA3))
        ctx.fill(CGRect(x: 60, y: 330, width: 392, height: 12))
        ctx.fill(CGRect(x: 60, y: 170, width: 392, height: 12))
        ctx.setFillColor(rgb(0x050506))
        for k in 0..<4 { ctx.fill(CGRect(x: 110 + k * 96, y: 0, width: 14, height: 512)) }   // ciemne słupki/ramy
    }

    // MARK: Model 3D stołu (Assets/table_model, eksport z poolTable2.blend)
    /// węzły proceduralnego stołu zastępowane przez model (sukno, rury łuz, bile, lampy zostają – zgodne z fizyką)
    static let proceduralParts: Set<String> = ["rail", "cushion", "casting", "body", "leg", "diamond", "liner"]
    static let modelProto: SCNNode? = {
        guard let url = Bundle.main.url(forResource: "pool_table", withExtension: "obj", subdirectory: "Assets/table_model") else { return nil }
        let asset = MDLAsset(url: url)
        asset.loadTextures()
        let sc = SCNScene(mdlAsset: asset)
        let n = SCNNode()
        for c in sc.rootNode.childNodes { n.addChildNode(c) }
        return n
    }()
    /// Model przeskalowany tak, by nosy band pokryły się z bandami fizyki (pole gry modelu 2·1,1676 × 2·0,584 m),
    /// a wierzch jego sukna (y = 0,766) wypadł na y = 0. Materiały: nasze (lakier ramy, okucia, sukno band).
    /// Elementy siatki (ModelIO łączy obiekty OBJ w jedną geometrię, w kolejności eksportu):
    /// 0–1 intarsje, 2 stopki, 3 podstawa, 4 nogi, 5 narożniki boków, 6 listwa, 7 boki, 8 wnętrze łuz,
    /// 9 nakładki łuz, 10 sukno modelu (pomijane), 11 bandy, 12 rama.
    static func modelTable(_ t: TableNodes, lacquer: SCNMaterial) -> SCNNode? {
        guard let proto = modelProto else { return nil }
        let sx = Phys.halfL / 1.1676, sz = Phys.halfW / 0.584, sy = (sx + sz) / 2
        let holder = SCNNode()
        holder.name = "tableModel"
        holder.scale = SCNVector3(sx, sy, sz)
        holder.position.y = CGFloat(-0.766 * sy)
        let pearl = pbr(nsc(0xF4F2EC), rough: 0.2, metal: 0)
        let hole = SCNMaterial(); hole.lightingModel = .constant; hole.diffuse.contents = NSColor.black; hole.isDoubleSided = true
        let rubber = pbr(nsc(0x101010), rough: 0.8, metal: 0)
        let fit = t.fitting ?? chromeMaterial()
        let felt = t.cushionMaterial ?? clothMaterial(blue: true, normalMap: false)
        let byIndex: [SCNMaterial?] = [pearl, pearl, rubber, fit, lacquer, lacquer, fit, lacquer, hole, fit, nil, felt, lacquer]
        let cl = proto.clone()
        cl.enumerateHierarchy { n, _ in
            guard let g = n.geometry else { return }
            var els: [SCNGeometryElement] = [], mats: [SCNMaterial] = []
            for (i, e) in g.elements.enumerated() {
                let m: SCNMaterial? = i < byIndex.count ? byIndex[i] : lacquer
                guard let m else { continue }        // sukno modelu: nasze (otwory łuz zgodne z fizyką)
                els.append(e); mats.append(m)
            }
            let ng = SCNGeometry(sources: g.sources, elements: els)
            ng.materials = mats
            n.geometry = ng
        }
        holder.addChildNode(cl)
        return holder
    }

    /// ćwierćokrąg w jednostkowym kwadracie – profil zaokrąglenia krawędzi SCNShape
    static func roundProfile() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: CGPoint(x: 0, y: 1))
        p.curve(to: CGPoint(x: 1, y: 0), controlPoint1: CGPoint(x: 0.55, y: 1), controlPoint2: CGPoint(x: 1, y: 0.55))
        return p
    }

    /// Banda między końcami a…b (oś x lokalnie, z = głębokość w stronę ramy). Rzut z góry to trapez
    /// z końcami ściętymi pod 45°, a wszystkie narożniki są zaokrąglone; nosek kolanka (jawR) wypada przy
    /// końcu bandy z fizyki. Górna krawędź ma łagodny ćwierćokrąg, więc guma płynnie schodzi do gardła łuzy.
    static func cushionNode(a: Double, b: Double, mat: SCNMaterial) -> SCNNode {
        let back = railIn, h = 0.046, e = 0.009, rTip = max(0.008, Phys.jawR + 0.001), rBack = 0.004
        let A = CGPoint(x: a - e, y: 0), B = CGPoint(x: b + e, y: 0)
        let C = CGPoint(x: b + e - back, y: -back), D = CGPoint(x: a - e + back, y: -back)
        let path = NSBezierPath()
        path.move(to: CGPoint(x: (a + b) / 2, y: 0))
        path.appendArc(from: B, to: C, radius: CGFloat(rTip))
        path.appendArc(from: C, to: D, radius: CGFloat(rBack))
        path.appendArc(from: D, to: A, radius: CGFloat(rBack))
        path.appendArc(from: A, to: B, radius: CGFloat(rTip))
        path.close()
        path.flatness = CGFloat(Double(ProcessInfo.processInfo.environment["BILARD_FLAT"] ?? "") ?? 0.0002)
        let sh = SCNShape(path: path, extrusionDepth: CGFloat(h))
        sh.chamferRadius = 0.0075
        sh.chamferMode = .front
        sh.chamferProfile = roundProfile()
        sh.materials = [mat]       // UV SCNShape = obwiednia 0…1; gęstość splotu ustawia contentsTransform materiału band
        let n = SCNNode(geometry: sh)
        n.eulerAngles.x = -.pi / 2           // y ścieżki → −z (głębokość), wyciągnięcie → y
        n.position.y = CGFloat(h / 2)
        return n
    }

    static func pocketCasting(_ p: Pocket, chrome: SCNMaterial) -> SCNNode {
        let ox = X + railW, oy = Y + railW, rr = 0.09
        let path = NSBezierPath()
        if !p.side {
            let sx = p.c.x > 0 ? 1.0 : -1.0, sy = p.c.y > 0 ? 1.0 : -1.0
            let ax = abs(p.c.x), ay = abs(p.c.y)
            let x0 = ax - 0.13, y0 = ay - 0.13
            let h1 = sqrt(max(0, p.r * p.r - pow(X - ax, 2))), h2 = sqrt(max(0, p.r * p.r - pow(Y - ay, 2)))
            func m(_ q: V2) -> CGPoint { CGPoint(x: q.x * sx, y: q.y * sy) }
            path.move(to: m(V2(x0, Y))); path.line(to: m(V2(x0, oy)))
            addArc(path, c: V2(ox - rr, oy - rr), r: rr, a1: .pi / 2, sweep: -.pi / 2, sx: sx, sy: sy)
            path.line(to: m(V2(ox, y0))); path.line(to: m(V2(X, y0)))
            let v = V2(X, ay - h1), h = V2(ax - h2, Y)
            let (a1, sw) = arcSweep(c: V2(ax, ay), r: p.r, p1: v, p2: h)
            addArc(path, c: V2(ax, ay), r: p.r, a1: a1, sweep: sw, sx: sx, sy: sy)
        } else {
            let sy = p.c.y > 0 ? 1.0 : -1.0, ay = abs(p.c.y), hw = 0.12
            let h3 = sqrt(max(0, p.r * p.r - pow(Y - ay, 2)))
            func m(_ q: V2) -> CGPoint { CGPoint(x: q.x, y: q.y * sy) }
            path.move(to: m(V2(-hw, Y))); path.line(to: m(V2(-hw, oy))); path.line(to: m(V2(hw, oy))); path.line(to: m(V2(hw, Y)))
            let (a1, sw) = arcSweep(c: V2(0, ay), r: p.r, p1: V2(h3, Y), p2: V2(-h3, Y))
            addArc(path, c: V2(0, ay), r: p.r, a1: a1, sweep: sw, sy: sy)
        }
        path.close()
        path.flatness = CGFloat(Double(ProcessInfo.processInfo.environment["BILARD_FLAT"] ?? "") ?? 0.0002)
        let sh = SCNShape(path: path, extrusionDepth: 0.012)
        sh.chamferRadius = 0.0055
        sh.chamferProfile = roundProfile()
        sh.chamferMode = .front
        sh.materials = [chrome]
        let n = SCNNode(geometry: sh)
        n.eulerAngles.x = -.pi / 2
        n.position.y = railTop - 0.002          // spód zagłębiony w ramie, wierzch 1 cm nad nią
        n.name = "casting"
        return n
    }

    static func addDiamond(_ root: SCNNode, _ m: SCNMaterial, x: Double, z: Double) {
        let b = SCNCylinder(radius: 0.0075, height: 0.0016)      // okrągła perłowa kropka
        b.radialSegmentCount = 24
        b.materials = [m]
        let n = SCNNode(geometry: b)
        n.name = "diamond"
        n.position = SCNVector3(x, railTop + 0.0008, z)
        root.addChildNode(n)
    }

    // MARK: Kij bilardowy (początek układu = czubek kija, ciało wzdłuż −Y)
    static func makeCue() -> SCNNode {
        let cue = SCNNode()
        cue.name = "cue"
        func part(_ g: SCNGeometry, _ m: SCNMaterial, _ y: Double) {
            g.materials = [m]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(0, y, 0)
            cue.addChildNode(n)
        }
        let tip = pbr(pack.tip, rough: 0.9, metal: 0)
        tip.normal.contents = pack.tipNormal
        let ferrule = pbr(nsc(0xF4F1E8), rough: 0.3, metal: 0)
        let maple = pbr(pack.mapleAlbedo, rough: 0.28, metal: 0)
        maple.normal.contents = pack.mapleNormal; maple.roughness.contents = pack.mapleRough
        maple.clearCoat.contents = 0.5
        let butt = pbr(pack.buttAlbedo, rough: 0.3, metal: 0)
        butt.normal.contents = pack.buttNormal; butt.roughness.contents = pack.buttRough
        butt.clearCoat.contents = 0.8; butt.clearCoatRoughness.contents = 0.08
        let ring = pbr(pack.brassAlbedo, rough: 0.3, metal: 1)
        ring.roughness.contents = pack.brassRough
        maple.name = "shaft"; butt.name = "butt"; ring.name = "ring"; ferrule.name = "ferrule"
        part(SCNCylinder(radius: 0.0053, height: 0.006), tip, -0.003)
        part(SCNCylinder(radius: 0.0062, height: 0.026), ferrule, -0.019)
        let shaft = SCNCone(topRadius: 0.0062, bottomRadius: 0.0098, height: 0.70)
        part(shaft, maple, -0.032 - 0.35)
        part(SCNCylinder(radius: 0.0101, height: 0.012), ring, -0.734)
        let bt = SCNCone(topRadius: 0.0100, bottomRadius: 0.0170, height: 0.72)
        part(bt, butt, -0.74 - 0.36)
        part(SCNCylinder(radius: 0.0172, height: 0.03), ring, -1.46)
        // ozdobne pierścienie na kolbie (widoczność wg definicji kija)
        let band = pbr(nsc(0xC9A24A), rough: 0.25, metal: 1)
        band.name = "band"
        for i in 0..<5 {
            let y = -0.80 - Double(i) * 0.12
            let r = 0.0100 + (-y - 0.74) / 0.72 * 0.0070 + 0.0004
            let g = SCNCylinder(radius: CGFloat(r), height: i % 2 == 0 ? 0.008 : 0.014)
            g.materials = [band]
            let n = SCNNode(geometry: g)
            n.position = SCNVector3(0, y, 0)
            n.name = "band\(i)"
            cue.addChildNode(n)
        }
        cue.castsShadow = true
        styleCue(cue, Settings.shared.cue)
        return cue
    }

    /// wygląd kija wg definicji (kolory, wykończenie; neon = poświata pierścieni)
    static func styleCue(_ cue: SCNNode, _ def: CueDef) {
        cue.enumerateHierarchy { n, _ in
            if let nn = n.name, nn.hasPrefix("band"), let i = Int(nn.dropFirst(4)) { n.isHidden = i >= def.bands }
            guard let m = n.geometry?.firstMaterial, let nm = m.name else { return }
            switch nm {
            case "shaft":
                if def.id == "maple" { m.diffuse.contents = pack.mapleAlbedo; m.normal.contents = pack.mapleNormal; m.roughness.contents = pack.mapleRough }
                else { m.diffuse.contents = nsc(def.shaft); m.normal.contents = def.id == "carbon" ? nil : pack.mapleNormal; m.roughness.contents = def.id == "carbon" ? 0.16 : 0.3 }
                m.clearCoat.contents = def.id == "carbon" ? 1.0 : 0.5
            case "butt":
                if def.id == "maple" { m.diffuse.contents = pack.buttAlbedo; m.normal.contents = pack.buttNormal; m.roughness.contents = pack.buttRough }
                else { m.diffuse.contents = nsc(def.butt); m.normal.contents = def.id == "carbon" ? nil : pack.buttNormal; m.roughness.contents = def.id == "carbon" ? 0.14 : 0.3 }
                m.emission.contents = def.glow.map { nsc($0) }; m.emission.intensity = def.glow == nil ? 0 : 0.18
            case "band":
                m.diffuse.contents = nsc(def.accent ?? def.ring); m.metalness.contents = def.metalRing ? 1.0 : 0.2; m.roughness.contents = 0.25
                m.emission.contents = def.glow.map { nsc($0) }; m.emission.intensity = def.glow == nil ? 0 : 2.0
            case "ring":
                m.diffuse.contents = nsc(def.ring); m.metalness.contents = def.metalRing ? 1.0 : 0.2; m.roughness.contents = 0.3
                m.emission.contents = def.glow.map { nsc($0) }; m.emission.intensity = def.glow == nil ? 0 : 2.2
            default: break
            }
        }
    }

    // MARK: Mapa otoczenia (IBL)
    static var envIntensity: CGFloat { CGFloat(Double(ProcessInfo.processInfo.environment["BILARD_ENV"] ?? "") ?? 0.35) }
    static var bgIntensity: CGFloat { CGFloat(Double(ProcessInfo.processInfo.environment["BILARD_BG"] ?? "") ?? 0.45) }
    static var envKey = ""
    static func configureEnvironment(_ scene: SCNScene, force: Bool = false) {
        let st = Settings.shared
        let key = "\(st.hdriId)|\(st.hdriBg)|\(st.hdriBlur)|\(st.hdriBright)"
        if !force && key == envKey { return }
        envKey = key
        // mgła w kolorze tła: podłoga rozpuszcza się płynnie w horyzoncie zamiast ostrej krawędzi
        scene.fogColor = nsc(0x15110E)
        scene.fogStartDistance = 5
        scene.fogEndDistance = 20
        scene.fogDensityExponent = 1.0
        if let u = Scans.hdriURL {
            // panorama HDRI (Poly Haven, CC0 lub własna): światło otoczenia, odbicia w bilach i opcjonalnie tło
            scene.lightingEnvironment.contents = u
            scene.lightingEnvironment.intensity = envIntensity * CGFloat(HDRIDef.envMul(id: st.hdriId, url: u))
            if ProcessInfo.processInfo.environment["BILARD_HDRBG"] != nil {
                scene.background.contents = u
                scene.background.intensity = bgIntensity
            } else if st.hdriBg > 0, let (img, fog) = HDRIBackground.make(url: u, blur: st.hdriBg == 1 ? st.hdriBlur : 0, brightness: st.hdriBright) {
                scene.background.contents = img
                scene.background.intensity = 1
                scene.fogColor = fog
            } else {
                // tryb ciemny: tło = ciemna sala w tonacji podłogi, zanikająca w ciemność
                scene.background.contents = makeImage(256, 1024) { ctx in
                    ctx.drawLinearGradient(gradient([rgb(0x15110E), rgb(0x15110E), rgb(0x15110E), rgb(0x15110E)], [0, 0.4, 0.6, 1]),
                                           start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 1024), options: [])
                    // delikatny dithering ±1, żeby nie było widać pasów (banding) w ciemnych tonach
                    var g = SeededGen(s: 77)
                    for y in 0..<1024 { for x in stride(from: 0, to: 256, by: 2) {
                        let v = CGFloat(g.next() % 100) / 100
                        ctx.setFillColor(CGColor(gray: 1, alpha: 0.012 * v)); ctx.fill(CGRect(x: x, y: y, width: 2, height: 1))
                    } }
                }
                scene.background.intensity = 1
            }
        } else {
            scene.lightingEnvironment.contents = pack.env
            scene.lightingEnvironment.intensity = 0.5
            scene.background.contents = nsc(0x0B0A0C)
        }
    }
}

// MARK: - Skany PBR (CC0) z Bilard.app/Contents/Resources/Assets; brak plików = tekstury z TextureFactory
enum Scans {
    static let dir: URL? = Bundle.main.resourceURL?.appendingPathComponent("Assets")
    static var hdriURL: URL? {
        let st = Settings.shared
        if st.hdriId == "custom", let c = HDRIDef.customURL { return c }
        for id in [st.hdriId, "billiard_hall"] {
            if let u = dir?.appendingPathComponent("\(id)/\(id)_2k.hdr"), FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
    static func img(_ rel: String) -> CGImage? {
        guard let u = dir?.appendingPathComponent(rel),
              let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
    /// skala szarości ze średnią jasnością `target` (kolor nadaje potem `multiply`, więc sukno może być zielone lub niebieskie)
    static func detailGray(_ i: CGImage, target: Double, contrast: Double = 1) -> CGImage? {
        let w = i.width, h = i.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let d = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.draw(i, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0.0
        for k in 0..<(w * h) { sum += Double(d[k]) }
        let k = target * 255 / max(1, sum / Double(w * h))
        let mean = target * 255
        // contrast < 1 ściska plamy skanu wokół średniej: kafelki 8/m nie tworzą z daleka szachownicy ani moiré
        for p in 0..<(w * h) { d[p] = UInt8(max(0, min(255, mean + (Double(d[p]) * k - mean) * contrast))) }
        return ctx.makeImage()
    }
    static var applied = false
    static func apply(_ p: TexturePack) -> TexturePack {
        var p = p
        var used: [String] = []
        if let c = img("snooker_cloth/fabrics_0075_color_1k.jpg"), let g = detailGray(c, target: 0.55, contrast: 0.35),
           let n = img("snooker_cloth/cloth_normal.jpg"), let r = img("snooker_cloth/fabrics_0075_roughness_1k.jpg") {
            p.clothDiffuse = g; p.clothNormal = n; p.clothRough = r; used.append("cloth")
        }
        if let a = img("american_walnut_veneer/walnut_diff.jpg"), let n = img("american_walnut_veneer/walnut_nor_gl.jpg"),
           let r = img("american_walnut_veneer/walnut_rough.jpg") {
            p.woodAlbedo = a; p.woodNormal = n; p.woodRough = r; used.append("walnut")
        }
        if let a = img("brown_leather/leather_albedo.jpg"), let n = img("brown_leather/leather_nor_gl.jpg") {
            p.leatherAlbedo = a; p.leatherNormal = n; used.append("leather")
        }
        applied = !used.isEmpty
        print("SCANS used: \(used) hdri=\(hdriURL != nil)")
        return p
    }
}
