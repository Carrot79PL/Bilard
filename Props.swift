import Cocoa
import SceneKit
import Metal

// MARK: - Dodatki na brzegu stołu (rekwizyty): popielniczka z dymiącym papierosem

enum Props {
    /// bryła obrotowa z profilu (r, y): gładkie normalne, UV (u = kąt, v = wzdłuż profilu)
    static func lathe(_ profile: [CGPoint], segments: Int = 96) -> SCNGeometry {
        var v: [SCNVector3] = [], n: [SCNVector3] = [], uv: [CGPoint] = [], idx: [Int32] = []
        let m = profile.count
        // długości łuku profilu (dla v)
        var acc: [CGFloat] = [0]
        for i in 1..<m { acc.append(acc[i - 1] + hypot(profile[i].x - profile[i - 1].x, profile[i].y - profile[i - 1].y)) }
        let total = max(acc.last ?? 1, 1e-6)
        for s in 0...segments {
            let a = Double(s) / Double(segments) * 2 * .pi, ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
            for i in 0..<m {
                let p = profile[i]
                v.append(SCNVector3(p.x * ca, p.y, p.x * sa))
                // styczna profilu -> normalna (w płaszczyźnie r-y, obrócona na zewnątrz)
                let p0 = profile[max(0, i - 1)], p1 = profile[min(m - 1, i + 1)]
                var tr = p1.x - p0.x, ty = p1.y - p0.y
                let l = max(hypot(tr, ty), 1e-9); tr /= l; ty /= l
                let nr = ty, ny = -tr                     // obrót o −90°: na zewnątrz przy profilu idącym „w górę”
                n.append(SCNVector3(nr * ca, ny, nr * sa))
                uv.append(CGPoint(x: CGFloat(s) / CGFloat(segments), y: acc[i] / total))
            }
        }
        for s in 0..<segments {
            for i in 0..<(m - 1) {
                let a = Int32(s * m + i), b = Int32((s + 1) * m + i), c = Int32((s + 1) * m + i + 1), d = Int32(s * m + i + 1)
                idx += [a, d, c, a, c, b]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n), SCNGeometrySource(textureCoordinates: uv)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        return g
    }

    static func pbr(_ c: NSColor, rough: CGFloat, metal: CGFloat = 0, coat: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = c; m.roughness.contents = rough; m.metalness.contents = metal
        if coat > 0 { m.clearCoat.contents = coat; m.clearCoatRoughness.contents = 0.04 }
        m.isDoubleSided = false
        return m
    }

    /// miękka plamka do dymu
    static let puff: NSImage = {
        let n = 128
        let cg = makeImage(n, n) { ctx in
            ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, 1), rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0.16), rgb(0xFFFFFF, 0)], [0, 0.35, 0.7, 1]),
                                   startCenter: CGPoint(x: n / 2, y: n / 2), startRadius: 0, endCenter: CGPoint(x: n / 2, y: n / 2), endRadius: CGFloat(n / 2), options: [])
        }
        return NSImage(cgImage: cg, size: NSSize(width: n, height: n))
    }()

    // MARK: Popielniczka (średnica ok. 10 cm, wys. 3 cm; początek układu: środek podstawy)
    static func ashtray() -> SCNNode {
        let root = SCNNode(); root.name = "ashtray"
        // ciężka, ciemna popielniczka szklana: gruba ścianka, rant, wklęsłe dno
        let outer: [CGPoint] = [
            CGPoint(x: 0.000, y: 0.0000), CGPoint(x: 0.036, y: 0.0000), CGPoint(x: 0.0435, y: 0.0012), CGPoint(x: 0.0475, y: 0.0045),
            CGPoint(x: 0.0500, y: 0.0110), CGPoint(x: 0.0525, y: 0.0200), CGPoint(x: 0.0545, y: 0.0268), CGPoint(x: 0.0545, y: 0.0290),
            CGPoint(x: 0.0530, y: 0.0305), CGPoint(x: 0.0505, y: 0.0305), CGPoint(x: 0.0488, y: 0.0290),   // rant (zaokrąglony)
            CGPoint(x: 0.0478, y: 0.0262), CGPoint(x: 0.0440, y: 0.0170), CGPoint(x: 0.0385, y: 0.0115), CGPoint(x: 0.0300, y: 0.0090),
            CGPoint(x: 0.0180, y: 0.0080), CGPoint(x: 0.0000, y: 0.0078)]
        let body = SCNNode(geometry: lathe(outer))
        body.geometry?.materials = [pbr(nsc(0xC8A04C), rough: 0.24, metal: 1.0)]   // polerowany mosiądz
        root.addChildNode(body)
        // popiół: nieregularny kopczyk + drobne grudki
        var rng = SeededGen(s: 0xA5F1)
        func r01() -> CGFloat { CGFloat(Double(rng.next() % 10000) / 10000) }
        let ashMat = pbr(nsc(0x8D8A85), rough: 1.0)
        let mound = SCNSphere(radius: 0.020); mound.segmentCount = 28; mound.firstMaterial = ashMat
        let mn = SCNNode(geometry: mound); mn.scale = SCNVector3(1.05, 0.30, 0.95); mn.position = SCNVector3(-0.012, 0.0085, 0.006)
        root.addChildNode(mn)
        for _ in 0..<26 {
            let s = SCNSphere(radius: 0.0016 + 0.0026 * r01()); s.segmentCount = 8
            s.firstMaterial = pbr(nsc(UInt32(0x6E6A66 + Int(r01() * 40) * 0x010101)), rough: 1.0)
            let nd = SCNNode(geometry: s); let a = Double(r01()) * 2 * .pi, rr = 0.026 * Double(r01()).squareRoot()
            nd.position = SCNVector3(-0.012 + CGFloat(cos(a) * rr), 0.0095 + 0.002 * r01(), 0.006 + CGFloat(sin(a) * rr)); nd.scale = SCNVector3(1.3, 0.55, 1.1)
            root.addChildNode(nd)
        }
        // dwa niedopałki w popiele
        for (i, (x, z, yaw)) in [(-0.020, -0.017, 0.7), (0.004, 0.026, -0.5)].enumerated() {
            let b = butt(length: i == 0 ? 0.019 : 0.014)
            b.position = SCNVector3(x, 0.0105, z); b.eulerAngles = SCNVector3(0.0, CGFloat(yaw), CGFloat(i == 0 ? 0.25 : -0.18)); root.addChildNode(b)
        }
        // palący się papieros oparty o rant
        let cig = cigarette()
        cig.position = SCNVector3(0.023, 0.0246, -0.002)
        cig.eulerAngles = SCNVector3(0, 0.34, 0.2215)          // koniec żarzący w misie, filtr na rancie
        root.addChildNode(cig)
        // dym z żaru
        let tip = SCNNode(); tip.position = cig.convertPosition(SCNVector3(-0.0545, 0.0, 0), to: root)
        tip.addChildNode(smoke())
        root.addChildNode(tip)
        return root
    }

    /// niedopałek: filtr (jasnopomarańczowy) + wypalony, zgnieciony koniec
    static func butt(length: CGFloat) -> SCNNode {
        let n = SCNNode()
        let f = SCNCylinder(radius: 0.0036, height: length); f.radialSegmentCount = 20
        f.firstMaterial = pbr(nsc(0xD39A55), rough: 0.85)
        let fn = SCNNode(geometry: f); fn.eulerAngles.z = .pi / 2; n.addChildNode(fn)
        let c = SCNCylinder(radius: 0.0033, height: 0.004); c.radialSegmentCount = 14
        c.firstMaterial = pbr(nsc(0x23201D), rough: 1.0)
        let cn = SCNNode(geometry: c); cn.eulerAngles.z = .pi / 2; cn.position = SCNVector3(-length / 2 - 0.0016, 0, 0); n.addChildNode(cn)
        return n
    }

    /// papieros: biały papier, pomarańczowy filtr z cienkim paskiem, żar i szary popiół na końcu (oś x; filtr w +x)
    static func cigarette() -> SCNNode {
        let n = SCNNode(); n.name = "cigarette"
        let L: CGFloat = 0.108, fl: CGFloat = 0.030, r: CGFloat = 0.0050
        let paper = SCNCylinder(radius: r, height: L - fl - 0.010); paper.radialSegmentCount = 24
        paper.firstMaterial = pbr(nsc(0xF4F1EA), rough: 0.78)
        let pn = SCNNode(geometry: paper); pn.eulerAngles.z = .pi / 2
        // oś: x = −L/2 (żar) … +L/2 (filtr)
        pn.position = SCNVector3(-L / 2 + 0.010 + (L - fl - 0.010) / 2, 0, 0)
        n.addChildNode(pn)
        let fil = SCNCylinder(radius: r * 1.005, height: fl); fil.radialSegmentCount = 24
        fil.firstMaterial = pbr(nsc(0xD9A05A), rough: 0.82)
        let fn = SCNNode(geometry: fil); fn.eulerAngles.z = .pi / 2; fn.position = SCNVector3(L / 2 - fl / 2, 0, 0); n.addChildNode(fn)
        let band = SCNCylinder(radius: r * 1.012, height: 0.0016); band.radialSegmentCount = 24
        band.firstMaterial = pbr(nsc(0xB07A3C), rough: 0.7)
        let bn = SCNNode(geometry: band); bn.eulerAngles.z = .pi / 2; bn.position = SCNVector3(L / 2 - fl - 0.0008, 0, 0); n.addChildNode(bn)
        // popiół na końcu (szary, lekko nierówny) i żar
        let ash = SCNCylinder(radius: r * 0.98, height: 0.0074); ash.radialSegmentCount = 18
        ash.firstMaterial = pbr(nsc(0x9C9893), rough: 1.0)
        let an = SCNNode(geometry: ash); an.eulerAngles.z = .pi / 2; an.position = SCNVector3(-L / 2 + 0.0063, 0, 0); n.addChildNode(an)
        let ember = SCNCylinder(radius: r * 0.82, height: 0.0035); ember.radialSegmentCount = 16
        let em = SCNMaterial(); em.lightingModel = .constant
        em.diffuse.contents = nsc(0xFF5A10); em.emission.contents = nsc(0xFF6A18); em.emission.intensity = 1.6
        ember.firstMaterial = em
        let en = SCNNode(geometry: ember); en.eulerAngles.z = .pi / 2; en.position = SCNVector3(-L / 2 + 0.0009, 0, 0); n.addChildNode(en)
        // żar lekko pulsuje
        en.runAction(.repeatForever(.sequence([.customAction(duration: 1.8) { _, t in
            em.emission.intensity = 1.35 + 0.35 * CGFloat(sin(Double(t) / 1.8 * 2 * .pi))
        }])))
        return n
    }

    /// cienka smużka dymu unosząca się z żaru: wiele półprzezroczystych, rosnących kłębków, kołysanych wspólną falą
    static func smoke() -> SCNNode {
        let ps = SCNParticleSystem()
        ps.particleImage = puff
        ps.birthRate = 26; ps.loops = true; ps.emissionDuration = 1
        ps.particleLifeSpan = 4.2; ps.particleLifeSpanVariation = 0.8
        ps.particleVelocity = 0.046; ps.particleVelocityVariation = 0.008
        ps.emitterShape = SCNSphere(radius: 0.0012)
        ps.spreadingAngle = 4
        ps.acceleration = SCNVector3(0, 0.004, 0)
        ps.particleSize = 0.0042; ps.particleSizeVariation = 0.001
        ps.particleColor = NSColor(white: 0.93, alpha: 0.55)
        ps.blendMode = .alpha; ps.isLightingEnabled = false; ps.isAffectedByGravity = false; ps.isAffectedByPhysicsFields = false
        ps.particleAngleVariation = 180; ps.particleAngularVelocity = 0.3; ps.particleAngularVelocityVariation = 0.6
        ps.sortingMode = .distance
        // rośnie i zanika
        let size = CAKeyframeAnimation(); size.values = [0.35, 0.8, 1.7, 3.2]; size.keyTimes = [0, 0.25, 0.6, 1.0]; size.duration = 1
        ps.propertyControllers = [.size: SCNParticlePropertyController(animation: size)]
        let op = CAKeyframeAnimation(); op.values = [0.0, 0.10, 0.06, 0.0]; op.keyTimes = [0, 0.08, 0.55, 1.0]; op.duration = 1
        ps.propertyControllers?[.opacity] = SCNParticlePropertyController(animation: op)
        let n = SCNNode(); n.addParticleSystem(ps)
        // emiter lekko „wije się” (suma dwóch fal), a nieprzypięte do emitera cząstki układają się w smużkę
        n.runAction(.repeatForever(.customAction(duration: 60) { node, t in
            let k = Double(t)
            node.position = SCNVector3(0.0045 * sin(k * 4.6) + 0.0022 * sin(k * 9.3 + 1.0), 0, 0.0035 * cos(k * 3.9 + 0.6) + 0.0018 * sin(k * 8.1))
        }))
        return n
    }

    // MARK: Ustawienie na ramie stołu

    /// Stawia rekwizyty na wierzchu ramy dłuższej strony stołu, w losowym miejscu (z dala od łuz i narożników).
    /// Wymiary ramy bierzemy z modelu 3D stołu (bbox po skali) albo z parametrów stołu proceduralnego.
    static func place(on root: SCNNode, seed: UInt64) -> SCNNode {
        let group = SCNNode(); group.name = "props"
        var rng = SeededGen(s: seed)
        func r01() -> Double { Double(rng.next() % 100000) / 100000 }
        var top = Double(TableBuilder.railTop), outer = Phys.halfW + TableBuilder.railIn + TableBuilder.railW
        if let tm = root.childNode(withName: "tableModel", recursively: false) {
            let (mn, mx) = tm.boundingBox
            let a = tm.convertPosition(mn, to: root), b = tm.convertPosition(mx, to: root)
            top = Double(max(a.y, b.y)); outer = Double(max(abs(a.z), abs(b.z)))
        }
        let inner = Phys.halfW + TableBuilder.railIn
        let width = outer - inner
        guard width > 0.03 else { return group }
        var side: Double = r01() < 0.5 ? -1 : 1
        var x = (r01() * 2 - 1) * (Phys.halfL * 0.62)
        if abs(x) < 0.30 { x = x < 0 ? x - 0.30 : x + 0.30 }
        if let pp = ProcessInfo.processInfo.environment["BILARD_PROPPOS"]?.split(separator: ",").compactMap({ Double($0) }), pp.count == 2 { x = pp[0]; side = pp[1] }   // test: stałe miejsce
        let a = ashtray()
        let sc = 0.74                                     // popielniczka (⌀ 8 cm): zewnętrzny brzeg równo z krawędzią ramy, wewnętrzny nad płaską górą bandy
        a.scale = SCNVector3(sc, sc, sc)
        a.position = SCNVector3(x, top, side * (outer - 0.0545 * Double(sc) - 0.002))
        a.eulerAngles.y = CGFloat(r01() * 2 * .pi)
        group.addChildNode(a)
        if ProcessInfo.processInfo.environment["BILARD_PROPDBG"] != nil {
            print(String(format: "PROPS top=%.4f outer=%.3f width=%.3f scale=%.2f x=%.2f", top, outer, width, sc, x))
        }
        return group
    }
}

// MARK: - Test: render samej popielniczki do pliku PNG (BILARD_PROPSHOT=<plik.png>), bez okna gry

enum PropShot {
    static func run(path: String) {
        guard let dev = MTLCreateSystemDefaultDevice() else { return }
        let env = ProcessInfo.processInfo.environment
        let sc = SCNScene(); sc.background.contents = nsc(0x16191F)
        if let u = Scans.hdriURL { sc.lightingEnvironment.contents = u; sc.lightingEnvironment.intensity = 0.55 }
        // drewniana rama pod spodem (fragment)
        let wood = SCNBox(width: 0.5, height: 0.04, length: 0.3, chamferRadius: 0.004)
        let wm = SCNMaterial(); wm.lightingModel = .physicallyBased; wm.diffuse.contents = nsc(0x120D0A); wm.roughness.contents = 0.28; wm.clearCoat.contents = 0.8
        wood.materials = [wm]
        let wn = SCNNode(geometry: wood); wn.position = SCNVector3(0, -0.02, 0); sc.rootNode.addChildNode(wn)
        let a = Props.ashtray(); sc.rootNode.addChildNode(a)
        let cam = SCNCamera(); cam.fieldOfView = 26; cam.zNear = 0.02; cam.wantsHDR = true; cam.bloomIntensity = 0.25; cam.bloomThreshold = 0.9
        let cn = SCNNode(); cn.camera = cam
        let ang = Double(env["BILARD_PROPANG"] ?? "") ?? 35, el = Double(env["BILARD_PROPEL"] ?? "") ?? 32, d = Double(env["BILARD_PROPDIST"] ?? "") ?? 0.36
        cn.position = SCNVector3(d * cos(el * .pi / 180) * sin(ang * .pi / 180), d * sin(el * .pi / 180) + 0.02, d * cos(el * .pi / 180) * cos(ang * .pi / 180))
        let tgt = SCNNode(); tgt.position = SCNVector3(0, CGFloat(Double(env["BILARD_PROPTY"] ?? "") ?? 0.02), 0); sc.rootNode.addChildNode(tgt)
        cn.constraints = [SCNLookAtConstraint(target: tgt)]; sc.rootNode.addChildNode(cn)
        let key = SCNLight(); key.type = .spot; key.intensity = 1800; key.spotOuterAngle = 70; key.castsShadow = true; key.shadowRadius = 4
        let kn = SCNNode(); kn.light = key; kn.position = SCNVector3(-0.5, 0.9, 0.5); kn.constraints = [SCNLookAtConstraint(target: tgt)]; sc.rootNode.addChildNode(kn)
        let fill = SCNLight(); fill.type = .omni; fill.intensity = 200; fill.color = nsc(0x7AA8FF)
        let fnode = SCNNode(); fnode.light = fill; fnode.position = SCNVector3(0.6, 0.4, 0.4); sc.rootNode.addChildNode(fnode)
        let r = SCNRenderer(device: dev, options: nil); r.scene = sc; r.pointOfView = cn; r.autoenablesDefaultLighting = false
        let size = CGSize(width: 1400, height: 1000)
        var t = 0.0
        while t < 9.0 { _ = r.snapshot(atTime: t, with: CGSize(width: 64, height: 64), antialiasingMode: .none); t += 1.0 / 30 }
        let img = r.snapshot(atTime: t, with: size, antialiasingMode: .multisampling4X)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        print("PROPSHOT saved \(path)")
    }
}
