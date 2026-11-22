import Cocoa
import SceneKit
import Metal
import SwiftUI
import simd
import Combine

// MARK: - Widok 3D z przekazywaniem zdarzeń

final class GameView: SCNView {
    weak var controller: GameSceneController?
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }
    override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(self); controller?.mouseDown(e) }
    override func mouseDragged(with e: NSEvent) { controller?.mouseDragged(e) }
    override func mouseUp(with e: NSEvent) { controller?.mouseUp(e) }
    override func mouseMoved(with e: NSEvent) { controller?.mouseMoved(e) }
    override func rightMouseDown(with e: NSEvent) { controller?.rightDown(e) }
    override func rightMouseDragged(with e: NSEvent) { controller?.rightDragged(e) }
    override func rightMouseUp(with e: NSEvent) { controller?.rightUp(e) }
    override func scrollWheel(with e: NSEvent) { controller?.scroll(e) }
    override func magnify(with e: NSEvent) { controller?.magnify(e) }
    override func keyDown(with e: NSEvent) { if !(controller?.keyDown(e) ?? false) { super.keyDown(with: e) } }
    override func keyUp(with e: NSEvent) { if !(controller?.keyUp(e) ?? false) { super.keyUp(with: e) } }
    // AppKit przywraca contentsScale przy pełnym ekranie / zmianie monitora – skala renderowania wraca
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); controller?.applyRenderScale() }
    override func layout() { super.layout(); controller?.enforceRenderScale() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in trackingAreas { removeTrackingArea(a) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
}

// MARK: - Kontroler gry

final class GameSceneController: NSObject, SCNSceneRendererDelegate {
    var fpsCount = 0
    var fpsT0 = CACurrentMediaTime()
    var tickCount = 0, tickMs = 0.0, tickMax = 0.0
    var benchDone = false
    var sweepDone = false
    var shownFrames = 0, shownT0 = CACurrentMediaTime()
    var hudChanges = 0
    var hudSink: AnyCancellable?
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        fpsCount += 1
        let n = CACurrentMediaTime()
        shownFrames += 1
        if n - shownT0 >= 0.5 {
            // @Published wolno zmieniać tylko z głównego wątku (ten callback działa na wątku renderowania)
            let show = Settings.shared.showFps
            let t = show ? String(format: "%.0f", Double(shownFrames) / (n - shownT0)) : ""
            DispatchQueue.main.async { [weak self] in
                guard let self, self.model.fpsText != t else { return }
                self.model.fpsText = t
            }
            shownFrames = 0; shownT0 = n
        }
        if n - fpsT0 > 3 {
            if env["BILARD_FPS"] != nil { print(String(format: "FPS %.1f  tick %.0f/s  upd %.2f ms (max %.1f)  phase %@", Double(fpsCount) / (n - fpsT0), Double(tickCount) / (n - fpsT0), tickMs / Double(max(1, tickCount)), tickMax, "\(phase)")); print("  ssao \(self.ssaoBase) hud changes/s \(Double(hudChanges) / (n - fpsT0))"); hudChanges = 0; DispatchQueue.main.async { [weak self] in guard let self, let w = self.scnView.window else { return }; let ml = self.scnView.layer as? CAMetalLayer; print("  key \(w.isKeyWindow) occl \(w.occlusionState.contains(.visible)) drawable \(ml?.drawableSize ?? .zero) maxFPS \(w.screen?.maximumFramesPerSecond ?? 0) aa \(self.scnView.antialiasingMode.rawValue)") } }
            fpsCount = 0; fpsT0 = n; tickCount = 0; tickMs = 0; tickMax = 0
        }
    }
    let scnView: GameView
    let scene = SCNScene()
    let physics = BilliardPhysics()
    var rules: GameModeRules = EightBallRules()
    var gameMode: GameMode = .eight
    let model = GameModel()
    let audio = GameAudio()
    var table: TableNodes
    let cameraNode = SCNNode()
    var rng = SeededGen(s: UInt64(Date().timeIntervalSince1970))

    // stan gry
    var phase: Phase = .menu { didSet { model.phase = phase } }
    var report = ShotReport()
    var aimYaw = 0.0                 // kierunek celowania (x=cos, z=sin)
    var camYawOffset = 0.0
    var camPitch = 0.36
    var camDist = 1.2
    var punch = 0.0            // „kopnięcie” kamery po uderzeniu
    var shake = 0.0
    var introDolly = 0.0
    var cueElev = 0.0
    var lastTurnPlayer = -1          // przy zmianie gracza zerujemy punkt uderzenia i kąt kija
    var ssaoBase = 0.7
    var cueVisElev = 0.0             // nachylenie kija na ekranie (≥ cueElev, omija stół i bile)
    var power = 0.0
    var spaceDown = false
    var spaceHeld = 0.0
    var charging = false
    var rightPull: Double? = nil
    var topBlend = 0.0
    let director = CameraDirector()
    var camSmooth = SmoothCam()
    // pauza: po chwili kamera przechodzi w zbliżenia na bile
    var pauseTestDone = false
    var aimYawTestOff = 0.0
    var pauseT = 0.0, pauseCineT = 0.0, pauseWasCine = false
    var pauseSmooth = SmoothCam()
    var camSmoothT = 0.09
    let recorder = ReplayRecorder()
    let trace = ShotTrace()
    var shotClock = 0.0
    var replaying = false
    var replayT = 0.0, replayPrevT = 0.0, replayCursor = 0, replayRate = 1.0
    var replayDec: ReplayDecision? = nil
    var replayCont: (() -> Void)? = nil
    var replaySaved: [Ball] = []
    var replayTopSaved = false
    var replayHitCursor = 0, replayPockCursor = 0
    var follow = 0.0                 // 0 = kamera przy kiju, 1 = przegląd stołu
    var menuAngle = 0.0
    var strikeT = 0.0
    var cueAlpha = 0.0
    var simTime = 0.0
    var lastTime = CACurrentMediaTime()
    var ballInHand = false
    var placingBreak = false
    var hoverPoint: V2? = nil
    var drops: [Int: (t: Double, from: V2, to: V2)] = [:]
    var smoothFocus = V3(0, 0, 0)
    var shotOff = V2(0, 0)           // zapamiętane na czas uderzenia
    var shotPower = 0.0
    var shotElev = 0.0
    var displayLink: CADisplayLink?

    // AI
    var aiStage = -1
    var aiT = 0.0
    var aiShot: AIShot? = nil
    var aiStartYaw = 0.0

    // linie celowania
    var lineMain = SCNNode(), lineTarget = SCNNode(), lineCue = SCNNode(), lineBounce = SCNNode()
    var gradeRep = 0.0
    var saveTestT = 0.0, saveTestN = 0
    var ghost = SCNNode()
    let aimInd = AimIndicator()

    // test / tryb automatyczny
    let env = ProcessInfo.processInfo.environment
    var autoplay = false
    var logLines = 0

    // tryb demo (attract mode): mecz AI vs AI filmowany kamerą TV
    let tv = TVCamera()
    var demo = false
    var demoPending = false
    var demoT = 0.0
    var demoOverT = 0.0
    var demoSavedMode: GameMode? = nil
    var demoFocus: (ball: Int?, pocket: Int?) = (nil, nil)
    let fx = ChalkRackState()
    var chalkTested = false
    let rig = SCNNode()                 // stół + kamera + nakładki (tożsamość; zostawione po próbie menu z okręgiem)
    var suspendedPhase: Phase? = nil   // „Wznów grę”: faza gry zawieszonej wyjściem do menu
    var resumeTestT = 0.0, resumeTestN = 0

    init(frame: CGRect) {
        Phys.modelTable = Settings.shared.tableModelId == "model"
        Phys.configure(snooker: false)
        scnView = GameView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        table = TableNodes()
        super.init()
        scnView.controller = self
        scnView.scene = scene
        scnView.delegate = self
        scnView.antialiasingMode = ProcessInfo.processInfo.environment["BILARD_AA"] == "0" ? .none : .multisampling4X
        scnView.preferredFramesPerSecond = 60
        scnView.rendersContinuously = true
        scnView.backgroundColor = nsc(0x0B0A0C)
        scnView.allowsCameraControl = false
        scnView.wantsLayer = true
    }

    var ready = false
    var tourPos: (Int, Int)? = nil
    var fliers = Set<Int>()           // bile lecące poza stół (animacja)
    var clothNormalBase: Double = 0.55
    var gameStart = Date()
    var breakBest = [0, 0]
    var ballTexCache: [String: [CGImage]] = [:]
    var ballSetToken = 0
    // deklaracja (Call Shot)
    var callBall: Int? = nil
    var callPocket: Int? = nil
    var callRingBall = SCNNode(), callRingPocket = SCNNode(), callLine = SCNNode()

    func makeCallNodes() {
        func mat(_ c: NSColor) -> SCNMaterial {
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = c; m.emission.contents = c
            m.writesToDepthBuffer = false; m.readsFromDepthBuffer = false
            return m
        }
        let amber = nsc(0xFFC93C)
        let t1 = SCNTorus(ringRadius: 0.04, pipeRadius: 0.0022); t1.materials = [mat(amber)]
        callRingBall = SCNNode(geometry: t1)
        let t2 = SCNTorus(ringRadius: 0.06, pipeRadius: 0.0045); t2.materials = [mat(amber)]
        callRingPocket = SCNNode(geometry: t2)
        let c = SCNCylinder(radius: 0.0012, height: 1); c.radialSegmentCount = 6; c.materials = [mat(nsc(0xFFC93C, 0.55))]
        callLine = SCNNode(geometry: c)
        for n in [callRingBall, callRingPocket, callLine] {
            n.renderingOrder = 105; n.castsShadow = false; n.isHidden = true
            rig.addChildNode(n)
        }
    }

    static let pocketNames = ["bliska lewa", "bliska prawa", "daleka lewa", "daleka prawa", "boczna lewa", "boczna prawa"]
    func updateCallText() {
        model.callBall = callBall; model.callPocket = callPocket
        model.needsCall = rules.needsCall
        guard rules.needsCall else { model.callText = ""; return }
        if let b = callBall, let p = callPocket { model.callText = "Deklaracja: bila \(b) → łuza \(Self.pocketNames[p])" }
        else if let b = callBall { model.callText = "Bila \(b) · teraz kliknij łuzę" }
        else { model.callText = "Zadeklaruj: kliknij bilę, potem łuzę" }
    }

    func updateCallVisuals() {
        let active = rules.needsCall && (phase == .aiming || phase == .striking || phase == .rolling)
        let pulse = 1 + 0.08 * sin(simTime * 5)
        if active, let b = callBall, physics.balls[b].active {
            let p = physics.balls[b].p
            callRingBall.isHidden = false
            (callRingBall.geometry as? SCNTorus)?.ringRadius = CGFloat(Phys.R * 1.5 * pulse)
            callRingBall.simdPosition = SIMD3<Float>(Float(p.x), Float(0.003), Float(p.y))
            if let k = callPocket {
                let pk = BilliardPhysics.pockets[k]
                callRingPocket.isHidden = false
                (callRingPocket.geometry as? SCNTorus)?.ringRadius = CGFloat(pk.r * 0.8 * pulse)
                callRingPocket.simdPosition = SIMD3<Float>(Float(pk.c.x), Float(TableBuilder.railTop + 0.006), Float(pk.c.y))
                placeLine(callLine, p, pk.c)
            } else { callRingPocket.isHidden = true; callLine.isHidden = true }
        } else { callRingBall.isHidden = true; callRingPocket.isHidden = true; callLine.isHidden = true }
    }

    func pocketNameOf(_ i: Int) -> String { Self.pocketNames[min(i, 5)] }

    /// zmiana geometrii stołu (pool 9 ft ↔ snooker 12 ft) bez restartu aplikacji
    func applyGeometry(for mode: GameMode) {
        let want = mode == .snooker, wantModel = Settings.shared.tableModelId == "model"
        guard want != Phys.snooker || wantModel != Phys.modelTable, ready else { return }
        Phys.modelTable = wantModel
        Phys.configure(snooker: want)
        table.root.removeFromParentNode()
        table = TableBuilder.build(blueCloth: model.blueCloth, pack: TableBuilder.pack, applied: true)
        rig.addChildNode(table.root)
        table.cue.isHidden = true
        applyLook(); applyGraphics()
        (ghost.geometry as? SCNSphere)?.radius = CGFloat(Phys.R)
        drops.removeAll()
        camDist = want ? 1.5 : 1.2
    }

    /// podgląd stołu wybranego trybu w menu
    func previewMode() {
        guard suspendedPhase == nil else { return }    // zawieszona gra: stół i bile bez zmian
        applyGeometry(for: gameMode)
        resetChalkRack()
        guard phase == .menu else { return }
        GameConfig.target = model.target
        rules = gameMode.makeRules()
        rules.reset(vsAI: true)
        physics.rack(seed: UInt64(Date().timeIntervalSince1970 * 1000), rules: rules)
        for (i, n) in table.balls.enumerated() { n.isHidden = !physics.balls[i].active; n.opacity = 1 }
        syncNodes()
    }

    func buildScene(_ pack: TexturePack) {
        table = TableBuilder.build(blueCloth: model.blueCloth, pack: pack)
        scene.rootNode.addChildNode(rig)
        makeCallNodes()
        rig.addChildNode(table.root)
        if env["BILARD_DUMP"] != nil {   // diagnostyka: geometrie leżące w pobliżu płaszczyzny sukna (z-fighting)
            table.root.enumerateHierarchy { n, _ in
                guard let g = n.geometry else { return }
                let (mn, mx) = n.boundingBox
                var lo = Double.infinity, hi = -Double.infinity
                for x in [mn.x, mx.x] { for y in [mn.y, mx.y] { for z in [mn.z, mx.z] {
                    let w = n.convertPosition(SCNVector3(x, y, z), to: nil); lo = min(lo, Double(w.y)); hi = max(hi, Double(w.y)) } } }
                if lo < 0.012 && hi > -0.03 && n.name != "cloth" || n.name == "cloth" { print("DUMP \(n.name ?? "-") \(type(of: g)) y=[\(String(format: "%.4f", lo)), \(String(format: "%.4f", hi))] w=\(String(format: "%.2f", mx.x - mn.x))x\(String(format: "%.2f", mx.y - mn.y))x\(String(format: "%.2f", mx.z - mn.z)) hidden=\(n.isHidden)") }
            }
        }
        TableBuilder.configureEnvironment(scene)

        // kamera: HDR, tone mapping, bloom
        let cam = SCNCamera()
        cam.zNear = 0.02; cam.zFar = 30
        cam.fieldOfView = 40
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = CGFloat(Double(ProcessInfo.processInfo.environment["BILARD_EXPO"] ?? "") ?? 0)
        cam.minimumExposure = -4; cam.maximumExposure = 2
        cam.whitePoint = 2.2
        cam.contrast = 0.08
        cam.saturation = 1.12
        cam.bloomIntensity = 0.04
        cam.bloomThreshold = 1.4
        cam.bloomBlurRadius = 9
        cam.vignettingIntensity = 0.32          // delikatna winieta
        cam.vignettingPower = 0.55
        cam.wantsDepthOfField = false   // ostre jak na zrzutach referencyjnych
        cam.fStop = 2.8
        cam.focalLength = 50
        cam.focalSize = 0.5
        cam.focalBlurSampleCount = 10
        cam.motionBlurIntensity = 0
        cam.categoryBitMask = 0xFFFF_FFFB
        cam.screenSpaceAmbientOcclusionIntensity = CGFloat(ssaoBase)     // AO w załamaniach band i pod bilami
        cam.screenSpaceAmbientOcclusionRadius = 0.08
        cam.screenSpaceAmbientOcclusionBias = 0.02
        cam.screenSpaceAmbientOcclusionDepthThreshold = 0.015
        cam.screenSpaceAmbientOcclusionNormalThreshold = 0.5
        if let m = ProcessInfo.processInfo.environment["BILARD_PLAIN"] {   // diagnostyka post-procesu
            if m.contains("a") { ssaoBase = 0 }
            if m.contains("b") { cam.bloomIntensity = 0 }
            if m.contains("h") { cam.wantsHDR = false }
        }
        cameraNode.camera = cam
        rig.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        // linie celowania i duch bili
        func mkLine(_ color: NSColor, _ r: CGFloat) -> SCNNode {
            let c = SCNCylinder(radius: r, height: 1)
            c.radialSegmentCount = 8
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = color; m.emission.contents = color
            m.writesToDepthBuffer = false; m.readsFromDepthBuffer = false
            c.materials = [m]
            let n = SCNNode(geometry: c); n.renderingOrder = 100; n.castsShadow = false
            rig.addChildNode(n)
            return n
        }
        lineMain = mkLine(nsc(0xFF4A3A, 0.9), 0.0011)
        lineTarget = mkLine(nsc(0xFFFFFF, 0.85), 0.0011)
        lineCue = mkLine(nsc(0x7FD0FF, 0.8), 0.0009)
        lineBounce = mkLine(nsc(0xFF4A3A, 0.4), 0.0008)
        let gs = SCNSphere(radius: Phys.R)
        let gm = SCNMaterial(); gm.lightingModel = .constant
        gm.diffuse.contents = nsc(0xFFFFFF, 0.28); gm.transparency = 0.5; gm.isDoubleSided = true
        gm.writesToDepthBuffer = false
        gs.materials = [gm]
        ghost = SCNNode(geometry: gs)
        ghost.castsShadow = false
        ghost.renderingOrder = 101
        rig.addChildNode(ghost)

        rig.addChildNode(aimInd.root)

        // callbacki HUD
        model.onShoot = { [weak self] in self?.humanShoot() }
        model.ballGeometry = { [weak self] id in (self?.table.balls.indices.contains(id) ?? false) ? self?.table.balls[id].geometry : nil }
        model.onToggleView = { [weak self] in self?.toggleView() }
        model.onChalk = { [weak self] in if self?.humanTurn == true { self?.startChalking() } }
        model.onCycleCamera = { [weak self] in self?.cycleCamera() }
        model.onResume = { [weak self] in self?.resumeGame() }
        model.onNewGame = { [weak self] ai in
            self?.discardSuspended()
            Settings.shared.match = nil; self?.model.showFaces = false; self?.model.tournamentActive = false; self?.tourPos = nil
            self?.newGame(vsAI: ai)
        }
        model.onStartMatch = { [weak self] r, i in self?.discardSuspended(); self?.startTournamentMatch(r, i) }
        model.onSelectMode = { [weak self] m in if m != self?.gameMode { self?.discardSuspended() }; self?.gameMode = m; self?.model.mode = m; self?.previewMode() }
        model.onSetTarget = { [weak self] t in self?.model.target = t; GameConfig.target = t }
        model.onToggleCloth = { [weak self] in self?.toggleCloth() }
        model.onBackToMenu = { [weak self] in self?.backToMenu() }
        model.onSaveGame = { [weak self] i in self?.saveGame(slot: i) ?? false }
        model.onLoadGame = { [weak self] i in self?.loadGame(slot: i) }
        model.onReposition = { [weak self] in self?.beginReposition() }

        physics.rack(seed: UInt64(Date().timeIntervalSince1970 * 1000), rules: rules)
        syncNodes()
        setLinesVisible(false)
        table.cue.isHidden = true
        phase = .menu
        model.names = [rules.name(0), rules.name(1)]
        let st = Settings.shared
        st.onLook = { [weak self] in self?.applyLook() }
        st.onGraphics = { [weak self] in self?.applyGraphics() }
        st.onAudio = { [weak self] in self?.audio.apply(st) }
        audio.apply(st)
        applyLook(); applyGraphics()
        ready = true
    }

    func start() {
        if env["BILARD_FPS"] != nil { hudSink = model.objectWillChange.sink { [weak self] _ in self?.hudChanges += 1 } }
        let link = scnView.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTime = CACurrentMediaTime()
    }

    // MARK: Nowa gra / menu

    func newGame(vsAI: Bool) {
        guard ready else { return }
        applyGeometry(for: gameMode)
        resetChalkRack()
        GameConfig.target = model.target
        rules = gameMode.makeRules()
        rules.reset(vsAI: vsAI)
        callBall = nil; callPocket = nil
        model.mode = gameMode
        physics.rack(seed: UInt64(Date().timeIntervalSince1970 * 1000) &+ 17, rules: rules)
        drops.removeAll()
        model.names = [rules.name(0), rules.name(1)]
        gameStart = Date(); breakBest = [0, 0]
        scnView.window?.makeFirstResponder(scnView)
        model.groups = rules.groups
        syncModel()
        model.current = 0
        lastTurnPlayer = -1
        model.pocketed = []
        model.winner = nil
        model.vsAI = vsAI
        model.message = "Rozbicie – \(rules.name(0))"
        report = ShotReport()
        ballInHand = false
        syncNodes()
        for (i, n) in table.balls.enumerated() { n.isHidden = !physics.balls[i].active; n.opacity = 1 }
        table.chalkMarks.forEach { $0.removeFromParentNode() }; table.chalkMarks.removeAll()
        aimYaw = 0; camYawOffset = 0
        startRackAnimation()
        beginTurn()
        if let p = env["BILARD_CAM"], let i = Int(p), let pr = CamPreset(rawValue: i) { director.preset = pr; model.cameraName = pr.title }
        if !autoplay && env["BILARD_NOINTRO"] == nil && env["BILARD_TOP"] == nil { director.startIntro() }
        if env["BILARD_TOP"] != nil { model.topView = true }
    }

    // MARK: Tryb demo (attract mode)

    func startDemo() {
        guard ready else { demoPending = true; return }
        if demoSavedMode == nil { demoSavedMode = gameMode }
        demo = true; model.demo = true
        autoplay = false
        demoT = 0; demoOverT = 0; demoFocus = (nil, nil)
        gameMode = [GameMode.eight, .nine, .eight, .ten].randomElement() ?? .eight
        tv.log = env["BILARD_TVLOG"] != nil || env["BILARD_DEMO_SECS"] != nil
        tv.reset()
        audio.setQuiet(true)
        model.topView = false
        newGame(vsAI: true)
        director.cancelCine(); director.skipIntro()
        if tv.log { print("DEMO start \(gameMode.rawValue)") }
    }

    func updateDemo(_ dt: Double) {
        demoT += dt
        if let n = Double(env["BILARD_DEMO_SECS"] ?? ""), demoT > n { endDemo(); return }
        if phase == .gameOver {
            demoOverT += dt
            if demoOverT > 3.5 { if tv.log { print("DEMO nowy mecz") }; startDemo() }
        }
        if phase == .striking || phase == .rolling { } else { demoFocus = (nil, nil) }
    }

    /// wyjście z demo do menu: bez śladów (model, reguły, wyniki, kamera, dźwięk)
    func endDemo() {
        guard demo else { return }
        demo = false; model.demo = false
        suspendedPhase = nil; model.canResume = false
        audio.setQuiet(false)
        if replaying { replaying = false; director.replayActive = false; model.replayLabel = nil }
        aiStage = -1; aiShot = nil; model.thinking = false
        power = 0; model.power = 0; spaceDown = false; charging = false
        callBall = nil; callPocket = nil; ballInHand = false; model.ballInHand = false
        drops.removeAll(); demoFocus = (nil, nil); physicsStruck = false; settleTimer = 0
        resetChalkRack()
        table.chalkMarks.forEach { $0.removeFromParentNode() }; table.chalkMarks.removeAll()
        cueVisElev = 0; cueElev = 0; shotElev = 0; shake = 0; punch = 0; follow = 0
        if let m = demoSavedMode { gameMode = m }
        model.mode = gameMode
        demoSavedMode = nil
        model.winner = nil; model.message = ""; model.pocketed = []
        phase = .menu
        previewMode()          // świeże reguły i ustawienie bil trybu wybranego w menu
        syncModel()
        model.names = [rules.name(0), rules.name(1)]
        model.current = 0
        model.topView = false
        table.cue.isHidden = true
        setLinesVisible(false)
        camSmooth = SmoothCam()
        if tv.log { print("DEMO end -> menu") }
    }

    /// wyjście do menu KOŃCZY grę (zawieszenia nie ma; zapis robi się z pauzy)
    func backToMenu() {
        let playing = !demo && [Phase.aiming, .placing, .striking, .rolling].contains(phase)
        if playing || (model.phase != .gameOver && !demo) {
            suspendedPhase = nil; model.canResume = false
            clearMatch()
            if replaying { replaying = false; director.replayActive = false; model.replayLabel = nil }
            aiStage = -1; aiShot = nil; model.thinking = false
            power = 0; model.power = 0; spaceDown = false; charging = false
            callBall = nil; callPocket = nil; ballInHand = false; model.ballInHand = false
            drops.removeAll(); physicsStruck = false; settleTimer = 0
            resetChalkRack()
            table.chalkMarks.forEach { $0.removeFromParentNode() }; table.chalkMarks.removeAll()
            cueElev = 0; cueVisElev = 0; shotElev = 0; shake = 0; punch = 0; follow = 0
            model.winner = nil; model.pocketed = []; model.topView = false
            phase = .menu
            previewMode()
            syncModel()
            model.names = [rules.name(0), rules.name(1)]
            model.current = 0
            camSmooth = SmoothCam()
        }
        model.paused = false
        phase = .menu
        model.message = ""
        table.cue.isHidden = true
        setLinesVisible(false)
    }

    func clearMatch() { Settings.shared.match = nil; model.showFaces = false; model.tournamentActive = false; tourPos = nil }

    /// porzucenie zawieszonej gry (nowa gra, mecz turnieju, zmiana trybu, demo)
    func discardSuspended() {
        guard suspendedPhase != nil || model.canResume else { return }
        suspendedPhase = nil; model.canResume = false
        clearMatch()
    }

    /// powrót do zawieszonej gry: stół do środka sali, kamera zjeżdża do widoku gry
    func resumeGame() {
        guard let ph = suspendedPhase, ready else { return }
        model.mode = gameMode
        applyGeometry(for: gameMode)
        suspendedPhase = nil; model.canResume = false
        phase = ph
        scnView.window?.makeFirstResponder(scnView)
        if env["BILARD_RESUMETEST"] != nil { print("RESUME -> \(ph)") }
    }

    /// test „Wznów grę” (BILARD_RESUMETEST): po 6 s gry wyjście do menu, po 3 s powrót; gra ma dojść do KONIEC
    func resumeTest(_ dt: Double) {
        resumeTestT += dt
        if resumeTestN == 0 && phase != .menu && resumeTestT > 6 {
            resumeTestN = 1; resumeTestT = 0
            let p = phase; backToMenu()
            print("RESUME suspend \(p) canResume=\(model.canResume) balls=\(physics.balls.filter { $0.active }.count)")
        } else if resumeTestN == 1 && phase == .menu && resumeTestT > 3 {
            resumeTestN = 2
            print("RESUME balls=\(physics.balls.filter { $0.active }.count)")
            resumeGame()
        }
    }

    func toggleCloth() {
        let all = ClothDef.all
        let i = all.firstIndex { $0.id == Settings.shared.clothId } ?? 0
        Settings.shared.clothId = all[(i + 1) % all.count].id     // didSet → applyLook()
    }

    // MARK: Tura

    /// karta „cel”: co wbijać (bile 3D + opis) dla gracza na ruchu
    func updateTargetInfo() {
        let p = rules.current
        var ids = rules.legalTargets(p).filter { $0 < physics.balls.count && physics.balls[$0].active }
        var title = "", sub = ""
        switch gameMode {
        case .eight:
            if let g = rules.groups[p] {
                if ids == [8] { title = "Czarna 8"; sub = "wbij ją w łuzę – wygrywasz" }
                else { title = g.name; sub = "zostało \(ids.count) do wbicia" }
            } else {
                let solid = ids.first { $0 < 8 }, stripe = ids.first { $0 > 8 }
                ids = [solid, stripe].compactMap { $0 }
                title = "Stół otwarty"; sub = "pełne albo połówki – bez czarnej"
            }
        case .nine, .ten:
            title = ids.first.map { "Bila \($0)" } ?? "—"
            sub = rules.needsCall ? "najniższa · deklaruj bilę i łuzę" : "najniższa na stole"
        case .straight:
            ids = []; title = "Dowolna bila"; sub = "deklaruj bilę i łuzę"
        case .snooker:
            if ids.count == 1, ids[0] > 15 { title = SnookerLayout.names[ids[0]]?.capitalized ?? "Kolor"; sub = "kolory w kolejności" }
            else if ids.allSatisfy({ $0 <= 15 }) { ids = Array(ids.prefix(1)); title = "Czerwona"; sub = "potem dowolny kolor" }
            else { title = "Kolor"; sub = "wybierz dowolny" }
        }
        model.targetIDs = ids; model.targetTitle = title; model.targetSub = sub
        model.targetWho = model.names.indices.contains(p) ? model.names[p] : ""
    }

    func syncModel() {
        updateTargetInfo()
        model.groups = rules.groups
        model.pocketed = rules.pocketed
        model.hints = [rules.targetHint(0), rules.targetHint(1)]
        model.scores = rules.scores
        model.tableCount = rules.tableCount
        model.curBreak = rules.currentBreak
        model.highBreak = rules.highBreak
        model.target = rules.target > 0 ? rules.target : model.target
        updateCallText()
    }

    func beginTurn() {
        model.current = rules.current
        if rules.current != lastTurnPlayer {
            model.spin = .zero; model.elevation = 0; cueElev = 0
            lastTurnPlayer = rules.current
        }
        if let sp = env["BILARD_SPIN"] {          // test: punkt uderzenia „x,y”[,elewacja°]
            let c = sp.split(separator: ",").compactMap { Double($0) }
            if c.count >= 2 { model.spin = CGPoint(x: c[0], y: c[1]) }
            if c.count >= 3 { model.elevation = c[2] }
            if c.count >= 4 { aimYawTestOff = c[3] * .pi / 180 }
        }
        callBall = nil; callPocket = nil
        syncModel()
        power = 0; model.power = 0
        let ai = rules.isAI(rules.current) || autoplay || demo
        if physics.balls[0].active == false { respawnCue() }
        if ballInHand && !ai {
            phase = .placing
            model.topView = true
            hoverPoint = physics.balls[0].p
            table.balls[0].isHidden = false
        } else {
            phase = .aiming
            if ballInHand { /* AI ustawi białą sama */ }
            if !ai { model.topView = model.topView && false || model.topView }
        }
        model.ballInHand = ballInHand
        model.chalk = fx.level[rules.current]
        if ai && !autoplay && phase == .aiming && fx.level[rules.current] < 0.45 { DispatchQueue.main.async { [weak self] in self?.startChalking() } }
        if !ai && !autoplay && fx.level[rules.current] < 0.35 { model.message = "Mało kredy – naciśnij K, aby zatrzeć kij" }
        if ai {
            aiStage = 0; aiT = 0; aiShot = nil
            model.thinking = true
        } else {
            aiStage = -1
            model.thinking = false
            // kierunek startowy: w stronę najbliższej bili docelowej
            let cue = physics.balls[0].p
            let targets = rules.legalTargets(rules.current).filter { physics.balls[$0].active }
            if let t = targets.min(by: { simd_length(physics.balls[$0].p - cue) < simd_length(physics.balls[$1].p - cue) }) {
                let d = physics.balls[t].p - cue
                aimYaw = atan2(d.y, d.x)
            }
        }
        aimYaw += aimYawTestOff; aimYawTestOff = 0
        camYawOffset = 0
        // każda tura startuje z domyślnej kamery (za kijem, auto, bez widoku z góry poza ustawianiem białej)
        camPitch = 0.36; camDist = Phys.snooker ? 1.5 : 1.2
        if director.preset != .auto { director.preset = .auto; model.cameraName = director.preset.title }
        director.cancelCine()
        if phase != .placing { model.topView = false }
        if !autoplay && !demo && isMatchBall() { director.startMatchBall() }
    }

    /// czy na stole zostaje już tylko bila decydująca o wygranej, w którą gracz musi celować
    func isMatchBall() -> Bool {
        let t = rules.legalTargets(rules.current).filter { physics.balls[$0].active }
        guard t.count == 1 else { return false }
        switch rules.mode {
        case .eight: return t[0] == 8
        case .nine: return t[0] == 9
        case .ten: return t[0] == 10
        case .snooker: return rules.tableCount <= 1
        default: return false
        }
    }

    /// diagnostyka mrugania: ⌥1…⌥6 wyłączają kolejno elementy sceny
    var dbg = [Bool](repeating: false, count: 6)
    func debugToggle(_ i: Int) {
        dbg[i].toggle()
        let on = dbg[i]
        let names = ["nakładki sukna", "cienie kontaktowe", "cienie świateł", "SSAO + bloom", "wygładzanie MSAA", "sukno jednolite"]
        switch i {
        case 0: table.decals.forEach { $0.isHidden = on }
        case 1: break
        case 2: for (k, l) in table.lampLights.enumerated() where k == 1 || env["BILARD_SH3"] != nil { l.castsShadow = !on }
        case 3: ssaoBase = on ? 0 : 0.7; cameraNode.camera?.bloomIntensity = on ? 0 : 0.04
        case 4: scnView.antialiasingMode = on ? .none : .multisampling4X
        default: break
        }
        model.message = "DIAG ⌥\(i + 1): \(names[i]) – \(i == 5 ? (on ? "WŁ." : "wył.") : (on ? "WYŁĄCZONE" : "włączone"))"
    }

    // MARK: Powtórki

    func evaluateReplay(out: ShotOutcome, shooter: Int) -> ReplayDecision? {
        if demo { return nil }
        var mode = model.replayMode
        if autoplay {
            guard let e = env["BILARD_REPLAY"] else { return nil }
            mode = e == "all" ? .all : .key
        }
        guard recorder.count > 4 else { return nil }
        return ShotEvaluator.evaluate(trace, out: out, shooter: shooter, mode: mode, isBreak: rules.breakShot,
                                      winnerIsShooter: out.winner == shooter)
    }

    func startReplay(_ d: ReplayDecision, then cont: @escaping () -> Void) {
        replayDec = d; replayCont = cont
        replaySaved = physics.balls            // jedna kopia na powtórkę (poza pętlą fizyki)
        drops.removeAll()
        replayT = max(d.startT, recorder.firstT); replayPrevT = replayT - 0.001
        replayCursor = 0; replayHitCursor = 0; replayPockCursor = 0
        while replayHitCursor < trace.nHits && trace.hitT[replayHitCursor] < replayT { replayHitCursor += 1 }
        while replayPockCursor < trace.nPockets && trace.pT[replayPockCursor] < replayT { replayPockCursor += 1 }
        replaying = true
        replayTopSaved = model.topView; model.topView = false
        director.cancelCine(); director.replayActive = true
        director.replayPocket = d.pocketIdx; director.replayPhase = 0
        model.replayLabel = d.label
        audio.setRolling(0)
        if autoplay { print("REPLAY start \(d.label) key=\(String(format: "%.2f", d.keyT)) from=\(String(format: "%.2f", d.startT))") }
    }

    func updateReplay(_ dt: Double) {
        guard let d = replayDec else { endReplay(); return }
        // slow-motion 0,25× wokół chwili wbicia
        let near = max(0, 1 - abs(replayT - d.keyT) / 0.7)
        let target = 0.55 - 0.40 * (near * near * (3 - 2 * near))        // ogólnie zwolnione (0,55×), przy wbiciu 0,15×
        replayRate += (target - replayRate) * (1 - exp(-dt * 14))
        replayPrevT = replayT
        replayT += dt * replayRate * (autoplay ? 4 : 1)
        if replayT >= min(d.endT, recorder.lastT + 0.5) { endReplay(); return }
        recorder.sample(at: min(replayT, recorder.lastT), cursor: &replayCursor, into: &physics.balls)
        // zdarzenia z zapisu: dźwięk zderzeń, wpadanie bil do łuz
        while replayHitCursor < trace.nHits && trace.hitT[replayHitCursor] <= replayT {
            audio.ballHit(speed: trace.hitSpeed[replayHitCursor], at: trace.hitPos[replayHitCursor]); replayHitCursor += 1
        }
        while replayPockCursor < trace.nPockets && trace.pT[replayPockCursor] <= replayT {
            let k = replayPockCursor
            let pk = BilliardPhysics.pockets[min(trace.pIdx[k], BilliardPhysics.pockets.count - 1)]
            drops[trace.pBall[k]] = (0, trace.pPos[k], pk.c)
            audio.pocket(at: pk.c)
            replayPockCursor += 1
        }
        let fb = physics.balls[d.focusBall]
        director.replayFocus = V3(fb.active ? fb.p.x : trace.pPos[0].x, Phys.R, fb.active ? fb.p.y : trace.pPos[0].y)
        director.replayPhase = CameraDirector.smooth((replayT - (d.keyT - 1.4)) / 1.0)
    }

    func endReplay() {
        guard replaying else { return }
        replaying = false
        director.replayActive = false
        model.replayLabel = nil
        if autoplay { print("REPLAY end") }
        physics.balls = replaySaved
        drops.removeAll()
        for (i, n) in table.balls.enumerated() where i < Phys.nBalls { n.isHidden = !physics.balls[i].active; n.opacity = 1 }
        model.topView = replayTopSaved
        syncNodes()
        let cont = replayCont; replayCont = nil; replayDec = nil
        cont?()
    }

    func cycleCamera() {
        guard phase != .menu else { return }
        model.topView = false
        model.cameraName = director.cycle().title
    }

    func respawnCue() {
        var p = rules.cueSpot
        var k = 0
        while !physics.isFree(p, ignoring: 0, margin: 0.004) && k < 40 { p.y = (k % 2 == 0 ? 1 : -1) * 0.07 * Double(k / 2 + 1); k += 1 }
        physics.balls[0].p = p
        physics.balls[0].v = V2(0, 0); physics.balls[0].w = V3(0, 0, 0)
        physics.balls[0].active = true
        table.balls[0].isHidden = false
        table.balls[0].opacity = 1
        syncNodes()
    }

    func beginReposition() {
        guard phase == .aiming, !(rules.isAI(rules.current)) else { return }
        // przy zwykłym rozbiciu wolno przestawić białą w „kuchni”
        ballInHand = true
        placingBreak = rules.breakShot
        model.ballInHand = true
        phase = .placing
        model.topView = true
        hoverPoint = physics.balls[0].p
    }

    // MARK: Pętla

    @objc func tick(_ link: CADisplayLink) {
        guard ready else { lastTime = CACurrentMediaTime(); return }
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - lastTime)
        lastTime = now
        simTime += dt
        let t0 = CACurrentMediaTime()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        update(dt)
        SCNTransaction.commit()
        let ms = (CACurrentMediaTime() - t0) * 1000
        tickCount += 1; tickMs += ms; tickMax = max(tickMax, ms)
        if env["BILARD_JITTER"] != nil, simTime > 7, !jitterDone { jitterDone = true; jitterTest(); exit(0) }
        if let shot = env["BILARD_SHOT"], simTime > (Double(env["BILARD_SHOT_AT"] ?? "") ?? 4.0), !shotTaken {
            shotTaken = true
            // test: zbliżenie łuzy (BILARD_LOOK=pocket – narożna, side – boczna)
            if env["BILARD_LOOK"] == "end" {      // test: krótki bok stołu, nisko z ukosa (krawędzie sukna, spód ramy)
                let r = table.root
                cameraNode.worldPosition = r.convertPosition(SCNVector3(Phys.halfL + 1.6, -0.22, Phys.halfW + 0.9), to: nil)
                cameraNode.look(at: r.convertPosition(SCNVector3(Phys.halfL, -0.05, 0.1), to: nil))
            }
            if let lk = env["BILARD_LOOK"], let p = BilliardPhysics.pockets.first(where: { $0.side == (lk == "side") && $0.c.x >= 0 && $0.c.y > 0 }) {
                let r = table.root, c = SCNVector3(p.c.x, -0.01, p.c.y)
                let eye = lk == "side" ? SCNVector3(c.x + 0.12, 0.20, c.z - 0.34) : SCNVector3(c.x - 0.30, 0.22, c.z - 0.22)
                cameraNode.position = r.convertPosition(eye, to: nil)
                cameraNode.look(at: r.convertPosition(c, to: nil))
            }
            let img = scnView.snapshot()
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: shot))
            }
            print("SHOT saved \(shot) api=\(scnView.renderingAPI.rawValue) size=\(scnView.bounds.size) scale=\(scnView.window?.backingScaleFactor ?? 0)")
            if env["BILARD_KEEP"] == nil { exit(0) }
        }
    }
    var shotTaken = false
    var debugCamShift = 0.0
    var jitterDone = false
    /// diagnostyka: kilka klatek z podpikselowo przesuniętą kamerą; mierzy zmienność sukna (powinna być ≈ 0 na jednolitym suknie)
    func jitterTest() {
        var frames: [[UInt8]] = []
        var w = 0, h = 0
        for k in 0..<8 {
            debugCamShift = Double(k) * 0.0004
            updateCamera(0.016)
            SCNTransaction.flush()
            let img = scnView.snapshot()
            guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            w = cg.width; h = cg.height
            var buf = [UInt8](repeating: 0, count: w * h)
            let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            frames.append(buf)
        }
        debugCamShift = 0
        let gx = 16, gy = 10
        for gj in 0..<gy {
            var row = ""
            for gi in 0..<gx {
                var s = 0, n = 0
                for i in 1..<frames.count { for y in (gj * h / gy)..<((gj + 1) * h / gy) { for x in (gi * w / gx)..<((gi + 1) * w / gx) { s += abs(Int(frames[i][y * w + x]) - Int(frames[i - 1][y * w + x])); n += 1 } } }
                row += String(format: "%5.1f", Double(s) / Double(max(1, n)))
            }
            print("GRID " + row)
        }
        // obszar: środek sukna, bez bil (lewa połowa pola gry, pas środkowy)
        let x0 = Int(Double(w) * 0.22), x1 = Int(Double(w) * 0.40), y0 = Int(Double(h) * 0.32), y1 = Int(Double(h) * 0.42)
        for i in 1..<frames.count {
            var sum = 0, mx = 0, cnt = 0
            for y in y0..<y1 { for x in x0..<x1 { let d = abs(Int(frames[i][y * w + x]) - Int(frames[i - 1][y * w + x])); sum += d; mx = max(mx, d); if d > 2 { cnt += 1 } } }
            print(String(format: "JITTER %d mean %.3f max %d frac>2 %.4f", i, Double(sum) / Double((x1 - x0) * (y1 - y0)), mx, Double(cnt) / Double((x1 - x0) * (y1 - y0))))
        }
    }

    /// BILARD_GPUBENCH=1: czas GPU jednej klatki (ms) dla kolejnych konfiguracji efektów, renderer poza ekranem 2560x1600
    func gpuBench() {
        guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue(), let scene = scnView.scene else { return }
        let r = SCNRenderer(device: dev, options: nil)
        r.scene = scene; r.pointOfView = cameraNode
        let W = Int(env["BILARD_BW"] ?? "") ?? 2560, H = Int(env["BILARD_BH"] ?? "") ?? 1600
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .private
        let tex = dev.makeTexture(descriptor: td)!
        let cam = cameraNode.camera!
        func measure(_ name: String, _ n: Int = 40) {
            var tot = 0.0, cnt = 0
            for i in 0..<(n + 5) {
                let pd = MTLRenderPassDescriptor()
                pd.colorAttachments[0].texture = tex; pd.colorAttachments[0].loadAction = .clear; pd.colorAttachments[0].storeAction = .store
                let cb = q.makeCommandBuffer()!
                r.render(atTime: Double(i) / 60, viewport: CGRect(x: 0, y: 0, width: W, height: H), commandBuffer: cb, passDescriptor: pd)
                cb.commit(); cb.waitUntilCompleted()
                if i >= 5 { tot += (cb.gpuEndTime - cb.gpuStartTime) * 1000; cnt += 1 }
            }
            print(String(format: "GPUBENCH %-34@ %6.2f ms/klatkę  (%.0f FPS max)", name as NSString, tot / Double(cnt), 1000 / (tot / Double(cnt))))
        }
        let ss0 = cam.screenSpaceAmbientOcclusionIntensity, bl0 = cam.bloomIntensity, hdr0 = cam.wantsHDR, aa0 = scnView.antialiasingMode
        measure("1. stan jak w grze")
        cam.screenSpaceAmbientOcclusionIntensity = 0.7; measure("2. + SSAO"); cam.screenSpaceAmbientOcclusionIntensity = ss0
        let sh = table.lampLights.map { $0.castsShadow }
        for l in table.lampLights { l.castsShadow = false }; measure("3. bez cieni lamp")
        for (l, v) in zip(table.lampLights, sh) { l.castsShadow = v }
        cam.bloomIntensity = 0; measure("4. bez bloom"); cam.bloomIntensity = bl0
        cam.wantsHDR = false; measure("5. bez HDR"); cam.wantsHDR = hdr0
        let env0 = scene.lightingEnvironment.contents
        scene.lightingEnvironment.contents = nil; measure("6. bez HDRI (oświetlenie otoczenia)"); scene.lightingEnvironment.contents = env0
        let tr = table.root; tr.isHidden = true; measure("7. bez stołu (same bile+kij)"); tr.isHidden = false
        for b in table.balls { b.isHidden = true }; measure("8. bez bil"); for b in table.balls { b.isHidden = false }
        cam.screenSpaceAmbientOcclusionIntensity = 0; cam.bloomIntensity = 0; cam.wantsHDR = false
        for l in table.lampLights { l.castsShadow = false }; scene.lightingEnvironment.contents = nil
        measure("9. wszystko wyłączone (sam stół)")
        _ = aa0
        exit(0)
    }

    func update(_ dt: Double) {
        if env["BILARD_AIMSWEEP"] != nil, phase == .aiming, !sweepDone { sweepDone = true; print("SWEEPSTART"); let o = V2(Double(model.spin.x), Double(model.spin.y)); aimInd.sweep(balls: physics.balls, aim: BilliardPhysics.squirtAim(V2(cos(aimYaw), sin(aimYaw)), off: o), off: o, elev: model.elevation * .pi / 180) }
        if env["BILARD_GPUBENCH"] != nil, simTime > 6, !benchDone { benchDone = true; gpuBench() }
        enforceRenderScale()
        if let t = env["BILARD_SCALETEST"], simTime > 6, abs(Settings.shared.renderScale - (Double(t) ?? 0.5)) > 0.001 { Settings.shared.renderScale = Double(t) ?? 0.5 }
        if env["BILARD_SAVETEST"] != nil {
            saveTestT += dt
            if saveTestN == 0 && phase == .aiming && saveTestT > 5 && !rules.isAI(rules.current) == false || saveTestN == 0 && phase == .aiming && saveTestT > 5 {
                saveTestN = 1; saveTestT = 0
                print("SAVE ok=\(saveGame(slot: 2)) balls=\(physics.balls.filter { $0.active }.count) cur=\(rules.current)")
                physics.balls[3].p = V2(0.1, 0.1); physics.balls[4].active = false
            } else if saveTestN == 1 && saveTestT > 2 {
                saveTestN = 2
                loadGame(slot: 2)
                print("LOAD balls=\(physics.balls.filter { $0.active }.count) b3=\(physics.balls[3].p) phase=\(phase) cur=\(rules.current)"); fflush(stdout); exit(0)
            }
        }
        updatePause(dt)
        if model.paused && !demo && phase != .menu && phase != .gameOver { updateCamera(dt); return }   // prawdziwa pauza: symulacja stoi
        updateRackAnimation(dt)
        if env["BILARD_CHALKTEST"] != nil, simTime > 5, phase == .aiming, !chalkTested, !fx.busy { chalkTested = true; fx.level = [0.3, 0.3]; startChalking() }
        updateChalking(dt)
        switch phase {
        case .menu:
            menuAngle += dt * 0.12
        case .placing:
            updatePlacing()
        case .aiming:
            if fx.busy { break }
            if aiStage >= 0 { updateAI(dt) } else { updateHumanAim(dt) }
        case .striking:
            updateStrike(dt)
        case .rolling:
            updateFollowThrough(dt)
            if replaying { updateReplay(dt) } else { updateRolling(dt) }
        case .gameOver:
            menuAngle += dt * 0.08
        }
        updateDrops(dt)
        updateCue(dt)
        updateAimLines()
        updateCamera(dt)
        syncNodes()
        updateVisualFX()
        updateCallVisuals()
        // dźwięk 3D: słuchacz = kamera
        let f = cameraNode.simdWorldFront
        audio.setListener(position: cameraNode.simdPosition, forward: f)
        if demoPending && phase == .menu { demoPending = false; startDemo() }
        if demo { updateDemo(dt) }
        if env["BILARD_RESUMETEST"] != nil { resumeTest(dt) }
        if env["BILARD_AUTOSTART"] != nil && phase == .menu && simTime > 0.5 && !demo && !model.canResume && resumeTestN == 0 {
            if let m = env["BILARD_MODE"], let gm = GameMode(rawValue: m) { gameMode = gm }
            autoplay = env["BILARD_AUTOPLAY"] != nil
            if env["BILARD_TOURNEY"] != nil {          // test: turniej 4 graczy, wszystkie mecze autoplay
                let ts = TournamentStore.shared
                ts.create(mode: gameMode, ids: ["you", "ai1", "ai2", "ai3"])
                if let (r, i) = ts.advanceAI() { startTournamentMatch(r, i) } else { print("TURNIEJ bez meczu człowieka"); exit(0) }
            } else {
                newGame(vsAI: true)
            }
        }
    }

    // MARK: Celowanie człowieka

    func updateHumanAim(_ dt: Double) {
        if let ht = env["BILARD_HUMANTEST"] {     // test: człowiek ustawia rotację/uniesienie/siłę w HUD, po 2 s strzela
            let c = ht.split(separator: ",").compactMap { Double($0) }
            humanTestT += dt
            if c.count >= 4 && humanTestT > 1.0 && humanTestT - dt <= 1.0 {
                model.spin = CGPoint(x: c[0], y: c[1]); model.elevation = c[2]; model.power = c[3]
                aimYaw += 0.35
            }
            if c.count >= 5 {           // 5. pole = 1: strzał stuknięciem spacji (wciśnij w 2,0 s, puść w 2,1 s)
                if humanTestT > 2.0 && humanTestT - dt <= 2.0 { spaceDown = true; spaceHeld = 0 }
                if humanTestT > 2.1 { humanTestT = -1e9; spaceReleased() }
            } else if humanTestT > 2.0 { humanTestT = -1e9; humanShoot() }
        }
        // spacja: krótkie stuknięcie = strzał z siłą ustawioną w HUD (tą, dla której celownik rysuje tor);
        // przytrzymanie > 0,2 s = ładowanie siły od zera (wcześniej każde wciśnięcie zerowało ustawioną siłę)
        if spaceDown && !charging { spaceHeld += dt; if spaceHeld > 0.2 { charging = true; power = 0.05 } }
        if charging {
            power = min(1, power + dt / 1.5)
            model.power = power
        } else if let rp = rightPull {
            power = rp; model.power = rp
        } else {
            power = model.power
        }
        cueElev = model.elevation * .pi / 180
    }

    func humanShoot() {
        guard phase == .aiming, aiStage < 0, !rules.isAI(rules.current) else { return }
        if power < 0.04 { power = max(0.45, model.power) }     // = siła, dla której celownik rysuje tor bez naciągu
        fire(power: power)
    }

    func fire(power p: Double) {
        if rules.needsCall && !(callBall != nil && callPocket != nil) {
            model.message = "Zadeklaruj bilę i łuzę przed strzałem"
            power = 0; model.power = 0; charging = false; spaceDown = false; rightPull = nil
            return
        }
        let human = !rules.isAI(rules.current)
        let cdef = Settings.shared.cue
        shotPower = human ? min(1.0, p * cdef.maxPower) : p
        if human { DispatchQueue.main.async { [weak self] in self?.model.lastPower = p } }
        shotOff = V2(Double(model.spin.x), Double(model.spin.y)) * (human ? cdef.spinCtl : 1)
        shotElev = cueElev
        strikeT = 0; physicsStruck = false
        phase = .striking
        charging = false
        spaceDown = false
        rightPull = nil
    }

    // MARK: Ustawianie białej

    func legalCuePos(_ p: V2) -> V2? {
        let R = Phys.R
        var q = p
        q.x = max(-Phys.halfL + R + 0.005, min(Phys.halfL - R - 0.005, q.x))
        q.y = max(-Phys.halfW + R + 0.005, min(Phys.halfW - R - 0.005, q.y))
        q = rules.clampCue(q, restricted: placingBreak || rules.breakShot && ballInHand)
        return q
    }
    func cueSpotFree(_ q: V2) -> Bool { physics.isFree(q, ignoring: 0, margin: 0.003) }

    func updatePlacing() {
        if let h = hoverPoint, let q = legalCuePos(h) {
            physics.balls[0].p = q
            let free = cueSpotFree(q)
            table.balls[0].opacity = free ? 1 : 0.4
        }
    }

    func confirmPlacing() {
        guard phase == .placing, let q = legalCuePos(hoverPoint ?? physics.balls[0].p), cueSpotFree(q) else { return }
        physics.balls[0].p = q
        table.balls[0].opacity = 1
        ballInHand = false
        model.ballInHand = false
        placingBreak = false
        phase = .aiming
        model.topView = false
        let targets = rules.legalTargets(rules.current).filter { physics.balls[$0].active }
        if let t = targets.min(by: { simd_length(physics.balls[$0].p - q) < simd_length(physics.balls[$1].p - q) }) {
            let d = physics.balls[t].p - q
            aimYaw = atan2(d.y, d.x)
        }
    }

    // MARK: AI

    func updateAI(_ dt: Double) {
        aiT += dt
        let fast = autoplay ? 0.25 : 1.0
        switch aiStage {
        case 0:
            if aiT > (demo ? 3.0 : 1.3) * fast {
                aiShot = AIPlayer.choose(balls: physics.balls, rules: rules, ballInHand: ballInHand, rng: &rng)
                if let s = aiShot, let c = s.cuePos {
                    physics.balls[0].p = c
                    syncNodes()
                    ballInHand = false
                    model.ballInHand = false
                }
                if rules.needsCall, var s = aiShot {
                    if s.ball == nil || s.pocket == nil {
                        let cue = physics.balls[0].p
                        let b = rules.legalTargets(rules.current).filter { physics.balls[$0].active }
                            .min { simd_length(physics.balls[$0].p - cue) < simd_length(physics.balls[$1].p - cue) } ?? 1
                        s.ball = b
                        s.pocket = BilliardPhysics.pockets.indices.min { simd_length(BilliardPhysics.pockets[$0].c - physics.balls[b].p) < simd_length(BilliardPhysics.pockets[$1].c - physics.balls[b].p) }
                        aiShot = s
                    }
                    callBall = s.ball; callPocket = s.pocket
                    updateCallText()
                }
                aiStartYaw = aimYaw
                aiStage = 1; aiT = 0
            }
        case 1:
            guard let s = aiShot else { return }
            var d = s.yaw - aiStartYaw
            while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
            // czas obrotu proporcjonalny do kąta (kij nie „wywija”): ~0,35 rad/s w szczycie, minimum 1,3 s, maksimum 4,5 s
            let dur = min(4.5, max(1.3, 0.9 + abs(d) * 1.9)) * fast
            let k = min(1, aiT / dur)
            let e = k * k * k * (k * (6 * k - 15) + 10)       // smootherstep: łagodny start i dojazd
            aimYaw = aiStartYaw + d * e
            if k >= 1 { aiStage = 2; aiT = 0; aimYaw = aiStartYaw + d }
        case 2:
            guard let s = aiShot else { return }
            let dur = (0.8 + 1.0 * s.power) * fast
            power = min(s.power, s.power * aiT / dur)
            model.power = power
            if aiT >= dur {
                shotOff = s.off
                shotElev = Double(env["BILARD_JUMP"] ?? "") ?? 0
                shotPower = s.power
                aiStage = -1
                model.thinking = false
                cueElev = 0
                strikeT = 0
                phase = .striking
            }
        default: break
        }
    }

    // MARK: Uderzenie i toczenie

    func updateStrike(_ dt: Double) {
        strikeT += dt
        let hit = autoplay ? 0.03 : 0.1
        if strikeT >= hit && !physicsStruck {
            physicsStruck = true
            let aim = V2(cos(aimYaw), sin(aimYaw))
            report = ShotReport()
            report.calledBall = callBall; report.calledPocket = callPocket
            if demo {
                let ai = computeAim(from: physics.balls[0].p, yaw: aimYaw)
                demoFocus = (ai.target, ai.target.map { CameraDirector.bestPocket(from: physics.balls[$0].p, dir: ai.tgtDir) })
            } else if !autoplay {
                let ai = computeAim(from: physics.balls[0].p, yaw: aimYaw)
                var long = false
                if let t = ai.target {
                    let tp = physics.balls[t].p
                    let pk = BilliardPhysics.pockets[CameraDirector.bestPocket(from: tp, dir: ai.tgtDir)]
                    long = simd_length(tp - physics.balls[0].p) + simd_length(pk.c - tp) > 0.75 * 2 * Phys.halfL
                }
                director.onShot(long: long, matchBall: isMatchBall(), aimTarget: ai.target, tgtDir: ai.tgtDir, balls: physics.balls)
            }
            recorder.reset(); trace.reset(physics.balls); shotClock = 0
            recorder.capture(physics.balls, t: 0)
            if env["BILARD_AIMCHECK"] != nil {      // test: prognoza celownika vs rzeczywisty tor białej
                let pr = aimInd.predict(balls: physics.balls, aim: aim, power: shotPower, off: shotOff, elev: shotElev)
                aimCheckPred = pr.cue; aimCheckReal = [physics.balls[0].p]
                print(String(format: "AIMCHECK shot power %.3f off %.2f,%.2f elev %.1f° | ostatnia prognoza: power %.3f off %.2f,%.2f elev %.1f° yawΔ %.4f",
                             shotPower, shotOff.x, shotOff.y, shotElev * 180 / .pi, lastPred.power, lastPred.off.x, lastPred.off.y, lastPred.elev * 180 / .pi, lastPred.yaw - aimYaw))
            }
            let cs = chalkStrike(aim: aim, off: shotOff, power: shotPower)
            if cs.3 { model.message = "Kiks! Za mało kredy na kiju" }
            physics.strike(aim: cs.0, power: cs.2, off: cs.1, elev: shotElev)
            audio.cueHit(power: shotPower, at: physics.balls[0].p)
            punch = 0.4 + 0.6 * shotPower; shake = max(shake, 0.3 + 0.7 * shotPower)
            let cg = cueGeometry()
            addChalkMark(contact: cg.tip - V3(physics.balls[0].p.x, Phys.R, physics.balls[0].p.y))
            // bila rusza natychmiast: faza toczenia zaczyna się w chwili kontaktu, a kij dokończa ruch w updateFollowThrough
            phase = .rolling
            simTime0 = simTime
            physics.resetAccumulator()
        }
    }

    func updateFollowThrough(_ dt: Double) {
        guard physicsStruck, phase != .striking else { return }
        strikeT += dt
        if strikeT >= (autoplay ? 0.03 : 0.1) + 0.25 { physicsStruck = false }
    }
    var physicsStruck = false
    var humanTestT = 0.0
    var aimCheckPred: [V2] = [], aimCheckReal: [V2] = []
    var lastPred = (power: 0.0, off: V2(0, 0), elev: 0.0, yaw: 0.0)
    /// porównanie: odległość punktów rzeczywistego toru (do długości prognozy) od łamanej prognozy
    func reportAimCheck() {
        guard aimCheckPred.count > 1, aimCheckReal.count > 1 else { return }
        func len(_ p: [V2]) -> Double { zip(p, p.dropFirst()).reduce(0) { $0 + simd_length($1.1 - $1.0) } }
        let lp = len(aimCheckPred)
        var acc = 0.0, maxD = 0.0, at = 0.0
        for (a, b) in zip(aimCheckReal, aimCheckReal.dropFirst()) {
            acc += simd_length(b - a); if acc > lp { break }
            var d = 1e9
            for (u, v) in zip(aimCheckPred, aimCheckPred.dropFirst()) {
                let e = v - u, t = max(0, min(1, simd_dot(b - u, e) / max(1e-12, simd_dot(e, e))))
                d = min(d, simd_length(b - (u + e * t)))
            }
            if d > maxD { maxD = d; at = acc }
        }
        print(String(format: "AIMCHECK tor: prognoza %.2f m, maks. odchyłka %.1f mm (po %.2f m)", lp, maxD * 1000, at))
        aimCheckPred = []
    }
    var simTime0 = 0.0

    func updateRolling(_ dt: Double) {
        let speedUp = autoplay ? 3.0 : 1.0
        physics.advance(dt * speedUp)
        if !aimCheckPred.isEmpty {
            aimCheckReal.append(physics.balls[0].p)
            let hitOrStop = physics.events.contains { if case .ballHit(let a, let b, _, _) = $0 { return a == 0 || b == 0 }; return false } || !physics.anyMoving
            if hitOrStop { reportAimCheck() }
        }
        shotClock += dt * speedUp
        processEvents()
        recorder.capture(physics.balls, t: shotClock)
        let timeout = simTime - simTime0 > 60
        if !physics.anyMoving || timeout {
            // chwila ciszy, potem rozstrzygnięcie
            settleTimer += dt
            if settleTimer > 0.35 {
                settleTimer = 0
                finishShot()
            }
        } else { settleTimer = 0 }
    }
    var settleTimer = 0.0

    func processEvents() {
        for e in physics.events {
            switch e {
            case let .ballHit(a, b, speed, pos):
                if report.firstContact == nil {
                    if a == 0 { report.firstContact = b } else if b == 0 { report.firstContact = a }
                }
                trace.hit(a, b, speed: speed, pos: pos, t: shotClock)
                audio.ballHit(speed: speed, at: pos)
                if speed > 3.5 { shake = max(shake, 0.18 * min(1, speed / 6)) }
            case let .cushion(ball, speed, pos):
                trace.cushion(ball)
                report.railBalls.insert(ball)
                if report.firstContact != nil { report.cushionAfterContact = true }
                audio.cushion(speed: speed, at: pos)
            case let .landed(_, speed, pos):
                audio.ballHit(speed: min(2.5, speed * 0.8), at: pos)
            case let .offTable(ball, pos):
                report.offTable.append(ball)
                if autoplay { print("OFFTABLE \(ball)") }
                if ball == 0 { report.pocketed.append(0) }
                let n = table.balls[ball]
                let v = physics.balls[ball].v
                fliers.insert(ball)
                n.isHidden = false
                n.removeAllActions()
                n.runAction(.sequence([
                    .move(by: SCNVector3(CGFloat(v.x) * 0.45, -0.95, CGFloat(v.y) * 0.45), duration: 0.5),
                    .run { [weak self] nd in self?.fliers.remove(ball); nd.isHidden = true }]))
                audio.ballHit(speed: 2.2, at: pos)
                shake = max(shake, 0.35)
                model.message = ball == 0 ? "Biała poza stołem!" : "Bila \(ball) poza stołem!"
            case let .pocket(ball, idx, pos):
                trace.pocket(ball, idx: idx, pos: pos, t: shotClock)
                report.pocketed.append(ball)
                report.pocketLog.append((ball: ball, pocket: idx))
                let pk = BilliardPhysics.pockets[min(idx, BilliardPhysics.pockets.count - 1)]
                drops[ball] = (0, pos, pk.c)
                audio.pocket(at: pk.c)
                shake = max(shake, 0.3)
                if report.firstContact != nil { report.cushionAfterContact = true }
            }
        }
        physics.events.removeAll(keepingCapacity: true)
        audio.setRolling(physics.balls.reduce(0.0) { $1.active ? max($0, $1.speed) : $0 } / 2.0)
    }

    /// stawia bilę w pobliżu punktu, szukając wolnego miejsca wzdłuż osi X (najpierw w stronę `dir`)
    func placeBall(_ id: Int, near spot: V2, dir: Double) {
        var found = spot
        outer: for k in 0..<400 {
            for sg in [dir, -dir] {
                let q = spot + V2(Double(k) * 0.012 * sg, 0)
                if abs(q.x) > Phys.halfL - Phys.R - 0.01 { continue }
                if physics.isFree(q, ignoring: id, margin: 0.003) { found = q; break outer }
            }
        }
        setBall(id, at: found)
    }
    func setBall(_ id: Int, at p: V2) {
        physics.balls[id].p = p; physics.balls[id].v = V2(0, 0); physics.balls[id].w = V3(0, 0, 0)
        physics.balls[id].active = true
        physics.balls[id].h = 0; physics.balls[id].vh = 0
        fliers.remove(id); table.balls[id].removeAllActions()
        table.balls[id].isHidden = false; table.balls[id].opacity = 1
        drops[id] = nil
    }

    func finishShot() {
        director.shotEnded()
        let shooter = rules.current
        let prevHigh = rules.highBreak
        var out = rules.resolve(report)
        // bile wybite poza stół: wracają na punkt, a wybicie jest faulem (biała poza stołem to zwykły faul „scratch”)
        if report.offTable.contains(0) { out.message = out.message.replacingOccurrences(of: "Biała wpadła do łuzy", with: "Biała wyleciała poza stół") }
        let offObj = report.offTable.filter { $0 != 0 }
        if !offObj.isEmpty {
            for id in offObj { placeBall(id, near: V2(Phys.halfL / 2, 0), dir: -1) }
            if out.winner == nil {
                if !out.foul {
                    if out.continueTurn { rules.current = 1 - rules.current }
                    out.foul = true; out.continueTurn = false; out.ballInHand = true
                    out.message = "Faul: bila poza stołem. " + out.message
                } else { out.message += " Bila poza stołem wraca na stół." }
            }
        }
        if rules.highBreak > prevHigh { breakBest[shooter] = max(breakBest[shooter], rules.highBreak) }
        model.message = out.message
        syncModel()
        if autoplay {
            logLines += 1
            print("TURA \(logLines): \(rules.name(shooter)) first=\(String(describing: report.firstContact)) call=\(String(describing: report.calledBall))/\(String(describing: report.calledPocket)) pocketed=\(report.pocketed) pts=\(rules.scores) -> \(out.message)")
        }
        if let dec = evaluateReplay(out: out, shooter: shooter) {
            startReplay(dec) { [weak self] in self?.completeShot(out) }
            return
        }
        completeShot(out)
    }

    func completeShot(_ out: ShotOutcome) {
        for id in out.respot {
            placeBall(id, near: out.respotAt[id] ?? V2(Phys.halfL / 2, 0), dir: out.respotDir)
        }
        if out.rerack {
            let rem = (1...15).filter { physics.balls[$0].active }
            let plan = rules.rerack(remainingAt: rem.first.map { physics.balls[$0].p } ?? V2(9, 9))
            for (id, p) in plan { setBall(id, at: p) }
            startRackAnimation()
            if physics.balls[0].active && !physics.isFree(physics.balls[0].p, ignoring: 0, margin: 0.003) {
                placeBall(0, near: rules.cueSpot, dir: -1)
            }
        }
        if let w = out.winner {
            model.winner = w
            if demo { phase = .gameOver; table.cue.isHidden = true; demoOverT = 0; return }
            saveRecords(winner: w)
            finishTournamentMatch(winner: w)
            phase = .gameOver
            table.cue.isHidden = true
            if autoplay && env["BILARD_TOURNEY"] != nil {
                print("KONIEC meczu: wygrywa \(rules.name(w))")
                DispatchQueue.main.async { [self] in
                    let ts = TournamentStore.shared
                    if let (r, i) = ts.advanceAI() { startTournamentMatch(r, i) }
                    else { print("TURNIEJ KONIEC: mistrz \(ts.profiles.profile(ts.t?.champion)?.name ?? "?")"); exit(0) }
                }
                return
            }
            if autoplay { print("KONIEC: wygrywa \(rules.name(w))"); if env["BILARD_KEEP"] == nil { exit(0) } }
            return
        }
        ballInHand = out.ballInHand
        // przy fauli z białą na stole człowiek też ustawia ją sam
        if rules.breakShot == false { placingBreak = false }
        beginTurn()
    }

    func updateDrops(_ dt: Double) {
        for (id, var d) in drops {
            d.t += dt
            drops[id] = d
            let n = table.balls[id]
            let k = min(1, d.t / 0.16)
            let e = k * k * (3 - 2 * k)
            let p = d.from + (d.to - d.from) * e * 0.8
            let y = Phys.R - 7.0 * d.t * d.t
            n.simdPosition = SIMD3<Float>(Float(p.x), Float(y), Float(p.y))
            if y < -0.14 { n.isHidden = true; drops[id] = nil; droppedDone.insert(id) }
        }
    }
    var droppedDone = Set<Int>()

    // MARK: Synchronizacja węzłów

    var syncedKey = [SIMD4<Double>](repeating: SIMD4<Double>(9e9, 0, 0, 0), count: 32)
    func syncNodes() {
        for i in 0..<Phys.nBalls {
            let b = physics.balls[i]
            let n = table.balls[i]
            if drops[i] != nil || fliers.contains(i) { continue }
            if !b.active { n.isHidden = true; continue }
            if n.isHidden { n.isHidden = false }
            // culling: bila śpiąca (v≈0, w≈0) i już zsynchronizowana – bez zapisu transformacji
            let key = SIMD4<Double>(b.p.x, b.p.y, b.h, b.q.real + b.q.imag.x + 3 * b.q.imag.y + 7 * b.q.imag.z)   // pozycja/orientacja bez zmian => pomiń zapis
            if syncedKey[i] == key && fx.rackT < 0 { continue }
            syncedKey[i] = key
            n.simdPosition = SIMD3<Float>(Float(b.p.x), Float(Phys.R + b.h), Float(b.p.y))
            n.simdOrientation = simd_quatf(ix: Float(b.q.imag.x), iy: Float(b.q.imag.y), iz: Float(b.q.imag.z), r: Float(b.q.real))
            if fx.rackT >= 0 { rackBallOffset(i, n) }
        }
    }

    // MARK: Efekty wizualne: cienie kontaktowe, blask anamorficzny, lampa, kreda

    let lampPos = V3(0, 2.4, 0)
    var probeFrame = 0
    var probeDirty = true
    var lastClothNormal: CGFloat = -1
    var clothFlat = false
    var lastShadowA: CGFloat = -1
    var shadowsOn = true
    var lastLampDir = [SIMD3<Float>](repeating: SIMD3<Float>(9, 9, 9), count: 32)
    func updateVisualFX() {
        // sonda odbić: odświeżana co ~0,4 s (jedna klatka .realtime), nie co klatkę – oszczędność GPU
        // perf: zamiast co 240 klatek (6 ścian cube-mapy = skok czasu GPU) – jedna klatka po zatrzymaniu bil
        if let pr = table.probe {
            let moving = phase == .rolling || phase == .striking
            if moving { probeDirty = true; probeFrame = 0 }
            else if probeDirty { probeFrame += 1
                if probeFrame == 2 { pr.probeUpdateType = .realtime } else if probeFrame >= 3 { pr.probeUpdateType = .never; probeDirty = false } }
        }
        // widok z góry: wygaszamy mikro-detal sukna (normal), który migotał przy podpikselowym ruchu
        let nIntensity = CGFloat(clothNormalBase * (1 - 0.92 * smooth(topBlend)))
        // z góry zamiast tekstur sukna – jednolity kolor o tej samej średniej jasności (zero aliasingu)
        let wantFlat = dbg[5] || topBlend > (clothFlat ? 0.35 : 0.6)
        if wantFlat != clothFlat {
            clothFlat = wantFlat
            for m in table.clothMaterials {
                m.diffuse.contents = wantFlat ? NSColor(white: 150.0 / 255.0, alpha: 1) : TableBuilder.pack.clothDiffuse
                m.roughness.contents = wantFlat ? 0.925 : TableBuilder.pack.clothRough
                m.normal.contents = wantFlat ? nil : TableBuilder.pack.clothNormal
            }
        }
        // z góry cienie świateł nic nie dają (cienie kontaktowe są osobno), a ich próbkowanie szumi – chowamy je
        let shadowA = CGFloat(1 - smooth(min(1, topBlend * 1.6)))
        if abs(shadowA - lastShadowA) > 0.01 {
            lastShadowA = shadowA
            for l in table.lampLights { l.shadowColor = NSColor(white: 0, alpha: shadowA) }
            // culling: gdy cienie są niewidoczne, nie renderujemy ich map wcale
            let on = shadowA > 0.02
            if on != shadowsOn { shadowsOn = on; for l in table.lampLights { l.castsShadow = on } }
        }
        // culling: pył/stożek światła niewidoczne z góry i w menu
        let hideShafts = topBlend > 0.5 || phase == .menu
        if table.shafts.isHidden != hideShafts { table.shafts.isHidden = hideShafts }
        if abs(nIntensity - lastClothNormal) > 0.002 {
            lastClothNormal = nIntensity
            for m in table.clothMaterials { m.normal.intensity = nIntensity; m.setValue(Float(smooth(topBlend)), forKey: "topMix") }
        }
        let camPos = cameraNode.simdPosition          // układ rig = układ stołu
        let inv = simd_inverse(cameraNode.simdTransform)
        _ = topBlend
        for i in 0..<Phys.nBalls {
            let b = physics.balls[i]
            let dropping = drops[i] != nil
            let visible = (b.active || dropping) && !table.balls[i].isHidden
            // culling: bila zdjęta ze stołu – bez żadnej pracy (cień kontaktowy ukryty raz)
            if !visible { if !table.contact[i].isHidden { table.contact[i].isHidden = true }; continue }
            let c = V3(Double(table.balls[i].simdPosition.x), Double(table.balls[i].simdPosition.y), Double(table.balls[i].simdPosition.z))
            // cień kontaktowy
            let cn = table.contact[i]
            cn.isHidden = !visible || dropping || dbg[2]
            cn.simdPosition = SIMD3<Float>(Float(c.x), Float(0.0020 + 0.012 * smooth(topBlend)), Float(c.z))
            cn.opacity = CGFloat(i == 0 && phase == .placing ? 0.45 : 1.0) * CGFloat(max(0, 1 - (c.y - Phys.R) / 0.09))
            // blask w punkcie odbicia lampy (wektor połówkowy)
            let L = simd_normalize(lampPos - c)
            let V = simd_normalize(V3(Double(camPos.x), Double(camPos.y), Double(camPos.z)) - c)
            let n = simd_normalize(L + V)
            _ = n   // sztuczny blask wyłączony – węzły glare nie są już aktualizowane (culling pracy CPU)
            // kierunek lampy w przestrzeni widoku (dla shadera bili): tylko gdy się realnie zmienił (KVC jest drogie)
            let dv = inv * SIMD4<Float>(Float(L.x), Float(L.y), Float(L.z), 0)
            let dir3 = SIMD3<Float>(dv.x, dv.y, dv.z)
            if simd_distance(dir3, lastLampDir[i]) > 0.004 {
                lastLampDir[i] = dir3
                table.ballMaterials[i].setValue(SCNVector3(dv.x, dv.y, dv.z), forKey: "lampDirV")
            }
        }
    }

    /// ślad kredy na białej bili w punkcie uderzenia (dekal przypięty do bili, obraca się razem z nią)
    func addChalkMark(contact c: V3) {
        let ball = table.balls[0]
        let q = ball.simdOrientation
        let local = simd_act(simd_inverse(q), SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z)))
        let dir = simd_normalize(local)
        // pula: znaczniki są współdzielone i recyklingowane – bez alokacji po zapełnieniu
        let n: SCNNode
        if table.chalkMarks.count >= 14 {
            n = table.chalkMarks.removeFirst()
            n.removeFromParentNode()
        } else {
            if chalkPlane == nil {
                let m = SCNMaterial()
                m.lightingModel = .constant
                m.diffuse.contents = TableBuilder.pack.chalk
                m.writesToDepthBuffer = false; m.transparency = 0.3
                m.isDoubleSided = false
                let pl = SCNPlane(width: 0.0075, height: 0.0075)
                pl.materials = [m]
                chalkPlane = pl
            }
            n = SCNNode(geometry: chalkPlane)
            n.castsShadow = false
            n.renderingOrder = 10
        }
        n.simdPosition = dir * Float(Phys.R * 1.0015)
        n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: dir)
        ball.addChildNode(n)
        table.chalkMarks.append(n)
    }
    var chalkPlane: SCNPlane? = nil

    // MARK: Kij i linie celowania

    /// czy kij (wizualnie) przy danym nachyleniu nie wchodzi w sukno, bandy, ramę ani inne bile
    func cueClear(_ e: Double, pull: Double) -> Bool {
        let g = cueGeometry(elev: e)
        let tip = g.tip - g.travel * (pull + 0.002)
        let ox = TableBuilder.X + TableBuilder.railW, oz = TableBuilder.Y + TableBuilder.railW
        var s = 0.02
        while s < 1.47 {
            let q = tip - g.travel * s
            let r = 0.006 + 0.011 * s / 1.46
            let ax = abs(q.x), az = abs(q.z)
            if ax < ox && az < oz {
                let floorY = (ax < Phys.halfL && az < Phys.halfW) ? 0.0 : TableBuilder.railTop + 0.012
                if q.y - r < floorY { return false }
            }
            s += 0.03
        }
        for i in 1..<Phys.nBalls where physics.balls[i].active {
            let c = V3(physics.balls[i].p.x, Phys.R, physics.balls[i].p.y)
            let t = max(0, min(1.47, simd_dot(tip - c, g.travel)))
            let q = tip - g.travel * t
            if simd_length(q - c) < Phys.R + 0.006 + 0.011 * t / 1.46 { return false }
        }
        return true
    }

    func cueGeometry(elev: Double? = nil) -> (tip: V3, travel: V3) {
        let aim = V2(cos(aimYaw), sin(aimYaw))
        let e = elev ?? cueVisElev
        let D = simd_normalize(V3(aim.x * cos(e), -sin(e), aim.y * cos(e)))
        let right = V3(-aim.y, 0, aim.x)
        let up = simd_normalize(simd_cross(right, D))
        let off = phase == .striking ? shotOff : V2(Double(model.spin.x), Double(model.spin.y))
        var o = off
        let ol = simd_length(o); if ol > 0.9 { o *= 0.9 / ol }
        let depth = sqrt(max(0, 1 - o.x * o.x - o.y * o.y))
        let c = Phys.R * (o.x * right + o.y * up - depth * D)
        let b = physics.balls[0]
        let center = V3(b.p.x, Phys.R, b.p.y)
        return (center + c, D)
    }

    func updateCue(_ dt: Double) {
        let showCue = (phase == .aiming && (aiStage != 0 || true)) || phase == .striking || (physicsStruck && phase == .rolling)
        var alpha = 1.0
        var pull = 0.0
        if phase == .aiming {
            pull = 0.03 + power * 0.22
            if aiStage == 0 { pull = 0.05 }
        } else if phase == .striking || physicsStruck {
            let hit = autoplay ? 0.03 : 0.1
            if strikeT < hit {
                let k = strikeT / hit
                pull = (0.03 + shotPower * 0.22) * (1 - k * k)
            } else {
                pull = -0.012
                alpha = max(0, 1 - (strikeT - hit) / 0.22)
            }
        }
        _ = alpha
        if fx.chalkT >= 0 && !model.pauseCine {
            let cp = chalkPose()
            table.cue.isHidden = false; table.cue.opacity = 1
            table.cue.simdPosition = SIMD3<Float>(Float(cp.tip.x), Float(cp.tip.y), Float(cp.tip.z))
            table.cue.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(Float(cp.d.x), Float(cp.d.y), Float(cp.d.z)))
            return
        }
        table.cue.isHidden = !showCue || model.pauseCine || fx.rackT >= 0
        aimInd.root.isHidden = model.pauseCine
        if showCue {
            // wizualne uniesienie kija nad przeszkody (fizyka uderzenia używa cueElev/shotElev bez zmian)
            let base = (phase == .striking || physicsStruck) ? shotElev : cueElev
            var need = base
            while need < 1.4 && !cueClear(need, pull: pull) { need += 0.02 }
            cueVisElev += (need - cueVisElev) * (need > cueVisElev ? 1 : (1 - exp(-dt * 8)))
            let g = cueGeometry()
            let tipPos = g.tip - g.travel * (pull + 0.002)
            table.cue.simdPosition = SIMD3<Float>(Float(tipPos.x), Float(tipPos.y), Float(tipPos.z))
            table.cue.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: SIMD3<Float>(Float(g.travel.x), Float(g.travel.y), Float(g.travel.z)))
            table.cue.opacity = CGFloat(alpha)
        }
    }

    func setLinesVisible(_ v: Bool) {
        [lineMain, lineTarget, lineCue, lineBounce, ghost].forEach { $0.isHidden = !v }
    }

    func placeLine(_ n: SCNNode, _ a: V2, _ b: V2) {
        let d = b - a
        let len = simd_length(d)
        if len < 0.002 { n.isHidden = true; return }
        n.isHidden = false
        (n.geometry as? SCNCylinder)?.height = CGFloat(len)
        let mid = (a + b) / 2
        n.simdPosition = SIMD3<Float>(Float(mid.x), Float(Phys.R), Float(mid.y))
        let dir = SIMD3<Float>(Float(d.x / len), 0, Float(d.y / len))
        n.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir)
    }

    struct AimInfo {
        var ghost: V2
        var target: Int?
        var tgtDir: V2 = V2(0, 0)
        var cueDir: V2 = V2(0, 0)
        var cueLen = 0.0
        var bounceDir: V2 = V2(0, 0)
    }

    func computeAim(from p: V2, yaw: Double, dir: V2? = nil) -> AimInfo {
        let R = Phys.R
        let d = dir ?? V2(cos(yaw), sin(yaw))
        var tBest = 10.0, hitBall: Int? = nil
        for b in physics.balls where b.active && b.id != 0 {
            let f = p - b.p
            let bb = simd_dot(f, d)
            let cc = simd_dot(f, f) - 4 * R * R
            let disc = bb * bb - cc
            if disc >= 0 {
                let t = -bb - sqrt(disc)
                if t > 0 && t < tBest { tBest = t; hitBall = b.id }
            }
        }
        var tWall = 10.0
        var wallN = V2(0, 0)
        let lim = V2(Phys.halfL - R, Phys.halfW - R)
        if d.x > 1e-9 { let t = (lim.x - p.x) / d.x; if t < tWall { tWall = t; wallN = V2(-1, 0) } }
        if d.x < -1e-9 { let t = (-lim.x - p.x) / d.x; if t < tWall { tWall = t; wallN = V2(1, 0) } }
        if d.y > 1e-9 { let t = (lim.y - p.y) / d.y; if t < tWall { tWall = t; wallN = V2(0, -1) } }
        if d.y < -1e-9 { let t = (-lim.y - p.y) / d.y; if t < tWall { tWall = t; wallN = V2(0, 1) } }
        if let hb = hitBall, tBest < tWall {
            let g = p + d * tBest
            let n = simd_normalize(physics.balls[hb].p - g)
            var info = AimInfo(ghost: g, target: hb)
            info.tgtDir = n
            let tang = d - n * simd_dot(d, n)
            let tl = simd_length(tang)
            if tl > 0.02 { info.cueDir = tang / tl; info.cueLen = 0.45 * tl }
            return info
        }
        var info = AimInfo(ghost: p + d * tWall, target: nil)
        info.bounceDir = d - wallN * (2 * simd_dot(d, wallN))
        return info
    }

    func updateAimLines() {
        let humanAim = phase == .aiming && aiStage < 0 && !rules.isAI(rules.current) && !autoplay && !demo && !fx.busy
        let placing = phase == .placing
        if !humanAim && !placing { setLinesVisible(false); aimInd.hide(); return }
        if placing { setLinesVisible(false); aimInd.hide(); return }
        let p = physics.balls[0].p
        let off = V2(Double(model.spin.x), Double(model.spin.y)) * Settings.shared.cue.spinCtl
        let aim = BilliardPhysics.squirtAim(V2(cos(aimYaw), sin(aimYaw)), off: off)
        let info = computeAim(from: p, yaw: aimYaw, dir: aim)
        setLinesVisible(false)
        aimInd.lineScale = Settings.shared.cue.aimLine
        let cdef = Settings.shared.cue
        // domyślnie linia liczona dla stałej, mocnej siły: nie „skacze” przy zmianie mocy; opcja: dokładnie dla ustawionej siły
        let pw = 0.65 * cdef.maxPower          // stała moc: linia nie zmienia się przy ustawianiu siły
        _ = info; _ = aim
        aimInd.update(dt: 1.0 / 60, balls: physics.balls, aimRaw: V2(cos(aimYaw), sin(aimYaw)), off: off, power: min(1, pw), elev: model.elevation * .pi / 180)
        lastPred = (min(1, pw), off, model.elevation * .pi / 180, aimYaw)
    }

    // MARK: Kamera

    func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    func updatePause(_ dt: Double) {
        if let t = env["BILARD_PAUSETEST"], let at = Double(t), simTime > at, !model.paused, phase == .aiming, pauseT == 0, !pauseTestDone {
            pauseTestDone = true; model.paused = true
        }
        let live = model.paused && !demo && phase != .menu && phase != .gameOver
        if !live { pauseT = 0; if model.pauseCine { model.pauseCine = false }; pauseWasCine = false; return }
        if pauseWasCine && !model.pauseCine { pauseT = 0 }       // gracz „obudził” pauzę – panel wraca
        pauseWasCine = model.pauseCine
        if !model.pauseCine { pauseT += dt; if pauseT > 4 { model.pauseCine = true; pauseCineT = 0 } }
    }

    /// zbliżenia na bile w pauzie: powolny przelot wokół kolejnych bil, kamera od strony środka stołu
    func pausePose(_ dt: Double) -> CamPose {
        pauseCineT += dt
        let act = physics.balls.indices.filter { physics.balls[$0].active }
        let per = 6.0
        let k = Int(pauseCineT / per)
        let i = act.isEmpty ? 0 : act[k % act.count]
        let lt = pauseCineT - Double(k) * per
        let p = physics.balls[i].p
        var d = -p; let l = simd_length(d); d = l > 0.05 ? d / l : V2(1, 0)
        let a = atan2(d.y, d.x) + 0.7 * sin(Double(k) * 1.7) + (lt / per - 0.5) * 0.9
        let r = Phys.R * (7.5 - 1.5 * lt / per)                  // lekki najazd
        let pos = V3(p.x + cos(a) * r, Phys.R * (2.6 + 0.6 * sin(Double(k))), p.y + sin(a) * r)
        return CamPose(pos: pos, look: V3(p.x, Phys.R * 0.9, p.y), up: V3(0, 1, 0), fov: 32)
    }

    func updateCamera(_ dt: Double) {
        let target = model.topView ? 1.0 : 0.0
        topBlend += (target - topBlend) * (1 - exp(-dt * 4.2))
        if abs(target - topBlend) < 0.0005 { topBlend = target }
        let wantFollow = (phase == .rolling || phase == .striking && strikeT > 0.1) ? 1.0 : 0.0
        follow += (wantFollow - follow) * (1 - exp(-dt * 1.8))

        let aspect = Double(max(1, scnView.bounds.width) / max(1, scnView.bounds.height))
        let cam = cameraNode.camera!

        // pozycja 3D (za kijem)
        let cue = physics.balls[0]
        let cueP = V3(cue.p.x, Phys.R, cue.p.y)
        let yaw = (phase == .menu || phase == .gameOver) ? menuAngle : aimYaw + camYawOffset
        let dirH = V3(cos(yaw), 0, sin(yaw))
        var pos3: V3, look3: V3
        if phase == .menu || phase == .gameOver {
            let sc = Phys.halfL / 1.27
            pos3 = V3(-cos(yaw) * 2.2 * sc, 1.45 * sc, -sin(yaw) * 2.2 * sc)
            look3 = V3(0, 0, 0)
        } else {
            let p = camPitch, D = camDist * (1 - 0.14 * power * (phase == .aiming ? 1 : 0)) * (1 - 0.06 * punch)
            let aimPos = cueP - dirH * (cos(p) * D) + V3(0, sin(p) * D, 0)
            // oś kamery ~0.29 rad nad kierunkiem na bilę: bila w dolnej części kadru, lampy u góry (jak na zdjęciach sal)
            let tilt = max(0.02, p - 0.25)
            let aimLook = aimPos + (dirH * cos(tilt) - V3(0, sin(tilt), 0)) * D
            let sc2 = Phys.halfL / 1.27
            let ovLook = director.trackPoint * 0.65
            let ovPos = ovLook * 0.5 - dirH * 1.55 * sc2 + V3(0, (1.45 + 0.35 * director.trackSpeed) * sc2, 0)
            let f = smooth(follow)
            pos3 = aimPos + (ovPos - aimPos) * f
            look3 = aimLook + (ovLook - aimLook) * f
        }
        pos3.y = max(pos3.y, 0.09)

        // widok z góry: dopasowany do proporcji okna
        let fovTop = 38.0
        let th = tan(fovTop / 2 * .pi / 180)
        let needW = 2 * (Phys.halfL + 0.30) / (2 * th * aspect)
        let needH = 2 * (Phys.halfW + 0.30) / (2 * th)
        let H = max(needW, needH)
        let topPos = V3(0, H, 0.0001)
        let topLook = V3(0, 0, 0)

        var s = smooth(topBlend)
        var pos = pos3 + (topPos - pos3) * s
        var look = look3 + (topLook - look3) * s
        var up = simd_normalize(V3(0, 1, 0) * (1 - s) + V3(0, 0, -1) * s)
        let fovAim = 40 + 10 * (1 - follow)
        var fovV = (fovAim + (fovTop - fovAim) * s + 7 * sin(.pi * s) - 3.5 * punch * (1 - s))
        if demo {
            // tryb demo: kamera TV zastępuje całą logikę kamery gry
            let st: TVStage
            switch phase {
            case .aiming: st = aiStage >= 2 || aiStage == 1 ? .aiming : .thinking
            case .striking: st = .aiming
            case .rolling: st = .rolling
            default: st = .idle
            }
            let p = tv.update(TVInput(dt: dt, balls: physics.balls, stage: st, cue: cueP, aimDir: V2(cos(aimYaw), sin(aimYaw)),
                                      cueElev: cueVisElev, focusBall: demoFocus.ball, focusPocket: demoFocus.pocket, aspect: aspect))
            pos = p.pos; look = p.look; up = p.up; fovV = p.fov
            s = tv.overhead ? 1 : 0
            shake = 0; punch = 0
        } else {
        // reżyser ujęć: nakłada TV / łuza / orbit / intro / najazd na bazową kamerę
        do {
            var tgt: Int? = nil, tdir = V2(0, 0)
            if director.preset == .pocket && humanTurn {
                let ai = computeAim(from: cue.p, yaw: aimYaw)
                tgt = ai.target; tdir = ai.tgtDir
            }
            let pose = director.update(CamContext(dt: dt, balls: physics.balls, rolling: phase == .rolling, topView: model.topView,
                                                  cue: cueP, aimTarget: tgt, aimTgtDir: tdir),
                                       base: CamPose(pos: pos, look: look, up: up, fov: fovV))
            // wygładzanie: lekkie przy celowaniu (responsywność), mocne przy przejściach, śledzeniu bil i zmianie ujęć
            let moving = director.active || director.replayActive || phase == .rolling || phase == .striking
                || abs(follow - wantFollow) > 0.02 || abs((model.topView ? 1.0 : 0.0) - topBlend) > 0.002 || phase == .gameOver
            let aiTurn = rules.isAI(rules.current) && (phase == .aiming || phase == .striking)
            camSmoothT += ((moving ? 0.55 : (aiTurn ? 0.5 : 0.09)) - camSmoothT) * (1 - exp(-dt * 2.5))
            let sp = camSmooth.step(pose, dt: dt, smoothTime: env["BILARD_NOSMOOTH"] != nil ? 0.0001 : camSmoothT)
            pos = sp.pos; look = sp.look; up = sp.up; fovV = sp.fov
        }
        }
        if model.pauseCine {
            if pauseCineT == 0 { pauseSmooth = SmoothCam(); pauseSmooth.seed(CamPose(pos: pos, look: look, up: up, fov: fovV)) }
            let lt = pauseCineT.truncatingRemainder(dividingBy: 6.0)
            let sp = pauseSmooth.step(pausePose(dt), dt: dt, smoothTime: lt < 1.2 ? 0.45 : 0.12)
            pos = sp.pos; look = sp.look; up = sp.up; fovV = sp.fov; s = 0
            camSmooth.seed(sp)                                    // po pauzie bez skoku
        }
        cam.fieldOfView = CGFloat(fovV)
        if env["BILARD_CAMLOG"] != nil { print(String(format: "CAM %.4f %.4f %.4f %.4f %.4f %.4f", pos.x, pos.y, pos.z, look.x, look.y, look.z)) }
        punch *= exp(-dt * 4.5); if punch < 0.002 { punch = 0 }
        shake *= exp(-dt * 7)
        let sh = shake * 0.006
        let jit = V3(Double.random(in: -1...1), Double.random(in: -1...1), Double.random(in: -1...1)) * sh * (1 - s)   // z góry bez drgań (migotanie sukna)
        cam.screenSpaceAmbientOcclusionIntensity = CGFloat(ssaoBase * (1 - s))   // SSAO z daleka szumi na suknie
        let focus = max(0.2, simd_length(look - pos))
        let lift = 0.0014 + 0.012 * s          // z góry nakładki unoszone wraz z kamerą (anty z-fighting)
        table.decals.forEach { $0.position.y = CGFloat(lift) }
        cam.zNear = CGFloat(0.02 + 1.2 * s)          // z góry większe zNear = precyzja głębi, koniec z-fightingu nakładek na suknie
        let nI = clothNormalBase * max(0, min(1, (2.0 - focus) / 1.2))   // detal normalny sukna zanika z odległością (moiré)
        table.clothMaterials.forEach { $0.normal.intensity = CGFloat(nI) }
        cam.focusDistance = CGFloat(focus)
        cam.fStop = CGFloat(7.0 + 8 * s)
        cam.focalSize = CGFloat(0.35 + focus * 0.25)
        // oprawa filmowa: powtórki dostają płytką ostrość, mocniejszą winietę i cieplejszą, kontrastowszą korekcję
        gradeRep += ((replaying ? 1.0 : 0.0) - gradeRep) * (1 - exp(-dt * 3))
        let g = gradeRep * (1 - s)
        if g > 0.01 {
            cam.wantsDepthOfField = true
            cam.fStop = CGFloat(Double(cam.fStop) * (1 - g) + 1.6 * g)
            cam.focalSize = CGFloat(Double(cam.focalSize) * (1 - g) + 0.05 * g)
        } else { cam.wantsDepthOfField = Settings.shared.dof }
        let aimGlow = phase == .aiming ? power : 0
        cam.vignettingIntensity = CGFloat(0.32 + 0.38 * g + 0.10 * aimGlow + 0.10 * punch)
        cam.contrast = CGFloat(0.08 + 0.08 * g)
        cam.saturation = CGFloat(1.12 + 0.12 * g)
        cam.bloomIntensity = Settings.shared.bloom ? CGFloat(0.04 + 0.04 * g + 0.03 * punch) : 0

        pos += jit
        cameraNode.simdPosition = SIMD3<Float>(Float(pos.x + debugCamShift), Float(pos.y), Float(pos.z))
        // look(at:) przyjmuje świat: kamera żyje w układzie rig (w menu obróconym na miejsce stołu)
        cameraNode.look(at: rig.convertPosition(SCNVector3(look.x, look.y, look.z), to: nil),
                        up: rig.convertVector(SCNVector3(up.x, up.y, up.z), to: nil), localFront: SCNVector3(0, 0, -1))
        // lampy (kategoria 8) renderowane tylko gdy kamera jest pod nimi: nigdy nie zasłaniają stołu z góry ani z przeglądu
        let lampsVisible = s < 0.02 && pos.y < 0.80
        cam.categoryBitMask = lampsVisible ? 0xFFFF_FFFB : 0xFFFF_FFF3
    }

    // MARK: Rzut myszy na płaszczyznę stołu

    func tablePoint(_ e: NSEvent) -> V2? {
        let p = scnView.convert(e.locationInWindow, from: nil)
        let a0 = scnView.unprojectPoint(SCNVector3(p.x, p.y, 0))
        let b0 = scnView.unprojectPoint(SCNVector3(p.x, p.y, 1))
        let a = rig.convertPosition(a0, from: nil)               // świat → układ stołu
        let b = rig.convertPosition(b0, from: nil)
        let dy = Double(b.y - a.y)
        if abs(dy) < 1e-9 { return nil }
        let t = (Double(Phys.R) - Double(a.y)) / dy
        if t < 0 { return nil }
        return V2(Double(a.x) + Double(b.x - a.x) * t, Double(a.z) + Double(b.z - a.z) * t)
    }

    // MARK: Zdarzenia

    var humanTurn: Bool { phase == .aiming && aiStage < 0 && !rules.isAI(rules.current) && !fx.busy }

    func mouseDown(_ e: NSEvent) {
        if demo { endDemo(); return }
        if replaying { endReplay(); return }
        if director.introActive { director.skipIntro(); return }
        if director.preset == .orbit, phase != .menu { if let m = tablePoint(e) { director.orbitPick(m, balls: physics.balls) }; return }
        if phase == .placing { hoverPoint = tablePoint(e) ?? hoverPoint; confirmPlacing(); return }
        if humanTurn && rules.needsCall, let m = tablePoint(e), handleCallClick(m) { return }
        if humanTurn && model.topView, let m = tablePoint(e) { aimAt(m) }
    }

    /// klik w bilę (deklaracja bili) albo w łuzę (deklaracja łuzy)
    func handleCallClick(_ m: V2) -> Bool {
        let cands = rules.callableBalls(rules.current).filter { physics.balls[$0].active }
        if let b = cands.min(by: { simd_length(physics.balls[$0].p - m) < simd_length(physics.balls[$1].p - m) }),
           simd_length(physics.balls[b].p - m) < 1.8 * Phys.R {
            callBall = b
            audio.cushion(speed: 0.4, at: physics.balls[b].p)
            updateCallText(); assistAim()
            return true
        }
        if callBall != nil, let (i, pk) = BilliardPhysics.pockets.enumerated().min(by: { simd_length($0.element.c - m) < simd_length($1.element.c - m) }),
           simd_length(pk.c - m) < pk.r + 0.12 {
            callPocket = i
            updateCallText(); assistAim()
            return true
        }
        return false
    }

    /// po pełnej deklaracji kij od razu celuje w „bilę-ducha” (można nadal poprawić celowanie)
    func assistAim() {
        guard let b = callBall, let k = callPocket else { return }
        let tb = physics.balls[b].p
        let n = simd_normalize(BilliardPhysics.pockets[k].c - tb)
        let g = tb - n * (2 * Phys.R)
        let d = g - physics.balls[0].p
        if simd_length(d) > 0.01 { aimYaw = atan2(d.y, d.x) }
    }
    func mouseMoved(_ e: NSEvent) {
        if phase == .placing { hoverPoint = tablePoint(e) ?? hoverPoint }
    }
    func mouseDragged(_ e: NSEvent) {
        if phase == .placing { hoverPoint = tablePoint(e) ?? hoverPoint; return }
        guard humanTurn else { return }
        if model.topView {
            if let m = tablePoint(e) { aimAt(m) }
        } else if e.modifierFlags.contains(.option) {
            camYawOffset += Double(e.deltaX) * 0.004
        } else {
            let slow = e.modifierFlags.contains(.shift) ? 0.25 : 1.0
            aimYaw += Double(e.deltaX) * 0.0035 * slow
            camPitch = max(0.10, min(1.35, camPitch - Double(e.deltaY) * 0.003))
        }
    }
    func mouseUp(_ e: NSEvent) {}

    func aimAt(_ m: V2) {
        let c = physics.balls[0].p
        let d = m - c
        if simd_length(d) > 0.01 { aimYaw = atan2(d.y, d.x) }
    }

    var rightStartY = 0.0
    func rightDown(_ e: NSEvent) {
        if demo { endDemo(); return }
        guard humanTurn else { return }
        rightStartY = Double(e.locationInWindow.y)
        rightPull = 0.04
    }
    func rightDragged(_ e: NSEvent) {
        guard humanTurn, rightPull != nil else { return }
        let dy = rightStartY - Double(e.locationInWindow.y)   // w dół = więcej siły
        rightPull = max(0.04, min(1, dy / 220))
    }
    func rightUp(_ e: NSEvent) {
        guard humanTurn, let p = rightPull else { return }
        rightPull = nil
        if p > 0.08 { fire(power: p) }
    }

    func scroll(_ e: NSEvent) {
        if demo { return }
        if director.preset == .orbit && phase != .menu {
            director.orbitScroll(dx: -Double(e.scrollingDeltaX), dy: Double(e.scrollingDeltaY))
            return
        }
        if model.topView { return }
        camDist = max(0.45, min(2.4, camDist - Double(e.scrollingDeltaY) * (e.hasPreciseScrollingDeltas ? 0.004 : 0.04)))
        if humanTurn && abs(e.scrollingDeltaX) > 0 {
            aimYaw += Double(e.scrollingDeltaX) * 0.0012
        }
    }
    func magnify(_ e: NSEvent) {
        if demo { return }
        if director.preset == .orbit && phase != .menu { director.orbitZoom(1 - Double(e.magnification)); return }
        camDist = max(0.45, min(2.4, camDist * (1 - Double(e.magnification)))) }

    func keyDown(_ e: NSEvent) -> Bool {
        if demo { if !e.isARepeat { endDemo() }; return true }
        if model.pauseCine { model.pauseCine = false; return true }
        guard let ch = e.charactersIgnoringModifiers?.lowercased() else { return false }
        if e.modifierFlags.contains(.option), let n = Int(ch), (1...6).contains(n) { debugToggle(n - 1); return true }
        if replaying { if e.keyCode == 49 || e.keyCode == 53 { endReplay() }; return true }
        if phase == .menu && model.canResume && (e.keyCode == 53 || e.keyCode == 36) { resumeGame(); return true }   // Esc/Enter: wznów grę
        if director.introActive && e.keyCode != 53 { director.skipIntro(); return true }
        switch e.keyCode {
        case 49: // spacja
            if humanTurn && !e.isARepeat && phase == .aiming { spaceDown = true; spaceHeld = 0 }   // nie przy potwierdzaniu bili z ręki
            if phase == .placing { confirmPlacing() }
            return true
        case 123: if humanTurn { aimYaw -= e.modifierFlags.contains(.shift) ? 0.0012 : 0.006 }; return true
        case 124: if humanTurn { aimYaw += e.modifierFlags.contains(.shift) ? 0.0012 : 0.006 }; return true
        case 126: if humanTurn { model.elevation = min(55, model.elevation + 1.5) }; return true
        case 125: if humanTurn { model.elevation = max(0, model.elevation - 1.5) }; return true
        case 53: if phase != .menu && phase != .gameOver { model.paused.toggle() }; return true
        default: break
        }
        switch ch {
        case "c": toggleView(); return true
        case "k": if humanTurn { startChalking() }; return true
        case "v": cycleCamera(); return true
        case "t": toggleCloth(); return true
        case "p": beginReposition(); return true
        case "r": camYawOffset = 0; camPitch = 0.36; camDist = Phys.snooker ? 1.5 : 1.2; return true
        case "n": newGame(vsAI: rules.vsAI); return true
        case "+", "=": camDist = max(0.45, camDist - 0.08); return true
        case "-": camDist = min(2.4, camDist + 0.08); return true
        case "m": Settings.shared.muted.toggle(); return true
        default: return false
        }
    }
    func keyUp(_ e: NSEvent) -> Bool {
        if e.keyCode == 49 {
            spaceReleased()
            return true
        }
        return false
    }
    func spaceReleased() {
        do {
            if spaceDown {
                spaceDown = false
                if charging { charging = false; if power > 0.06 && humanTurn { fire(power: power) } else { power = 0; model.power = 0 } }
                else if humanTurn { humanShoot() }      // stuknięcie: siła z HUD
                spaceHeld = 0
            }
        }
    }

    func toggleView() {
        guard phase != .menu else { return }
        model.topView.toggle()
    }
}

extension GameSceneController {
    func resetChalkRack() {
        placeChalkCube()
        fx.chalkT = -1; fx.rackT = -1; fx.rackIDs = []; fx.rackDelay = [:]
        fx.tri?.removeFromParentNode(); fx.tri = nil
        fx.puff?.birthRate = 0
        fx.level = [1, 1]; model.chalk = 1; model.chalking = false
    }
}
