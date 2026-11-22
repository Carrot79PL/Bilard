import SwiftUI
import SceneKit

// MARK: - Menu główne: zakładki Gra / Wygląd / Rekordy / Grafika / Dźwięk / O autorze

struct Chip: View {
    let title: String
    let selected: Bool
    var width: CGFloat? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5, weight: .medium)).foregroundColor(selected ? .black : UI.text)
                .padding(.horizontal, 10).frame(width: width, height: 26)
                .background(Capsule().fill(selected ? UI.accent : Color.white.opacity(0.08)))
        }.buttonStyle(.plain)
    }
}

struct Row<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(label).font(.system(size: 11.5)).foregroundColor(UI.dim).frame(width: 128, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

struct StatBar: View {
    let label: String, value: Double      // 0…1
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 9.5)).foregroundColor(UI.faint).frame(width: 52, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(UI.accent).frame(width: 70 * max(0.05, min(1, value)))
            }.frame(width: 70, height: 4)
        }
    }
}

struct MenuRoot: View {
    @ObservedObject var m: GameModel
    @ObservedObject var s: Settings
    @ObservedObject var rec: RecordStore
    @State private var tab = 0
    @State private var recMode: GameMode = .eight
    private let tabs = ["Gra", "Wygląd", "Rekordy", "Turniej", "Grafika", "Dźwięk", "O autorze"]

    var body: some View {
        ZStack {
            ZStack {
                Color.black.opacity(0.28)
                RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 200, endRadius: 900)
            }.ignoresSafeArea().allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: -10) {
                    BallChip(n: 1, size: 28).offset(y: 3)
                    BallChip(n: 8, size: 33).zIndex(1)
                    BallChip(n: 9, size: 28).offset(y: 3)
                }.padding(.bottom, 8)
                Text("BILARD").font(.system(size: 34, weight: .heavy)).tracking(10).foregroundColor(UI.text)

                HStack(spacing: 6) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Button { tab = i } label: {
                            Text(tabs[i]).font(.system(size: 12, weight: .semibold))
                                .foregroundColor(tab == i ? UI.text : UI.dim)
                                .padding(.horizontal, 9).frame(height: 28)
                                .background(Capsule().fill(Color.white.opacity(tab == i ? 0.14 : 0.0)))
                                .overlay(Capsule().strokeBorder(tab == i ? UI.accent.opacity(0.7) : Color.clear, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }.padding(.top, 14)
                Rectangle().fill(UI.line).frame(height: 1).padding(.vertical, 12)

                SwiftUI.Group {
                    switch tab {
                    case 0: gameTab
                    case 1: lookTab
                    case 2: recordsTab
                    case 3: TournamentTab(m: m)
                    case 4: graphicsTab
                    case 5: audioTab
                    default: aboutTab
                    }
                }
                .frame(width: 560, height: 430, alignment: .top)
            }
            .padding(.horizontal, 36).padding(.vertical, 26)
            .fixedSize()
            .onAppear { tab = m.menuTab }
            .onReceive(m.$menuTab) { tab = $0 }
            .panel(24, tint: 0.5)
            .interactive()
        }
    }

    // MARK: Gra
    var gameTab: some View {
        VStack(spacing: 10) {
            VStack(spacing: 8) {
                ForEach([Array(GameMode.allCases.prefix(3)), Array(GameMode.allCases.dropFirst(3))], id: \.first) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { gm in
                            Button { m.onSelectMode(gm) } label: {
                                Text(gm.title).font(.system(size: 13, weight: .semibold)).tracking(1)
                                    .foregroundColor(m.mode == gm ? .black : UI.text)
                                    .frame(width: 96, height: 32)
                                    .background(RoundedRectangle(cornerRadius: 9).fill(m.mode == gm ? UI.accent : Color.white.opacity(0.08)))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Caps(m.mode.subtitle, color: UI.faint, size: 9).multilineTextAlignment(.center)
            if m.mode == .straight {
                HStack(spacing: 8) {
                    Caps("Do punktów", color: UI.dim, size: 9)
                    ForEach([50, 100], id: \.self) { t in
                        Chip(title: "\(t)", selected: m.target == t, width: 52) { m.onSetTarget(t) }
                    }
                }
            }
            Rectangle().fill(UI.line).frame(height: 1)
            Row(label: "Gracz 1") { nameField($s.name1, "Gracz 1") }
            Row(label: "Gracz 2") { nameField($s.name2, "Gracz 2") }
            Row(label: "Poziom komputera") {
                ForEach(AILevel.allCases, id: \.rawValue) { l in
                    Chip(title: l.title, selected: s.aiLevel == l.rawValue) { s.aiLevel = l.rawValue }
                }
            }
            Caps(s.level.blurb, color: UI.faint, size: 9)
            if m.savePicker == 2 {
                SaveSlotsView(m: m, saving: false) { m.savePicker = 0 }
                MenuButton(title: "Wróć", icon: "chevron.left") { m.savePicker = 0 }.scaleEffect(0.93)
            } else {
            if m.canResume {
                MenuButton(title: "Wznów grę", subtitle: "Esc lub Enter · powrót do przerwanej partii", icon: "play.fill", primary: true) { m.onResume() }
                    .scaleEffect(0.93)
            }
            HStack(spacing: 12) {
                MenuButton(title: "Gra z komputerem", subtitle: s.level.title, icon: "desktopcomputer", primary: !m.canResume) { m.onNewGame(true) }
                MenuButton(title: "Dwóch graczy", subtitle: "\(s.name1) i \(s.name2)", icon: "person.2.fill") { m.onNewGame(false) }
            }.scaleEffect(0.93)
            MenuButton(title: "Wczytaj grę", subtitle: "zapisane rozgrywki", icon: "square.and.arrow.up") { m.savePicker = 2 }.scaleEffect(0.93)
            if !m.canResume { ReplayPicker(m: m).scaleEffect(0.95) }   // miejsce na „Wznów grę”
            }
        }
    }

    func nameField(_ b: Binding<String>, _ ph: String) -> some View {
        TextField(ph, text: b)
            .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(UI.text)
            .padding(.horizontal, 10).frame(width: 220, height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: Wygląd
    var lookTab: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                LookPreview(cue: s.cueId, cloth: s.clothId, set: s.ballSetId, finish: s.finishId)
                    .frame(width: 250, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                let c = s.cue
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.name).font(.system(size: 12.5, weight: .semibold)).foregroundColor(UI.text)
                    Text(c.blurb).font(.system(size: 10.5)).foregroundColor(UI.dim)
                    StatBar(label: "Linia", value: c.aimLine / 1.5)
                    StatBar(label: "Moc", value: (c.maxPower - 0.8) / 0.3)
                    StatBar(label: "Spin", value: (c.spinCtl - 0.7) / 0.6)
                }.frame(width: 250, alignment: .leading)
                Text("Wygląd i statystyki wpływają na rozgrywkę od następnego strzału.")
                    .font(.system(size: 9.5)).foregroundColor(UI.faint).frame(width: 250, alignment: .leading)
            }
            ScrollView(.vertical, showsIndicators: true) { VStack(alignment: .leading, spacing: 10) {
                Caps("Kij", size: 9)
                FlowChips(items: CueDef.all.map { ($0.id, $0.name) }, sel: s.cueId) { s.cueId = $0 }
                Caps("Sukno", size: 9)
                HStack(spacing: 6) {
                    ForEach(ClothDef.all) { c in
                        Button { s.clothId = c.id } label: {
                            VStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 5).fill(Color(nsc(c.color))).frame(width: 40, height: 28)
                                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(s.clothId == c.id ? UI.accent : Color.white.opacity(0.25), lineWidth: s.clothId == c.id ? 2 : 0.8))
                                Text(c.name.components(separatedBy: " ").last ?? c.name).font(.system(size: 8.5)).foregroundColor(s.clothId == c.id ? UI.text : UI.dim)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Caps("Model stołu", size: 9)
                FlowChips(items: [("model", "Model 3D"), ("classic", "Proceduralny")], sel: s.tableModelId) { s.tableModelId = $0 }
                Text("Łuzy i bandy w fizyce dopasowane do wybranego modelu (zmiana od następnej partii)").font(.system(size: 10)).foregroundColor(UI.faint)
                Caps("Tekstura stołu (rama)", size: 9)
                FlowChips(items: FinishDef.tables.map { ($0.id, FinishDef.part($0.name, 0)) },
                          sel: FinishDef.tables.first { FinishDef.part($0.name, 0) == FinishDef.part(s.finish.name, 0) && $0.railTint == s.finish.railTint }?.id ?? s.finishId) { s.finishId = $0 }
                Caps("Tekstura łuz (okucia)", size: 9)
                FlowChips(items: [("auto", "Jak stół")] + FinishDef.pockets.map { ($0.id, FinishDef.part($0.name, 1)) },
                          sel: s.pocketId == "auto" ? "auto" : (FinishDef.pockets.first { FinishDef.part($0.name, 1) == FinishDef.part(s.pocketFinish.name, 1) }?.id ?? s.pocketId)) { s.pocketId = $0 }
                Caps("Zestaw bil", size: 9)
                FlowChips(items: BallSetDef.all.map { ($0.id, $0.name) }, sel: s.ballSetId) { s.ballSetId = $0 }
                Text(s.ballSet.blurb).font(.system(size: 10)).foregroundColor(UI.faint)
            }.padding(.trailing, 8) }.frame(height: 430)
        }
    }

    // MARK: Rekordy
    var recordsTab: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(GameMode.allCases, id: \.self) { gm in Chip(title: gm.title, selected: recMode == gm) { recMode = gm } }
            }
            let rows = rec.rows(recMode)
            VStack(spacing: 0) {
                recRow(["Gracz", "Mecze", "Wygrane", "Zwycięstw", "Break", "Najszybsza"], head: true)
                if rows.isEmpty {
                    Text("Brak rozegranych partii w trybie \(recMode.title)").font(.system(size: 12)).foregroundColor(UI.faint).padding(.top, 40)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows, id: \.0) { (name, e) in
                            recRow([name, "\(e.games)", "\(e.wins)", "\(e.winPct)%",
                                    recMode.isPoints ? "\(e.bestBreak)" : "—", e.fastest.map { Self.time($0) } ?? "—"], head: false)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button { rec.reset() } label: {
                Text("Wyczyść rekordy").font(.system(size: 11)).foregroundColor(UI.foul)
            }.buttonStyle(.plain)
        }
    }

    static func time(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }

    func recRow(_ c: [String], head: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(c.indices, id: \.self) { i in
                Text(c[i]).font(.system(size: head ? 9.5 : 12, weight: head ? .semibold : .regular))
                    .foregroundColor(head ? UI.faint : (i == 0 ? UI.text : UI.dim)).lineLimit(1)
                    .frame(width: i == 0 ? 190 : 74, alignment: i == 0 ? .leading : .trailing)
            }
        }.padding(.vertical, 5).overlay(Rectangle().fill(UI.line).frame(height: 1), alignment: .bottom)
    }

    // MARK: Grafika
    var graphicsTab: some View {
        VStack(alignment: .leading, spacing: 11) {
            Row(label: "Preset") {
                ForEach(GfxPreset.allCases.dropLast(), id: \.rawValue) { p in
                    Chip(title: p.title, selected: s.preset == p.rawValue) { s.setPreset(p) }
                }
                if s.preset == GfxPreset.custom.rawValue { Text("Własne").font(.system(size: 11)).foregroundColor(UI.accent) }
            }
            Rectangle().fill(UI.line).frame(height: 1)
            Row(label: "Tekstury (bile, sukno)") {
                ForEach([1, 2, 4], id: \.self) { r in Chip(title: "\(r)K", selected: s.texRes == r, width: 48) { s.texRes = r } }
            }
            Row(label: "Odbicia") {
                Chip(title: "Wyłączone", selected: s.reflections == 0) { s.reflections = 0 }
                Chip(title: "Odbicia środowiskowe", selected: s.reflections == 1) { s.reflections = 1 }
                Chip(title: "Pełne (sonda)", selected: s.reflections == 2) { s.reflections = 2 }
            }
            Row(label: "Cienie") {
                ForEach(Array(["Wył.", "Niskie", "Średnie", "Wysokie"].enumerated()), id: \.0) { i, t in
                    Chip(title: t, selected: s.shadows == i) { s.shadows = i }
                }
            }
            Row(label: "Post-processing") {
                toggle("Bloom", $s.bloom); toggle("Głębia ostrości", $s.dof); toggle("Pył w świetle", $s.dust); toggle("SSAO (wolne)", $s.ssao); toggle("Licznik FPS", $s.showFps); toggle("Tło panelu sterowania", $s.dockBg)
            }
            Row(label: "Rozdzielczość 3D") {
                HStack(spacing: 8) {
                    Slider(value: $s.renderScale, in: 0.25...1.0, step: 0.05).frame(width: 240).tint(UI.accent)
                    Text("\(Int((s.renderScale * 100).rounded()))%").font(UI.number(11)).foregroundColor(UI.dim).frame(width: 38, alignment: .trailing)
                }
            }
            Row(label: "Limit klatek") {
                ForEach([60, 120], id: \.self) { f in Chip(title: "\(f) FPS", selected: s.fps == f, width: 70) { s.fps = f } }
            }
            Text("SceneKit nie ma odbić w przestrzeni ekranu (SSR) – odbicia opierają się na mapie otoczenia i opcjonalnej sondzie. Zmiany działają od razu. Niższa rozdzielczość 3D wyraźnie zwiększa płynność; interfejs zostaje ostry.")
                .font(.system(size: 10)).foregroundColor(UI.faint).fixedSize(horizontal: false, vertical: true)
        }
    }

    func toggle(_ t: String, _ b: Binding<Bool>) -> some View { Chip(title: t, selected: b.wrappedValue) { b.wrappedValue.toggle() } }

    // MARK: Dźwięk
    var audioTab: some View {
        VStack(alignment: .leading, spacing: 13) {
            Row(label: "Muzyka") { slider($s.musicVol) }
            Row(label: "Efekty (SFX)") { slider($s.sfxVol) }
            Row(label: "Klub (otoczenie)") { slider($s.ambVol) }
            let styles = MusicStyle.allCases
            Row(label: "Styl muzyki") {
                ForEach(styles.prefix(4), id: \.rawValue) { st in
                    Chip(title: st.title, selected: s.musicStyle == st.rawValue) { s.musicStyle = st.rawValue }
                }
            }
            Row(label: "") {
                ForEach(styles.dropFirst(4), id: \.rawValue) { st in
                    Chip(title: st.title, selected: s.musicStyle == st.rawValue) { s.musicStyle = st.rawValue }
                }
            }
            Row(label: "Wyciszenie") { toggle("Wycisz wszystko (M)", $s.muted) }
            Text("Muzyka i odgłosy klubu (szum, rozmowy, szkło) są syntezowane na bieżąco – bez plików dźwiękowych.")
                .font(.system(size: 10)).foregroundColor(UI.faint).fixedSize(horizontal: false, vertical: true)
        }
    }

    func slider(_ b: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Slider(value: b, in: 0...1).frame(width: 240).tint(UI.accent)
            Text("\(Int(b.wrappedValue * 100))%").font(UI.number(11)).foregroundColor(UI.dim).frame(width: 38, alignment: .trailing)
        }
    }

    // MARK: O autorze
    var aboutTab: some View {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Bilard · wersja \(v)").font(.system(size: 17, weight: .bold)).foregroundColor(UI.text)
                Text("Autor: Tomasz Marchewka · studio BLUEROOT").font(.system(size: 13)).foregroundColor(UI.accent)
                Text("Natywna gra na macOS napisana w Swift z SceneKit/Metal: własna fizyka bil, tryby 8/9/10-Ball, 14/1 i snooker, komputerowy przeciwnik i muzyka syntezowana na żywo. Dziękuję za granie!")
                    .font(.system(size: 12)).foregroundColor(UI.dim).fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(UI.line).frame(height: 1)
                Caps("Licencje użytych skanów (CC0 / domena publiczna)", size: 9)
                lic("Poly Haven", "Orzech amerykański (american_walnut_veneer), skóra (brown_leather), HDRI sali bilardowej (billiard_hall) – CC0, polyhaven.com")
                lic("TextureCan", "Sukno bilardowe „Fabrics 0075” (kolor, chropowatość, AO) – CC0, texturecan.com")
                Text("Pozostałe tekstury, dźwięki i muzyka są generowane proceduralnie przez aplikację.")
                    .font(.system(size: 11)).foregroundColor(UI.faint)
            }.frame(width: 540, alignment: .leading)
        }
    }

    func lic(_ n: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(n).font(.system(size: 12, weight: .semibold)).foregroundColor(UI.text)
            Text(t).font(.system(size: 11)).foregroundColor(UI.dim).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FlowChips: View {
    let items: [(String, String)]
    let sel: String
    let pick: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items, id: \.0) { it in
                Chip(title: it.1, selected: sel == it.0) { pick(it.0) }
            }
        }
    }
}

// MARK: - Podgląd 3D wyglądu (osobna mała scena)

struct LookPreview: NSViewRepresentable {
    let cue: String, cloth: String, set: String, finish: String

    final class Coord {
        var scene: SCNScene? = nil
        let rig = SCNNode()
        var key = ""
    }
    func makeCoordinator() -> Coord { Coord() }

    func makeNSView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.backgroundColor = nsc(0x0B0A0C)
        v.antialiasingMode = .multisampling4X
        let sc = SCNScene()
        TableBuilder.configureEnvironment(sc)
        sc.background.contents = nsc(0x101114)
        let cam = SCNCamera(); cam.fieldOfView = 34; cam.wantsHDR = true
        cam.zNear = 0.05; cam.zFar = 20
        let cn = SCNNode(); cn.camera = cam
        cn.position = SCNVector3(-0.25, 0.5, 0.8)
        cn.look(at: SCNVector3(-0.25, 0.03, 0.0))
        sc.rootNode.addChildNode(cn)
        let l = SCNLight(); l.type = .omni; l.intensity = 900; l.color = nsc(0xFFF4E6)
        let ln = SCNNode(); ln.light = l; ln.position = SCNVector3(-0.4, 1.4, 0.6)
        sc.rootNode.addChildNode(ln)
        sc.rootNode.addChildNode(context.coordinator.rig)
        v.scene = sc; v.pointOfView = cn
        v.rendersContinuously = true
        context.coordinator.scene = sc
        context.coordinator.rig.runAction(.repeatForever(.sequence([
            .rotateBy(x: 0, y: 0.25, z: 0, duration: 4), .rotateBy(x: 0, y: -0.5, z: 0, duration: 8), .rotateBy(x: 0, y: 0.25, z: 0, duration: 4)])))
        rebuild(context.coordinator)
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) {
        let k = "\(cue)|\(cloth)|\(set)|\(finish)"
        if k != context.coordinator.key { rebuild(context.coordinator) }
    }

    private func rebuild(_ c: Coord) {
        if TableBuilder.pack == nil { c.key = ""; return }     // tekstury jeszcze się generują
        c.key = "\(cue)|\(cloth)|\(set)|\(finish)"
        let rig = c.rig
        rig.childNodes.forEach { $0.removeFromParentNode() }
        let st = Settings.shared
        // sukno
        let plane = SCNBox(width: 3.2, height: 0.02, length: 2.0, chamferRadius: 0)
        let cm = TableBuilder.clothMaterial(blue: true)
        cm.multiply.contents = nsc(ClothDef.find(cloth).color)
        let k = CGFloat(ClothDef.find(cloth).density) * 6
        let t = SCNMatrix4MakeScale(k, k, 1)
        cm.diffuse.contentsTransform = t; cm.normal.contentsTransform = t; cm.roughness.contentsTransform = t
        cm.normal.intensity = 0.55 * CGFloat(ClothDef.find(cloth).weave)
        plane.materials = [cm]
        let pn = SCNNode(geometry: plane); pn.position = SCNVector3(0, -0.01, 0)
        rig.addChildNode(pn)
        // fragment ramy i okucie łuzy (wykończenie stołu)
        let fd = FinishDef.find(finish)
        let rail = SCNBox(width: 3.2, height: 0.05, length: 0.3, chamferRadius: 0.012)
        let rm = TableBuilder.woodMaterial(); TableBuilder.styleRail(rm, fd); rail.materials = [rm]
        let rn = SCNNode(geometry: rail); rn.position = SCNVector3(0, 0.0, -1.1); rig.addChildNode(rn)
        let plate = SCNBox(width: 0.34, height: 0.012, length: 0.22, chamferRadius: 0.006)
        let fm = TableBuilder.chromeMaterial(); TableBuilder.styleFitting(fm, fd); plate.materials = [fm]
        let pln = SCNNode(geometry: plate); pln.position = SCNVector3(0.05, 0.03, -1.0); rig.addChildNode(pln)
        // bile (powiększone: promień 4 cm)
        let ids = [8, 3, 12, 0]
        for (i, n) in ids.enumerated() {
            let g = SCNSphere(radius: 0.04); g.segmentCount = 40
            let m = TableBuilder.pbr(TextureFactory.ballAlbedo(n, set: set, outW: 512), rough: 0.05, metal: 0)
            m.clearCoat.contents = 1.0; m.clearCoatRoughness.contents = 0.02
            if set == "dark" { m.emission.contents = TextureFactory.ballAlbedo(n, set: set, outW: 512); m.emission.intensity = 0.9 }
            g.materials = [m]
            let b = SCNNode(geometry: g)
            b.position = SCNVector3(Float(i) * 0.082 + 0.0, 0.04, Float(i % 2) * 0.02 - 0.01)
            b.eulerAngles = SCNVector3(0.4 * Float(i), 1.1 * Float(i), 0)
            rig.addChildNode(b)
        }
        // kij: ciało wzdłuż −Y → kładziemy wzdłuż −X, czubek przy bilach
        let q = TableBuilder.makeCue()
        TableBuilder.styleCue(q, CueDef.find(cue))
        q.eulerAngles = SCNVector3(0, 0, -Double.pi / 2)
        q.position = SCNVector3(-0.1, 0.045, 0.0)
        rig.addChildNode(q)
        _ = st
    }
}
