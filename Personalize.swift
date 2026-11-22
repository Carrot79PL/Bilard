import SceneKit
import Cocoa

// MARK: - Zastosowanie personalizacji i ustawień graficznych bez restartu

extension GameSceneController {
    func applyLook() {
        let st = Settings.shared
        TableBuilder.styleCue(table.cue, st.cue)
        styleTable(table)
        let cmNow = clothMenuOn
        if let was = cmUI.prevOn, was != cmNow {          // przełączenie w ustawieniach: demo startuje, panel zostaje otwarty
            if cmNow { if phase == .menu && !demo { demoPending = true }; model.menuTab = 5; model.panelOpen = true } else { model.panelOpen = false }
        }
        cmUI.prevOn = cmNow
        clothNormalBase = 0.55 * st.cloth.weave
        lastClothNormal = -1
        applyBallSet()
    }

    /// sukno, bandy i okucia wg personalizacji (prawdziwy stół i klony na okręgu)
    func styleTable(_ table: TableNodes) {
        let st = Settings.shared
        let cl = st.cloth
        let k = CGFloat(cl.density)
        for m in table.clothMaterials {
            m.multiply.contents = TableBuilder.clothColor()
            let t = SCNMatrix4MakeScale(k, k, 1)
            m.diffuse.contentsTransform = t; m.normal.contentsTransform = t; m.roughness.contentsTransform = t
        }
        if let en = table.emblem {
            let img = Emblems.image(st.emblemId)
            en.isHidden = img == nil
            en.geometry?.firstMaterial?.diffuse.contents = img
        }
        table.cushionMaterial?.multiply.contents = TableBuilder.cushionColor()
        let f = st.finish
        for m in table.railMaterials { TableBuilder.styleRail(m, f) }
        if let fm = table.fitting { TableBuilder.styleFitting(fm, st.pocketFinish) }
    }

    func applyBallSet() {
        let st = Settings.shared
        let set = st.ballSetId
        let w = st.texRes >= 2 ? 2048 : 1024
        let key = "\(set)-\(w)"
        let mats = table.ballMaterials
        let dark = set == "dark"
        let pack0 = TableBuilder.pack
        let metallic = set == "chrome" || set == "gold"
        // odbicia sąsiednich bil w chromie/złocie/szkle: SSR SceneKitu (tylko dla tych zestawów; BILARD_NOSSR=1 wyłącza)
        if let sc = scnView.scene, (metallic || set == "glass" || sc.wantsScreenSpaceReflection) {
            sc.wantsScreenSpaceReflection = (metallic || set == "glass") && env["BILARD_NOSSR"] == nil
            sc.screenSpaceReflectionSampleCount = 24
            sc.screenSpaceReflectionMaximumDistance = 0.6
            sc.screenSpaceReflectionStride = 4
        }
        func assign(_ imgs: [CGImage]) {
            for i in 0..<min(16, mats.count) {
                if Phys.snooker && i >= 1 { continue }
                let m = mats[i]
                m.diffuse.contents = imgs[i]
                m.emission.contents = dark ? imgs[i] : nil
                m.emission.intensity = dark ? 0.9 : 0
                // właściwości materiału zestawu (powrót do żywicy dla klasycznych)
                m.transparencyMode = set == "glass" ? .dualLayer : .default
                if env["BILARD_NOBALLSH"] == nil, let sh = TableBuilder.shaders[set == "pearl" ? "ball_pearl" : "ball_surface"],
                   (m.shaderModifiers?[.surface] ?? "") != sh { m.shaderModifiers = [.surface: sh] }
                if metallic {
                    let maps = TextureFactory.exoticMaps(i, set: set)
                    m.metalness.contents = maps.metal; m.roughness.contents = maps.rough
                    m.normal.intensity = set == "gold" ? 0.15 : 0
                } else {
                    m.metalness.contents = 0.0
                    switch set {
                    case "pearl": m.roughness.contents = 0.16; m.normal.intensity = 0.1
                    case "glass": m.roughness.contents = 0.02; m.normal.intensity = 0
                    case "onyx": m.roughness.contents = 0.07; m.normal.intensity = 0.15
                    default: m.roughness.contents = pack0?.ballRough ?? 0.05; m.normal.intensity = 0.25
                    }
                }
            }
        }
        if let c = ballTexCache[key] { assign(c); return }
        ballSetToken += 1
        let token = ballSetToken
        guard let pack = TableBuilder.pack else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var out = [CGImage?](repeating: nil, count: 16)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: 16) { i in
                let img: CGImage = set == "classic" ? (w >= 2048 ? pack.balls[i] : Gfx.scaled(pack.balls[i], width: w))
                                                    : TextureFactory.ballAlbedo(i, set: set, outW: w)
                lock.lock(); out[i] = img; lock.unlock()
            }
            let imgs = out.map { $0! }
            DispatchQueue.main.async {
                guard let self, token == self.ballSetToken else { return }
                self.ballTexCache[key] = imgs
                assign(imgs)
            }
        }
    }

    /// skala renderowania 3D: część natywnej rozdzielczości (HUD SwiftUI zostaje ostry – osobna warstwa)
    func applyRenderScale() {
        let bs = scnView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let sc = max(0.25, min(1.0, Settings.shared.renderScale))
        scnView.layer?.contentsScale = bs * CGFloat(sc)
        scnView.layer?.magnificationFilter = .linear
        enforceRenderScale()
    }

    /// pilnuje rozmiaru bufora Metal (SceneKit/AppKit potrafią go przywrócić do pełnej rozdzielczości)
    func enforceRenderScale() {
        guard let ml = scnView.layer as? CAMetalLayer else { return }
        let bs = scnView.window?.backingScaleFactor ?? 2
        let sc = CGFloat(max(0.25, min(1.0, Settings.shared.renderScale)))
        let want = CGSize(width: (scnView.bounds.width * bs * sc).rounded(), height: (scnView.bounds.height * bs * sc).rounded())
        if abs(ml.contentsScale - bs * sc) > 0.001 { ml.contentsScale = bs * sc }
        if want.width >= 1 && (abs(ml.drawableSize.width - want.width) > 1 || abs(ml.drawableSize.height - want.height) > 1) {
            ml.drawableSize = want
            if ProcessInfo.processInfo.environment["BILARD_FPS"] != nil { print("SCALE drawable -> \(want)") }
        }
    }

    func applyGraphics() {
        HDRSupport.apply(Settings.shared.hdr, to: scnView)
        applyRenderScale()
        if ProcessInfo.processInfo.environment["BILARD_PLAIN"]?.contains("a") != true { ssaoBase = Settings.shared.ssao ? 0.7 : 0 }
        let st = Settings.shared
        let sizes: [CGFloat] = [512, 512, 1024, 2048], samples = [2, 2, 4, 8]
        // perf: cień rzuca tylko środkowa lampa. Każda mapa cienia to osobny przebieg ~200 tys. trójkątów;
        // 3 mapy = 30 FPS na M2, 1 mapa = 60 FPS. Boczne lampy świecą ×0.015, więc ich cienie były niewidoczne
        // (różnica w kadrze: śr. 0,4/255). BILARD_SH3=1 przywraca 3 cienie.
        for (k, l) in table.lampLights.enumerated() {
            l.castsShadow = st.shadows > 0 && (k == 1 || env["BILARD_SH3"] != nil)
            l.shadowMapSize = CGSize(width: sizes[st.shadows], height: sizes[st.shadows])
            l.shadowSampleCount = samples[st.shadows]
        }
        if let cam = cameraNode.camera {
            cam.bloomIntensity = st.bloom ? 0.04 : 0
            cam.whitePoint = st.hdr ? 1.6 : 2.2          // HDR: szersze światła, mniej ściskania jasnych partii
            cam.wantsDepthOfField = st.dof
        }
        table.shafts.isHidden = !st.dust
        let cc = Double(env["BILARD_CC"] ?? "") ?? 1.0
        for m in table.ballMaterials { m.clearCoat.contents = st.reflections == 0 ? 0.0 : cc }
        if let node = table.probeNode {
            if st.reflections == 2 {
                if node.parent == nil { table.root.addChildNode(node) }
                table.probe = table.probeLight
            } else { node.removeFromParentNode(); table.probe = nil }
        }
        let aniso: CGFloat = [4, 8, 16][min(2, st.texRes == 1 ? 0 : (st.texRes == 2 ? 1 : 2))]
        for m in table.ballMaterials + table.clothMaterials { for p in [m.diffuse, m.normal, m.roughness] { p.maxAnisotropy = aniso } }
        scnView.preferredFramesPerSecond = st.fps
        applyBallSet()
    }

    func saveRecords(winner w: Int) {
        let secs = Date().timeIntervalSince(gameStart)
        for p in 0..<2 {
            RecordStore.shared.record(mode: gameMode, name: rules.name(p), won: w == p, bestBreak: breakBest[p], seconds: secs)
        }
    }
}

extension GameSceneController {
    /// start meczu turniejowego (człowiek na miejscu 0 przy grze z komputerem)
    func startTournamentMatch(_ r: Int, _ i: Int) {
        let ts = TournamentStore.shared
        guard let t = ts.t, let ms = ts.setup(round: r, index: i) else { return }
        Settings.shared.match = ms
        gameMode = GameMode(rawValue: t.mode) ?? .eight
        model.mode = gameMode
        model.faces = ms.faces
        model.showFaces = true
        model.tournamentActive = true
        tourPos = (r, i)
        newGame(vsAI: ms.vsAI)
    }

    func finishTournamentMatch(winner w: Int) {
        guard let (r, i) = tourPos, let ms = Settings.shared.match else { return }
        TournamentStore.shared.report(round: r, index: i, winner: ms.ids[w])
        tourPos = nil
    }
}

enum Gfx {
    static func scaled(_ img: CGImage, width: Int) -> CGImage {
        let h = max(1, img.height * width / max(1, img.width))
        return makeImage(width, h) { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: width, height: h))
        }
    }
}
