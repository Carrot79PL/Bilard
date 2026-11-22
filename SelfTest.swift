import Foundation
import simd

// MARK: - Test bezokienkowy: partie AI vs AI szukające anomalii fizyki i zasad
// Uruchomienie: BILARD_SELFTEST=<liczba partii> [BILARD_STMODE=8ball|9ball|10ball|straight|snooker] [BILARD_STLEVEL=0..2] [BILARD_STSEED=n]

enum SelfTest {
    static func run(games: Int) {
        let env = ProcessInfo.processInfo.environment
        let mode = GameMode(rawValue: env["BILARD_STMODE"] ?? "8ball") ?? .eight
        Settings.shared.aiLevel = Int(env["BILARD_STLEVEL"] ?? "") ?? 1
        let seed0 = UInt64(env["BILARD_STSEED"] ?? "") ?? 1
        Settings.shared.foulKitchen = env["BILARD_STKITCHEN"] != nil
        Phys.modelTable = true
        Phys.configure(snooker: mode == .snooker)
        var anomalies: [String: Int] = [:]
        var samples: [String: String] = [:]
        func flag(_ k: String, _ detail: String) {
            anomalies[k, default: 0] += 1
            if samples[k] == nil { samples[k] = detail }
        }
        var totalShots = 0, fouls = 0, finished = 0, offTable = 0, scratches = 0
        var shotsPerGame: [Int] = []
        let t0 = Date()

        for g in 0..<games {
            let rules = mode.makeRules()
            rules.reset(vsAI: false)
            GameConfig.target = 50
            let phys = BilliardPhysics()
            let seed = seed0 &+ UInt64(g) &* 7919
            phys.rack(seed: seed, rules: rules)
            var rng = SeededGen(s: seed &+ 99)
            var ballInHand = false
            var shots = 0
            var winner: Int? = nil

            func isFree(_ q: V2, _ id: Int) -> Bool { phys.isFree(q, ignoring: id, margin: 0.003) }
            func place(_ id: Int, near spot: V2, dir: Double) {
                var found = spot
                outer: for k in 0..<400 {
                    for sg in [dir, -dir] {
                        let q = spot + V2(Double(k) * 0.012 * sg, 0)
                        if abs(q.x) > Phys.halfL - Phys.R - 0.01 { continue }
                        if isFree(q, id) { found = q; break outer }
                    }
                }
                phys.balls[id].p = found; phys.balls[id].v = V2(0, 0); phys.balls[id].w = V3(0, 0, 0)
                phys.balls[id].active = true; phys.balls[id].h = 0; phys.balls[id].vh = 0
            }

            while winner == nil && shots < 400 {
                if !phys.balls[0].active {
                    var p = rules.cueSpot; var k = 0
                    while !isFree(p, 0) && k < 40 { p.y = (k % 2 == 0 ? 1 : -1) * 0.07 * Double(k / 2 + 1); k += 1 }
                    phys.balls[0].p = p; phys.balls[0].v = V2(0, 0); phys.balls[0].w = V3(0, 0, 0); phys.balls[0].active = true
                }
                guard var s = AIPlayer.choose(balls: phys.balls, rules: rules, ballInHand: ballInHand, rng: &rng) as AIShot? else { break }
                if let c = s.cuePos {
                    let restr = rules.breakShot || (Settings.shared.foulKitchen && [.eight, .nine, .ten].contains(rules.mode))
                    let q = rules.clampCue(c, restricted: restr)
                    if !isFree(q, 0) { flag("AI: biała ustawiona na innej bili", "g\(g) \(q)") }
                    if simd_length(q - c) > 1e-6 { flag("AI: biała poza strefą ustawiania", "g\(g) \(c)") }
                    phys.balls[0].p = c
                }
                if rules.needsCall && (s.ball == nil || s.pocket == nil) {
                    let cue = phys.balls[0].p
                    let b = rules.legalTargets(rules.current).filter { phys.balls[$0].active }
                        .min { simd_length(phys.balls[$0].p - cue) < simd_length(phys.balls[$1].p - cue) } ?? 1
                    s.ball = b
                    s.pocket = BilliardPhysics.pockets.indices.min { simd_length(BilliardPhysics.pockets[$0].c - phys.balls[b].p) < simd_length(BilliardPhysics.pockets[$1].c - phys.balls[b].p) }
                }
                ballInHand = false
                var report = ShotReport()
                report.calledBall = s.ball; report.calledPocket = s.pocket
                let shooter = rules.current
                phys.strike(aim: V2(cos(s.yaw), sin(s.yaw)), power: s.power, off: s.off, elev: 0)
                shots += 1; totalShots += 1

                // symulacja do zatrzymania
                var t = 0.0, still = 0.0
                var settled = false
                while t < 60 {
                    phys.advance(1.0 / 120.0); t += 1.0 / 120.0
                    for e in phys.events {
                        switch e {
                        case let .ballHit(a, b, _, _):
                            if report.firstContact == nil { if a == 0 { report.firstContact = b } else if b == 0 { report.firstContact = a } }
                        case let .cushion(ball, _, _):
                            report.railBalls.insert(ball)
                            if report.firstContact != nil { report.cushionAfterContact = true }
                        case let .offTable(ball, pos):
                            report.offTable.append(ball); offTable += 1
                            if ball == 0 { report.pocketed.append(0) }
                            flag("bila poza stołem", "g\(g) shot\(shots) ball \(ball) at \(pos)")
                        case let .pocket(ball, idx, _):
                            report.pocketed.append(ball); report.pocketLog.append((ball: ball, pocket: idx))
                            if report.firstContact != nil { report.cushionAfterContact = true }
                        case .landed: break
                        }
                    }
                    phys.events.removeAll(keepingCapacity: true)
                    // anomalie położenia
                    for i in 0..<Phys.nBalls where phys.balls[i].active {
                        let b = phys.balls[i]
                        if !b.p.x.isFinite || !b.p.y.isFinite || !b.v.x.isFinite || !b.v.y.isFinite { flag("NaN w fizyce", "g\(g) shot\(shots) ball \(i)"); phys.balls[i].active = false; continue }
                        if abs(b.p.x) > Phys.halfL + 0.004 || abs(b.p.y) > Phys.halfW + 0.004 {
                            let nearPocket = BilliardPhysics.pockets.contains { simd_length($0.c - b.p) < $0.r * 1.5 + Phys.R }
                            if !nearPocket { flag("bila za bandą poza łuzą", "g\(g) shot\(shots) ball \(i) at \(b.p) v \(b.v)"); phys.balls[i].active = false; report.offTable.append(i) }
                        }
                    }
                    if phys.anyMoving { still = 0 } else { still += 1.0 / 120.0 }
                    if still > 0.35 { settled = true; break }
                }
                if !settled { flag("bile nie zatrzymały się w 60 s", "g\(g) shot\(shots)") ; for i in 0..<Phys.nBalls { phys.balls[i].v = V2(0, 0); phys.balls[i].w = V3(0, 0, 0) } }
                // nakładanie się bil po zatrzymaniu
                let act = (0..<Phys.nBalls).filter { phys.balls[$0].active }
                outer2: for i in 0..<act.count { for j in (i + 1)..<max(i + 1, act.count) {
                    if simd_length(phys.balls[act[i]].p - phys.balls[act[j]].p) < Phys.R * 2 - 0.004 {
                        flag("bile nachodzą na siebie", "g\(g) shot\(shots) \(act[i])/\(act[j])"); break outer2
                    }
                } }

                // rozstrzygnięcie jak w finishShot
                var out = rules.resolve(report)
                let offObj = report.offTable.filter { $0 != 0 }
                if !offObj.isEmpty {
                    for id in offObj { place(id, near: V2(Phys.halfL / 2, 0), dir: -1) }
                    if out.winner == nil {
                        if !out.foul {
                            if out.continueTurn { rules.current = 1 - rules.current }
                            out.foul = true; out.continueTurn = false; out.ballInHand = true
                        }
                    }
                }
                if report.pocketed.contains(0) {
                    scratches += 1
                    if !out.foul && out.winner == nil && mode != .snooker { flag("biała wbita bez faulu", "g\(g) shot\(shots) \(out.message)") }
                }
                if out.foul { fouls += 1 }
                if out.foul && out.continueTurn { flag("faul, ale ta sama tura", "g\(g) shot\(shots) \(out.message)") }
                if report.firstContact == nil && !out.foul && out.winner == nil && mode != .snooker && mode != .practice && !(mode == .straight) {
                    flag("brak trafienia bez faulu", "g\(g) shot\(shots) shooter \(shooter) \(out.message)")
                }
                for id in out.respot { place(id, near: out.respotAt[id] ?? V2(Phys.halfL / 2, 0), dir: out.respotDir) }
                for (id, p) in out.placeExact { phys.balls[id].p = p; phys.balls[id].v = V2(0, 0); phys.balls[id].w = V3(0, 0, 0); phys.balls[id].active = true }
                if out.rerack {
                    let rem = (1...15).filter { phys.balls[$0].active }
                    let plan = rules.rerack(remainingAt: rem.first.map { phys.balls[$0].p } ?? V2(9, 9))
                    for (id, p) in plan { phys.balls[id].p = p; phys.balls[id].v = V2(0, 0); phys.balls[id].w = V3(0, 0, 0); phys.balls[id].active = true }
                    if phys.balls[0].active && !isFree(phys.balls[0].p, 0) { place(0, near: rules.cueSpot, dir: -1) }
                }
                if let w = out.winner { winner = w; break }
                ballInHand = out.ballInHand
            }
            if winner != nil { finished += 1 } else { flag("partia bez zwycięzcy po 400 uderzeniach", "g\(g) mode \(mode.rawValue)") }
            shotsPerGame.append(shots)
        }

        let dt = Date().timeIntervalSince(t0)
        let avg = shotsPerGame.isEmpty ? 0 : Double(shotsPerGame.reduce(0, +)) / Double(shotsPerGame.count)
        print("SELFTEST tryb=\(mode.rawValue) poziom=\(Settings.shared.activeLevel.title) partii=\(games) ukończone=\(finished) uderzeń=\(totalShots) (śr. \(String(format: "%.1f", avg))/partię) faule=\(fouls) białe wbite=\(scratches) poza stołem=\(offTable) czas=\(String(format: "%.1f", dt)) s")
        if anomalies.isEmpty { print("  brak anomalii") }
        for (k, v) in anomalies.sorted(by: { $0.value > $1.value }) { print("  ANOMALIA \(k): \(v)×  np. \(samples[k] ?? "")") }
    }
}
