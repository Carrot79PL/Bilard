import SceneKit
import AppKit
import Foundation
import SwiftUI
import simd

// MARK: - Zasady 8-Ball, maszyna stanów, model dla HUD, prosty przeciwnik AI

enum Group: Int {
    case solids = 0, stripes = 1
    var name: String { self == .solids ? "Pełne" : "Połówki" }
    var range: ClosedRange<Int> { self == .solids ? 1...7 : 9...15 }
    static func of(_ ball: Int) -> Group? { ball >= 1 && ball <= 7 ? .solids : (ball >= 9 && ball <= 15 ? .stripes : nil) }
}

enum Phase {
    case menu          // ekran startowy
    case placing       // „biała w ręce”: ustawianie białej bili
    case aiming        // celowanie (gracz lub komputer)
    case striking      // animacja uderzenia kijem
    case rolling       // bile w ruchu
    case gameOver
}

struct ShotReport {
    var firstContact: Int? = nil
    var pocketed: [Int] = []
    var pocketLog: [(ball: Int, pocket: Int)] = []     // bila → indeks łuzy
    var cushionAfterContact = false
    var railBalls: Set<Int> = []
    var calledBall: Int? = nil          // deklaracja (Call Shot: 10-Ball, 14/1)
    var calledPocket: Int? = nil
    var offTable: [Int] = []            // bile wybite poza stół (skok)
}

struct ShotOutcome {
    var foul = false
    var message = ""
    var continueTurn = false
    var winner: Int? = nil
    var respot: [Int] = []          // bile do ustawienia z powrotem na punkcie startowym (najbliższe wolne miejsce na osi)
    var respotAt: [Int: V2] = [:]   // j.w., ale z własnym punktem (snooker: punkty kolorowych)
    var respotDir = -1.0            // w którą stronę osi X szukać wolnego miejsca
    var placeExact: [Int: V2] = [:] // dokładne pozycje (trójkąt w 14/1)
    var rerack = false
    var ballInHand = false
    var assigned: Group? = nil      // grupa przypisana strzelającemu
    var scoreDelta: [Int] = [0, 0]
}

/// ustawienia z menu / zmiennych środowiskowych
enum GameConfig {
    static var target = Int(ProcessInfo.processInfo.environment["BILARD_TARGET"] ?? "") ?? 50
    static var reds = max(1, min(15, Int(ProcessInfo.processInfo.environment["BILARD_REDS"] ?? "") ?? 15))
}

/// punkty kolorowych bil snookera (x wzdłuż stołu, y = z poprzecznie); bila 16 żółta … 21 czarna
enum SnookerLayout {
    static var baulkX: Double { -Phys.halfL + 0.737 }
    static var spots: [Int: V2] {
        [16: V2(baulkX, 0.292), 17: V2(baulkX, -0.292), 18: V2(baulkX, 0),
         19: V2(0, 0), 20: V2(Phys.halfL / 2, 0), 21: V2(Phys.halfL - 0.324, 0)]
    }
    static let names = [16: "żółta", 17: "zielona", 18: "brązowa", 19: "niebieska", 20: "różowa", 21: "czarna"]
    static func value(_ id: Int) -> Int { id <= 15 ? 1 : id - 14 }
}

enum GameMode: String, CaseIterable {
    case eight = "8ball", nine = "9ball", ten = "10ball", straight = "straight", snooker = "snooker"
    var title: String {
        switch self { case .eight: return "8-Ball"; case .nine: return "9-Ball"; case .ten: return "10-Ball"; case .straight: return "14/1"; case .snooker: return "Snooker" }
    }
    var subtitle: String {
        switch self {
        case .eight: return "Pełne i połówki, 15 bil, czarna ósemka"
        case .nine: return "Bile 1–9 po kolei, wygrywa dziewiątka"
        case .ten: return "Bile 1–10, deklaracja bili i łuzy (Call Shot), wygrywa dziesiątka"
        case .straight: return "Gra do N punktów, deklarowane wbicia, trójkąt po 14 bilach"
        case .snooker: return "Stół 12 ft, 15 czerwonych i 6 kolorowych, punktacja do czarnej"
        }
    }
    var ballCount: Int { switch self { case .eight, .straight: return 15; case .nine: return 9; case .ten: return 10; case .snooker: return 21 } }
    var isPoints: Bool { self == .straight || self == .snooker }
    func makeRules() -> GameModeRules {
        switch self {
        case .eight: return EightBallRules()
        case .nine: return NineBallRules()
        case .ten: return TenBallRules()
        case .straight: return StraightPoolRules()
        case .snooker: return SnookerRules()
        }
    }
}

/// Wzorzec Strategy: wszystko, co zależy od odmiany gry.
protocol GameModeRules: AnyObject {
    var mode: GameMode { get }
    var current: Int { get set }
    var breakShot: Bool { get }
    var pocketed: [Int] { get }
    var groups: [Group?] { get }
    var vsAI: Bool { get }
    var needsCall: Bool { get }                 // czy trzeba zadeklarować zagranie (Call Shot)
    var ballSet: [Int] { get }                  // bile bryłowe używane w tym trybie (bez białej)
    var scores: [Int] { get }                   // punktacja (tryby punktowe)
    var tableCount: Int { get }                 // bile pozostałe na stole (bez białej)
    var currentBreak: Int { get }               // seria punktów w bieżącym podejściu
    var highBreak: Int { get }                  // najwyższa seria w partii
    var target: Int { get }                     // cel punktowy (14/1), 0 gdy brak
    var cueSpot: V2 { get }                     // gdzie ląduje biała po rozbiciu/wbiciu
    func reset(vsAI: Bool)
    func name(_ p: Int) -> String
    func isAI(_ p: Int) -> Bool
    /// ułożenie bil na stole: id → pozycja (stół, punkt rozbicia); nie wymienione = poza grą
    func layout(rng: inout SeededGen) -> [Int: V2]
    func legalTargets(_ p: Int) -> [Int]        // bile legalne jako pierwszy kontakt
    func callableBalls(_ p: Int) -> [Int]       // bile, które wolno zadeklarować
    func resolve(_ r: ShotReport) -> ShotOutcome
    func targetHint(_ p: Int) -> String         // krótki opis celu dla HUD
    func clampCue(_ p: V2, restricted: Bool) -> V2   // strefa ustawiania białej
    func rerack(remainingAt: V2) -> [Int: V2]        // 14/1: pozycje bil w nowym trójkącie
}

class BaseRules {
    var current = 0
    var breakShot = true
    var pocketed: [Int] = []
    var vsAI = true
    var scores = [0, 0]
    var currentBreak = 0
    var highBreak = 0
    var target: Int { 0 }
    var cueSpot: V2 { V2(-Phys.halfL / 2, 0) }
    func reset(vsAI: Bool) { current = 0; breakShot = true; pocketed = []; scores = [0, 0]; currentBreak = 0; highBreak = 0; self.vsAI = vsAI; resetExtra() }
    func resetExtra() {}
    func name(_ p: Int) -> String { Settings.shared.playerName(p, vsAI: vsAI) }
    func isAI(_ p: Int) -> Bool { vsAI && p == 1 }
    func callableBalls(_ p: Int) -> [Int] { [] }
    func clampCue(_ p: V2, restricted: Bool) -> V2 { var q = p; if restricted { q.x = min(q.x, -Phys.halfL / 2) }; return q }
    func rerack(remainingAt: V2) -> [Int: V2] { [:] }

    /// romb/trójkąt w standardowym miejscu: wiersze od wierzchołka; zwraca pozycje dla listy rzędów
    static func rackPositions(rows: [Int], apexX: Double? = nil) -> [V2] {
        let R = Phys.R
        let dx = 2 * R * cos(Double.pi / 6) + 0.0004, dz = 2 * R + 0.0004
        var out: [V2] = []
        for (k, n) in rows.enumerated() {
            for j in 0..<n { out.append(V2((apexX ?? Phys.halfL / 2) + Double(k) * dx, (Double(j) - Double(n - 1) / 2) * dz)) }
        }
        return out
    }
}

// MARK: 8-Ball

final class EightBallRules: BaseRules, GameModeRules {
    var mode: GameMode { .eight }
    var groups: [Group?] = [nil, nil]
    var needsCall: Bool { false }
    var ballSet: [Int] { Array(1...15) }
    var tableCount: Int { 15 - pocketed.count }
    override func resetExtra() { groups = [nil, nil] }

    func layout(rng: inout SeededGen) -> [Int: V2] {
        var pool = Array(1...15).filter { $0 != 8 }
        pool.shuffle(using: &rng)
        let sc = pool.remove(at: pool.firstIndex { $0 <= 7 }!)
        let tc = pool.remove(at: pool.firstIndex { $0 >= 9 }!)
        var slots: [(Int, Int)] = []
        for k in 0..<5 { for j in 0...k { slots.append((k, j)) } }
        let pos = Self.rackPositions(rows: [1, 2, 3, 4, 5])
        var rest = pool
        var out: [Int: V2] = [:]
        for (idx, s) in slots.enumerated() {
            let (k, j) = s
            let id: Int
            if k == 2 && j == 1 { id = 8 }
            else if k == 4 && j == 0 { id = sc }
            else if k == 4 && j == 4 { id = tc }
            else { id = rest.removeLast() }
            out[id] = pos[idx]
        }
        return out
    }

    func remaining(_ g: Group) -> [Int] { g.range.filter { !pocketed.contains($0) } }

    func legalTargets(_ p: Int) -> [Int] {
        if let g = groups[p] {
            let r = remaining(g)
            return r.isEmpty ? [8] : r
        }
        return (1...15).filter { $0 != 8 && !pocketed.contains($0) }
    }

    func targetHint(_ p: Int) -> String { groups[p]?.name ?? "Stół otwarty" }

    func resolve(_ r: ShotReport) -> ShotOutcome {
        var o = ShotOutcome()
        let me = current, opp = 1 - current
        let cue = r.pocketed.contains(0)
        var objs = r.pocketed.filter { $0 != 0 }
        var foulText = ""

        if breakShot {
            if cue { foulText = "Biała wpadła do łuzy" }
            else if r.firstContact == nil { foulText = "Biała nie trafiła w żadną bilę" }
            else if objs.isEmpty && r.railBalls.count < 4 { foulText = "Nielegalne rozbicie (min. 4 bile do band)" }
            if objs.contains(8) { o.respot = [8]; objs.removeAll { $0 == 8 } }
        } else {
            if cue { foulText = "Biała wpadła do łuzy" }
            else if let f = r.firstContact {
                if let g = groups[me] {
                    let legal = remaining(g).isEmpty ? [8] : remaining(g)
                    if !legal.contains(f) { foulText = "Pierwszy kontakt z niewłaściwą bilą" }
                } else if f == 8 { foulText = "Pierwszy kontakt z czarną bilą" }
            } else { foulText = "Biała nie trafiła w żadną bilę" }
            if foulText.isEmpty && objs.isEmpty && !r.cushionAfterContact { foulText = "Po kontakcie żadna bila nie dotknęła bandy" }
        }

        if !breakShot && objs.contains(8) {
            let clean = groups[me] != nil && remaining(groups[me]!).isEmpty
            if clean && foulText.isEmpty {
                o.winner = me
                o.message = "\(name(me)) wbija czarną i wygrywa!"
            } else {
                o.winner = opp
                o.message = clean ? "\(name(me)): faul przy czarnej – wygrywa \(name(opp))"
                                  : "\(name(me)) wbił czarną za wcześnie – wygrywa \(name(opp))"
            }
            pocketed += objs
            return o
        }

        if groups[me] == nil && !breakShot && foulText.isEmpty, let first = objs.first(where: { $0 != 8 }), let g = Group.of(first) {
            groups[me] = g
            groups[opp] = g == .solids ? .stripes : .solids
            o.assigned = g
        }
        pocketed += objs

        if !foulText.isEmpty {
            o.foul = true
            o.ballInHand = true
            o.continueTurn = false
            o.message = "Faul: \(foulText). Biała w ręce dla: \(name(opp))"
        } else if breakShot {
            o.continueTurn = !objs.isEmpty
            o.message = objs.isEmpty ? "Zmiana gracza" : "Wbito bilę na rozbiciu – \(name(me)) gra dalej (stół otwarty)"
        } else if let g = groups[me] {
            let mine = objs.contains { Group.of($0) == g } || (remaining(g).isEmpty && objs.contains(8))
            o.continueTurn = mine
            if let a = o.assigned { o.message = "\(name(me)) gra: \(a.name)" }
            else { o.message = mine ? "Dobrze! \(name(me)) gra dalej" : "Zmiana gracza" }
        } else {
            o.continueTurn = false
            o.message = "Zmiana gracza"
        }
        breakShot = false
        if !o.continueTurn { current = opp }
        return o
    }
}

// MARK: 9-Ball

final class NineBallRules: BaseRules, GameModeRules {
    var mode: GameMode { .nine }
    var groups: [Group?] { [nil, nil] }
    var needsCall: Bool { false }
    var ballSet: [Int] { Array(1...9) }
    var tableCount: Int { 9 - pocketed.count }

    var lowest: Int? { (1...9).first { !pocketed.contains($0) } }

    /// romb: 1 na szczycie, 9 w środku, pozostałe losowo
    func layout(rng: inout SeededGen) -> [Int: V2] {
        var rest = Array(2...8)
        rest.shuffle(using: &rng)
        let pos = Self.rackPositions(rows: [1, 2, 3, 2, 1])
        var out: [Int: V2] = [1: pos[0], 9: pos[4]]
        var idx = 1
        for i in 1..<pos.count where i != 4 { out[rest[idx - 1]] = pos[i]; idx += 1 }
        return out
    }

    func legalTargets(_ p: Int) -> [Int] { lowest.map { [$0] } ?? [] }
    func targetHint(_ p: Int) -> String { lowest.map { "Bila \($0)" } ?? "—" }

    func resolve(_ r: ShotReport) -> ShotOutcome {
        var o = ShotOutcome()
        let me = current, opp = 1 - current
        let cue = r.pocketed.contains(0)
        let objs = r.pocketed.filter { $0 != 0 }
        var foulText = ""
        if cue { foulText = "Biała wpadła do łuzy" }
        else if let f = r.firstContact {
            if let low = lowest, f != low { foulText = "Pierwszy kontakt nie z najniższą bilą (\(low))" }
        } else { foulText = "Biała nie trafiła w żadną bilę" }
        if foulText.isEmpty && objs.isEmpty && !r.cushionAfterContact && !(breakShot && r.railBalls.count >= 4) {
            foulText = breakShot ? "Nielegalne rozbicie (min. 4 bile do band)" : "Po kontakcie żadna bila nie dotknęła bandy"
        }
        let nineIn = objs.contains(9)
        if nineIn && (foulText.isEmpty) {
            pocketed += objs
            o.winner = me
            o.message = "\(name(me)) wbija dziewiątkę i wygrywa!"
            return o
        }
        if nineIn { o.respot = [9] }                 // faul + 9 → wraca na stół
        pocketed += objs.filter { $0 != 9 }
        if !foulText.isEmpty {
            o.foul = true; o.ballInHand = true; o.continueTurn = false
            o.message = "Faul: \(foulText). Biała w ręce dla: \(name(opp))"
        } else if !objs.isEmpty {
            o.continueTurn = true
            o.message = "Dobrze! \(name(me)) gra dalej"
        } else {
            o.message = "Zmiana gracza"
        }
        breakShot = false
        if !o.continueTurn { current = opp }
        return o
    }
}

// MARK: 10-Ball (Call Shot)

final class TenBallRules: BaseRules, GameModeRules {
    var mode: GameMode { .ten }
    var groups: [Group?] { [nil, nil] }
    var needsCall: Bool { !breakShot }
    var ballSet: [Int] { Array(1...10) }
    var tableCount: Int { 10 - pocketed.count }
    var lowest: Int? { (1...10).first { !pocketed.contains($0) } }

    /// trójkąt 1–2–3–4: 1 na szczycie, 10 w środku trzeciego rzędu
    func layout(rng: inout SeededGen) -> [Int: V2] {
        var rest = Array(2...9)
        rest.shuffle(using: &rng)
        let pos = Self.rackPositions(rows: [1, 2, 3, 4])
        var out: [Int: V2] = [1: pos[0], 10: pos[4]]
        var k = 0
        for i in 1..<pos.count where i != 4 { out[rest[k]] = pos[i]; k += 1 }
        return out
    }

    func legalTargets(_ p: Int) -> [Int] { lowest.map { [$0] } ?? [] }
    override func callableBalls(_ p: Int) -> [Int] { (1...10).filter { !pocketed.contains($0) } }
    func targetHint(_ p: Int) -> String { lowest.map { "Bila \($0)" } ?? "—" }

    func resolve(_ r: ShotReport) -> ShotOutcome {
        var o = ShotOutcome()
        let me = current, opp = 1 - current
        let cue = r.pocketed.contains(0)
        let objs = r.pocketed.filter { $0 != 0 }
        var foulText = ""
        if cue { foulText = "Biała wpadła do łuzy" }
        else if let f = r.firstContact {
            if let low = lowest, f != low { foulText = "Pierwszy kontakt nie z najniższą bilą (\(low))" }
        } else { foulText = "Biała nie trafiła w żadną bilę" }
        if foulText.isEmpty && objs.isEmpty && !r.cushionAfterContact && !(breakShot && r.railBalls.count >= 4) {
            foulText = breakShot ? "Nielegalne rozbicie (min. 4 bile do band)" : "Po kontakcie żadna bila nie dotknęła bandy"
        }
        func end(_ text: String) {
            o.foul = true; o.ballInHand = true; o.continueTurn = false
            o.message = "Faul: \(text). Biała w ręce dla: \(name(opp))"
        }
        if breakShot {
            o.respot = objs                      // wbite na rozbiciu wracają na stół
            if !foulText.isEmpty { end(foulText) }
            else { o.message = objs.isEmpty ? "Zmiana gracza" : "Wbite na rozbiciu wracają na stół – zmiana gracza" }
            breakShot = false; current = opp
            return o
        }
        let calledOK = foulText.isEmpty && r.calledBall != nil &&
            r.pocketLog.contains { $0.ball == r.calledBall! && $0.pocket == r.calledPocket }
        if calledOK, let c = r.calledBall {
            if c == 10 {
                pocketed.append(c)
                o.winner = me
                o.message = "\(name(me)) wbija dziesiątkę i wygrywa!"
                return o
            }
            pocketed.append(c)
            o.respot = objs.filter { $0 != c }
            o.continueTurn = true
            o.message = o.respot.isEmpty ? "Dobrze! \(name(me)) gra dalej" : "Dobrze! Niezadeklarowane bile wracają na stół"
        } else {
            o.respot = objs                      // niezadeklarowane lub faul – bile wracają
            if !foulText.isEmpty { end(foulText) }
            else { o.message = "Zmiana gracza – zadeklarowana bila nie wpadła do wskazanej łuzy" }
        }
        if !o.continueTurn { current = opp }
        return o
    }
}

// MARK: 14/1 – Straight Pool

final class StraightPoolRules: BaseRules, GameModeRules {
    var mode: GameMode { .straight }
    var groups: [Group?] { [nil, nil] }
    var needsCall: Bool { !breakShot }
    var ballSet: [Int] { Array(1...15) }
    let goal = GameConfig.target
    override var target: Int { goal }
    var onTable: [Int] { (1...15).filter { !pocketed.contains($0) } }
    var tableCount: Int { onTable.count }
    var lastRemaining = 0

    func layout(rng: inout SeededGen) -> [Int: V2] {
        var ids = Array(1...15)
        ids.shuffle(using: &rng)
        let pos = Self.rackPositions(rows: [1, 2, 3, 4, 5])
        var out: [Int: V2] = [:]
        for (i, id) in ids.enumerated() { out[id] = pos[i] }
        return out
    }
    func legalTargets(_ p: Int) -> [Int] { onTable }
    override func callableBalls(_ p: Int) -> [Int] { onTable }
    func targetHint(_ p: Int) -> String { "\(scores[p]) / \(goal)" }

    /// nowy trójkąt: 14 bil w miejscach 2–15; pozostała bila zostaje, o ile nie koliduje z rozstawem (inaczej trafia na szczyt)
    override func rerack(remainingAt: V2) -> [Int: V2] {
        let slots = Self.rackPositions(rows: [1, 2, 3, 4, 5])
        let ids = Array(1...15).filter { $0 != lastRemaining }
        var out: [Int: V2] = [:]
        if lastRemaining == 0 { for (i, id) in ids.enumerated() { out[id] = slots[i] }; return out }   // stół pusty: pełny trójkąt
        for (i, id) in ids.enumerated() { out[id] = slots[i + 1] }
        if slots.dropFirst().contains(where: { simd_length($0 - remainingAt) < 2 * Phys.R + 0.004 }) { out[lastRemaining] = slots[0] }
        return out
    }

    func resolve(_ r: ShotReport) -> ShotOutcome {
        var o = ShotOutcome()
        let me = current, opp = 1 - current
        let cue = r.pocketed.contains(0)
        let objs = r.pocketed.filter { $0 != 0 }
        var foulText = ""
        if cue { foulText = "Biała wpadła do łuzy" }
        else if r.firstContact == nil { foulText = "Biała nie trafiła w żadną bilę" }
        else if objs.isEmpty {
            if breakShot { if r.railBalls.subtracting([0]).count < 2 { foulText = "Nielegalne rozbicie (min. 2 bile do band)" } }
            else if !r.cushionAfterContact { foulText = "Po kontakcie żadna bila nie dotknęła bandy" }
        }
        var passTurn = true
        if !foulText.isEmpty {
            let pen = breakShot ? 2 : 1
            scores[me] -= pen
            o.foul = true; o.ballInHand = cue; o.scoreDelta[me] = -pen
            pocketed += objs
            o.message = "Faul: \(foulText) (−\(pen) pkt)" + (cue ? ". Biała w ręce dla: \(name(opp))" : ". Gra: \(name(opp))")
        } else if breakShot {
            pocketed += objs
            scores[me] += objs.count; currentBreak += objs.count
            if !objs.isEmpty { passTurn = false }
            o.message = objs.isEmpty ? "Zmiana gracza" : "Dobrze! \(name(me)) gra dalej (+\(objs.count))"
        } else {
            let ok = r.calledBall != nil && r.pocketLog.contains { $0.ball == r.calledBall! && $0.pocket == r.calledPocket }
            if ok {
                pocketed += objs
                scores[me] += objs.count; currentBreak += objs.count
                o.scoreDelta[me] = objs.count
                passTurn = false
                o.message = "Dobrze! \(name(me)) gra dalej (+\(objs.count))"
            } else {
                o.respot = objs                  // bez deklaracji bile wracają, brak punktów
                o.message = "Zmiana gracza"
            }
        }
        highBreak = max(highBreak, currentBreak)
        breakShot = false
        if scores[me] >= goal && !o.foul {
            o.winner = me
            o.message = "\(name(me)) wygrywa do \(goal) punktów!"
            return o
        }
        // został jeden bila → nowy trójkąt
        let left = onTable.filter { !o.respot.contains($0) }
        if left.count <= 1 && o.respot.isEmpty {
            lastRemaining = left.first ?? 0
            o.rerack = true
            o.message += " · Nowy trójkąt"
            pocketed = []
        }
        if passTurn { current = opp; currentBreak = 0 }
        return o
    }
}

// MARK: Snooker

final class SnookerRules: BaseRules, GameModeRules {
    var mode: GameMode { .snooker }
    var groups: [Group?] { [nil, nil] }
    var needsCall: Bool { false }
    var ballSet: [Int] { Array(1...(GameConfig.reds)) + Array(16...21) }
    let redsTotal = GameConfig.reds
    // stage: 0 – czerwona, 1 – kolor, 2 – kolory po kolei (seq = 2…7)
    var stage = 0
    var seq = 2
    var redsLeft: Int { (1...redsTotal).filter { !pocketed.contains($0) }.count }
    var tableCount: Int { redsLeft }
    override var cueSpot: V2 { V2(SnookerLayout.baulkX - 0.12, 0.08) }

    func layout(rng: inout SeededGen) -> [Int: V2] {
        let apexX = SnookerLayout.spots[20]!.x + 2 * Phys.R + 0.003
        let pos = Self.rackPositions(rows: [1, 2, 3, 4, 5], apexX: apexX)
        var out: [Int: V2] = [:]
        for i in 0..<redsTotal { out[i + 1] = pos[i] }
        for (id, p) in SnookerLayout.spots { out[id] = p }
        out[0] = cueSpot
        return out
    }

    override func clampCue(_ p: V2, restricted: Bool) -> V2 {
        // półkole „D”: x ≤ linia baulk, odległość od środka linii ≤ 292 mm
        var q = p
        let c = V2(SnookerLayout.baulkX, 0), rr = 0.292 - Phys.R
        q.x = min(q.x, c.x)
        let d = q - c
        let l = simd_length(d)
        if l > rr { q = c + d / l * rr }
        return q
    }

    func colorsOnTable() -> [Int] { (16...21).filter { !pocketed.contains($0) } }
    func redsOnTable() -> [Int] { (1...redsTotal).filter { !pocketed.contains($0) } }

    func legalTargets(_ p: Int) -> [Int] {
        switch stage {
        case 0: return redsOnTable()
        case 1: return colorsOnTable()
        default: return [seq + 14]
        }
    }
    func targetHint(_ p: Int) -> String {
        if p != current { return "—" }
        switch stage {
        case 0: return "czerwona"
        case 1: return "kolor"
        default: return "kolor: \(SnookerLayout.names[seq + 14] ?? "")"
        }
    }

    func resolve(_ r: ShotReport) -> ShotOutcome {
        var o = ShotOutcome()
        let me = current, opp = 1 - current
        let cue = r.pocketed.contains(0)
        let objs = r.pocketed.filter { $0 != 0 }
        let reds = objs.filter { $0 <= 15 }, cols = objs.filter { $0 >= 16 }
        var foulText = ""
        let legal = Set(legalTargets(me))
        if cue { foulText = "Biała wpadła do łuzy" }
        else if let f = r.firstContact {
            if !legal.contains(f) { foulText = "Pierwszy kontakt z niewłaściwą bilą" }
        } else { foulText = "Biała nie trafiła w żadną bilę" }
        if foulText.isEmpty {
            switch stage {
            case 0: if !cols.isEmpty { foulText = "Wbita zła bila (kolor zamiast czerwonej)" }
            case 1: if !reds.isEmpty || cols.count > 1 || (cols.count == 1 && cols[0] != r.firstContact) { foulText = "Wbita zła bila" }
            default: if objs.contains(where: { $0 != seq + 14 }) { foulText = "Wbita zła bila" }
            }
        }
        let stageBefore = stage
        let wasLastRed = redsLeft - reds.count == 0
        var spotCols: [Int] = []
        if !foulText.isEmpty {
            var val = 4
            if let f = r.firstContact { val = max(val, SnookerLayout.value(f)) }
            for b in objs { val = max(val, SnookerLayout.value(b)) }
            scores[opp] += val
            o.foul = true; o.ballInHand = cue; o.scoreDelta[opp] = val
            pocketed += reds
            spotCols = cols                      // wbite kolory wracają na stół
            if stageBefore == 2 { spotCols = cols }
            o.message = "Faul: \(foulText) (+\(val) dla: \(name(opp)))" + (cue ? ". Biała w D" : "")
            o.continueTurn = false
            currentBreak = 0
        } else if objs.isEmpty {
            o.message = "Zmiana gracza"
            currentBreak = 0
        } else {
            var pts = 0
            switch stageBefore {
            case 0: pts = reds.count; pocketed += reds
            case 1: pts = SnookerLayout.value(cols[0]); spotCols = cols
            default: pts = SnookerLayout.value(cols[0]); pocketed += cols
            }
            scores[me] += pts; currentBreak += pts
            o.scoreDelta[me] = pts
            o.continueTurn = true
            o.message = "Dobrze! +\(pts) · \(name(me)) gra dalej"
        }
        highBreak = max(highBreak, currentBreak)
        // przejście etapów
        if stageBefore == 0 && !o.foul && !reds.isEmpty { stage = 1 }
        else if stageBefore == 1 {
            stage = (redsLeft > 0) ? 0 : 2
            if stage == 2 { seq = 2 }
        } else if stageBefore == 0 && redsLeft == 0 && !o.foul { stage = 2; seq = 2 }
        else if stageBefore == 0 && o.foul && redsLeft == 0 { stage = 2; seq = 2 }
        else if stageBefore == 2 && !o.foul && !objs.isEmpty { seq += 1 }
        if stage == 0 && redsLeft == 0 { stage = 2; seq = 2 }
        _ = wasLastRed
        for c in spotCols { o.respotAt[c] = SnookerLayout.spots[c]!; o.respot.append(c) }
        o.respotDir = 1
        breakShot = false
        // koniec: czarna wbita w sekwencji
        if stage == 2 && seq > 7 {
            if scores[0] == scores[1] {
                seq = 7                                         // remis: czarna wraca, gra się dalej
                pocketed.removeAll { $0 == 21 }
                o.respotAt[21] = SnookerLayout.spots[21]!; o.respot.append(21)
                o.message = "Remis \(scores[0]):\(scores[1]) – czarna wraca na stół"
                o.continueTurn = false
            } else {
                o.winner = scores[0] > scores[1] ? 0 : 1
                o.message = "\(name(o.winner!)) wygrywa \(max(scores[0], scores[1])):\(min(scores[0], scores[1]))!"
                return o
            }
        }
        // faul na ostatniej czarnej (sekwencja) nie kończy frejma: czarna wraca (spotCols), gra toczy się dalej
        if !o.continueTurn { current = opp; currentBreak = 0 }
        return o
    }
}

// MARK: - Model HUD

final class GameModel: ObservableObject {
    @Published var phase: Phase = .menu
    @Published var current = 0
    @Published var groups: [Group?] = [nil, nil]
    @Published var pocketed: [Int] = []
    @Published var names = ["Gracz", "Komputer"]
    @Published var message = ""
    @Published var targetIDs: [Int] = []       // bile 3D w karcie „cel”
    @Published var targetTitle = ""
    @Published var targetSub = ""
    @Published var targetWho = ""
    var ballGeometry: (Int) -> SCNGeometry? = { _ in nil }
    @Published var lastPower = 0.0     // siła ostatniego uderzenia człowieka (znacznik na pasku)
    @Published var chalk = 1.0          // ilość kredy na kiju aktualnego gracza (0…1)
    @Published var chalking = false
    @Published var power = 0.0
    @Published var spin = CGPoint(x: 0, y: 0)          // x w prawo, y w górę, −1…1
    @Published var elevation = 0.0                       // stopnie
    @Published var topView = false
    @Published var vsAI = true
    @Published var mode: GameMode = .eight
    @Published var scores = [0, 0]
    @Published var tableCount = 15
    @Published var curBreak = 0
    @Published var highBreak = 0
    @Published var target = GameConfig.target
    @Published var needsCall = false
    @Published var callBall: Int? = nil
    @Published var callPocket: Int? = nil
    @Published var callText = ""
    @Published var hints = ["", ""]
    @Published var blueCloth = true
    @Published var ballInHand = false
    @Published var thinking = false
    @Published var winner: Int? = nil
    @Published var showHelp = false
    @Published var canResume = false                     // gra zawieszona wyjściem do menu (Esc / „Menu główne”)
    var onResume: () -> Void = {}
    @Published var fpsText = ""                          // licznik FPS (opcja w ustawieniach grafiki)
    @Published var demo = false                          // tryb demo: HUD gry ukryty, tylko plansza DEMO
    @Published var pauseCine = false                     // pauza: kamera zbliżeń na bile (panel ukryty)
    @Published var paused = false { didSet { if !paused { savePicker = 0 } } }                        // nakładka pauzy (tylko HUD)
    @Published var interactiveRects: [CGRect] = []
    @Published var loading = 0.0
    @Published var loadText = "Przygotowanie…"

    let settings = Settings.shared
    @Published var faces: [NSImage?] = [nil, nil]
    @Published var showFaces = false
    @Published var menuTab = Int(ProcessInfo.processInfo.environment["BILARD_TAB"] ?? "") ?? 0
    @Published var tournamentActive = false
    var onStartMatch: (Int, Int) -> Void = { _, _ in }
    let records = RecordStore.shared
    var onShoot: () -> Void = {}
    @Published var replayLabel: String? = nil
    @Published var replayMode: ReplayMode = ReplayMode.saved { didSet { ReplayMode.saved = replayMode } }
    var onToggleView: () -> Void = {}
    var onChalk: () -> Void = {}
    var onCycleCamera: () -> Void = {}
    @Published var cameraName = CamPreset.auto.title
    var onNewGame: (Bool) -> Void = { _ in }
    var onSetTarget: (Int) -> Void = { _ in }
    var onSelectMode: (GameMode) -> Void = { _ in }
    var onToggleCloth: () -> Void = {}
    var onBackToMenu: () -> Void = {}
    var onSaveGame: (Int) -> Bool = { _ in false }
    var onLoadGame: (Int) -> Void = { _ in }
    @Published var saveTick = 0
    @Published var savePicker = 0                       // 0 brak, 1 zapis, 2 odczyt
    var onReposition: () -> Void = {}
}

// MARK: - Przeciwnik komputerowy

struct AIShot {
    var ball: Int? = nil           // zadeklarowana bila i łuza (Call Shot)
    var pocket: Int? = nil
    var yaw: Double
    var power: Double
    var off: V2
    var cuePos: V2?        // wybrana pozycja białej (gdy „w ręce”)
}

enum AIPlayer {
    static func segDist(_ p: V2, _ a: V2, _ b: V2) -> Double {
        let ab = b - a
        let l2 = simd_dot(ab, ab)
        if l2 < 1e-12 { return simd_length(p - a) }
        let t = max(0, min(1, simd_dot(p - a, ab) / l2))
        return simd_length(p - (a + ab * t))
    }

    /// najlepsze zagranie z danej pozycji białej; zwraca (zagranie, ocena) albo nil
    static func bestPocketShot(cue: V2, balls: [Ball], targets: [Int], lvl: AILevel = .club, depth: Int = 1, rng: UnsafeMutablePointer<SeededGen>? = nil) -> (AIShot, Double)? {
        let R = Phys.R
        var best: (AIShot, Double)? = nil
        for tid in targets {
            let tb = balls[tid]
            guard tb.active else { continue }
            for (pidx, pk) in BilliardPhysics.pockets.enumerated() {
                // punkt celowania w łuzę: lekko w głąb od środka
                let toward = simd_normalize(pk.c - tb.p)
                let aimPt = pk.c - (pk.side ? V2(0, 0) : V2(0, 0)) + toward * 0.0
                let n = simd_normalize(aimPt - tb.p)
                let ghost = tb.p - n * (2 * R)
                let toGhost = ghost - cue
                let dCG = simd_length(toGhost)
                if dCG < 1e-6 { continue }
                let dir = toGhost / dCG
                let cosCut = simd_dot(dir, n)
                if cosCut < lvl.minCut { continue }
                let dTP = simd_length(aimPt - tb.p)
                // czystość drogi: biała → ghost, cel → łuza
                var clear = true
                for ob in balls where ob.active && ob.id != 0 && ob.id != tid {
                    if segDist(ob.p, cue, ghost) < 2 * R * 0.99 { clear = false; break }
                    if segDist(ob.p, tb.p, aimPt) < 2 * R * 0.99 { clear = false; break }
                }
                if !clear { continue }
                // ścieżka celu nie może wpaść na kolanko pod ostrym kątem – ocena po kącie wejścia
                var score = cosCut * 1.2 - 0.22 * (dCG + dTP) - (pk.side ? 0.15 : 0)
                if lvl.pickNoise > 0, let r = rng { score += Double(r.pointee.next() % 1001) / 1000 * lvl.pickNoise }
                if depth >= 2 {
                    // plan: biała zatrzymuje się mniej więcej przy bili „ghost”; oceń kolejne zagranie z tej pozycji
                    var nb = balls; nb[tid].active = false
                    let rest = targets.filter { $0 != tid }
                    if !rest.isEmpty, let nxt = bestPocketShot(cue: ghost, balls: nb, targets: rest, lvl: lvl, depth: 1) { score += 0.35 * nxt.1 }
                    else if rest.isEmpty { score += 0.2 }
                }
                if best == nil || score > best!.1 {
                    let power = max(0.2, min(1.0, 0.24 + 0.2 * (dCG + dTP) + 0.12 * (1 - cosCut)))
                    best = (AIShot(ball: tid, pocket: pidx, yaw: atan2(dir.y, dir.x), power: power, off: V2(0, 0.08), cuePos: nil), score)
                }
            }
        }
        return best
    }

    static func choose(balls: [Ball], rules: GameModeRules, ballInHand: Bool, rng: inout SeededGen, level lvl: AILevel = Settings.shared.activeLevel) -> AIShot {
        let me = rules.current
        let targets = rules.legalTargets(me)
        let R = Phys.R
        var cue = balls[0].p
        var shot: AIShot? = nil

        if rules.breakShot && !ballInHand && rules.mode != .snooker {
            let apex = balls[1...15].filter { $0.active }.min { $0.p.x > $1.p.x ? false : true }?.p ?? V2(Phys.halfL / 2, 0)
            let d = simd_normalize(apex - cue)
            return AIShot(yaw: atan2(d.y, d.x), power: 0.93, off: V2(0, 0.1), cuePos: nil)
        }
        if ballInHand {
            // próbkuj pozycje białej
            var bestScore = -1e9
            var cands: [V2] = []
            let xMax = rules.breakShot ? -Phys.halfL / 2 : Phys.halfL - 0.1
            let fine = rules.mode == .snooker ? 0.5 : 1.0
            var gx = -Phys.halfL + 0.1
            while gx <= xMax {
                var gz = -Phys.halfW + 0.08
                while gz <= Phys.halfW - 0.08 {
                    let c = V2(gx, gz)
                    if simd_length(rules.clampCue(c, restricted: rules.breakShot) - c) < 1e-9 { cands.append(c) }
                    gz += 0.12 * fine
                }
                gx += 0.14 * fine
            }
            for c in cands {
                if balls.contains(where: { $0.active && $0.id != 0 && simd_length($0.p - c) < 2 * R + 0.01 }) { continue }
                if let (s, sc) = bestPocketShot(cue: c, balls: balls, targets: targets, lvl: lvl), sc > bestScore {
                    bestScore = sc; shot = s; shot?.cuePos = c; cue = c
                }
            }
            if shot == nil {
                // brak czystego strzału: ustaw białą blisko środka i graj w najbliższy cel
                let c = rules.clampCue(V2(rules.breakShot ? -Phys.halfL * 0.6 : -0.3, 0), restricted: rules.breakShot)
                cue = balls.contains(where: { $0.active && $0.id != 0 && simd_length($0.p - c) < 2 * R + 0.01 }) ? V2(c.x, c.y + 0.2) : c
                shot = AIShot(yaw: 0, power: 0.5, off: V2(0, 0), cuePos: cue)
            }
        } else {
            shot = withUnsafeMutablePointer(to: &rng) { bestPocketShot(cue: cue, balls: balls, targets: targets, lvl: lvl, depth: lvl.depth, rng: $0) }?.0
        }
        if var s = shot, s.power > 0 {
            if s.cuePos == nil || shot != nil {
                // fallback jeśli yaw=0 z domyślnego kształtu: celuj w najbliższy cel
                if bestPocketShot(cue: cue, balls: balls, targets: targets, lvl: lvl) == nil {
                    let t = targets.compactMap { id -> Ball? in balls[id].active ? balls[id] : nil }
                        .min { simd_length($0.p - cue) < simd_length($1.p - cue) }
                    if let t {
                        let d = simd_normalize(t.p - cue)
                        s.yaw = atan2(d.y, d.x); s.power = 0.55
                    }
                }
            }
            // błąd ludzki: niewielki rozrzut kąta i siły
            let e = (Double(rng.next() % 2001) / 1000 - 1) * lvl.angleErr * (rules.mode == .snooker ? 0.3 : 1)
            let pe = 1 + (Double(rng.next() % 2001) / 1000 - 1) * lvl.powerErr
            s.yaw += e
            s.power = max(0.12, min(1, s.power * pe))
            return s
        }
        // awaryjnie: celuj w najbliższą legalną bilę
        let t = targets.compactMap { id -> Ball? in balls[id].active ? balls[id] : nil }
            .min { simd_length($0.p - cue) < simd_length($1.p - cue) }
        let d = t.map { simd_normalize($0.p - cue) } ?? V2(1, 0)
        let np = t.flatMap { tb in BilliardPhysics.pockets.indices.min { simd_length(BilliardPhysics.pockets[$0].c - tb.p) < simd_length(BilliardPhysics.pockets[$1].c - tb.p) } }
        return AIShot(ball: t?.id, pocket: np, yaw: atan2(d.y, d.x), power: 0.55, off: V2(0, 0), cuePos: ballInHand ? cue : nil)
    }
}
