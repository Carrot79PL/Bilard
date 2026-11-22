import Foundation
import Combine
import AppKit

// MARK: - Definicje personalizacji (kije, sukna, zestawy bil)

struct CueDef: Identifiable, Equatable {
    let id: String, name: String, blurb: String
    let shaft: UInt32, butt: UInt32, ring: UInt32
    let metalRing: Bool
    /// długość linii pomocniczej / precyzja celowania (1 = bazowa)
    let aimLine: Double
    /// mnożnik maksymalnej mocy uderzenia
    let maxPower: Double
    /// kontrola rotacji (mnożnik efektywnego przesunięcia punktu uderzenia)
    let spinCtl: Double
    var glow: UInt32? = nil
    /// ozdobne pierścienie na kolbie (0…5) i ich kolor
    var bands = 0
    var accent: UInt32? = nil

    static let all: [CueDef] = [
        CueDef(id: "maple", name: "Klonowy klasyczny", blurb: "Wyważony, uniwersalny", shaft: 0xE9D3A4, butt: 0x6B3E1F, ring: 0xC9A24A, metalRing: true, aimLine: 1.0, maxPower: 1.0, spinCtl: 1.0, bands: 2),
        CueDef(id: "carbon", name: "Karbonowy czarny", blurb: "Precyzyjny, lżejszy w mocy", shaft: 0x16171A, butt: 0x0C0C0E, ring: 0x9AA0A8, metalRing: true, aimLine: 1.3, maxPower: 0.95, spinCtl: 0.92, bands: 2, accent: 0xD0D4DA),
        CueDef(id: "mahogany", name: "Mahoniowy zdobiony", blurb: "Mocny, krótsza linia celowania", shaft: 0xDDBE86, butt: 0x4A1A12, ring: 0xD7B25A, metalRing: true, aimLine: 0.85, maxPower: 1.07, spinCtl: 1.05, bands: 3),
        CueDef(id: "ash", name: "Snookerowy jesionowy", blurb: "Najlepsza kontrola rotacji", shaft: 0xF1E4C4, butt: 0xB98A55, ring: 0xB8B2A4, metalRing: true, aimLine: 1.1, maxPower: 0.93, spinCtl: 1.18, bands: 1, accent: 0x6B3E1F),
        CueDef(id: "neon", name: "Futurystyczny", blurb: "Długa linia, mniejsza kontrola spinu", shaft: 0xCFD6DE, butt: 0x1B2A3A, ring: 0x35E0FF, metalRing: false, aimLine: 1.45, maxPower: 1.03, spinCtl: 0.85, glow: 0x35E0FF, bands: 3),
        CueDef(id: "ebony", name: "Heban i mosiądz", blurb: "Mocny, ciężki, bardzo stabilny", shaft: 0xE6D2A2, butt: 0x1A1210, ring: 0xD7B25A, metalRing: true, aimLine: 0.9, maxPower: 1.1, spinCtl: 0.95, bands: 3, accent: 0xD7B25A),
        CueDef(id: "ruby", name: "Rubinowy", blurb: "Lekki, dobra kontrola spinu", shaft: 0xF0E2BE, butt: 0x6A0F18, ring: 0xD8DCE2, metalRing: true, aimLine: 1.05, maxPower: 0.96, spinCtl: 1.12, bands: 2, accent: 0xE8E8EE),
        CueDef(id: "cobalt", name: "Kobaltowy", blurb: "Długa linia, wyważony", shaft: 0xDCE4EE, butt: 0x123A7A, ring: 0xC0C8D8, metalRing: true, aimLine: 1.25, maxPower: 1.0, spinCtl: 1.0, bands: 3, accent: 0x7FB0FF),
        CueDef(id: "emerald", name: "Szmaragdowy", blurb: "Precyzja i kontrola kosztem mocy", shaft: 0xEADFC0, butt: 0x0F4A2E, ring: 0xE6E6E0, metalRing: true, aimLine: 1.15, maxPower: 0.92, spinCtl: 1.2, bands: 2, accent: 0xE6E6E0),
        CueDef(id: "royal", name: "Królewski złoty", blurb: "Najmocniejszy, krótka linia", shaft: 0xF4E6C0, butt: 0x3A2A10, ring: 0xF2C75C, metalRing: true, aimLine: 0.8, maxPower: 1.14, spinCtl: 0.9, bands: 5, accent: 0xF2C75C),
    ]
    static func find(_ id: String) -> CueDef { all.first { $0.id == id } ?? all[0] }
}

struct ClothDef: Identifiable, Equatable {
    let id: String, name: String
    let color: UInt32
    /// siła mikro-reliefu splotu (mnożnik normal mapy)
    let weave: Double
    /// gęstość splotu (skala powtarzania tekstury)
    let density: Double
    static let all: [ClothDef] = [
        ClothDef(id: "blue", name: "Tournament Blue", color: 0x1C56D2, weave: 1.0, density: 1.0),
        ClothDef(id: "green", name: "English Green", color: 0x13703A, weave: 1.1, density: 1.0),
        ClothDef(id: "burgundy", name: "Burgundy", color: 0x8A2233, weave: 1.25, density: 0.9),
        ClothDef(id: "charcoal", name: "Charcoal", color: 0x3C4046, weave: 0.9, density: 1.25),
        ClothDef(id: "camel", name: "Camel", color: 0xA07A48, weave: 1.4, density: 0.8),
        ClothDef(id: "purple", name: "Royal Purple", color: 0x4B2A86, weave: 1.1, density: 1.0),
        ClothDef(id: "teal", name: "Teal", color: 0x0E7C86, weave: 1.0, density: 1.1),
        ClothDef(id: "racing", name: "Racing Green", color: 0x0A4A2E, weave: 1.2, density: 1.0),
        ClothDef(id: "midnight", name: "Midnight", color: 0x0F1C48, weave: 0.9, density: 1.2),
        ClothDef(id: "sky", name: "Sky Blue", color: 0x3F8FE0, weave: 1.0, density: 1.0),
        ClothDef(id: "crimson", name: "Crimson", color: 0xB3202E, weave: 1.2, density: 0.95),
        ClothDef(id: "orange", name: "Sunset Orange", color: 0xD2601C, weave: 1.1, density: 0.9),
        ClothDef(id: "lime", name: "Lime", color: 0x6FB82C, weave: 1.0, density: 1.0),
        ClothDef(id: "rose", name: "Rose", color: 0xC86088, weave: 1.0, density: 1.0),
        ClothDef(id: "slate", name: "Slate", color: 0x5A6878, weave: 0.9, density: 1.2),
        ClothDef(id: "sand", name: "Sand", color: 0xC8B48A, weave: 1.3, density: 0.85),
        ClothDef(id: "black", name: "Black", color: 0x1A1B1E, weave: 0.9, density: 1.3),
        ClothDef(id: "ice", name: "Ice White", color: 0xD6DEE6, weave: 1.0, density: 1.1),
        ClothDef(id: "gold", name: "Antique Gold", color: 0xB8932E, weave: 1.3, density: 0.85),
        ClothDef(id: "emerald", name: "Emerald", color: 0x0E8A58, weave: 1.1, density: 1.0),
    ]
    static func find(_ id: String) -> ClothDef { all.first { $0.id == id } ?? all[0] }
}

struct BallSetDef: Identifiable, Equatable {
    let id: String, name: String, blurb: String
    static let all: [BallSetDef] = [
        BallSetDef(id: "classic", name: "Aramith klasyczny", blurb: "Standardowe kolory 1–15"),
        BallSetDef(id: "tv", name: "Turniejowy TV", blurb: "Różowa 4 i brązowa 7 dla kamer"),
        BallSetDef(id: "dark", name: "Dark Edition", blurb: "Czarna żywica, neonowe numery"),
        BallSetDef(id: "snooker", name: "Snookerowy", blurb: "Matowe, jednolite barwy snookera"),
        BallSetDef(id: "chrome", name: "Lustrzany chrom", blurb: "Polerowany metal odbija salę i sąsiednie bile"),
        BallSetDef(id: "gold", name: "Złoto szczotkowane", blurb: "Szczotkowane złoto, biała z miedzi"),
        BallSetDef(id: "pearl", name: "Perłowy", blurb: "Masa perłowa mieniąca się pod kątem"),
        BallSetDef(id: "glass", name: "Szklany", blurb: "Półprzezroczyste szkło z kryjącymi numerami"),
        BallSetDef(id: "onyx", name: "Onyks", blurb: "Czarny kamień z żyłkami, biała z marmuru"),
    ]
    static func find(_ id: String) -> BallSetDef { all.first { $0.id == id } ?? all[0] }
}

/// wykończenie stołu: rama (lakier/drewno) + okucia łuz
struct FinishDef: Identifiable, Equatable {
    let id: String, name: String
    let railTint: UInt32          // mnożnik koloru ramy (0xFFFFFF = naturalny orzech)
    let natural: Bool             // true: widoczne drewno (mniej lakieru), false: głęboki lakier
    let fittingTint: UInt32       // barwa okuć
    let mirror: Bool              // true: lustrzany chrom, false: szczotkowany metal
    let fittingGloss: Double      // połysk okuć 0…1
    var solid = false             // true: jednolity lakier w kolorze railTint (bez słojów)
    static let all: [FinishDef] = [
        FinishDef(id: "alu", name: "Czarny lakier · aluminium szczotkowane", railTint: 0x060606, natural: false, fittingTint: 0xFFFFFF, mirror: false, fittingGloss: 0.28),
        FinishDef(id: "chrome", name: "Czarny lakier · chrom lustrzany", railTint: 0x060606, natural: false, fittingTint: 0xFFFFFF, mirror: true, fittingGloss: 0.95),
        FinishDef(id: "walnut", name: "Orzech naturalny · mosiądz szczotkowany", railTint: 0xFFFFFF, natural: true, fittingTint: 0xE0B25C, mirror: false, fittingGloss: 0.35),
        FinishDef(id: "navy", name: "Granatowy lakier · grafitowa stal", railTint: 0x0A1A40, natural: false, fittingTint: 0x8A8F99, mirror: false, fittingGloss: 0.22),
        FinishDef(id: "burgundy", name: "Bordowy lakier · miedź szczotkowana", railTint: 0x3A0812, natural: false, fittingTint: 0xE0905F, mirror: false, fittingGloss: 0.3),
        FinishDef(id: "blackgold", name: "Czarny lakier · złoto lustrzane", railTint: 0x060606, natural: false, fittingTint: 0xFFD27A, mirror: true, fittingGloss: 0.95),
        FinishDef(id: "gunmetal", name: "Czarny lakier · czarna stal polerowana", railTint: 0x060606, natural: false, fittingTint: 0x6A707A, mirror: true, fittingGloss: 0.9),
        FinishDef(id: "rose", name: "Czarny lakier · różowe złoto szczotkowane", railTint: 0x060606, natural: false, fittingTint: 0xF0B49A, mirror: false, fittingGloss: 0.3),
        FinishDef(id: "mahogany", name: "Mahoń · mosiądz szczotkowany", railTint: 0xD89A80, natural: true, fittingTint: 0xE0B25C, mirror: false, fittingGloss: 0.35),
        FinishDef(id: "cherry", name: "Wiśnia · miedź lustrzana", railTint: 0xE87A5A, natural: true, fittingTint: 0xFFA070, mirror: true, fittingGloss: 0.9),
        FinishDef(id: "forest", name: "Zielony lakier · złoto lustrzane", railTint: 0x0F3B26, natural: false, fittingTint: 0xFFD27A, mirror: true, fittingGloss: 0.95, solid: true),
        FinishDef(id: "ivory", name: "Kość słoniowa · mosiądz szczotkowany", railTint: 0xDCD3BC, natural: false, fittingTint: 0xE0B25C, mirror: false, fittingGloss: 0.35, solid: true),
        FinishDef(id: "red", name: "Czerwony lakier · chrom lustrzany", railTint: 0x6E1016, natural: false, fittingTint: 0xFFFFFF, mirror: true, fittingGloss: 0.95, solid: true),
        FinishDef(id: "graphite", name: "Grafit satynowy · tytan szczotkowany", railTint: 0x2B2E34, natural: false, fittingTint: 0xAEB8C8, mirror: false, fittingGloss: 0.25, solid: true),
        FinishDef(id: "white", name: "Biały lakier · brąz antyczny", railTint: 0xE8E8E8, natural: false, fittingTint: 0xA8743C, mirror: false, fittingGloss: 0.25, solid: true),
        FinishDef(id: "emeraldrail", name: "Szmaragdowy lakier · srebro lustrzane", railTint: 0x0E5A44, natural: false, fittingTint: 0xE6E9EE, mirror: true, fittingGloss: 0.95, solid: true),
        FinishDef(id: "violet", name: "Fioletowy lakier · złoto szczotkowane", railTint: 0x3A1D5C, natural: false, fittingTint: 0xE8C060, mirror: false, fittingGloss: 0.3, solid: true),
        FinishDef(id: "azure", name: "Błękitny lakier · chrom czarny", railTint: 0x1B5FA8, natural: false, fittingTint: 0x2A2C30, mirror: true, fittingGloss: 0.9, solid: true),
        FinishDef(id: "tangerine", name: "Pomarańczowy lakier · miedź patynowana", railTint: 0xC9541A, natural: false, fittingTint: 0x5FA58A, mirror: false, fittingGloss: 0.25, solid: true),
        FinishDef(id: "rosewood", name: "Palisander · tytan lustrzany", railTint: 0x8A5A48, natural: true, fittingTint: 0xB8C4D4, mirror: true, fittingGloss: 0.9),
        FinishDef(id: "ebony", name: "Heban · mosiądz lustrzany", railTint: 0x241814, natural: true, fittingTint: 0xF0CC7A, mirror: true, fittingGloss: 0.92),
        FinishDef(id: "silver", name: "Srebrny lakier · stal niebieska", railTint: 0xA8AEB6, natural: false, fittingTint: 0x5A7AA8, mirror: false, fittingGloss: 0.3, solid: true),
        FinishDef(id: "turquoise", name: "Turkusowy lakier · różowe złoto lustrzane", railTint: 0x14808A, natural: false, fittingTint: 0xF6B8A4, mirror: true, fittingGloss: 0.93, solid: true),
        FinishDef(id: "sandy", name: "Piaskowy lakier · platyna szczotkowana", railTint: 0xC4A878, natural: false, fittingTint: 0xCFD2D8, mirror: false, fittingGloss: 0.28, solid: true),
    ]
    static func part(_ n: String, _ i: Int) -> String { let a = n.components(separatedBy: " · "); return a[min(i, a.count - 1)] }
    /// unikalne wykończenia stołu (rama) i łuz (okucia) do osobnego wyboru
    static var tables: [FinishDef] { var seen = Set<String>(); return all.filter { seen.insert(part($0.name, 0) + String($0.railTint)).inserted } }
    static var pockets: [FinishDef] { var seen = Set<String>(); return all.filter { seen.insert(part($0.name, 1)).inserted } }
    static func find(_ id: String) -> FinishDef { all.first { $0.id == id } ?? all[0] }
}

enum AILevel: Int, CaseIterable {
    case amateur = 0, club, master
    var title: String { ["Amator", "Klubowicz", "Mistrz"][rawValue] }
    var blurb: String { ["Duży rozrzut, tylko łatwe strzały", "Zrównoważony", "Precyzyjny, planuje kolejne uderzenie"][rawValue] }
    /// odchylenie kąta [rad], rozrzut siły, minimalny cosinus „cięcia”, szum doboru, głębokość planu
    var angleErr: Double { [0.032, 0.011, 0.0035][rawValue] }
    var powerErr: Double { [0.16, 0.06, 0.022][rawValue] }
    var minCut: Double { [0.55, 0.28, 0.12][rawValue] }
    var pickNoise: Double { [0.55, 0.0, 0.0][rawValue] }
    var depth: Int { [1, 1, 2][rawValue] }
}

// MARK: - Ustawienia (UserDefaults)

enum GfxPreset: Int, CaseIterable {
    case low = 0, medium, high, ultra, custom
    var title: String { ["Niska", "Średnia", "Wysoka", "Ultra", "Własne"][rawValue] }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard
    private var loading = true

    var onLook: () -> Void = {}
    var onGraphics: () -> Void = {}
    var onAudio: () -> Void = {}

    // gracze
    @Published var name1: String { didSet { d.set(name1, forKey: "p1Name") } }
    @Published var name2: String { didSet { d.set(name2, forKey: "p2Name") } }
    @Published var aiLevel: Int { didSet { d.set(aiLevel, forKey: "aiLevel") } }
    var level: AILevel { AILevel(rawValue: aiLevel) ?? .club }

    // personalizacja
    @Published var cueId: String { didSet { d.set(cueId, forKey: "cueId"); look() } }
    @Published var clothMenu: Bool { didSet { d.set(clothMenu, forKey: "clothMenu"); look() } }
    @Published var emblemId: String { didSet { d.set(emblemId, forKey: "emblemId"); look() } }
    @Published var clothId: String { didSet { d.set(clothId, forKey: "clothId"); look() } }
    @Published var ballSetId: String { didSet { d.set(ballSetId, forKey: "ballSetId"); look() } }
    @Published var finishId: String { didSet { d.set(finishId, forKey: "finishId"); look() } }
    @Published var tableModelId: String { didSet { d.set(tableModelId, forKey: "tableModelId"); look() } }
    @Published var pocketId: String { didSet { d.set(pocketId, forKey: "pocketId"); look() } }   // "auto" = jak stół
    var finish: FinishDef { FinishDef.find(finishId) }
    var pocketFinish: FinishDef { pocketId == "auto" ? finish : FinishDef.find(pocketId) }
    var cue: CueDef { CueDef.find(cueId) }
    var cloth: ClothDef { ClothDef.find(clothId) }
    var ballSet: BallSetDef { BallSetDef.find(ballSetId) }

    // grafika
    @Published var preset: Int { didSet { d.set(preset, forKey: "gfxPreset") } }
    @Published var texRes: Int { didSet { d.set(texRes, forKey: "gfxTex"); gfx() } }            // 1, 2, 4 (K)
    @Published var reflections: Int { didSet { d.set(reflections, forKey: "gfxRefl"); gfx() } }  // 0 wył., 1 środowiskowe, 2 pełne (sonda)
    @Published var shadows: Int { didSet { d.set(shadows, forKey: "gfxShadow"); gfx() } }        // 0…3
    @Published var hdr: Bool { didSet { d.set(hdr, forKey: "gfxHDR"); gfx() } }            // wyjście HDR/EDR na ekran z podwyższonym zakresem jasności
    @Published var bloom: Bool { didSet { d.set(bloom, forKey: "gfxBloom"); gfx() } }
    @Published var dof: Bool { didSet { d.set(dof, forKey: "gfxDof"); gfx() } }
    @Published var dockBg: Bool { didSet { d.set(dockBg, forKey: "hudDockBg") } }      // tło panelu sterowania (siła/kąt)
    @Published var dust: Bool { didSet { d.set(dust, forKey: "gfxDust"); gfx() } }
    @Published var ssao: Bool { didSet { d.set(ssao, forKey: "gfxSSAO"); gfx() } }     // SSAO SceneKit: ~-15 FPS, niezależnie od rozdzielczości
    @Published var aimUsesPower: Bool { didSet { d.set(aimUsesPower, forKey: "aimUsesPower") } }   // linia celowania zależna od ustawionej siły
    @Published var showFps: Bool { didSet { d.set(showFps, forKey: "gfxShowFps") } }   // licznik FPS w rogu ekranu
    @Published var fps: Int { didSet { d.set(fps, forKey: "gfxFps"); gfx() } }
    @Published var renderScale: Double { didSet { d.set(renderScale, forKey: "gfxScale"); if !loading { onGraphics() } } }   // 0,25…1 (część rozdzielczości ekranu)

    // dźwięk
    @Published var musicVol: Double { didSet { d.set(musicVol, forKey: "audMusic"); snd() } }
    @Published var sfxVol: Double { didSet { d.set(sfxVol, forKey: "audSfx"); snd() } }
    @Published var ambVol: Double { didSet { d.set(ambVol, forKey: "audAmb"); snd() } }
    @Published var musicStyle: String { didSet { d.set(musicStyle, forKey: "audStyle"); snd() } }
    @Published var muted: Bool { didSet { d.set(muted, forKey: "audMute"); snd() } }

    private func look() { if !loading { onLook() } }
    private func gfx() { if !loading { if !applyingPreset { preset = GfxPreset.custom.rawValue }; onGraphics() } }
    private func snd() { if !loading { onAudio() } }
    private var applyingPreset = false

    init() {
        func s(_ k: String, _ def: String) -> String { UserDefaults.standard.string(forKey: k) ?? def }
        func i(_ k: String, _ def: Int) -> Int { UserDefaults.standard.object(forKey: k) as? Int ?? def }
        func f(_ k: String, _ def: Double) -> Double { UserDefaults.standard.object(forKey: k) as? Double ?? def }
        func b(_ k: String, _ def: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? def }
        name1 = s("p1Name", "Gracz 1"); name2 = s("p2Name", "Gracz 2")
        aiLevel = i("aiLevel", 1)
        finishId = s("finishId", "alu")
        pocketId = s("pocketId", "auto")
        tableModelId = ProcessInfo.processInfo.environment["BILARD_TABLEMODEL"] ?? s("tableModelId", "model")
        cueId = s("cueId", "maple"); clothId = s("clothId", "blue"); clothMenu = ProcessInfo.processInfo.environment["BILARD_CLOTHMENU"] != nil || ((UserDefaults.standard.object(forKey: "clothMenu") as? Bool) ?? false); emblemId = ProcessInfo.processInfo.environment["BILARD_EMBLEM"] ?? s("emblemId", "blueroot"); ballSetId = ProcessInfo.processInfo.environment["BILARD_BALLSET"] ?? s("ballSetId", "classic")
        preset = i("gfxPreset", GfxPreset.high.rawValue)
        texRes = i("gfxTex", 2); reflections = i("gfxRefl", 1); shadows = i("gfxShadow", 2)
        hdr = ProcessInfo.processInfo.environment["BILARD_HDR"] != nil || b("gfxHDR", false); bloom = b("gfxBloom", true); dof = b("gfxDof", false); dust = b("gfxDust", true); ssao = b("gfxSSAO", false); fps = i("gfxFps", 60); showFps = b("gfxShowFps", false); dockBg = b("hudDockBg", true); aimUsesPower = b("aimUsesPower", false)
        renderScale = Double(ProcessInfo.processInfo.environment["BILARD_SCALE"] ?? "") ?? f("gfxScale", 1.0)
        musicVol = f("audMusic", 0.5); sfxVol = f("audSfx", 0.9); ambVol = f("audAmb", 0.35)
        musicStyle = s("audStyle", "jazz"); muted = b("audMute", false)
        loading = false
    }

    func setPreset(_ p: GfxPreset) {
        guard p != .custom else { return }
        loading = true
        applyingPreset = true
        switch p {
        case .low:    texRes = 1; reflections = 0; shadows = 0; bloom = false; dof = false; dust = false; ssao = false; fps = 60
        case .medium: texRes = 2; reflections = 1; shadows = 1; bloom = true; dof = false; dust = false; ssao = false; fps = 60
        case .high:   texRes = 2; reflections = 1; shadows = 2; bloom = true; dof = false; dust = true; ssao = false; fps = 60
        case .ultra:  texRes = 4; reflections = 2; shadows = 3; hdr = HDRSupport.available; bloom = true; dof = false; dust = true; ssao = true; fps = 120
        case .custom: break
        }
        applyingPreset = false
        preset = p.rawValue
        loading = false
        onGraphics()
    }

    /// nazwa gracza z uwzględnieniem trybu z komputerem
    var match: MatchSetup? = nil
    var activeLevel: AILevel { match?.levels[1] ?? level }

    func playerName(_ p: Int, vsAI: Bool) -> String {
        if let m = match { return m.names[p] }
        func clean(_ s: String, _ def: String) -> String { let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? def : String(t.prefix(16)) }
        if p == 0 { return clean(name1, "Gracz 1") }
        return vsAI ? "Komputer · \(level.title)" : clean(name2, "Gracz 2")
    }
}

// MARK: - Tablica rekordów (JSON w Application Support)

struct RecEntry: Codable {
    var games = 0, wins = 0, bestBreak = 0
    var fastest: Double? = nil        // najkrótsza wygrana partia [s] (czyszczenie stołu)
    var winPct: Int { games == 0 ? 0 : Int((Double(wins) / Double(games) * 100).rounded()) }
}

final class RecordStore: ObservableObject {
    static let shared = RecordStore()
    @Published private(set) var data: [String: [String: RecEntry]] = [:]
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bilard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("records.json")
        if let raw = try? Data(contentsOf: url), let d = try? JSONDecoder().decode([String: [String: RecEntry]].self, from: raw) { data = d }
    }

    func record(mode: GameMode, name: String, won: Bool, bestBreak: Int, seconds: Double) {
        if ProcessInfo.processInfo.environment["BILARD_NOSAVE"] != nil { return }
        var e = data[mode.rawValue]?[name] ?? RecEntry()
        e.games += 1
        if won {
            e.wins += 1
            e.fastest = min(e.fastest ?? .infinity, seconds)
        }
        e.bestBreak = max(e.bestBreak, bestBreak)
        data[mode.rawValue, default: [:]][name] = e
        save()
    }

    func rows(_ mode: GameMode) -> [(String, RecEntry)] {
        (data[mode.rawValue] ?? [:]).sorted { ($0.value.wins, $0.value.games) > ($1.value.wins, $1.value.games) }
    }

    func reset() { data = [:]; save() }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) { try? raw.write(to: url, options: .atomic) }
    }
}
