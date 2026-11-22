import Foundation
import simd

// MARK: - Smart Instant Replay: bufor pierścieniowy stanu bil
// Pamięć alokowana raz (konstruktor); zapis klatki = kopiowanie liczb, zero alokacji w pętli gry.

enum ReplayMode: Int, CaseIterable {
    case off, key, all
    var title: String { switch self { case .off: return "Wyłączone"; case .key: return "Kluczowe"; case .all: return "Wszystkie udane" } }
    static var saved: ReplayMode {
        get { ReplayMode(rawValue: UserDefaults.standard.object(forKey: "bilard.replayMode") as? Int ?? 1) ?? .key }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "bilard.replayMode") }
    }
}

final class ReplayRecorder {
    let cap = 4096                       // ~34 s przy 120 Hz
    let n = Phys.nBalls
    private let pos: UnsafeMutablePointer<Float>
    private let quat: UnsafeMutablePointer<Float>
    private let act: UnsafeMutablePointer<UInt8>
    private let times: UnsafeMutablePointer<Double>
    private var head = 0
    private(set) var count = 0

    init() {
        pos = .allocate(capacity: cap * n * 2)
        quat = .allocate(capacity: cap * n * 4)
        act = .allocate(capacity: cap * n)
        times = .allocate(capacity: cap)
    }
    deinit { pos.deallocate(); quat.deallocate(); act.deallocate(); times.deallocate() }

    func reset() { head = 0; count = 0 }

    func capture(_ balls: [Ball], t: Double) {
        let f = head
        times[f] = t
        for i in 0..<n {
            let b = balls[i]
            let o = f * n + i
            pos[o * 2] = Float(b.p.x); pos[o * 2 + 1] = Float(b.p.y)
            quat[o * 4] = Float(b.q.imag.x); quat[o * 4 + 1] = Float(b.q.imag.y); quat[o * 4 + 2] = Float(b.q.imag.z); quat[o * 4 + 3] = Float(b.q.real)
            act[o] = b.active ? 1 : 0
        }
        head = (head + 1) % cap
        count = min(count + 1, cap)
    }

    private func phys(_ i: Int) -> Int { (head - count + i + cap) % cap }
    var firstT: Double { count > 0 ? times[phys(0)] : 0 }
    var lastT: Double { count > 0 ? times[phys(count - 1)] : 0 }

    /// ustawia bile na stan z chwili t (interpolacja położenia, slerp obrotu); cursor – indeks logiczny, rośnie monotonicznie
    func sample(at t: Double, cursor: inout Int, into balls: inout [Ball]) {
        guard count > 0 else { return }
        while cursor + 1 < count && times[phys(cursor + 1)] <= t { cursor += 1 }
        let a = phys(cursor), b = phys(min(cursor + 1, count - 1))
        let ta = times[a], tb = times[b]
        let f = tb > ta ? Float(max(0, min(1, (t - ta) / (tb - ta)))) : 0
        for i in 0..<n {
            let oa = a * n + i, ob = b * n + i
            balls[i].active = act[oa] != 0
            if act[oa] == 0 { continue }
            let both = act[ob] != 0
            let g = both ? f : 0
            balls[i].p = V2(Double(pos[oa * 2] + (pos[ob * 2] - pos[oa * 2]) * g), Double(pos[oa * 2 + 1] + (pos[ob * 2 + 1] - pos[oa * 2 + 1]) * g))
            let qa = simd_quatf(ix: quat[oa * 4], iy: quat[oa * 4 + 1], iz: quat[oa * 4 + 2], r: quat[oa * 4 + 3])
            let qb = simd_quatf(ix: quat[ob * 4], iy: quat[ob * 4 + 1], iz: quat[ob * 4 + 2], r: quat[ob * 4 + 3])
            let q = simd_slerp(qa, qb, g)
            balls[i].q = simd_quatd(ix: Double(q.imag.x), iy: Double(q.imag.y), iz: Double(q.imag.z), r: Double(q.real))
            balls[i].v = V2(0, 0)
        }
    }
}
