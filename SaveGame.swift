import Foundation
import SceneKit
import SwiftUI
import simd

// MARK: - Zapis i wczytanie rozgrywki (3 sloty, plik JSON w Application Support/Bilard)

struct SavedBall: Codable { var id: Int; var x: Double; var y: Double; var active: Bool; var q: [Double] }

struct SaveGame: Codable {
    var date: Date
    var mode: String
    var vsAI: Bool
    var target: Int
    var names: [String]
    var scores: [Int]
    var current: Int
    var breakShot: Bool
    var pocketed: [Int]
    var currentBreak: Int
    var highBreak: Int
    var groups: [Int]            // -1 brak, 0 pełne, 1 połówki
    var lastRemaining: Int
    var stage: Int
    var seq: Int
    var balls: [SavedBall]
    var ballInHand: Bool
    var aimYaw: Double
    var chalk: [Double]
    var elapsed: Double
}

enum SaveStore {
    static let slots = 3
    static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bilard", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func url(_ i: Int) -> URL { dir.appendingPathComponent("zapis\(i + 1).json") }
    static func read(_ i: Int) -> SaveGame? {
        guard let d = try? Data(contentsOf: url(i)) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(SaveGame.self, from: d)
    }
    static func write(_ s: SaveGame, _ i: Int) -> Bool {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(s) else { return false }
        return (try? d.write(to: url(i), options: .atomic)) != nil
    }
    static func delete(_ i: Int) { try? FileManager.default.removeItem(at: url(i)) }
}

extension GameSceneController {
    var canSaveNow: Bool { !demo && !model.tournamentActive && (phase == .aiming || phase == .placing) && !fx.busy }

    func saveGame(slot: Int) -> Bool {
        guard canSaveNow, let br = rules as? BaseRules else { model.message = "Zapis możliwy, gdy bile stoją"; return false }
        let balls = physics.balls.map { b in
            SavedBall(id: b.id, x: b.p.x, y: b.p.y, active: b.active, q: [b.q.imag.x, b.q.imag.y, b.q.imag.z, b.q.real])
        }
        var g = rules.groups.map { $0?.rawValue ?? -1 }
        if g.count < 2 { g = [-1, -1] }
        let s = SaveGame(date: Date(), mode: gameMode.rawValue, vsAI: rules.vsAI, target: GameConfig.target,
                         names: [rules.name(0), rules.name(1)], scores: rules.scores, current: rules.current, breakShot: rules.breakShot,
                         pocketed: rules.pocketed, currentBreak: br.currentBreak, highBreak: br.highBreak, groups: g,
                         lastRemaining: (rules as? StraightPoolRules)?.lastRemaining ?? 0,
                         stage: (rules as? SnookerRules)?.stage ?? 0, seq: (rules as? SnookerRules)?.seq ?? 2,
                         balls: balls, ballInHand: ballInHand, aimYaw: aimYaw, chalk: fx.level, elapsed: Date().timeIntervalSince(gameStart))
        let ok = SaveStore.write(s, slot)
        model.saveTick += 1
        return ok
    }

    func loadGame(slot: Int) {
        guard ready, let s = SaveStore.read(slot), let mode = GameMode(rawValue: s.mode) else { return }
        discardSuspended()
        Settings.shared.match = nil; model.showFaces = false; model.tournamentActive = false; tourPos = nil
        model.paused = false
        gameMode = mode; model.mode = mode
        model.target = s.target; GameConfig.target = s.target
        newGame(vsAI: s.vsAI)                       // geometria stołu, reguły, kamera
        resetChalkRack()                            // bez animacji ustawiania trójkąta
        if let br = rules as? BaseRules {
            br.current = s.current; br.breakShot = s.breakShot; br.pocketed = s.pocketed
            br.scores = s.scores; br.currentBreak = s.currentBreak; br.highBreak = s.highBreak
        }
        if let e = rules as? EightBallRules { e.groups = s.groups.map { Group(rawValue: $0) } }
        (rules as? StraightPoolRules)?.lastRemaining = s.lastRemaining
        if let sn = rules as? SnookerRules { sn.stage = s.stage; sn.seq = s.seq }
        for b in s.balls where b.id < physics.balls.count {
            var pb = physics.balls[b.id]
            pb.p = V2(b.x, b.y); pb.v = .zero; pb.w = .zero; pb.active = b.active; pb.h = 0; pb.vh = 0
            if b.q.count == 4 { pb.q = simd_quatd(ix: b.q[0], iy: b.q[1], iz: b.q[2], r: b.q[3]) }
            physics.balls[b.id] = pb
        }
        for i in 0..<min(2, s.chalk.count) { fx.level[i] = s.chalk[i] }
        gameStart = Date().addingTimeInterval(-s.elapsed)
        ballInHand = s.ballInHand
        model.pocketed = s.pocketed
        model.groups = rules.groups
        model.names = [rules.name(0), rules.name(1)]
        for (i, n) in table.balls.enumerated() where i < Phys.nBalls { n.isHidden = !physics.balls[i].active; n.opacity = 1 }
        syncNodes(); syncModel()
        director.cancelCine(); director.skipIntro()
        beginTurn()
        aimYaw = s.aimYaw
        model.message = "Wczytano zapis – \(rules.name(rules.current))"
    }
}

/// lista slotów zapisu/odczytu
struct SaveSlotsView: View {
    @ObservedObject var m: GameModel
    let saving: Bool
    let onDone: () -> Void
    var body: some View {
        let _ = m.saveTick
        VStack(spacing: 8) {
            Caps(saving ? "Zapisz grę w slocie" : "Wczytaj grę", color: UI.dim, size: 10)
            ForEach(0..<SaveStore.slots, id: \.self) { i in
                let s = SaveStore.read(i)
                Button {
                    if saving { if m.onSaveGame(i) { onDone() } }
                    else if s != nil { m.onLoadGame(i); onDone() }
                } label: {
                    HStack(spacing: 10) {
                        Text("\(i + 1)").font(.system(size: 18, weight: .heavy)).foregroundColor(UI.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            if let s = s {
                                Text("\(GameMode(rawValue: s.mode)?.title ?? s.mode) · \(s.names.joined(separator: " – "))").font(.system(size: 12, weight: .semibold)).foregroundColor(UI.text)
                                Text("\(s.scores[0]) : \(s.scores[1]) · bile \(s.balls.filter { $0.active }.count - 1) · \(s.date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundColor(UI.dim)
                            } else {
                                Text("Pusty slot").font(.system(size: 12)).foregroundColor(UI.faint)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12).frame(width: 340, height: 46)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .opacity(!saving && s == nil ? 0.45 : 1)
                }.buttonStyle(.plain)
            }
        }
    }
}
