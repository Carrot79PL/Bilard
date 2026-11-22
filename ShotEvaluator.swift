import Foundation
import simd

// MARK: - Zapis przebiegu strzału (stałe tablice – bez alokacji) i ocena, czy zagranie zasługuje na powtórkę

final class ShotTrace {
    static let nb = 24, nh = 160
    var startPos = [V2](repeating: V2(0, 0), count: nb)
    var cushions = [Int](repeating: 0, count: nb)
    // zderzenia bila–bila
    var hitA = [Int](repeating: 0, count: nh), hitB = [Int](repeating: 0, count: nh)
    var hitSpeed = [Double](repeating: 0, count: nh), hitT = [Double](repeating: 0, count: nh)
    var hitPos = [V2](repeating: V2(0, 0), count: nh)
    var nHits = 0
    // wbicia
    var pBall = [Int](repeating: 0, count: nb), pIdx = [Int](repeating: 0, count: nb)
    var pPos = [V2](repeating: V2(0, 0), count: nb), pT = [Double](repeating: 0, count: nb)
    var pCushions = [Int](repeating: 0, count: nb)
    var nPockets = 0

    func reset(_ balls: [Ball]) {
        for i in 0..<min(Self.nb, balls.count) { startPos[i] = balls[i].p; cushions[i] = 0 }
        nHits = 0; nPockets = 0
    }
    func hit(_ a: Int, _ b: Int, speed: Double, pos: V2, t: Double) {
        guard nHits < Self.nh else { return }
        hitA[nHits] = a; hitB[nHits] = b; hitSpeed[nHits] = speed; hitPos[nHits] = pos; hitT[nHits] = t; nHits += 1
    }
    func cushion(_ ball: Int) { if ball < Self.nb { cushions[ball] += 1 } }
    func pocket(_ ball: Int, idx: Int, pos: V2, t: Double) {
        guard nPockets < Self.nb, ball < Self.nb else { return }
        pBall[nPockets] = ball; pIdx[nPockets] = idx; pPos[nPockets] = pos; pT[nPockets] = t; pCushions[nPockets] = cushions[ball]; nPockets += 1
    }
    var firstHitT: Double { nHits > 0 ? hitT[0] : 0 }
}

struct ReplayDecision {
    var label: String
    var startT: Double
    var endT: Double
    var keyT: Double
    var pocketIdx: Int
    var focusBall: Int
}

enum ShotEvaluator {
    static func evaluate(_ tr: ShotTrace, out: ShotOutcome, shooter: Int, mode: ReplayMode, isBreak: Bool, winnerIsShooter: Bool) -> ReplayDecision? {
        guard mode != .off else { return nil }
        // wbite bile bryłowe (bez białej)
        var objs: [Int] = []
        for k in 0..<tr.nPockets where tr.pBall[k] != 0 { objs.append(k) }
        guard !objs.isEmpty else { return nil }
        let fl = out.foul

        var label: String? = nil
        var key = objs.last!

        if winnerIsShooter && !fl { label = "MATCH WINNER"; key = objs.last! }

        // combo: pierwsza bila, która dotknęła wbitej, nie była białą
        if label == nil && !fl {
            for k in objs {
                let b = tr.pBall[k]
                for h in 0..<tr.nHits where tr.hitA[h] == b || tr.hitB[h] == b {
                    let other = tr.hitA[h] == b ? tr.hitB[h] : tr.hitA[h]
                    if other != 0 { label = "COMBO"; key = k }
                    break
                }
                if label != nil { break }
            }
        }
        if label == nil && !fl, let k = objs.first(where: { tr.pCushions[$0] >= 1 }) { label = "BANK SHOT"; key = k }
        if label == nil && !fl && objs.count >= (isBreak ? 3 : 2) { label = "MULTI-POT"; key = objs.last! }
        if label == nil && !fl {
            // długi strzał: bila uderzona wprost białą; droga biała→bila + bila→łuza > 75 % długości stołu
            for k in objs {
                let b = tr.pBall[k]
                var direct = false
                for h in 0..<tr.nHits where tr.hitA[h] == b || tr.hitB[h] == b { direct = (tr.hitA[h] == 0 || tr.hitB[h] == 0); break }
                guard direct else { continue }
                let d = simd_length(tr.startPos[b] - tr.startPos[0]) + simd_length(tr.pPos[k] - tr.startPos[b])
                if d > 0.75 * 2 * Phys.halfL { label = "LONG POT"; key = k; break }
            }
        }
        if label == nil && mode == .all && !fl { label = "POT" }
        guard let lab = label else { return nil }

        let keyT = tr.pT[key]
        var start = max(0, (tr.nHits > 0 ? tr.firstHitT : 0) - 1.2)
        if keyT - start > 9 { start = keyT - 9 }
        return ReplayDecision(label: lab, startT: start, endT: keyT + 2.2, keyT: keyT, pocketIdx: tr.pIdx[key], focusBall: tr.pBall[key])
    }
}
