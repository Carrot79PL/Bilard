import Cocoa
import SceneKit
import SpriteKit

// MARK: - Intro studia w 3D: czarna ósemka toczy się po lśniącej podłodze, a w jej białym polu „8” zamienia się w znak BLUEROOT

final class Intro3DView: SCNView {
    var onDone: (() -> Void)?
    var finished = false
    static let duration = 7.8
    var frontU: CGFloat = CGFloat(Double(ProcessInfo.processInfo.environment["BILARD_INTRO3D_U"] ?? "") ?? 0.5)            // pozycja poziomo w teksturze, która trafia na przód bili (skalibrowana)

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with e: NSEvent) { finish() }
    override func keyDown(with e: NSEvent) { finish() }
    func finish() {
        guard !finished else { return }
        finished = true
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.6; self.animator().alphaValue = 0 }) { [weak self] in
            self?.removeFromSuperview()
            self?.onDone?()
        }
    }

    // MARK: Tekstury bili (równoprostokątne 2:1, pole na przodzie)
    static let TW = 2048, TH = 1024
    /// u – środek pola w teksturze (0…1), mode: 0 = ósemka, 1 = znak studia (przezroczyste tło)
    static func ballTexture(u: CGFloat, mode: Int) -> CGImage {
        makeImage(TW, TH) { ctx in
            if mode == 0 { ctx.setFillColor(rgb(0x0B0B0D)); ctx.fill(CGRect(x: 0, y: 0, width: TW, height: TH)) }
            else { ctx.clear(CGRect(x: 0, y: 0, width: TW, height: TH)) }
            let c = CGPoint(x: CGFloat(TW) * u, y: CGFloat(TH) / 2), R: CGFloat = 190
            for dx in [-CGFloat(TW), 0, CGFloat(TW)] {      // szew tekstury
                let cc = CGPoint(x: c.x + dx, y: c.y)
                if mode == 0 { ctx.setFillColor(rgb(0xE4E1D8)); ctx.fillEllipse(in: CGRect(x: cc.x - R, y: cc.y - R, width: 2 * R, height: 2 * R)) }
                if mode == 2 {
                    let f = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, R * 1.25, nil)
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "8", attributes: [.font: f, .foregroundColor: NSColor(white: 0.04, alpha: 1)]))
                    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                    ctx.textPosition = CGPoint(x: cc.x - b.midX, y: cc.y - b.midY); CTLineDraw(line, ctx)
                } else if mode == 1 || mode == 3 {
                    // znak studia z wektorów intra, wpasowany w pole (oś y w dół → odwracamy)
                    let m = BluerootIntro.markPaths
                    let paths: [CGPath] = m.bands + m.leaves
                    var box = CGRect.null
                    for p in paths { box = box.union(p.boundingBoxOfPath) }
                    let s = R * 1.75 / max(box.width, box.height)
                    var tr = CGAffineTransform(translationX: cc.x, y: cc.y).scaledBy(x: s, y: -s).translatedBy(x: -box.midX, y: -box.midY)
                    func dim(_ h: UInt32) -> CGColor { CGColor(red: CGFloat((h >> 16) & 255) / 255 * 1.0, green: CGFloat((h >> 8) & 255) / 255 * 1.0, blue: CGFloat(h & 255) / 255 * 1.0, alpha: 1) }
                    let pal = mode == 1 ? BluerootIntro.pO : BluerootIntro.pB
                    ctx.setFillColor(dim(0x34C26B)); m.leaves.forEach { if let q = $0.copy(using: &tr) { ctx.addPath(q) } }; ctx.fillPath()
                    for (i, p) in m.bands.enumerated() { ctx.setFillColor(dim(pal["b\(i)"]!)); if let q = p.copy(using: &tr) { ctx.addPath(q) }; ctx.fillPath() }
                }
            }
        }
    }

    // MARK: Budowa sceny
    func build() {
        let env = ProcessInfo.processInfo.environment
        backgroundColor = nsc(BluerootIntro.bg)
        antialiasingMode = .multisampling4X
        allowsCameraControl = false
        let sc = SCNScene()
        sc.background.contents = nsc(BluerootIntro.bg)
        scene = sc
                if let u = Scans.hdriURL { sc.lightingEnvironment.contents = u; sc.lightingEnvironment.intensity = 0.16 }

        let cam = SCNCamera()
        cam.fieldOfView = 24; cam.zNear = 0.5; cam.zFar = 60
        cam.wantsHDR = false
        let cn = SCNNode(); cn.camera = cam
        let dist: CGFloat = 9.0
        cn.position = SCNVector3(0, 0.15, dist)
        let aim = SCNNode(); aim.position = SCNVector3(0, -0.40, 0); sc.rootNode.addChildNode(aim)
        cn.constraints = [SCNLookAtConstraint(target: aim)]
        sc.rootNode.addChildNode(cn); pointOfView = cn

        // miękki cień pod bilą (bez podłogi – tło zostaje jednolite jak w dotychczasowym intro) i poświata za bilą
        func radial(_ rgbc: UInt32, _ a: CGFloat) -> CGImage {
            // 1024² z ditheringiem (szum ±1,5/255), żeby nie było pasów ani widocznych pikseli na łagodnym gradiencie
            let n = 1024
            let cr = Double((rgbc >> 16) & 255) / 255, cg = Double((rgbc >> 8) & 255) / 255, cb = Double(rgbc & 255) / 255
            var buf = [UInt8](repeating: 0, count: n * n * 4)
            var seed: UInt64 = 0x9E3779B97F4A7C15
            for y in 0..<n { for x in 0..<n {
                let dx = (Double(x) + 0.5) / Double(n) * 2 - 1, dy = (Double(y) + 0.5) / Double(n) * 2 - 1
                let r = min(1, (dx * dx + dy * dy).squareRoot())
                let f = pow(1 - r, 2.2)                      // gładki spadek do zera na brzegu
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let noise = (Double(seed >> 40) / Double(1 << 24) - 0.5) * 3.0 / 255
                let al = max(0, min(1, Double(a) * f + (f > 0 ? noise : 0)))
                let i = (y * n + x) * 4
                buf[i] = UInt8(cr * al * 255); buf[i + 1] = UInt8(cg * al * 255); buf[i + 2] = UInt8(cb * al * 255); buf[i + 3] = UInt8(al * 255)
            } }
            let prov = CGDataProvider(data: Data(buf) as CFData)!
            return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        }
        let glowP = SCNPlane(width: 7, height: 7); let gm = SCNMaterial(); gm.lightingModel = .constant; gm.diffuse.contents = radial(0x2E86FF, 0.10); gm.blendMode = .add; gm.writesToDepthBuffer = false
        glowP.materials = [gm]; let glowN = SCNNode(geometry: glowP); glowN.position = SCNVector3(0, 0, -2.5); glowN.renderingOrder = -2; sc.rootNode.addChildNode(glowN)
        let shP = SCNPlane(width: 1.9, height: 0.8); let shm = SCNMaterial(); shm.lightingModel = .constant; shm.diffuse.contents = radial(0x000000, 0.65); shm.blendMode = .alpha; shm.writesToDepthBuffer = false
        shP.materials = [shm]; let shN = SCNNode(geometry: shP); shN.eulerAngles.x = -.pi / 2; shN.position = SCNVector3(0.1, -0.499, 0.05); shN.renderingOrder = -1

        // światła: główne (cień), przeciwne chłodne, pas połysku
        let key = SCNLight(); key.type = .spot; key.intensity = 1700; key.temperature = 6200
        key.spotInnerAngle = 25; key.spotOuterAngle = 70; key.castsShadow = false
        let kn = SCNNode(); kn.light = key; kn.position = SCNVector3(-2.5, 5.0, 4.5)
        kn.constraints = [SCNLookAtConstraint(target: sc.rootNode)]
        sc.rootNode.addChildNode(kn)
        let amb = SCNLight(); amb.type = .ambient; amb.color = nsc(0x2A3342); amb.intensity = 500
        let an = SCNNode(); an.light = amb; sc.rootNode.addChildNode(an)
        let fill = SCNLight(); fill.type = .omni; fill.intensity = 300; fill.color = nsc(0x4DA3FF)
        let fnode = SCNNode(); fnode.light = fill; fnode.position = SCNVector3(3.5, 1.5, 2.5); sc.rootNode.addChildNode(fnode)
        let sweep = SCNLight(); sweep.type = .omni; sweep.intensity = 0; sweep.color = nsc(0xFFFFFF); sweep.attenuationEndDistance = 12
        let sn = SCNNode(); sn.light = sweep; sn.position = SCNVector3(-5, 1.2, 2.0); sc.rootNode.addChildNode(sn)

        // bila
        let sphere = SCNSphere(radius: 0.5); sphere.segmentCount = 96
        func mat(_ img: CGImage, transparent: Bool) -> SCNMaterial {
            let m = SCNMaterial(); m.lightingModel = .physicallyBased
            m.diffuse.contents = img; m.roughness.contents = 0.18; m.metalness.contents = 0.0
            m.clearCoat.contents = 0.55; m.clearCoatRoughness.contents = 0.04
            m.diffuse.mipFilter = .linear; m.diffuse.maxAnisotropy = 8
            if transparent { m.lightingModel = .lambert; m.diffuse.contents = img; m.blendMode = .alpha; m.writesToDepthBuffer = false }
            return m
        }
        let u = frontU
        sphere.materials = [mat(Self.ballTexture(u: u, mode: 0), transparent: false)]
        let ball = SCNNode(geometry: sphere); ball.castsShadow = true
        // nakładki: cyfra „8” (znika) i znak studia w prawdziwych kolorach (pojawia się)
        let ov = SCNSphere(radius: 0.5008); ov.segmentCount = 96
        let cm = SCNMaterial(); cm.lightingModel = .constant; cm.diffuse.contents = Self.ballTexture(u: u, mode: 1)
        cm.blendMode = .alpha; cm.writesToDepthBuffer = false; cm.diffuse.mipFilter = .linear
        ov.materials = [cm]
        let ovn = SCNNode(geometry: ov); cm.transparency = 0; ovn.opacity = 1; ovn.castsShadow = false; ovn.renderingOrder = 6
        ball.addChildNode(ovn)
        let bo = SCNSphere(radius: 0.5012); bo.segmentCount = 96
        let bm = SCNMaterial(); bm.lightingModel = .constant; bm.diffuse.contents = Self.ballTexture(u: u, mode: 3)
        bm.blendMode = .alpha; bm.writesToDepthBuffer = false; bm.diffuse.mipFilter = .linear; bm.transparency = 0
        bo.materials = [bm]
        let bon = SCNNode(geometry: bo); bon.castsShadow = false; bon.renderingOrder = 7
        ball.addChildNode(bon)
        let nu = SCNSphere(radius: 0.5004); nu.segmentCount = 96
        let nm = mat(Self.ballTexture(u: u, mode: 2), transparent: true)
        nu.materials = [nm]
        let nn = SCNNode(geometry: nu); nn.castsShadow = false; nn.renderingOrder = 5
        ball.addChildNode(nn)
        let holder = SCNNode(); holder.addChildNode(ball); holder.addChildNode(shN); sc.rootNode.addChildNode(holder)

        // ruch: toczenie z lewej, wytracanie, drobne kołysanie
        let startX: CGFloat = -5.2
        holder.position = SCNVector3(startX, 0, 0)
        ball.eulerAngles = SCNVector3(0, 0, 0)
        let roll = 1.9
        let rollAct = SCNAction.customAction(duration: roll) { node, t in
            let p = CGFloat(t) / CGFloat(roll)
            let e = 1 - pow(1 - p, 2.6)
            let x = startX * (1 - e)
            node.position = SCNVector3(x, 0, 0)
            // toczenie bez poślizgu: obrót wokół osi z = przesunięcie / promień (pole zatrzymuje się na przodzie)
            ball.eulerAngles = SCNVector3(0, 0, -x / 0.5)
        }
        let settle = SCNAction.customAction(duration: 4.0) { _, t in
            let k = CGFloat(t)
            let wob = sin(k * 1.1) * 0.10 * (1 - min(1, k / 4))
            ball.eulerAngles = SCNVector3(0, wob, 0)
        }
        holder.runAction(.sequence([.wait(duration: 0.25), rollAct, settle]))
        // „8” → znak studia
        ovn.runAction(.sequence([.wait(duration: 2.35), .customAction(duration: 0.7) { _, t in cm.transparency = CGFloat(t) / 0.7 }]))
        bon.runAction(.sequence([.wait(duration: 3.7), .customAction(duration: 0.9) { _, t in bm.transparency = CGFloat(t) / 0.9; cm.transparency = 1 - CGFloat(t) / 0.9 }]))
        // błysk przy zmianie koloru
        sn.runAction(.sequence([.wait(duration: 3.6), .customAction(duration: 0.9) { _, t in
            let p = CGFloat(t) / 0.9; sweep.intensity = 500 * sin(p * .pi); sn.position = SCNVector3(0.2, 0.9, 2.6)
        }]), forKey: "flash")
        nn.runAction(.sequence([.wait(duration: 2.35), .customAction(duration: 0.5) { _, t in nm.transparency = 1 - CGFloat(t) / 0.5 }, .hide()]))
        // powolny najazd kamery
        cn.runAction(.customAction(duration: Self.duration) { node, t in
            let p = CGFloat(t) / CGFloat(Self.duration)
            node.position = SCNVector3(0, 0.15, dist - 0.55 * p)
        })

        // napisy: warstwa SpriteKit nad sceną (wektorowy napis studia + podpis)
        let ov2 = SKScene(size: bounds.size); ov2.scaleMode = .resizeFill; ov2.backgroundColor = .clear
        let w = bounds.width, h = bounds.height
        let sw = min(w, h * 16 / 9), sh = sw * 9 / 16
        let rect = CGRect(x: (w - sw) / 2, y: (h - sh) / 2, width: sw, height: sh)
        let px = window?.backingScaleFactor ?? 2
        let wordImg = makeImage(Int(sw * px), Int(sh * px)) { ctx in
            ctx.translateBy(x: 0, y: CGFloat(Int(sh * px))); ctx.scaleBy(x: 1, y: -1)
            ctx.scaleBy(x: CGFloat(Int(sw * px)) / CGFloat(BluerootIntro.W), y: CGFloat(Int(sw * px)) / CGFloat(BluerootIntro.W))
            if let (wd, st) = BluerootIntro.wordPaths {
                ctx.setFillColor(rgb(0xFFFFFF)); ctx.addPath(wd); ctx.fillPath()
                ctx.setFillColor(rgb(0x4DA3FF)); ctx.addPath(st); ctx.fillPath()
            }
        }
        let word = SKSpriteNode(texture: SKTexture(cgImage: wordImg), size: rect.size)
        word.position = CGPoint(x: rect.midX, y: rect.midY - sh * 0.10); word.alpha = 0
        ov2.addChild(word)
        word.run(.sequence([.wait(forDuration: 4.1), .fadeIn(withDuration: 0.8)]))
        overlaySKScene = ov2

        // zakończenie
        holder.runAction(.sequence([.wait(duration: Self.duration), .run { [weak self] _ in DispatchQueue.main.async { self?.finish() } }]))
        if env["BILARD_INTRO3D_DEBUG"] != nil { print("INTRO3D frontU=\(u)") }
    }
}
