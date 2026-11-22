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
            Text(title).font(.system(size: 11.5, weight: UI.menuOn && selected ? .bold : .medium)).foregroundColor(selected && !UI.menuOn ? .black : UI.text)
                .padding(.horizontal, 10).frame(width: width, height: 26)
                .background(Capsule().fill(UI.menuOn ? Color.white.opacity(selected ? 0.18 : 0.04) : (selected ? UI.menuAccent : Color.white.opacity(0.08))))
                .overlay(Capsule().strokeBorder(UI.menuOn ? Color.white.opacity(selected ? 0.95 : 0.28) : Color.clear, lineWidth: selected ? 1.5 : 1))
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
                Capsule().fill(UI.menuAccent).frame(width: 70 * max(0.05, min(1, value)))
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
    private let tabs = ["Gra", "Wygląd", "Rekordy", "Turniej", "Wyzwania", "Grafika", "Dźwięk", "O autorze"]

    var body: some View {
        ZStack {
            ZStack {
                Color.black.opacity(0.10)
                RadialGradient(colors: [.clear, .black.opacity(0.32)], center: .center, startRadius: 200, endRadius: 900)
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
                                .overlay(Capsule().strokeBorder(tab == i ? UI.menuAccent.opacity(0.95) : Color.clear, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                    if m.clothMenu {
                        Button { m.panelOpen = false; m.savePicker = 0 } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundColor(UI.text)
                                .frame(width: 28, height: 28).background(Circle().fill(Color.white.opacity(0.14)))
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
                    case 4: ChallengesTab()
                    case 5: graphicsTab
                    case 6: audioTab
                    default: aboutTab
                    }
                }
                .frame(width: tab == 1 || tab == 4 ? 820 : (tab == 5 ? 680 : 560), height: tab == 1 ? 600 : (tab == 4 ? 440 : (tab == 5 ? 520 : 430)), alignment: .top)
            }
            .padding(.horizontal, 36).padding(.vertical, 26)
            .fixedSize()
            .onAppear { tab = m.menuTab }
            .onReceive(m.$menuTab) { tab = $0 }
            .panel(24, tint: 0.05, glass: 0.3)
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(UI.menuOn ? 0.6 : 0), lineWidth: 1.5))
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
                                    .foregroundColor(m.mode == gm && !UI.menuOn ? .black : UI.text)
                                    .frame(width: 96, height: 32)
                                    .background(RoundedRectangle(cornerRadius: 9).fill(UI.menuOn ? Color.white.opacity(m.mode == gm ? 0.18 : 0.04) : (m.mode == gm ? UI.menuAccent : Color.white.opacity(0.08))))
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(UI.menuOn ? Color.white.opacity(m.mode == gm ? 0.95 : 0.28) : Color.clear, lineWidth: m.mode == gm ? 1.5 : 1))
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
            if [.eight, .nine, .ten].contains(m.mode) {
                Row(label: "Biała po faulu") {
                    Chip(title: "W ręce", selected: !s.foulKitchen) { s.foulKitchen = false }
                    Chip(title: "Za linią", selected: s.foulKitchen) { s.foulKitchen = true }
                }
            }
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

    // MARK: Wygląd (bez przewijania: sekcje w wierszach z zawijanymi opcjami)
    func lookRow<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Caps(label, size: 9).frame(width: 82, alignment: .leading).padding(.top, 7)
            content()
        }
    }

    var lookTab: some View {
        let c = s.cue
        let railSel = FinishDef.tables.first { FinishDef.part($0.name, 0) == FinishDef.part(s.finish.name, 0) && $0.railTint == s.finish.railTint }?.id ?? s.finishId
        let pocketSel = s.pocketId == "auto" ? "auto" : (FinishDef.pockets.first { FinishDef.part($0.name, 1) == FinishDef.part(s.pocketFinish.name, 1) }?.id ?? s.pocketId)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    LookPreview(cue: s.cueId, cloth: s.clothId, set: s.ballSetId, finish: s.finishId)
                        .frame(width: 215, height: 112)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    Text(c.name).font(.system(size: 12.5, weight: .semibold)).foregroundColor(UI.text)
                    Text(c.blurb).font(.system(size: 10.5)).foregroundColor(UI.dim).fixedSize(horizontal: false, vertical: true)
                    StatBar(label: "Linia", value: c.aimLine / 1.5)
                    StatBar(label: "Moc", value: (c.maxPower - 0.8) / 0.34)
                    StatBar(label: "Spin", value: (c.spinCtl - 0.7) / 0.6)
                }.frame(width: 215, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Caps("Kij", size: 9)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(CueDef.all) { d in
                            Button { s.cueId = d.id } label: {
                                HStack(spacing: 8) {
                                    CueStrip(d: d).frame(width: 118, height: 16)
                                    Text(d.name).font(.system(size: 10.5, weight: s.cueId == d.id ? .bold : .regular)).foregroundColor(s.cueId == d.id ? UI.text : UI.dim).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8).frame(height: 30)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(s.cueId == d.id ? 0.14 : 0.04)))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(s.cueId == d.id ? UI.menuAccent : Color.white.opacity(0.14), lineWidth: s.cueId == d.id ? 1.8 : 1))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Rectangle().fill(UI.line).frame(height: 1)
            lookRow("Sukno") {
                FlowLayout(spacing: 6) {
                    ForEach(ClothDef.all) { d in
                        Button { s.clothId = d.id } label: {
                            RoundedRectangle(cornerRadius: 5).fill(Color(nsc(d.color))).frame(width: 28, height: 20)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(s.clothId == d.id ? UI.menuAccent : Color.white.opacity(0.22), lineWidth: s.clothId == d.id ? 2.2 : 0.8))
                        }.buttonStyle(.plain).help(d.name)
                    }
                }
            }
            lookRow("Emblemat") {
                WrapChips(items: EmblemDef.all.filter { $0.id != "custom" || Emblems.hasCustom }.map { ($0.id, $0.name) } + [("+", Emblems.hasCustom ? "Zmień własny…" : "Własny obraz…")], sel: s.emblemId) { id in
                    if id == "+" { Emblems.pickCustom { ok in if ok { s.emblemId = "custom" } } } else { s.emblemId = id }
                }
            }
            lookRow("Model stołu") { WrapChips(items: [("model", "Model 3D"), ("classic", "Proceduralny")], sel: s.tableModelId) { s.tableModelId = $0 } }
            lookRow("Rama stołu") {
                FlowLayout(spacing: 6) {
                    ForEach(FinishDef.tables) { d in
                        Button { s.finishId = d.id } label: {
                            RoundedRectangle(cornerRadius: 6).fill(Self.railColor(d)).frame(width: 26, height: 22)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(railSel == d.id ? UI.menuAccent : Color.white.opacity(0.22), lineWidth: railSel == d.id ? 2.2 : 0.8))
                        }.buttonStyle(.plain).help(FinishDef.part(d.name, 0))
                    }
                }
            }
            lookRow("Łuzy") {
                FlowLayout(spacing: 6) {
                    Button { s.pocketId = "auto" } label: {
                        Text("Jak stół").font(.system(size: 9.5, weight: .medium)).foregroundColor(UI.text).padding(.horizontal, 7).frame(height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(pocketSel == "auto" ? UI.menuAccent : Color.white.opacity(0.22), lineWidth: pocketSel == "auto" ? 2 : 0.8))
                    }.buttonStyle(.plain)
                    ForEach(FinishDef.pockets) { d in
                        Button { s.pocketId = d.id } label: {
                            Circle().fill(Self.metalGradient(d)).frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(pocketSel == d.id ? UI.menuAccent : Color.white.opacity(0.22), lineWidth: pocketSel == d.id ? 2.2 : 0.8))
                        }.buttonStyle(.plain).help(FinishDef.part(d.name, 1))
                    }
                }
            }
            lookRow("Zestaw bil") { WrapChips(items: BallSetDef.all.map { ($0.id, $0.name) }, sel: s.ballSetId) { s.ballSetId = $0 } }
            Text("Sukno: \(s.cloth.name) · Rama: \(FinishDef.part(s.finish.name, 0)) · Łuzy: \(FinishDef.part(s.pocketFinish.name, 1)) · Bile: \(s.ballSet.name)")
                .font(.system(size: 10)).foregroundColor(UI.dim)
            Text("Najedź na próbkę, by zobaczyć nazwę. Model stołu i statystyki kija działają od następnej partii.")
                .font(.system(size: 9.5)).foregroundColor(UI.faint)
        }
    }

    static func railColor(_ d: FinishDef) -> Color {
        let t = d.railTint
        var r = Double((t >> 16) & 0xFF) / 255, g = Double((t >> 8) & 0xFF) / 255, b = Double(t & 0xFF) / 255
        if d.natural && !d.solid { r *= 0.55; g *= 0.36; b *= 0.22 }   // drewno orzecha × barwa
        return Color(red: min(1, r * (d.natural ? 1.4 : 1)), green: min(1, g * (d.natural ? 1.4 : 1)), blue: min(1, b * (d.natural ? 1.4 : 1)))
    }
    static func metalGradient(_ d: FinishDef) -> LinearGradient {
        let c = Color(nsc(d.fittingTint))
        let stops: [Color] = d.mirror ? [.white.opacity(0.95), c, c.opacity(0.55), c, .white.opacity(0.7)] : [c.opacity(0.95), c.opacity(0.7), c.opacity(0.9)]
        return LinearGradient(colors: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Rekordy
    var recordsTab: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(GameMode.allCases.filter { $0 != .practice }, id: \.self) { gm in Chip(title: gm.title, selected: recMode == gm) { recMode = gm } }
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
            Row(label: "Menu główne") {
                Chip(title: "Na suknie (demo)", selected: s.clothMenu) { s.clothMenu = true }
                Chip(title: "Klasyczne", selected: !s.clothMenu) { s.clothMenu = false }
            }
            Row(label: "Otoczenie (HDRI)") {
                WrapChips(items: HDRIDef.all.map { ($0.id, $0.name) } + (HDRIDef.hasCustom ? [("custom", "Własne")] : []) + [("+", HDRIDef.hasCustom ? "Zmień własne…" : "Dodaj własne…")], sel: s.hdriId) { id in
                    if id == "+" { HDRIDef.pickCustom { ok in if ok { s.hdriId = "custom"; TableBuilder.envKey = ""; s.hdriBg = s.hdriBg } } } else { s.hdriId = id }
                }
            }
            Row(label: "Tło") {
                Chip(title: "Ciemne", selected: s.hdriBg == 0) { s.hdriBg = 0 }
                Chip(title: "Rozmyte", selected: s.hdriBg == 1) { s.hdriBg = 1 }
                Chip(title: "Ostre", selected: s.hdriBg == 2) { s.hdriBg = 2 }
            }
            if s.hdriBg > 0 {
                Row(label: "Jasność tła") { Slider(value: $s.hdriBright, in: 0.1...1.5).frame(width: 240).tint(UI.menuAccent) }
                if s.hdriBg == 1 { Row(label: "Rozmycie tła") { Slider(value: $s.hdriBlur, in: 0...1).frame(width: 240).tint(UI.menuAccent) } }
            }
            Row(label: "Preset") {
                ForEach(GfxPreset.allCases.dropLast(), id: \.rawValue) { p in
                    Chip(title: p.title, selected: s.preset == p.rawValue) { s.setPreset(p) }
                }
                if s.preset == GfxPreset.custom.rawValue { Text("Własne").font(.system(size: 11)).foregroundColor(UI.menuAccent) }
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
                toggle("HDR", $s.hdr); toggle("Bloom", $s.bloom); toggle("Głębia ostrości", $s.dof); toggle("Pył w świetle", $s.dust); toggle("SSAO (wolne)", $s.ssao); toggle("Licznik FPS", $s.showFps); toggle("Tło panelu sterowania", $s.dockBg)
            }
            if s.hdr {
                Text(HDRSupport.available ? "HDR: ekran obsługuje rozszerzony zakres jasności (\(String(format: "%.1f", HDRSupport.headroom))×), światła są jaśniejsze." : "HDR: ten ekran nie obsługuje rozszerzonego zakresu jasności, więc efekt jest ograniczony do szerszych świateł.")
                    .font(.system(size: 10)).foregroundColor(UI.faint)
            }
            Row(label: "Rozdzielczość 3D") {
                HStack(spacing: 8) {
                    Slider(value: $s.renderScale, in: 0.25...1.0, step: 0.05).frame(width: 240).tint(UI.menuAccent)
                    Text("\(Int((s.renderScale * 100).rounded()))%").font(UI.number(11)).foregroundColor(UI.dim).frame(width: 38, alignment: .trailing)
                }
            }
            Row(label: "Dynamiczna rozdzielczość") {
                Chip(title: "Włączona", selected: s.adaptiveRes, width: 90) { s.adaptiveRes = true }
                Chip(title: "Wyłączona", selected: !s.adaptiveRes, width: 90) { s.adaptiveRes = false }
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
            Slider(value: b, in: 0...1).frame(width: 240).tint(UI.menuAccent)
            Text("\(Int(b.wrappedValue * 100))%").font(UI.number(11)).foregroundColor(UI.dim).frame(width: 38, alignment: .trailing)
        }
    }

    // MARK: O autorze
    var aboutTab: some View {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    if let u = Bundle.main.url(forResource: "author", withExtension: "jpg"), let img = NSImage(contentsOf: u) {
                        Image(nsImage: img).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(Circle())
                            .overlay(Circle().stroke(UI.menuAccent.opacity(0.7), lineWidth: 1.5))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bilard · wersja \(v)").font(.system(size: 17, weight: .bold)).foregroundColor(UI.text)
                        Text("Autor: Tomasz Marchewka · studio BLUEROOT").font(.system(size: 13)).foregroundColor(UI.menuAccent)
                    }
                }
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


/// opcje zawijane w wiersze (zamiast jednej długiej kolumny)
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}

struct WrapChips: View {
    let items: [(String, String)]
    let sel: String
    let pick: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(items, id: \.0) { it in Chip(title: it.1, selected: sel == it.0) { pick(it.0) } }
        }
    }
}


/// miniatura kija: końcówka, trzonek, kolba z pierścieniami (kolory z definicji)
struct CueStrip: View {
    let d: CueDef
    var body: some View {
        Canvas { ctx, size in
            func col(_ c: UInt32) -> Color { Color(nsc(c)) }
            let y = size.height / 2, w = size.width, split = w * 0.5
            var shaft = Path()
            shaft.move(to: CGPoint(x: 0, y: y - 2)); shaft.addLine(to: CGPoint(x: split, y: y - 3.3))
            shaft.addLine(to: CGPoint(x: split, y: y + 3.3)); shaft.addLine(to: CGPoint(x: 0, y: y + 2)); shaft.closeSubpath()
            ctx.fill(shaft, with: .color(col(d.shaft)))
            var butt = Path()
            butt.move(to: CGPoint(x: split, y: y - 3.6)); butt.addLine(to: CGPoint(x: w, y: y - 6))
            butt.addLine(to: CGPoint(x: w, y: y + 6)); butt.addLine(to: CGPoint(x: split, y: y + 3.6)); butt.closeSubpath()
            if let g = d.glow { ctx.drawLayer { l in l.addFilter(.shadow(color: col(g).opacity(0.9), radius: 3)); l.fill(butt, with: .color(col(d.butt))) } }
            else { ctx.fill(butt, with: .color(col(d.butt))) }
            ctx.fill(Path(CGRect(x: 0, y: y - 2, width: 4, height: 4)), with: .color(col(0xF4F1E8)))
            ctx.fill(Path(CGRect(x: split - 1.5, y: y - 3.8, width: 3, height: 7.6)), with: .color(col(d.ring)))
            ctx.fill(Path(CGRect(x: w - 3, y: y - 6.2, width: 3, height: 12.4)), with: .color(col(d.ring)))
            let accent = col(d.accent ?? d.ring)
            for i in 0..<d.bands {
                let x = split + (w - split) * (0.22 + 0.14 * CGFloat(i))
                let hh = 3.8 + (x - split) / (w - split) * 2.3
                if let g = d.glow { ctx.drawLayer { l in l.addFilter(.shadow(color: col(g), radius: 2)); l.fill(Path(CGRect(x: x, y: y - hh, width: 2.2, height: hh * 2)), with: .color(col(g))) } }
                else { ctx.fill(Path(CGRect(x: x, y: y - hh, width: i % 2 == 0 ? 2.2 : 3.4, height: hh * 2)), with: .color(accent)) }
            }
        }
    }
}
