import Foundation
import AppKit

// MARK: - Profile graczy (imię, zdjęcie, poziom AI) i turniej pucharowy

struct Profile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var isAI: Bool
    var level: Int = 1          // AILevel dla graczy komputerowych
    var titles = 0              // wygrane turnieje
}

final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()
    @Published var list: [Profile] = []
    private let dir: URL
    private let url: URL
    private var cache: [String: NSImage] = [:]

    init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bilard/faces", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.deletingLastPathComponent().appendingPathComponent("profiles.json")
        if let raw = try? Data(contentsOf: url), let l = try? JSONDecoder().decode([Profile].self, from: raw), !l.isEmpty { list = l }
        else {
            list = [Profile(id: "you", name: Settings.shared.name1, isAI: false, level: 1),
                    Profile(id: "ai1", name: "Marek", isAI: true, level: 1), Profile(id: "ai2", name: "Ola", isAI: true, level: 0),
                    Profile(id: "ai3", name: "Wiktor", isAI: true, level: 2), Profile(id: "ai4", name: "Kasia", isAI: true, level: 1),
                    Profile(id: "ai5", name: "Bartek", isAI: true, level: 0), Profile(id: "ai6", name: "Ewa", isAI: true, level: 2),
                    Profile(id: "ai7", name: "Janusz", isAI: true, level: 1)]
            save()
        }
    }

    func profile(_ id: String?) -> Profile? { list.first { $0.id == id } }
    func save() { if let raw = try? JSONEncoder().encode(list) { try? raw.write(to: url, options: .atomic) } }
    func update(_ p: Profile) { if let i = list.firstIndex(where: { $0.id == p.id }) { list[i] = p; save() } }
    func add(ai: Bool) {
        let n = list.count + 1
        list.append(Profile(id: UUID().uuidString, name: ai ? "Komputer \(n)" : "Gracz \(n)", isAI: ai, level: 1)); save()
    }
    func remove(_ id: String) {
        list.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: faceURL(id)); cache[id] = nil; save()
        objectWillChange.send()
    }
    func faceURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).jpg") }
    func face(_ id: String?) -> NSImage? {
        guard let id else { return nil }
        if let c = cache[id] { return c }
        if let img = NSImage(contentsOf: faceURL(id)) { cache[id] = img; return img }
        return nil
    }
    /// zdjęcie z pliku: kadr kwadratowy ze środka, 256 px, JPEG w Application Support
    func setFace(_ id: String, from file: URL) {
        guard let img = NSImage(contentsOf: file), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let s = min(cg.width, cg.height)
        guard let crop = cg.cropping(to: CGRect(x: (cg.width - s) / 2, y: (cg.height - s) / 2, width: s, height: s)) else { return }
        let out = makeImage(256, 256) { ctx in ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 256, height: 256)) }
        let rep = NSBitmapImageRep(cgImage: out)
        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) { try? data.write(to: faceURL(id), options: .atomic) }
        cache[id] = nil
        objectWillChange.send()
    }
    func clearFace(_ id: String) { try? FileManager.default.removeItem(at: faceURL(id)); cache[id] = nil; objectWillChange.send() }

    /// łączne statystyki gracza ze wszystkich trybów (rekordy po imieniu)
    func totals(_ name: String) -> (games: Int, wins: Int) {
        RecordStore.shared.data.values.reduce((0, 0)) { acc, m in
            let e = m[name]; return (acc.0 + (e?.games ?? 0), acc.1 + (e?.wins ?? 0))
        }
    }
}

struct TMatch: Codable, Equatable {
    var a: String? = nil
    var b: String? = nil
    var winner: String? = nil
}

struct Tournament: Codable {
    var mode: String
    var size: Int
    var rounds: [[TMatch]]
    var champion: String? = nil
}

/// ustawienia aktualnie granego meczu turniejowego (imiona, poziomy AI, zdjęcia)
struct MatchSetup {
    var names: [String]
    var levels: [AILevel]
    var faces: [NSImage?]
    var vsAI: Bool
    var ids: [String]          // id profilu dla miejsca 0/1 w grze
    var round: Int, index: Int
}

final class TournamentStore: ObservableObject {
    static let shared = TournamentStore()
    @Published var t: Tournament?
    private let url: URL
    var profiles: ProfileStore { .shared }

    init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bilard/tournament.json")
        if let raw = try? Data(contentsOf: url), let v = try? JSONDecoder().decode(Tournament.self, from: raw) { t = v }
    }
    private func save() {
        if let t, let raw = try? JSONEncoder().encode(t) { try? raw.write(to: url, options: .atomic) } else { try? FileManager.default.removeItem(at: url) }
    }

    func create(mode: GameMode, ids: [String]) {
        let shuffled = ids.shuffled()
        var rounds: [[TMatch]] = [stride(from: 0, to: shuffled.count, by: 2).map { TMatch(a: shuffled[$0], b: shuffled[$0 + 1]) }]
        var n = shuffled.count / 4
        while n >= 1 { rounds.append(Array(repeating: TMatch(), count: n)); n /= 2 }
        t = Tournament(mode: mode.rawValue, size: ids.count, rounds: rounds)
        save()
    }
    func abandon() { t = nil; save() }

    func isHuman(_ id: String?) -> Bool { profiles.profile(id).map { !$0.isAI } ?? false }

    func nextPlayable() -> (Int, Int)? {
        guard let t, t.champion == nil else { return nil }
        for (r, round) in t.rounds.enumerated() { for (i, m) in round.enumerated() where m.a != nil && m.b != nil && m.winner == nil { return (r, i) } }
        return nil
    }

    func report(round r: Int, index i: Int, winner: String) {
        guard var tt = t else { return }
        tt.rounds[r][i].winner = winner
        if r + 1 < tt.rounds.count {
            if i % 2 == 0 { tt.rounds[r + 1][i / 2].a = winner } else { tt.rounds[r + 1][i / 2].b = winner }
        } else {
            tt.champion = winner
            if var p = profiles.profile(winner) { p.titles += 1; profiles.update(p) }
        }
        t = tt; save()
    }

    /// symuluje mecze komputer–komputer aż do pierwszego meczu z udziałem człowieka (zwraca go) albo końca turnieju
    @discardableResult
    func advanceAI() -> (Int, Int)? {
        let mode = GameMode(rawValue: t?.mode ?? "") ?? .eight
        while let (r, i) = nextPlayable() {
            guard let t, let a = profiles.profile(t.rounds[r][i].a), let b = profiles.profile(t.rounds[r][i].b) else { return nil }
            if !a.isAI || !b.isAI { return (r, i) }
            func skill(_ p: Profile) -> Double { Double(p.level) + Double(abs(p.id.hashValue) % 100) / 400 }
            let pa = 1 / (1 + exp(-(skill(a) - skill(b)) * 1.3))
            let aWins = Double.random(in: 0..<1) < pa
            let secs = Double.random(in: 280...900)
            RecordStore.shared.record(mode: mode, name: a.name, won: aWins, bestBreak: 0, seconds: secs)
            RecordStore.shared.record(mode: mode, name: b.name, won: !aWins, bestBreak: 0, seconds: secs)
            report(round: r, index: i, winner: aWins ? a.id : b.id)
        }
        return nil
    }

    /// konfiguracja gry dla meczu: człowiek zawsze na miejscu 0 gdy gra z komputerem
    func setup(round r: Int, index i: Int) -> MatchSetup? {
        guard let t, let a = profiles.profile(t.rounds[r][i].a), let b = profiles.profile(t.rounds[r][i].b) else { return nil }
        var pl = [a, b]
        if pl[0].isAI && !pl[1].isAI { pl.swapAt(0, 1) }
        let vsAI = pl[1].isAI
        return MatchSetup(names: pl.map { $0.name }, levels: pl.map { AILevel(rawValue: $0.level) ?? .club },
                          faces: pl.map { profiles.face($0.id) }, vsAI: vsAI, ids: pl.map { $0.id }, round: r, index: i)
    }
}
