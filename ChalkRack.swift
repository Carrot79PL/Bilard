import SceneKit
import AppKit
import simd

/// Stan kostki kredy i trójkąta (układanie bil). Węzły żyją w `rig`, więc przeżywają przebudowę stołu.
final class ChalkRackState {
    var level: [Double] = [1, 1]          // kreda na kiju każdego gracza
    var cube: SCNNode?
    var puff: SCNParticleSystem?
    var chalkT = -1.0                      // <0: nieaktywne
    var pose0: (tip: V3, d: V3) = (V3(0, 0, 0), V3(1, 0, 0))
    var chalkRefilled = false
    var cubeRest = SIMD3<Float>(0, 0, 0)
    var cubeRestYaw: Float = 0.45
    var tri: SCNNode?
    var rackT = -1.0
    var rackIDs: [Int] = []
    var rackDelay: [Int: Double] = [:]
    var rackApex = V2(0, 0)
    var busy: Bool { chalkT >= 0 || rackT >= 0 }
}

extension GameSceneController {
    static let chalkDur = 2.2
    static let rackDrop = 0.5, rackStep = 0.07, rackFall = 0.32, rackPause = 0.3, rackLift = 0.7

    // MARK: Kostka kredy

    func placeChalkCube() {
        if fx.cube == nil {
            let root = SCNNode()
            let blue = SCNMaterial()
            blue.lightingModel = .physicallyBased
            blue.diffuse.contents = NSColor(red: 0.16, green: 0.36, blue: 0.78, alpha: 1)
            blue.roughness.contents = 0.95; blue.metalness.contents = 0.0
            let box = SCNBox(width: 0.034, height: 0.032, length: 0.034, chamferRadius: 0.0035)
            box.materials = [blue]
            let body = SCNNode(geometry: box)
            root.addChildNode(body)
            let dust = SCNMaterial()
            dust.lightingModel = .physicallyBased
            dust.diffuse.contents = NSColor(red: 0.55, green: 0.74, blue: 1.0, alpha: 1)
            dust.roughness.contents = 1.0
            let cup = SCNCylinder(radius: 0.0125, height: 0.0016)
            cup.materials = [dust]
            let cn = SCNNode(geometry: cup)
            cn.position = SCNVector3(0, 0.0162, 0)
            root.addChildNode(cn)
            let ps = SCNParticleSystem()
            ps.birthRate = 0
            ps.particleLifeSpan = 0.9; ps.particleLifeSpanVariation = 0.4
            ps.emitterShape = SCNCylinder(radius: 0.009, height: 0.002)
            ps.birthLocation = .surface
            ps.particleVelocity = 0.035; ps.particleVelocityVariation = 0.02
            ps.spreadingAngle = 40
            ps.emittingDirection = SCNVector3(0, 1, 0)
            ps.particleImage = TableBuilder.pack.dot
            ps.particleSize = 0.0032; ps.particleSizeVariation = 0.0015
            ps.particleColor = NSColor(red: 0.7, green: 0.85, blue: 1, alpha: 0.35)
            ps.blendMode = .additive
            ps.isLightingEnabled = false
            cn.addParticleSystem(ps)
            fx.puff = ps
            root.castsShadow = true
            rig.addChildNode(root)
            fx.cube = root
        }
        // na drewnianej ramie, po stronie gracza, z boku od osi kamery
        let onModel = Phys.modelTable && !Phys.snooker
        // model stołu: rama kończy się ok. 10,5 cm za polem gry, górna powierzchnia ok. 4 cm nad suknem
        let z = onModel ? Phys.halfW + 0.080 : TableBuilder.Y + TableBuilder.railW * 0.55
        let top = onModel ? 0.0405 : TableBuilder.railTop
        fx.cube?.position = SCNVector3(-0.30 * Phys.halfL, top + 0.0160, z)
        fx.cube?.eulerAngles = SCNVector3(0, 0.45, 0)
        fx.cubeRest = fx.cube?.simdPosition ?? SIMD3<Float>(0, 0, 0)
        if env["BILARD_RAILDBG"] != nil, let m = table.root.childNode(withName: "tableModel", recursively: false) {
            let (a, b) = m.boundingBox
            print("RAILDBG scale", m.scale, "pos", m.position, "bbox", a, b, "halfL", Phys.halfL, "halfW", Phys.halfW)
            // profil wysokości wzdłuż z (przekrój przy x = -0.3 halfL): promienie w dół
            let x = Float(-0.30 * Phys.halfL)
            for zz in stride(from: Float(Phys.halfW), through: Float(Phys.halfW) + 0.40, by: 0.02) {
                let hit = rig.hitTestWithSegment(from: SCNVector3(x, 1.0, zz), to: SCNVector3(x, -0.5, zz), options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.closest.rawValue])
                print("RAILDBG z", zz, "y", hit.first.map { String(format: "%.4f", $0.worldCoordinates.y) } ?? "-")
            }
        }
    }

    /// punkt czubka kija na kostce (środek proszku)
    var chalkTop: V3 {
        let p = fx.cube?.simdPosition ?? SIMD3<Float>(0, 0, 0)
        return V3(Double(p.x), Double(p.y) + 0.0172, Double(p.z))
    }

    func startChalking() {
        guard !autoplay, phase == .aiming, !fx.busy, fx.cube != nil, !model.paused else { return }
        let g = cueGeometry()
        fx.pose0 = (g.tip - g.travel * 0.05, g.travel)
        fx.chalkT = 0; fx.chalkRefilled = false
        model.chalking = true
        setLinesVisible(false); aimInd.hide()
    }

    func updateChalking(_ dt: Double) {
        guard fx.chalkT >= 0 else { return }
        fx.chalkT += dt
        let t = fx.chalkT, T = Self.chalkDur
        // faza nacierania: 0.6 … 1.6 s
        let rub = t > 0.5 && t < 1.65
        fx.puff?.birthRate = rub ? 70 : 0
        if rub {
            let k = (t - 0.6) / 1.0
            let cur = fx.level[rules.current]
            fx.level[rules.current] = cur + (1 - cur) * min(1, dt * 3.2)
            _ = k
        }
        updateChalkCube()
        if t >= T {
            fx.level[rules.current] = 1
            fx.chalkT = -1; model.chalking = false
            placeChalkCube()
            fx.puff?.birthRate = 0
        }
        model.chalk = fx.level[rules.current]
    }

    /// nacieranie: kij zostaje w ręku przy celowaniu, kostka podlatuje z ramy do czubka, jest nim pocierana i wraca
    func chalkPose() -> (tip: V3, d: V3) {
        let t = fx.chalkT, p0 = fx.pose0
        // kij lekko się unosi i drży w rytm tarcia
        let rub = t > 0.5 && t < 1.65
        let w = (t - 0.5) * 16
        let lift = rub ? 0.004 : 0
        return (p0.tip + V3(0, lift, 0), p0.d)
    }

    func updateChalkCube() {
        guard fx.chalkT >= 0, let cube = fx.cube else { return }
        let t = fx.chalkT, p0 = fx.pose0
        func ease(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        let d = simd_normalize(V3(p0.d.x, 0, p0.d.z))
        let side = V3(-d.z, 0, d.x)
        // punkt zetknięcia: tuż nad czubkiem, kostka trzymana od góry
        let tip = p0.tip + V3(0, 0.004, 0)
        let hold = tip + V3(0, 0.0053 + 0.0165, 0)
        let rest = V3(Double(fx.cubeRest.x), Double(fx.cubeRest.y), Double(fx.cubeRest.z))
        var pos = hold, yaw = atan2(-d.z, d.x), roll = 0.0
        if t < 0.5 {
            let k = ease(t / 0.5)
            pos = rest + (hold - rest) * k + V3(0, 0.10 * sin(.pi * k), 0)
            yaw = Double(fx.cubeRestYaw) + (atan2(-d.z, d.x) - Double(fx.cubeRestYaw)) * k
        } else if t < 1.65 {
            let w = (t - 0.5) * 17
            pos = hold + d * (0.007 * sin(w)) + side * (0.004 * cos(w * 0.5)) + V3(0, 0.0012 * sin(w * 2), 0)
            roll = 0.25 * sin(w * 0.5)
        } else {
            let k = ease((t - 1.65) / (Self.chalkDur - 1.65))
            pos = hold + (rest - hold) * k + V3(0, 0.10 * sin(.pi * k), 0)
            yaw = atan2(-d.z, d.x) + (Double(fx.cubeRestYaw) - atan2(-d.z, d.x)) * k
        }
        cube.simdPosition = SIMD3<Float>(Float(pos.x), Float(pos.y), Float(pos.z))
        cube.eulerAngles = SCNVector3(CGFloat(roll), CGFloat(yaw), 0)
    }

    /// koszt kredy za uderzenie i ewentualny kiks; zwraca (aim, off, power, kiks)
    func chalkStrike(aim: V2, off: V2, power: Double) -> (V2, V2, Double, Bool) {
        guard !autoplay else { return (aim, off, power, false) }
        let who = rules.current
        let lvl = fx.level[who]
        fx.level[who] = max(0, lvl - (0.06 + 0.07 * min(1, simd_length(off)) + 0.05 * power))
        model.chalk = fx.level[who]
        guard lvl < 0.35 else { return (aim, off, power, false) }
        let risk = (0.35 - lvl) / 0.35
        let side = min(1, simd_length(off) / 0.7)
        let p = risk * (0.15 + 0.85 * side)
        guard Double.random(in: 0..<1) < p else { return (aim, off, power, false) }
        // kiks: czubek ślizga się po bili – kierunek odchylony, siła osłabiona, efekt prawie znika
        let a = (Double.random(in: 0.05...0.13)) * (Bool.random() ? 1 : -1)
        let c = cos(a), s = sin(a)
        return (V2(aim.x * c - aim.y * s, aim.x * s + aim.y * c), off * 0.35, power * Double.random(in: 0.55...0.85), true)
    }

    // MARK: Trójkąt i układanie bil

    private func hull(_ pts: [V2]) -> [V2] {
        let s = pts.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        guard s.count > 2 else { return s }
        func cross(_ o: V2, _ a: V2, _ b: V2) -> Double { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lo: [V2] = [], up: [V2] = []
        for p in s { while lo.count >= 2 && cross(lo[lo.count - 2], lo[lo.count - 1], p) <= 1e-9 { lo.removeLast() }; lo.append(p) }
        for p in s.reversed() { while up.count >= 2 && cross(up[up.count - 2], up[up.count - 1], p) <= 1e-9 { up.removeLast() }; up.append(p) }
        lo.removeLast(); up.removeLast()
        return lo + up        // przeciwnie do ruchu wskazówek (x w prawo, y w górę)
    }

    /// bile tworzące zwarty zestaw (łączą się stykając): największa składowa, bez białej
    private func rackCluster() -> [Int] {
        let ids = (1..<Phys.nBalls).filter { physics.balls[$0].active }
        let thr = 2 * Phys.R + 0.0016
        var seen = Set<Int>(), best: [Int] = []
        for s in ids where !seen.contains(s) {
            var comp = [s], stack = [s]; seen.insert(s)
            while let c = stack.popLast() {
                for o in ids where !seen.contains(o) && simd_length(physics.balls[o].p - physics.balls[c].p) < thr {
                    seen.insert(o); comp.append(o); stack.append(o)
                }
            }
            if comp.count > best.count { best = comp }
        }
        return best.count >= 3 ? best : []
    }

    private func buildTriangle(_ pts: [V2]) -> SCNNode {
        let h = hull(pts)
        let root = SCNNode()
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        mat.diffuse.contents = NSColor(red: 0.03, green: 0.03, blue: 0.035, alpha: 1)
        mat.roughness.contents = 0.5; mat.metalness.contents = 0.0
        mat.clearCoat.contents = 0.25; mat.clearCoatRoughness.contents = 0.3
        let thick = 0.022, height = 0.030
        let dc = Phys.R + 0.0018 + thick / 2
        let n = h.count
        func seg(_ a: V2, _ b: V2) {         // belka od a do b (środek taśmy)
            let len = simd_length(b - a)
            guard len > 1e-5 else { return }
            let e = (b - a) / len
            let box = SCNBox(width: CGFloat(len + 0.0006), height: CGFloat(height), length: CGFloat(thick), chamferRadius: 0.006)
            box.chamferSegmentCount = 3
            box.materials = [mat]
            let bn = SCNNode(geometry: box)
            let m = (a + b) / 2
            bn.position = SCNVector3(m.x, height / 2, m.y)
            bn.eulerAngles.y = CGFloat(atan2(-e.y, e.x))
            bn.castsShadow = true
            root.addChildNode(bn)
        }
        for i in 0..<n {
            let a = h[i], b = h[(i + 1) % n], c = h[(i + 2) % n]
            let e = simd_normalize(b - a), eN = simd_normalize(c - b)
            let n1 = V2(e.y, -e.x), n2 = V2(eN.y, -eN.x)
            seg(a + n1 * dc, b + n1 * dc)                      // prosty bok
            // zaokrąglony narożnik: łuk o promieniu dc wokół bili w narożniku b
            let a1 = atan2(n1.y, n1.x)
            var d = atan2(n2.y, n2.x) - a1
            while d < 0 { d += 2 * .pi }
            while d > .pi { d -= 2 * .pi }
            let steps = max(2, Int(ceil(abs(d) / 0.22)))
            var prev = b + n1 * dc
            for k in 1...steps {
                let ang = a1 + d * Double(k) / Double(steps)
                let pt = b + V2(cos(ang), sin(ang)) * dc
                seg(prev, pt); prev = pt
            }
        }
        return root
    }

    func startRackAnimation() {
        guard !autoplay, env["BILARD_NORACK"] == nil else { return }
        let ids = rackCluster()
        guard !ids.isEmpty else { return }
        fx.tri?.removeFromParentNode()
        let pts = ids.map { physics.balls[$0].p }
        let tri = buildTriangle(pts)
        tri.opacity = 1
        rig.addChildNode(tri)
        fx.tri = tri
        // kolejność: od wierzchołka (najbliżej środka stołu po stronie wierzchołka) ku podstawie
        let apex = pts.min { simd_length($0 - V2(0, 0)) < simd_length($1 - V2(0, 0)) } ?? V2(0, 0)
        let order = ids.sorted { simd_length(physics.balls[$0].p - apex) < simd_length(physics.balls[$1].p - apex) }
        fx.rackDelay = [:]
        for (k, id) in order.enumerated() { fx.rackDelay[id] = Self.rackDrop + Double(k) * Self.rackStep }
        fx.rackIDs = ids
        fx.rackT = 0
        updateRackAnimation(0)
    }

    var rackTotal: Double {
        Self.rackDrop + Double(max(0, fx.rackIDs.count - 1)) * Self.rackStep + Self.rackFall + Self.rackPause + Self.rackLift
    }

    func updateRackAnimation(_ dt: Double) {
        guard fx.rackT >= 0, let tri = fx.tri else { return }
        fx.rackT += dt
        let t = fx.rackT
        let ballsDone = Self.rackDrop + Double(max(0, fx.rackIDs.count - 1)) * Self.rackStep + Self.rackFall + Self.rackPause
        // trójkąt opada na stół
        let dk = min(1, t / Self.rackDrop)
        var y = 0.30 * (1 - dk * dk)
        var op = 1.0
        var sc = 1.0
        if t > ballsDone {
            let k = min(1, (t - ballsDone) / Self.rackLift)
            y = 0.55 * k * k
            op = 1 - k
            sc = 1 + 0.05 * k
        }
        tri.position = SCNVector3(0, y, 0)
        tri.opacity = CGFloat(op)
        tri.scale = SCNVector3(sc, sc, sc)
        if t >= rackTotal {
            tri.removeFromParentNode(); fx.tri = nil
            fx.rackT = -1; fx.rackIDs = []; fx.rackDelay = [:]
            syncNodes()
        }
    }

    /// wizualne przesunięcie bili podczas układania (wołane z syncNodes po ustawieniu pozycji); true = bila ukryta
    func rackBallOffset(_ i: Int, _ n: SCNNode) {
        guard fx.rackT >= 0, let d = fx.rackDelay[i] else { return }
        let k = (fx.rackT - d) / Self.rackFall
        if k < 0 { n.isHidden = true; return }
        n.isHidden = false
        if k < 1 {
            n.simdPosition.y += Float(0.28 * (1 - k * k))
        }
    }
}
