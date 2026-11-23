import Cocoa
import SceneKit
import SpriteKit


// MARK: - Podpis autora: linia pióra z grubością w każdym punkcie (dane z podpis_art.json)

final class SignaturePen {
    struct Seg { let a: CGPoint, b: CGPoint, wa: CGFloat, wb: CGFloat, t: Double }
    let w: CGFloat, h: CGFloat
    var segs: [Seg] = []
    var next = 0
    var total = 0.0
    var tip = CGPoint.zero

    init?(url: URL?) {
        guard let url, let data = try? Data(contentsOf: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jw = j["w"] as? Double, let jh = j["h"] as? Double, let st = j["strokes"] as? [[String: Any]] else { return nil }
        w = CGFloat(jw); h = CGFloat(jh)
        struct S { var c: Int; var p: [[Double]] }
        let strokes = st.compactMap { d -> S? in
            guard let c = d["c"] as? Int, let p = d["p"] as? [[Double]] else { return nil }
            return S(c: c, p: p)
        }
        func len(_ p: [[Double]]) -> Double { var l = 0.0; for i in 1..<max(1, p.count) { l += hypot(p[i][0] - p[i - 1][0], p[i][1] - p[i - 1][1]) }; return l }
        let letters = strokes.filter { $0.c != 999 }.reduce(0.0) { $0 + len($1.p) }
        let nComp = Set(strokes.filter { $0.c != 999 }.map { $0.c }).count
        let writeTime = 4.4, pause = 0.075
        let speed = letters / max(0.5, writeTime - Double(nComp) * pause)
        let swooshTime = 0.95
        var t = 0.0, prev = -1
        for s in strokes {
            if prev != -1 && s.c != prev { t += (s.c == 999 ? 0.28 : pause) }
            prev = s.c
            let L = len(s.p)
            let sp = s.c == 999 ? max(1, L / swooshTime) : speed
            var acc = 0.0
            for i in 1..<max(1, s.p.count) {
                let a = s.p[i - 1], b = s.p[i]
                let d = hypot(b[0] - a[0], b[1] - a[1]); acc += d
                segs.append(Seg(a: CGPoint(x: a[0], y: a[1]), b: CGPoint(x: b[0], y: b[1]), wa: CGFloat(a[2]), wb: CGFloat(b[2]), t: t + acc / sp))
            }
            t += L / sp
        }
        total = t
    }

    /// Dorysowuje do `ctx` (układ: jednostki podpisu, oś y w dół) wszystkie odcinki do chwili `t`; zwraca true, gdy coś doszło
    @discardableResult
    func advance(to t: Double, ctx: CGContext) -> Bool {
        var drew = false
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setStrokeColor(CGColor(red: 0.965, green: 0.973, blue: 0.992, alpha: 1))
        while next < segs.count && segs[next].t <= t {
            let sg = segs[next]
            ctx.setLineWidth(max(0.8, (sg.wa + sg.wb) / 2 * 1.15))
            ctx.move(to: sg.a); ctx.addLine(to: sg.b); ctx.strokePath()
            tip = sg.b; next += 1; drew = true
        }
        return drew
    }
}

// MARK: - Intro studia w 3D: czarna ósemka toczy się po lśniącej podłodze, a w jej białym polu „8” zamienia się w znak BLUEROOT

final class Intro3DView: SCNView {
    var onDone: (() -> Void)?
    var finished = false
    var duration = 12.0
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
                duration = 4.3 + 5.2 + 0.15 + 0.8 + 1.6
        let dur = duration
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
        // odbicie bili: odwrócona kopia pod spodem (wspólne materiały), mocno rozmyta i przyciemniona
        let reflN = SCNNode()
        let ballM = ball.clone(); ballM.position = SCNVector3(0, 0, 0); ballM.castsShadow = false
        ballM.eulerAngles = SCNVector3(0, 0, CGFloat.pi)
        if let bf = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 34.0]),
           let dim = CIFilter(name: "CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.22, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.22, z: 0, w: 0),
                                                                    "inputBVector": CIVector(x: 0, y: 0, z: 0.22, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.22)]) { reflN.filters = [bf, dim] }
        reflN.addChildNode(ballM); reflN.position = SCNVector3(0, -1.0, 0); reflN.opacity = 1.0
        holder.addChildNode(reflN)
        if ballM.childNodes.count >= 3 { ballM.childNodes[2].runAction(.sequence([.wait(duration: 2.85), .hide()])) }

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
            ball.eulerAngles = SCNVector3(0, 0, -x / 0.5); ballM.eulerAngles = SCNVector3(0, 0, -x / 0.5 + CGFloat.pi)
        }
        let settle = SCNAction.customAction(duration: 4.0) { _, t in
            let k = CGFloat(t)
            let wob = sin(k * 1.1) * 0.10 * (1 - min(1, k / 4))
            ball.eulerAngles = SCNVector3(0, wob, 0); ballM.eulerAngles = SCNVector3(0, wob, CGFloat.pi)
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
        cn.runAction(.customAction(duration: dur) { node, t in
            let p = CGFloat(t) / CGFloat(dur)
            node.position = SCNVector3(0, 0.15, dist - 0.55 * p)
        })

        // podpis (animowana linia pióra) + napis STUDIO: warstwa SpriteKit nad sceną
        let ov2 = SKScene(size: bounds.size); ov2.scaleMode = .resizeFill; ov2.backgroundColor = .clear
        let w = bounds.width, h = bounds.height
        let sw = min(w, h * 16 / 9), sh = sw * 9 / 16
        let rect = CGRect(x: (w - sw) / 2, y: (h - sh) / 2, width: sw, height: sh)
        let px = window?.backingScaleFactor ?? 2
        let writeStart = 4.3, writeDur = 5.2
        let studioAt = writeStart + writeDur + 0.15
        // gdy wchodzi STUDIO: tło (bila i jej odbicie) rozmywa się – płytka głębia ostrości
        cam.wantsDepthOfField = true; cam.wantsHDR = true; cam.bloomIntensity = 0; cam.screenSpaceAmbientOcclusionIntensity = 0; cam.wantsExposureAdaptation = false; cam.fStop = 64; cam.focusDistance = dist; cam.focalBlurSampleCount = 64
        cn.runAction(.sequence([.wait(duration: studioAt - 0.2), .customAction(duration: 1.6) { _, t in
            let p = CGFloat(t) / 1.6; let e = p * p * (3 - 2 * p)
            cam.focusDistance = dist - 7.0 * e
            cam.fStop = 64 - 63.8 * e
        }]), forKey: "dof")
        if let sigURL = Bundle.main.url(forResource: "podpis_sig", withExtension: "png"),
           let stuURL = Bundle.main.url(forResource: "podpis_studio", withExtension: "png"),
           let sigImg = NSImage(contentsOf: sigURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let sigW = sw * 0.56, sigH = sigW * CGFloat(sigImg.height) / CGFloat(sigImg.width)
            let center = CGPoint(x: rect.midX, y: rect.maxY - sh * CGFloat(Double(env["BILARD_INTRO_Y"] ?? "") ?? 0.60))
            // kolejność pisania: mapa czasu (16 bit w R,G) – piksel pojawia się, gdy pióro dojdzie do jego miejsca na linii
            guard let tmURL = Bundle.main.url(forResource: "podpis_time", withExtension: "png"),
                  let tmImg = NSImage(contentsOf: tmURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let penURL = Bundle.main.url(forResource: "podpis_pen", withExtension: "json"),
                  let pj = (try? Data(contentsOf: penURL)).flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any],
                  let track = pj["tip"] as? [[Double]], !track.isEmpty else { return }
            let tmTex = SKTexture(cgImage: tmImg); tmTex.filteringMode = .nearest
            // warianty efektów: BILARD_INTRO_FX = A (kometa), B (złoty pył), C (neon), D (gwiazdki)
            let fx = (env["BILARD_INTRO_FX"] ?? "B").uppercased()
            let cfg: (wetT: String, wetG: String, wetLen: String, flash: String, halo: String, hc: String, col: UInt32, col2: UInt32, foil: String, m1: String, m2: String)
            switch fx {
            case "B": cfg = ("1.0, 0.80, 0.42", "0.30, 0.20, 0.04", "0.06", "1.0, 0.85, 0.5", "1.0", "mix(vec3(1.0,0.55,0.12), vec3(1.0,0.85,0.4), v_tex_coord.x)", 0xFFD98A, 0xFFB347, "1.0", "0.62, 0.42, 0.10", "1.0, 0.86, 0.45")
            case "C": cfg = ("0.35, 1.0, 0.95", "0.05, 0.35, 0.40", "0.12", "0.9, 0.4, 1.0", "1.0", "mix(vec3(0.1,0.9,1.0), vec3(0.85,0.3,1.0), v_tex_coord.x)", 0x6CF6FF, 0xE070FF, "0.0", "1.0, 1.0, 1.0", "1.0, 1.0, 1.0")
            case "D": cfg = ("1.0, 0.95, 0.85", "0.25, 0.22, 0.12", "0.05", "1.0, 1.0, 0.9", "1.0", "vec3(1.0,0.93,0.75)", 0xFFF3C8, 0xBEDCFF, "1.0", "0.45, 0.52, 0.62", "0.98, 0.99, 1.0")
            default:  cfg = ("0.50, 0.76, 1.0", "0.10, 0.22, 0.45", "0.09", "0.55, 0.78, 1.0", "1.0", "mix(vec3(0.25,0.55,1.0), vec3(0.6,0.85,1.0), v_tex_coord.x)", 0xBEDCFF, 0x78AAFF, "0.0", "1.0, 1.0, 1.0", "1.0, 1.0, 1.0")
            }
            let uT = SKUniform(name: "u_t", float: 0), uS = SKUniform(name: "u_s", float: -2), uH = SKUniform(name: "u_h", float: 0), uF = SKUniform(name: "u_f", float: Float(cfg.foil) ?? 0)
            let shader = SKShader(source: """
                void main() {
                    vec4 c = texture2D(u_texture, v_tex_coord);
                    vec4 tm = texture2D(u_order, v_tex_coord);
                    float raw = tm.r * 255.0 * 256.0 + tm.g * 255.0;
                    float t = (raw - 500.0) / 65000.0;
                    float a = (raw < 1.0) ? 0.0 : 1.0 - smoothstep(u_t - 0.006, u_t, t);
                    float wet = clamp(1.0 - (u_t - t) / \(cfg.wetLen), 0.0, 1.0);          // świeży tusz świeci
                    vec3 rgb = c.rgb * mix(vec3(1.0), vec3(\(cfg.wetT)), wet) + c.a * wet * vec3(\(cfg.wetG));
                    float d = v_tex_coord.x - u_s + 0.16 * (v_tex_coord.y - 0.5);  // pochylony błysk po skończeniu podpisu
                    rgb += c.a * exp(-d * d * 420.0) * vec3(\(cfg.flash)) * 0.9;
                    if (u_f > 0.0) {                                                // metaliczna folia: gradient + fazowane krawędzie + refleks
                        vec2 px = vec2(3.0 / 2400.0, 3.0 / 880.0);
                        float gx = texture2D(u_texture, v_tex_coord + vec2(px.x, 0.0)).a - texture2D(u_texture, v_tex_coord - vec2(px.x, 0.0)).a;
                        float gy = texture2D(u_texture, v_tex_coord + vec2(0.0, px.y)).a - texture2D(u_texture, v_tex_coord - vec2(0.0, px.y)).a;
                        vec3 n = normalize(vec3(-gx * 1.4, gy * 1.4, 0.55));
                        float g = v_tex_coord.y;
                        vec3 metal = mix(vec3(\(cfg.m2)), vec3(\(cfg.m1)), smoothstep(0.1, 0.75, g));
                        metal *= 0.82 + 0.18 * sin(g * 26.0 + v_tex_coord.x * 5.0);
                        float spec = pow(clamp(dot(n, normalize(vec3(0.45, 0.55, 0.7))), 0.0, 1.0), 5.0);
                        metal += spec * 0.55 + pow(clamp(dot(n, normalize(vec3(-0.5, -0.4, 0.75))), 0.0, 1.0), 8.0) * 0.25;
                        rgb = mix(c.a * metal, rgb, wet);
                    }
                    vec4 outc = vec4(rgb, c.a) * a;
                    if (u_h > 0.0) {                                                // neonowa poświata wokół liter
                        float h = 0.0;
                        for (int i = 0; i < 8; i++) {
                            float an = float(i) * 0.7854;
                            vec2 dir = vec2(cos(an) / 2400.0, sin(an) / 880.0);
                            vec2 u1 = v_tex_coord + dir * 12.0, u2 = v_tex_coord + dir * 34.0;
                            vec4 t1 = texture2D(u_order, u1), t2 = texture2D(u_order, u2);
                            float r1 = (t1.r * 255.0 * 256.0 + t1.g * 255.0 - 500.0) / 65000.0, r2 = (t2.r * 255.0 * 256.0 + t2.g * 255.0 - 500.0) / 65000.0;
                            float v1 = (t1.r + t1.g < 0.001) ? 0.0 : 1.0 - smoothstep(u_t - 0.006, u_t, r1);
                            float v2 = (t2.r + t2.g < 0.001) ? 0.0 : 1.0 - smoothstep(u_t - 0.006, u_t, r2);
                            h += texture2D(u_texture, u1).a * v1 + texture2D(u_texture, u2).a * v2 * 0.6;
                        }
                        h = clamp(h / 5.0, 0.0, 1.0) * u_h;
                        vec3 hc = \(cfg.hc);
                        outc += vec4(hc * h * 1.5, h * 0.9);
                    }
                    gl_FragColor = outc;
                }
                """, uniforms: [uT, uS, uH, uF, SKUniform(name: "u_order", texture: tmTex)])
            let sprite = SKSpriteNode(texture: SKTexture(cgImage: sigImg), size: CGSize(width: sigW, height: sigH))
            sprite.shader = shader; sprite.position = center
            ov2.addChild(sprite)
            // odbicie w szklanej tafli pod podpisem
            let maskTex = SKTexture(cgImage: makeImage(8, 128) { c in
                c.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.15), rgb(0xFFFFFF, 0)], [0, 1]), start: CGPoint(x: 0, y: 128), end: CGPoint(x: 0, y: 0), options: [])
            })
            let reflCrop = SKCropNode()
            let reflMask = SKSpriteNode(texture: maskTex, size: CGSize(width: sigW, height: sigH)); let mirrorY = center.y + sigH / 2 - 0.80 * sigH     // lustro tuż pod podkreśleniem (jak pod bilą)
            reflMask.position = CGPoint(x: center.x, y: mirrorY - sigH * 0.5)
            reflCrop.maskNode = reflMask
            let refl = SKSpriteNode(texture: SKTexture(cgImage: sigImg), size: CGSize(width: sigW, height: sigH))
            refl.shader = shader; refl.yScale = -1; refl.position = CGPoint(x: center.x, y: 2 * mirrorY - center.y)
            reflCrop.addChild(refl)
            let blurN = SKEffectNode(); blurN.shouldEnableEffects = true; blurN.shouldRasterize = false
            blurN.filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 12 * px])
            blurN.alpha = 0.55; blurN.addChild(reflCrop); ov2.addChild(blurN)
            let glowTex = SKTexture(cgImage: makeImage(128, 128) { c in
                c.drawRadialGradient(gradient([rgb(cfg.col, 0.95), rgb(cfg.col2, 0)], [0, 1]), startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                     endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
            })
            // gwiazdka 4-ramienna (flara)
            let starTex = SKTexture(cgImage: makeImage(128, 128) { c in
                let g = gradient([rgb(0xFFFFFF, 0), rgb(0xFFFFFF, 1), rgb(0xFFFFFF, 0)], [0, 0.5, 1])
                for vertical in [false, true] {
                    c.saveGState()
                    if vertical { c.translateBy(x: 128, y: 0); c.rotate(by: .pi / 2) }
                    c.clip(to: CGRect(x: 0, y: 61, width: 128, height: 6))
                    c.drawLinearGradient(g, start: CGPoint(x: 0, y: 64), end: CGPoint(x: 128, y: 64), options: [])
                    c.restoreGState()
                }
                c.drawRadialGradient(gradient([rgb(0xFFFFFF, 0.9), rgb(0xFFFFFF, 0)], [0, 1]), startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                     endCenter: CGPoint(x: 64, y: 64), endRadius: 22, options: [])
            })
            let glow = SKSpriteNode(texture: glowTex, size: CGSize(width: sh * 0.15, height: sh * 0.15)); glow.alpha = 0; glow.blendMode = .add
            ov2.addChild(glow)
            let flare = SKSpriteNode(texture: starTex, size: CGSize(width: sh * 0.26, height: sh * 0.26)); flare.alpha = 0; flare.blendMode = .add
            flare.color = nsc(cfg.col); flare.colorBlendFactor = 0.6
            ov2.addChild(flare)
            // pozioma smuga anamorficzna
            let streak = SKSpriteNode(texture: glowTex, size: CGSize(width: sh * 0.9, height: sh * 0.022)); streak.alpha = 0; streak.blendMode = .add
            streak.color = nsc(cfg.col); streak.colorBlendFactor = 0.5; ov2.addChild(streak)
            let sparks = SKEmitterNode()
            sparks.particleTexture = glowTex; sparks.particleBirthRate = 0
            sparks.particleColor = nsc(cfg.col); sparks.particleColorBlendFactor = 1
            sparks.particleBlendMode = .add; sparks.targetNode = ov2
            var sparkRate: CGFloat = 140
            switch fx {
            case "B":   // złoty pył opadający
                sparkRate = 260; sparks.particleLifetime = 1.4; sparks.particleLifetimeRange = 0.4
                sparks.particleSpeed = 20; sparks.particleSpeedRange = 16; sparks.emissionAngle = -.pi / 2; sparks.emissionAngleRange = .pi * 0.9
                sparks.yAcceleration = -70; sparks.particleScale = 0.12; sparks.particleScaleRange = 0.08; sparks.particleScaleSpeed = -0.05
                sparks.particleAlpha = 0.9; sparks.particleAlphaSpeed = -0.8; sparks.particlePositionRange = CGVector(dx: 6, dy: 6)
            case "C":   // neonowe iskry
                sparkRate = 380; sparks.particleLifetime = 0.8; sparks.particleLifetimeRange = 0.2
                sparks.particleSpeed = 44; sparks.particleSpeedRange = 30; sparks.emissionAngleRange = .pi * 2
                sparks.particleScale = 0.12; sparks.particleScaleRange = 0.06; sparks.particleScaleSpeed = -0.08
                sparks.particleAlpha = 0.9; sparks.particleAlphaSpeed = -1.5; sparks.particlePositionRange = CGVector(dx: 3, dy: 3)
                sparks.particleColorSequence = SKKeyframeSequence(keyframeValues: [nsc(0x6CF6FF), nsc(0xE070FF)], times: [0, 1])
                sparks.particleColorBlendFactor = 1
            case "D":   // gwiazdki zostające na literach
                sparkRate = 70; sparks.particleTexture = starTex; sparks.particleLifetime = 0.8; sparks.particleLifetimeRange = 0.3
                sparks.particleSpeed = 6; sparks.particleSpeedRange = 8; sparks.emissionAngleRange = .pi * 2
                sparks.particleScale = 0.28; sparks.particleScaleRange = 0.16; sparks.particleScaleSpeed = -0.2
                sparks.particleRotationRange = .pi; sparks.particleRotationSpeed = 2.5
                sparks.particleAlpha = 0.95; sparks.particleAlphaSpeed = -1.2; sparks.particlePositionRange = CGVector(dx: 10, dy: 10)
            default:    // A – kometa z długim ogonem
                sparkRate = 700; sparks.particleLifetime = 1.4; sparks.particleLifetimeRange = 0.3
                sparks.particleSpeed = 4; sparks.particleSpeedRange = 6; sparks.emissionAngleRange = .pi * 2
                sparks.particleScale = 0.16; sparks.particleScaleRange = 0.03; sparks.particleScaleSpeed = -0.1
                sparks.particleAlpha = 0.8; sparks.particleAlphaSpeed = -1.0; sparks.particlePositionRange = CGVector(dx: 1, dy: 1)
            }
            ov2.addChild(sparks)
            // migotanie gwiazdek po skończeniu podpisu (A, B, D) – w losowych punktach linii pióra
            if fx != "C" {
                let n = fx == "D" ? 26 : 16
                for _ in 0..<n {
                    let tp = track[Int.random(in: 0..<track.count)]
                    let st = SKSpriteNode(texture: starTex, size: CGSize(width: sh * CGFloat.random(in: 0.025...0.07), height: sh * CGFloat.random(in: 0.025...0.07)))
                    st.position = CGPoint(x: center.x - sigW / 2 + CGFloat(tp[0]) * sigW, y: center.y + sigH / 2 - CGFloat(tp[1]) * sigH)
                    st.alpha = 0; st.blendMode = .add; st.zRotation = CGFloat.random(in: -0.3...0.3); st.color = nsc(cfg.col); st.colorBlendFactor = 0.5
                    st.run(.sequence([.wait(forDuration: writeStart + writeDur + Double.random(in: 0.0...1.5)),
                                      .group([.sequence([.fadeAlpha(to: 1, duration: 0.12), .fadeOut(withDuration: 0.5)]),
                                              .sequence([.scale(to: 1.4, duration: 0.15), .scale(to: 0.2, duration: 0.5)])]), .removeFromParent()]))
                    ov2.addChild(st)
                }
            }
            // finał: fontanna iskier jadąca z błyskiem, fale uderzeniowe i rozbłysk
            let fountain = SKEmitterNode()
            fountain.particleTexture = glowTex; fountain.particleBirthRate = 0; fountain.targetNode = ov2
            fountain.particleLifetime = 1.0; fountain.particleLifetimeRange = 0.4; fountain.particleSpeed = 150; fountain.particleSpeedRange = 90
            fountain.emissionAngle = .pi / 2; fountain.emissionAngleRange = .pi * 0.8; fountain.yAcceleration = -160
            fountain.particleScale = 0.14; fountain.particleScaleRange = 0.08; fountain.particleScaleSpeed = -0.1
            fountain.particleAlpha = 1; fountain.particleAlphaSpeed = -0.9; fountain.particleColor = nsc(cfg.col); fountain.particleColorBlendFactor = 1
            fountain.particleBlendMode = .add; fountain.position = CGPoint(x: -9999, y: -9999); ov2.addChild(fountain)
            let flashN = SKSpriteNode(color: nsc(cfg.col), size: CGSize(width: sw * 2, height: sh * 2)); flashN.alpha = 0; flashN.blendMode = .add
            flashN.position = CGPoint(x: rect.midX, y: rect.midY); ov2.addChild(flashN)
            for k in 0..<3 {
                let ring = SKShapeNode(circleOfRadius: sh * 0.05); ring.strokeColor = nsc(k == 1 ? cfg.col2 : cfg.col); ring.lineWidth = 2; ring.fillColor = NSColor.clear
                ring.blendMode = SKBlendMode.add; ring.alpha = 0; ring.position = center; ov2.addChild(ring)
                let big = CGFloat(sw / (sh * 0.1) * 0.45)
                let pop = SKAction.sequence([SKAction.fadeAlpha(to: 0.45, duration: 0.05), SKAction.fadeOut(withDuration: 0.9)])
                let grow = SKAction.scale(to: big, duration: 1.0)
                ring.run(SKAction.sequence([SKAction.wait(forDuration: writeStart + writeDur + 0.05 + Double(k) * 0.18), SKAction.group([pop, grow])]))
            }
            flashN.run(.sequence([.wait(forDuration: writeStart + writeDur), .fadeAlpha(to: 0.22, duration: 0.08), .fadeOut(withDuration: 0.7)]))
            sprite.run(.customAction(withDuration: dur) { _, e in
                let t = Double(e) - writeStart
                guard t >= 0 else { uT.floatValue = -1; return }
                let p = min(1, t / writeDur)
                uT.floatValue = Float(p >= 1 ? 1.1 : p)
                glow.alpha = (p > 0 && p < 1) ? 1 : 0
                flare.alpha = (p > 0 && p < 1) ? CGFloat(0.75 + 0.25 * sin(t * 40)) : 0
                flare.zRotation = CGFloat(t * 2.0); streak.alpha = flare.alpha * 0.8
                sparks.particleBirthRate = (p > 0 && p < 1) ? sparkRate : 0
                uS.floatValue = Float(-0.2 + max(0, t - writeDur) / 1.3 * 1.5)
                uH.floatValue = Float(min(1, p * 4) * (p >= 1 ? 0.28 + 0.07 * sin((t - writeDur) * 4) + 0.7 * max(0, 1 - (t - writeDur) / 1.0) : 1))
                let q = (t - writeDur) / 1.3
                if q > 0 && q < 1 {
                    fountain.particleBirthRate = 500
                    fountain.position = CGPoint(x: center.x - sigW / 2 + CGFloat(-0.2 + q * 1.5) * sigW, y: center.y - sigH * 0.1)
                } else { fountain.particleBirthRate = 0 }
                if p < 1 {
                    sparks.position = glow.position
                    let i = min(track.count - 1, Int(p * Double(track.count - 1)))
                    glow.position = CGPoint(x: center.x - sigW / 2 + CGFloat(track[i][0]) * sigW, y: center.y + sigH / 2 - CGFloat(track[i][1]) * sigH)
                    flare.position = glow.position; streak.position = glow.position
                }
            })
            if let st = NSImage(contentsOf: stuURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let studio = SKSpriteNode(texture: SKTexture(cgImage: st), size: CGSize(width: sigW, height: sigH))
                studio.position = center; studio.alpha = 0
                studio.run(.sequence([.wait(forDuration: studioAt), .fadeIn(withDuration: 0.8)]))
                ov2.addChild(studio)
            }
        }
        overlaySKScene = ov2

        // zakończenie
        holder.runAction(.sequence([.wait(duration: dur), .run { [weak self] _ in DispatchQueue.main.async { self?.finish() } }]))
        if env["BILARD_INTRO3D_DEBUG"] != nil { print("INTRO3D frontU=\(u)") }
    }
}
