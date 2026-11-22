import Cocoa
import SceneKit

// MARK: - Menu główne jako biały nadruk na suknie (nad nim toczy się demo AI vs AI, widok z góry)

struct CMItem {
    let id: String
    let rect: CGRect      // obszar klikalny w pikselach obrazu (oś y w dół)
}

final class ClothMenuUI {
    let node = SCNNode()
    private let mat = SCNMaterial()
    var items: [CMItem] = []
    var hover = ""
    var prevOn: Bool? = nil
    private var key = ""
    private(set) var W = 2048
    let H = 1024
    private(set) var halfL = 1.27, halfW = 0.635

    init() {
        mat.lightingModel = .constant
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.diffuse.mipFilter = .linear; mat.diffuse.minificationFilter = .linear; mat.diffuse.maxAnisotropy = 16
        let p = SCNPlane(width: 1, height: 1)
        p.materials = [mat]
        node.geometry = p
        node.eulerAngles.x = -.pi / 2
        node.renderingOrder = 5
        node.castsShadow = false
        node.isHidden = true
    }

    /// punkt na suknie (metry, układ stołu) → piksel obrazu menu
    func pixel(x: Double, z: Double) -> CGPoint {
        CGPoint(x: (x / (2 * halfL) + 0.5) * Double(W), y: (0.5 + z / (2 * halfW)) * Double(H))
    }
    func hit(x: Double, z: Double) -> String {
        let p = pixel(x: x, z: z)
        return items.first { $0.rect.contains(p) }?.id ?? ""
    }

    func refresh(mode: GameMode, level: Int, halfL hl: Double, halfW hw: Double) {
        let k = "\(mode.rawValue)|\(level)|\(hover)|\(hl)|\(hw)"
        if k == key { return }
        key = k; halfL = hl; halfW = hw
        W = max(1024, Int((Double(H) * hl / hw).rounded()))
        if let p = node.geometry as? SCNPlane { p.width = CGFloat(2 * hl); p.height = CGFloat(2 * hw) }
        mat.diffuse.contents = draw(mode: mode, level: level)
    }

    // MARK: rysowanie

    private func ctline(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ track: CGFloat, _ alpha: CGFloat) -> (CTLine, CGFloat) {
        let a = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                           .foregroundColor: NSColor(white: 1, alpha: alpha), .kern: track])
        let l = CTLineCreateWithAttributedString(a)
        return (l, CGFloat(CTLineGetTypographicBounds(l, nil, nil, nil)) - track)
    }

    private func draw(mode: GameMode, level: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setLineCap(.round)
        items = []
        let cx = CGFloat(W) / 2, Hf = CGFloat(H)

        /// tekst wyśrodkowany w (x, y); y liczone od góry obrazu
        @discardableResult
        func text(_ s: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .semibold, track: CGFloat = 6,
                  alpha: CGFloat = 0.8, id: String? = nil, frame: Bool = false, underline: Bool = false, padX: CGFloat = 22, padY: CGFloat = 14) -> CGRect {
            let hov = id != nil && id == hover
            let (l, w) = ctline(s, size, weight, track, hov ? 1 : alpha)
            let rect = CGRect(x: x - w / 2 - padX, y: y - size * 0.5 - padY, width: w + 2 * padX, height: size + 2 * padY)
            let up = CGRect(x: rect.minX, y: Hf - rect.maxY, width: rect.width, height: rect.height)
            if frame || hov {
                let path = CGPath(roundedRect: up, cornerWidth: 20, cornerHeight: 20, transform: nil)
                if hov { ctx.addPath(path); ctx.setFillColor(CGColor(gray: 1, alpha: 0.14)); ctx.fillPath() }
                ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: hov ? 0.95 : 0.4)); ctx.setLineWidth(hov ? 4 : 2.5); ctx.strokePath()
            }
            ctx.textPosition = CGPoint(x: x - w / 2, y: Hf - y - size * 0.36)
            CTLineDraw(l, ctx)
            if underline || (hov && !frame) {
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.95)); ctx.setLineWidth(max(3, size * 0.07))
                ctx.move(to: CGPoint(x: x - w / 2, y: Hf - y - size * 0.62)); ctx.addLine(to: CGPoint(x: x + w / 2, y: Hf - y - size * 0.62)); ctx.strokePath()
            }
            if let id = id { items.append(CMItem(id: id, rect: rect)) }
            return rect
        }
        func rule(_ y: CGFloat, _ half: CGFloat, _ a: CGFloat) {
            ctx.setStrokeColor(CGColor(gray: 1, alpha: a)); ctx.setLineWidth(2.5)
            ctx.move(to: CGPoint(x: cx - half, y: Hf - y)); ctx.addLine(to: CGPoint(x: cx + half, y: Hf - y)); ctx.strokePath()
        }

        // tytuł
        text("BILARD", x: cx, y: 165, size: 170, weight: .heavy, track: 46, alpha: 0.95)
        rule(272, 330, 0.55)
        text("FOTOREALISTYCZNY BILARD 3D", x: cx, y: 308, size: 24, weight: .medium, track: 12, alpha: 0.5)

        // tryby gry
        let modes = GameMode.allCases
        for (i, gm) in modes.enumerated() {
            let x = cx + (CGFloat(i) - CGFloat(modes.count - 1) / 2) * 232
            text(gm.title.uppercased(), x: x, y: 392, size: 34, weight: .bold, track: 5, alpha: gm == mode ? 1 : 0.7, id: "mode:\(gm.rawValue)", underline: gm == mode)
        }

        // przyciski główne
        text("GRA Z KOMPUTEREM", x: cx, y: 510, size: 60, weight: .bold, track: 9, alpha: 1, id: "ai", frame: true, padX: 60, padY: 26)
        text("DWÓCH GRACZY", x: cx, y: 622, size: 60, weight: .bold, track: 9, alpha: 1, id: "two", frame: true, padX: 60, padY: 26)
        text("WCZYTAJ GRĘ", x: cx, y: 722, size: 40, weight: .semibold, track: 7, alpha: 0.92, id: "load", frame: true, padX: 50, padY: 20)

        // poziom komputera
        text("POZIOM KOMPUTERA", x: cx, y: 802, size: 20, weight: .medium, track: 9, alpha: 0.45)
        for (i, l) in AILevel.allCases.enumerated() {
            text(l.title.uppercased(), x: cx + CGFloat(i - 1) * 270, y: 842, size: 32, weight: .semibold, track: 5, alpha: l.rawValue == level ? 1 : 0.65,
                 id: "level:\(l.rawValue)", underline: l.rawValue == level, padY: 8)
        }

        // dolna nawigacja → panele z ustawieniami
        let nav = ["WYGLĄD", "REKORDY", "TURNIEJ", "WYZWANIA", "GRAFIKA", "DŹWIĘK", "O AUTORZE"]
        for (i, n) in nav.enumerated() {
            text(n, x: cx + (CGFloat(i) - 3) * 232, y: 928, size: 26, weight: .medium, track: 5, alpha: 0.75, id: "tab:\(i + 1)", padY: 8)
        }
        return ctx.makeImage()
    }
}

// MARK: - Sterowanie menu z poziomu sceny

extension GameSceneController {
    var clothMenuOn: Bool { Settings.shared.clothMenu && env["BILARD_OLDMENU"] == nil }

    /// punkt na płaszczyźnie sukna (y = 0) pod kursorem
    func cmPoint(_ e: NSEvent) -> V2? { cmPointView(scnView.convert(e.locationInWindow, from: nil)) }
    func cmPointView(_ p: CGPoint) -> V2? {
        let a = scnView.unprojectPoint(SCNVector3(p.x, p.y, 0))
        let b = scnView.unprojectPoint(SCNVector3(p.x, p.y, 1))
        let dy = Double(b.y - a.y)
        if abs(dy) < 1e-9 { return nil }
        let t = -Double(a.y) / dy
        if t < 0 { return nil }
        return V2(Double(a.x) + Double(b.x - a.x) * t, Double(a.z) + Double(b.z - a.z) * t)
    }

    var cmActive: Bool { demo && clothMenuOn && !model.panelOpen }

    func cmMove(_ e: NSEvent) {
        guard cmActive, let m = cmPoint(e) else { return }
        let h = cmUI.hit(x: m.x, z: m.y)
        if env["BILARD_CMDBG"] != nil { let v = scnView.convert(e.locationInWindow, from: nil); let px = cmUI.pixel(x: m.x, z: m.y); NSLog("CMDBG view=%.0f,%.0f size=%.0fx%.0f world=%.3f,%.3f px=%.0f,%.0f hit=%@ L=%.3f W=%.3f", v.x, v.y, scnView.bounds.width, scnView.bounds.height, m.x, m.y, px.x, px.y, h, Phys.halfL, Phys.halfW) }
        if h != cmUI.hover { cmUI.hover = h; NSCursor.current.set(); (h.isEmpty ? NSCursor.arrow : NSCursor.pointingHand).set() }
    }

    func cmClick(_ e: NSEvent) {
        guard cmActive, let m = cmPoint(e) else { return }
        let id = cmUI.hit(x: m.x, z: m.y)
        if !id.isEmpty { cmAct(id) }
    }

    func cmAct(_ id: String) {
        let parts = id.split(separator: ":").map(String.init)
        switch parts[0] {
        case "ai": model.onNewGame(true)
        case "two": model.onNewGame(false)
        case "load": model.menuTab = 0; model.savePicker = 2; model.panelOpen = true
        case "tab": model.savePicker = 0; model.menuTab = Int(parts[1]) ?? 0; model.panelOpen = true
        case "level": Settings.shared.aiLevel = Int(parts[1]) ?? 1
        case "mode":
            if let gm = GameMode(rawValue: parts[1]), gm != gameMode {
                gameMode = gm; model.mode = gm; demoSavedMode = gm
                startDemo()
            }
        default: break
        }
    }

    /// klawisze w menu: Enter = gra z komputerem, Esc zamyka panel
    func cmKey(_ e: NSEvent) -> Bool {
        if e.keyCode == 53, model.panelOpen { model.panelOpen = false; model.savePicker = 0; return true }
        if e.keyCode == 36, !model.panelOpen { model.onNewGame(true); return true }
        return true
    }

    /// co klatkę: widoczność nadruku, podmiana emblematu, odświeżenie obrazu po zmianie stanu
    func cmFrame() {
        if model.clothMenu != clothMenuOn { model.clothMenu = clothMenuOn }
        if let t = env["BILARD_CMTEST"], cmActive, Int(simTime * 2) != cmTestTick, simTime > 3 {   // test: "ułamek x,ułamek y" okna → trafiony element
            cmTestTick = Int(simTime * 2)
            let f = t.split(separator: ",").compactMap { Double($0) }
            if f.count == 2, let m = cmPointView(CGPoint(x: f[0] * scnView.bounds.width, y: (1 - f[1]) * scnView.bounds.height)) {
                let px = cmUI.pixel(x: m.x, z: m.y)
                NSLog("CMTEST world=%.3f,%.3f px=%.0f,%.0f hit=%@", m.x, m.y, px.x, px.y, cmUI.hit(x: m.x, z: m.y))
            }
        }
        if let a = env["BILARD_CMACT"] {      // test: kolejne akcje menu co 5 s, np. "mode:snooker,tab:4,ai"
            let acts = a.split(separator: ",").map(String.init)
            if cmActDone < acts.count, simTime > 4 + 5 * Double(cmActDone) { cmActDone += 1; NSLog("CMACT %@", acts[cmActDone - 1]); cmAct(acts[cmActDone - 1]) }
        }
        if env["BILARD_CONFETTI"] != nil, simTime > 3, confettiNode == nil, cmActDone == 0 { cmActDone = 1; startConfetti(); let t0 = CACurrentMediaTime(); audio.applause(); NSLog("APPLAUSE gen %.0f ms", (CACurrentMediaTime() - t0) * 1000) }   // test
        if env["BILARD_CHTEST"] != nil, simTime > 4, !chTested {   // test wyzwań: symulacja wbić i wygranej
            chTested = true
            let c = Challenges.shared
            c.gameStart(); c.shot(pots: 2, foul: false, human: true); c.shot(pots: 15, foul: false, human: true)
            c.gameEnd(humanWon: true, vsAI: true, level: 1, mode: .nine, tournament: false)
        }
        let show = cmActive
        if cmUI.node.isHidden == show { cmUI.node.isHidden = !show }
        if show {
            table.emblem?.isHidden = true
            cmUI.refresh(mode: gameMode, level: Settings.shared.aiLevel, halfL: Phys.halfL, halfW: Phys.halfW)
        } else if let en = table.emblem {
            let h = Settings.shared.emblemId == "none"
            if en.isHidden != h { en.isHidden = h }
        }
    }
}
