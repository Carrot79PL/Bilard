import Foundation
import simd

// MARK: - Fizyka bilarda (własny silnik, stały krok 240 Hz, przy szybkich bilach 2 × 480 Hz)
// Układ: x – wzdłuż stołu, z – w poprzek, y – w górę. Jednostki SI (metry, sekundy).
// Bila: położenie (x,z), prędkość v, prędkość kątowa w = (wx, wy, wz); wy = obrót wokół osi pionowej (gwint boczny).

typealias V2 = SIMD2<Double>
typealias V3 = SIMD3<Double>

enum Phys {
    static let nBalls = 22               // 0 = biała, 1–15 numerowane/czerwone, 16–21 kolorowe snookera
    static var snooker = false           // geometria zależna od trybu: stół 9 ft (pool) albo 12 ft (snooker)
    static var R = 0.028575              // promień bili (57,15 mm; snooker 52,5 mm)
    static var mass = 0.17
    static var I: Double { 0.4 * mass * R * R }    // moment bezwładności kuli
    static let g = 9.81
    static var halfL = 1.27              // stół 9 stóp: pole gry 2,54 × 1,27 m (snooker 3,569 × 1,778)
    static var halfW = 0.635
    static let muSlide = 0.2             // tarcie ślizgowe bila–sukno
    static let rollRes = 0.0055          // opór toczenia (×g)
    static let eBall = 0.95              // sprężystość bila–bila
    static let eCushion = 0.75           // sprężystość bila–banda
    static let muBall = 0.05             // tarcie bila–bila (rzut boczny)
    static let muCushion = 0.20          // tarcie bila–banda
    static let airDrag = 0.0030          // opór powietrza a = k·v|v|
    static let spinDecay = 14.0          // zanik gwintu pionowego [rad/s²]
    static let dt = 1.0 / 240.0
    static let maxSpeed = 9.5            // m/s przy sile 100 %
    static var tipGap = 0.085            // odległość końców band od narożników
    static var sideTip = 0.065           // półszerokość gardła łuzy bocznej
    static var jawR = 0.008              // promień „kolanka” bandy przy łuzie
    static var cornerR = 0.082, cornerOff = 0.035   // łuza narożna: promień wychwytu i odsunięcie środka od pola gry
    static var sideR = 0.075, sideOff = 0.040       // łuza boczna

    /// stół z modelu 3D (Assets/table_model): łuzy i końce band zmierzone z siatki modelu po skali ×1,0875
    static var modelTable = false
    /// przełączenie geometrii stołu (wywołać przed budową stołu i ułożeniem bil)
    static func configure(snooker s: Bool) {
        snooker = s
        if s {
            R = 0.02625; mass = 0.142
            halfL = 1.7845; halfW = 0.889
            tipGap = 0.062; sideTip = 0.045; jawR = 0.006
            cornerR = 0.063; cornerOff = 0.030; sideR = 0.056; sideOff = 0.032
        } else {
            R = 0.028575; mass = 0.17
            halfL = 1.27; halfW = 0.635
            tipGap = 0.085; sideTip = 0.065; jawR = 0.008
            cornerR = 0.082; cornerOff = 0.035; sideR = 0.075; sideOff = 0.040
            if modelTable {   // otwory łuz modelu na poziomie sukna; środek narożnej leży 7,5 mm w głąb pola
                tipGap = 0.0916; sideTip = 0.0706; jawR = 0.008
                cornerR = 0.054; cornerOff = 0.003; sideR = 0.058; sideOff = 0.022
            }
        }
        BilliardPhysics.rebuildGeometry()
    }
}

struct Pocket {
    let c: V2
    let r: Double
    let side: Bool
}

enum PhysEvent {
    case ballHit(a: Int, b: Int, speed: Double, pos: V2)
    case cushion(ball: Int, speed: Double, pos: V2)
    case pocket(ball: Int, index: Int, pos: V2)
    case landed(ball: Int, speed: Double, pos: V2)     // lądowanie po skoku
    case offTable(ball: Int, pos: V2)                  // bila wybita poza stół
}

struct Ball {
    var id: Int
    var p = V2(0, 0)
    var v = V2(0, 0)
    var w = V3(0, 0, 0)
    var q = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1)
    var active = true
    var h = 0.0                 // wysokość środka bili nad pozycją spoczynkową (skok)
    var vh = 0.0                // prędkość pionowa
    var speed: Double { simd_length(v) }
}

final class BilliardPhysics {
    var balls: [Ball] = (0..<Phys.nBalls).map { Ball(id: $0) }
    var events: [PhysEvent] = []
    private var acc = 0.0

    static var pockets: [Pocket] = []
    /// Końce band (kolanka łuz) – punktowe przeszkody
    static var tips: [V2] = []

    static func rebuildGeometry() {
        var a: [Pocket] = []
        for sx in [-1.0, 1.0] { for sz in [-1.0, 1.0] {
            a.append(Pocket(c: V2(sx * (Phys.halfL + Phys.cornerOff), sz * (Phys.halfW + Phys.cornerOff)), r: Phys.cornerR, side: false))
        } }
        for sz in [-1.0, 1.0] { a.append(Pocket(c: V2(0, sz * (Phys.halfW + Phys.sideOff)), r: Phys.sideR, side: true)) }
        pockets = a
        var t: [V2] = []
        let lx = Phys.halfL - Phys.tipGap, sz = Phys.halfW - Phys.tipGap
        for s in [-1.0, 1.0] {
            for x in [-lx, -Phys.sideTip, Phys.sideTip, lx] { t.append(V2(x, s * Phys.halfW)) }
            for z in [-sz, sz] { t.append(V2(s * Phys.halfL, z)) }
        }
        tips = t
    }

    var anyMoving: Bool { balls.contains { $0.active && ($0.speed > 1e-4 || abs($0.w.y) > 0.5) } }

    // MARK: Uderzenie kijem
    /// aim – jednostkowy kierunek poziomy; power 0…1; off – punkt uderzenia na bili (x w prawo, y w górę, w jednostkach promienia); elev – nachylenie kija [rad]
    /// Boczne uderzenie lekko odchyla białą w przeciwną stronę (squirt); używane też przez podgląd celowania
    static func squirtAim(_ aim: V2, off: V2) -> V2 {
        let right = V2(-aim.y, aim.x)
        return simd_normalize(aim - right * (0.035 * off.x))
    }

    func strike(aim aim0: V2, power: Double, off: V2, elev: Double) {
        let aim = Self.squirtAim(aim0, off: off)
        var cb = balls[0]
        let D = V3(aim.x * cos(elev), -sin(elev), aim.y * cos(elev))
        let Dn = simd_normalize(D)
        let fwd = V3(aim.x, 0, aim.y)
        let right = V3(-aim.y, 0, aim.x)
        var o = off
        let ol = simd_length(o)
        if ol > 0.9 { o *= 0.9 / ol }
        let depth = sqrt(max(0, 1 - o.x * o.x - o.y * o.y))
        let up = simd_normalize(simd_cross(right, Dn))
        let c = Phys.R * (o.x * right + o.y * up - depth * Dn)
        _ = fwd
        // skuteczna masa uderzenia: im dalej od środka, tym wolniejsza bila
        let a2 = o.x * o.x + o.y * o.y
        let ratio = 7.73 / (7.73 + 14.7 * a2)
        let vb = power * Phys.maxSpeed * ratio
        cb.v = V2(aim.x, aim.y) * vb
        let J = Phys.mass * vb / max(0.2, cos(elev))
        cb.w = simd_cross(c, Dn) * (J / Phys.I)
        // skok: mocno nachylony kij (> ~18°) odbija bilę od sukna
        let jumpElev = 0.32
        if elev > jumpElev {
            cb.vh = vb * sin(elev) * 0.55 * min(1, (elev - jumpElev) / 0.35 + 0.35)
            cb.v *= 0.85
        }
        balls[0] = cb
    }

    // MARK: Pętla czasowa
    func advance(_ frameTime: Double) {
        acc += min(frameTime, 0.05)
        var n = 0
        while acc >= Phys.dt && n < 40 {
            // szybkie bile: poddzielenie kroku (zachowanie jak przy 480 Hz, bez tunelowania)
            if fastest() > 1.8 { step(Phys.dt / 2); step(Phys.dt / 2) } else { step(Phys.dt) }
            acc -= Phys.dt
            n += 1
        }
    }

    func resetAccumulator() { acc = 0 }

    private func fastest() -> Double {
        var m = 0.0
        for i in 0..<Phys.nBalls where balls[i].active { m = max(m, simd_length(balls[i].v)) }
        return m
    }

    private func step(_ dt: Double) {
        let R = Phys.R, g = Phys.g
        for i in 0..<Phys.nBalls where balls[i].active {
            var b = balls[i]
            // „sen”: bila w spoczynku nie jest całkowana (budzi ją zderzenie przez zmianę v)
            let air = b.h > 0 || b.vh != 0
            if !air && b.v.x == 0 && b.v.y == 0 && b.w.x == 0 && b.w.y == 0 && b.w.z == 0 { continue }
            if air {
                b.vh -= g * dt
                b.h += b.vh * dt
                b.p += b.v * dt
                if b.h <= 0 && b.vh < 0 {
                    let impact = -b.vh
                    b.h = 0
                    if impact > 0.35 { b.vh = impact * 0.42; b.v *= 0.92 } else { b.vh = 0 }
                    if impact > 0.25 { events.append(.landed(ball: i, speed: impact, pos: b.p)) }
                }
                let wq = simd_quatd(ix: b.w.x, iy: b.w.y, iz: b.w.z, r: 0)
                let dq = wq * b.q
                b.q = simd_normalize(simd_quatd(ix: b.q.imag.x + 0.5 * dt * dq.imag.x, iy: b.q.imag.y + 0.5 * dt * dq.imag.y,
                                                iz: b.q.imag.z + 0.5 * dt * dq.imag.z, r: b.q.real + 0.5 * dt * dq.real))
                balls[i] = b
                continue
            }
            let u = V2(b.v.x + R * b.w.z, b.v.y - R * b.w.x)
            let ul = simd_length(u)
            if ul > 0.002 {
                // ślizganie: tarcie kinetyczne
                let dir = u / ul
                let maxdu = 3.5 * Phys.muSlide * g * dt
                let f = min(1, ul / maxdu)
                b.v -= dir * (Phys.muSlide * g * dt * f)
                let Fx = -Phys.mass * Phys.muSlide * g * f * dir.x
                let Fz = -Phys.mass * Phys.muSlide * g * f * dir.y
                b.w.x += -R * Fz / Phys.I * dt
                b.w.z += R * Fx / Phys.I * dt
            } else {
                // toczenie: opór toczenia, w sprzężone z v
                let sp = simd_length(b.v)
                if sp > 0 {
                    let ns = max(0, sp - Phys.rollRes * g * dt)
                    b.v *= ns / sp
                }
                b.w.x = b.v.y / R
                b.w.z = -b.v.x / R
                if simd_length(b.v) < 0.0015 { b.v = V2(0, 0); b.w.x = 0; b.w.z = 0 }
            }
            let s2 = simd_length(b.v)
            if s2 > 0 { b.v -= b.v * (Phys.airDrag * s2 * dt) }
            // zanik gwintu pionowego
            let dec = Phys.spinDecay * dt * (s2 < 0.01 ? 2.5 : 1)
            if abs(b.w.y) <= dec { b.w.y = 0 } else { b.w.y -= dec * (b.w.y > 0 ? 1 : -1) }
            b.p += b.v * dt
            // orientacja
            let wq = simd_quatd(ix: b.w.x, iy: b.w.y, iz: b.w.z, r: 0)
            let dq = wq * b.q
            b.q = simd_normalize(simd_quatd(ix: b.q.imag.x + 0.5 * dt * dq.imag.x,
                                            iy: b.q.imag.y + 0.5 * dt * dq.imag.y,
                                            iz: b.q.imag.z + 0.5 * dt * dq.imag.z,
                                            r: b.q.real + 0.5 * dt * dq.real))
            balls[i] = b
        }
        // bila–bila
        for i in 0..<(Phys.nBalls - 1) where balls[i].active {
            for j in (i + 1)..<Phys.nBalls where balls[j].active {
                if max(balls[i].h, balls[j].h) > 0.8 * R { continue }     // bila w locie przelatuje nad inną
                let d = balls[j].p - balls[i].p
                let d2 = simd_dot(d, d)
                if d2 < 4 * R * R {
                    let dist = sqrt(d2)
                    let n = dist > 1e-9 ? d / dist : V2(1, 0)
                    let overlap = 2 * R - dist
                    balls[i].p -= n * (overlap / 2)
                    balls[j].p += n * (overlap / 2)
                    let vn = simd_dot(balls[i].v - balls[j].v, n)
                    if vn > 0 {
                        let jn = (1 + Phys.eBall) / 2 * vn
                        balls[i].v -= n * jn
                        balls[j].v += n * jn
                        // tarcie styczne (rzut boczny, przekaz gwintu)
                        let t = V2(-n.y, n.x)
                        let s = simd_dot(balls[i].v, t) - balls[i].w.y * R - (simd_dot(balls[j].v, t) + balls[j].w.y * R)
                        let fmax = Phys.muBall * jn
                        let f = min(fmax, abs(s) / 7) * (s >= 0 ? 1 : -1)
                        balls[i].v -= t * f
                        balls[j].v += t * f
                        balls[i].w.y += f / (0.4 * R)
                        balls[j].w.y += f / (0.4 * R)
                        events.append(.ballHit(a: i, b: j, speed: vn, pos: balls[i].p + n * R))
                    }
                }
            }
        }
        // bandy, kolanka, łuzy
        let lim = V2(Phys.halfL - R, Phys.halfW - R)
        let lx = Phys.halfL - Phys.tipGap, sz = Phys.halfW - Phys.tipGap
        for i in 0..<Phys.nBalls where balls[i].active {
            var b = balls[i]
            // łuzy
            var potted = false
            for (k, pk) in Self.pockets.enumerated() where b.h < 0.012 && simd_length(b.p - pk.c) < pk.r + 0.006 {      // +6 mm: bez szczeliny między otworem a kolankami
                balls[i].active = false
                balls[i].v = V2(0, 0)
                events.append(.pocket(ball: i, index: k, pos: b.p))
                potted = true
                break
            }
            if potted { continue }
            // kolanka
            for tip in Self.tips {
                let d = b.p - tip
                let dist = simd_length(d)
                if dist < R + Phys.jawR && dist > 1e-9 {
                    let n = d / dist
                    b.p = tip + n * (R + Phys.jawR)
                    let vn = simd_dot(b.v, n)
                    if vn < 0 {
                        b.v -= n * ((1 + 0.6) * vn)
                        events.append(.cushion(ball: i, speed: -vn, pos: b.p))
                    }
                }
            }
            // bila, która minęła linię bandy we wlocie łuzy poza obszarem wychwytu, wpada do najbliższej łuzy (nie wylatuje za stół)
            if b.h < 0.012 && (abs(b.p.x) > Phys.halfL + 0.006 || abs(b.p.y) > Phys.halfW + 0.006) {
                var best = 0, bd = Double.infinity
                for (k, pk) in Self.pockets.enumerated() { let d = simd_length(b.p - pk.c); if d < bd { bd = d; best = k } }
                balls[i].active = false
                balls[i].v = V2(0, 0)
                events.append(.pocket(ball: i, index: best, pos: b.p))
                continue
            }
            // bandy długie (z = ±halfW) i krótkie (x = ±halfL)
            let ax = abs(b.p.x), az = abs(b.p.y)
            // bila wysoko nad bandą (dolna krawędź powyżej burty) wylatuje ze stołu
            if b.h > 0.045 && (ax > lim.x + 0.004 || az > lim.y + 0.004) {
                b.p.x = max(-Phys.halfL - 0.5, min(Phys.halfL + 0.5, b.p.x))
                balls[i] = b
                balls[i].active = false
                events.append(.offTable(ball: i, pos: b.p))
                continue
            }
            let inLong = ax > Phys.sideTip && ax < lx + 0.01
            let inShort = az < sz + 0.01
            if inLong && az > lim.y {
                let s = b.p.y > 0 ? 1.0 : -1.0
                b.p.y = s * lim.y
                bounce(&b, n: V2(0, s))
            }
            if inShort && ax > lim.x {
                let s = b.p.x > 0 ? 1.0 : -1.0
                b.p.x = s * lim.x
                bounce(&b, n: V2(s, 0))
            }
            // zabezpieczenie: poza stołem
            if abs(b.p.x) > Phys.halfL + 0.12 || abs(b.p.y) > Phys.halfW + 0.12 {
                b.p.x = max(-Phys.halfL - 0.12, min(Phys.halfL + 0.12, b.p.x))
                b.p.y = max(-Phys.halfW - 0.12, min(Phys.halfW + 0.12, b.p.y))
                b.v = V2(0, 0)
                balls[i] = b
                balls[i].active = false
                events.append(.offTable(ball: i, pos: b.p))
                continue
            }
            balls[i] = b
        }
    }

    /// Odbicie od bandy; n – normalna skierowana w stronę bandy
    /// Wspólny wzór odbicia od bandy (fizyka i podgląd): zwraca nową prędkość i gwint pionowy
    static func cushionResponse(v: V2, wy: Double, n: V2) -> (v: V2, wy: Double, vn: Double)? {
        let vn = simd_dot(v, n)
        guard vn > 0 else { return nil }
        var v = v, wy = wy
        let e = max(0.55, Phys.eCushion - 0.012 * vn)
        v -= n * ((1 + e) * vn)
        let t = V2(-n.y, n.x)
        let slip = simd_dot(v, t) - wy * Phys.R
        let f = min(Phys.muCushion * (1 + e) * vn, abs(slip) / 3.5) * (slip >= 0 ? 1 : -1)
        v -= t * f
        wy += f / (0.4 * Phys.R)
        return (v, wy, vn)
    }

    private func bounce(_ b: inout Ball, n: V2) {
        guard let r = Self.cushionResponse(v: b.v, wy: b.w.y, n: n) else { return }
        let vn = r.vn
        b.v = r.v; b.w.y = r.wy
        events.append(.cushion(ball: b.id, speed: vn, pos: b.p))
    }

    // MARK: Ustawienie bil
    func rack(seed: UInt64, rules: GameModeRules) {
        var rng = SeededGen(s: seed)
        let lay = rules.layout(rng: &rng)
        for i in 1..<Phys.nBalls {
            if let p = lay[i] {
                balls[i].p = p; balls[i].active = true
            } else { balls[i].active = false; balls[i].p = V2(0, 5) }
            balls[i].v = V2(0, 0); balls[i].w = V3(0, 0, 0)
            balls[i].q = Self.randomQuat(&rng)
        }
        balls[0].p = lay[0] ?? rules.cueSpot
        balls[0].v = V2(0, 0); balls[0].w = V3(0, 0, 0); balls[0].active = true
        balls[0].q = Self.randomQuat(&rng)
    }

    static func randomQuat(_ r: inout SeededGen) -> simd_quatd {
        let a = Double(r.next() % 6283) / 1000, b = Double(r.next() % 3141) / 1000
        let axis = simd_normalize(V3(sin(b) * cos(a), sin(b) * sin(a), cos(b)))
        return simd_quatd(angle: Double(r.next() % 6283) / 1000, axis: axis)
    }

    func isFree(_ p: V2, ignoring: Int = 0, margin: Double = 0.002) -> Bool {
        for b in balls where b.active && b.id != ignoring {
            if simd_length(b.p - p) < 2 * Phys.R + margin { return false }
        }
        return true
    }
}

struct SeededGen: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
