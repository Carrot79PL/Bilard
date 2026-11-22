import Foundation
import simd

// MARK: - Cinematic Camera Director
// Nakłada na „bazową” kamerę gry (celowanie ↔ z góry ↔ przegląd) ujęcia reżyserskie:
// TV z rogu pokoju, zza łuzy, swobodny orbit, intro, najazd na bilę decydującą.
// Przejścia: pozycja po krzywej Béziera, kierunek patrzenia przez Slerp. Nic nie alokuje w pętli.

enum CamPreset: Int, CaseIterable {
    case auto, broadcast, pocket, orbit
    var title: String {
        switch self { case .auto: return "Kamera: auto"; case .broadcast: return "Kamera: TV"; case .pocket: return "Kamera: łuza"; case .orbit: return "Kamera: swobodna" }
    }
    var icon: String {
        switch self { case .auto: return "video"; case .broadcast: return "tv"; case .pocket: return "scope"; case .orbit: return "rotate.3d" }
    }
    var next: CamPreset { CamPreset(rawValue: (rawValue + 1) % CamPreset.allCases.count)! }
}

struct CamPose {
    var pos: V3
    var look: V3
    var up: V3
    var fov: Double
}

struct CamContext {
    var dt: Double
    var balls: [Ball]
    var rolling: Bool
    var topView: Bool
    var cue: V3                 // środek białej
    var aimTarget: Int?         // bila, w którą celuje gracz (jeśli znana)
    var aimTgtDir: V2           // kierunek, w którym poleci bila docelowa po zderzeniu
}

final class CameraDirector {
    var preset: CamPreset = .auto
    // swobodna kamera
    var orbitYaw = 0.6, orbitPitch = 0.55, orbitDist = 1.6
    var orbitFocus: Int? = nil

    // śledzenie akcji (dla przeglądu / TV)
    private(set) var trackPoint = V3(0, 0, 0)
    private(set) var trackSpeed = 0.0

    private var w = 0.0                         // waga ujęcia nakładanego (0 = baza)
    private var cine: Cine = .none
    private var cineT = 0.0
    private var autoPocket = false              // kamera zza łuzy dla trudnego zagrania, do końca ruchu bil
    private var pocketIdx = 0
    private var sc = 1.0
    // powtórka
    var replayActive = false
    var replayPocket = 0
    var replayFocus = V3(0, 0, 0)
    var replayPhase = 0.0          // 0 = ujęcie szerokie, 1 = zza łuzy

    private enum Cine { case none, intro, matchBall }

    var introActive: Bool { cine == .intro }
    var active: Bool { w > 0.001 || cine != .none }

    // MARK: Sterowanie z zewnątrz

    func startIntro() { cine = .intro; cineT = 0 }
    func skipIntro() { if cine == .intro { cine = .none } }
    func startMatchBall() { if cine == .none { cine = .matchBall; cineT = 0 } }
    func cycle() -> CamPreset { preset = preset.next; return preset }

    /// wywoływane w chwili uderzenia: czy przełączyć na ujęcie zza łuzy
    func onShot(long: Bool, matchBall: Bool, aimTarget: Int?, tgtDir: V2, balls: [Ball]) {
        autoPocket = false
        guard (long || matchBall), let t = aimTarget else { return }
        pocketIdx = Self.bestPocket(from: balls[t].p, dir: tgtDir)
        autoPocket = true
    }
    func shotEnded() { autoPocket = false }
    func cancelCine() { cine = .none }

    static func bestPocket(from p: V2, dir: V2) -> Int {
        var best = 0, bs = -2.0
        for (i, pk) in BilliardPhysics.pockets.enumerated() {
            let d = pk.c - p
            let l = simd_length(d)
            if l < 1e-6 { continue }
            let s = simd_dot(d / l, dir) - 0.05 * l
            if s > bs { bs = s; best = i }
        }
        return best
    }

    // MARK: Orbit (gesty gładzika)

    func orbitScroll(dx: Double, dy: Double) {
        orbitYaw += dx * 0.004
        orbitPitch = max(0.08, min(1.45, orbitPitch + dy * 0.004))
    }
    func orbitZoom(_ f: Double) { orbitDist = max(0.25, min(4.0, orbitDist * f)) }
    func orbitPick(_ p: V2, balls: [Ball]) {
        var best: Int? = nil, bd = 0.12
        for b in balls where b.active { let d = simd_length(b.p - p); if d < bd { bd = d; best = b.id } }
        orbitFocus = best
        if best != nil { orbitDist = min(orbitDist, 0.5) } else { orbitDist = max(orbitDist, 1.6) }
    }

    // MARK: Główna aktualizacja

    func update(_ c: CamContext, base: CamPose) -> CamPose {
        let dt = c.dt
        sc = Phys.halfL / 1.27
        updateTracking(c)

        // czas ujęć kinowych
        if cine != .none {
            cineT += dt
            let dur = cine == .intro ? 2.2 : 2.4
            if cineT >= dur { cine = .none }
        }
        if c.topView && cine == .matchBall { cine = .none }
        if replayActive { cine = .none }

        if cine == .intro { return introPose(cineT / 2.2, base) }
        if cine == .matchBall { return matchBallPose(cineT / 2.4, base, c) }

        // ujęcie nakładane
        var target = 0.0
        var ovr = base
        if replayActive {
            ovr = replayPose(c); target = 1
        } else if !c.topView {
            if autoPocket && preset != .orbit {
                ovr = pocketPose(c, idx: pocketIdx); target = 1
            } else {
                switch preset {
                case .auto: break
                case .broadcast: ovr = broadcastPose(c, base); target = 1
                case .pocket:
                    let idx = c.aimTarget.map { Self.bestPocket(from: c.balls[$0].p, dir: c.aimTgtDir) } ?? pocketIdx
                    pocketIdx = idx
                    ovr = pocketPose(c, idx: idx); target = 1
                case .orbit: ovr = orbitPose(c); target = 1
                }
            }
        }
        w += (target - w) * (1 - exp(-dt * (replayActive ? 4.0 : 3.0)))
        if abs(target - w) < 0.0005 { w = target }
        if w <= 0.0005 { return base }
        return blend(base, ovr, Self.smooth(w))
    }

    // MARK: Śledzenie akcji

    private func updateTracking(_ c: CamContext) {
        var want = V3(0, 0, 0)
        var spd = 0.0
        if c.rolling {
            // środek ciężkości ruchomych bil (ważony prędkością) – nie przeskakuje między bilami; biała ma dodatkową wagę
            var sx = 0.0, sz = 0.0, sw = 0.0, mx = 0.0
            for b in c.balls where b.active {
                let v = b.speed
                if v < 0.08 { continue }
                let wgt = v * v * (b.id == 0 ? 2.5 : 1) + 0.02
                sx += b.p.x * wgt; sz += b.p.y * wgt; sw += wgt; mx = max(mx, v)
            }
            if sw > 0 { want = V3(sx / sw, 0, sz / sw) * 0.8; spd = min(1, mx / 4) }
        }
        let k = 1 - exp(-c.dt * 1.3)
        trackPoint += (want - trackPoint) * k
        trackSpeed += (spd - trackSpeed) * (1 - exp(-c.dt * 1.0))
    }

    // MARK: Pozycje kamer

    private func broadcastPose(_ c: CamContext, _ base: CamPose) -> CamPose {
        let hl = Phys.halfL, hw = Phys.halfW
        let pos = V3(-hl * 1.45, 1.15 * sc, hw * 2.9)
        let look = V3(trackPoint.x * 0.7, 0, trackPoint.z * 0.7)
        // pan & zoom: im bliżej akcja, tym ciaśniejsze ujęcie
        let fov = 40 - 7 * trackSpeed
        return CamPose(pos: pos, look: look, up: V3(0, 1, 0), fov: fov)
    }

    private func pocketPose(_ c: CamContext, idx: Int) -> CamPose {
        let pk = BilliardPhysics.pockets[min(idx, BilliardPhysics.pockets.count - 1)]
        let n = simd_length(pk.c) > 1e-6 ? simd_normalize(pk.c) : V2(1, 0)
        // „zza łuzy”: tuż za krawędzią stołu, nisko, patrzymy na biała/bilę docelową
        let pos = V3(pk.c.x + n.x * 0.75, 0.24, pk.c.y + n.y * 0.75)
        var focus = c.cue
        if let t = c.aimTarget { focus = V3(c.balls[t].p.x, Phys.R, c.balls[t].p.y) }
        if c.rolling { focus = V3(trackPoint.x, Phys.R, trackPoint.z) * 0.5 + V3(pk.c.x, Phys.R, pk.c.y) * 0.1 + focus * 0.4 }
        return CamPose(pos: pos, look: focus * 0.6 + V3(0, Phys.R, 0), up: V3(0, 1, 0), fov: 40)
    }

    /// powtórka: ujęcie szerokie z rogu → nisko zza łuzy przy bili kluczowej
    private func replayPose(_ c: CamContext) -> CamPose {
        let hl = Phys.halfL, hw = Phys.halfW
        let wide = CamPose(pos: V3(hl * 1.35, 1.0 * sc, -hw * 2.8),
                           look: V3(replayFocus.x * 0.55, 0, replayFocus.z * 0.55), up: V3(0, 1, 0), fov: 38)
        let pk = BilliardPhysics.pockets[min(replayPocket, BilliardPhysics.pockets.count - 1)]
        let n = simd_length(pk.c) > 1e-6 ? simd_normalize(pk.c) : V2(1, 0)
        let close = CamPose(pos: V3(pk.c.x + n.x * 0.55, 0.15, pk.c.y + n.y * 0.55),
                            look: V3(replayFocus.x, Phys.R, replayFocus.z) * 0.85 + V3(pk.c.x, Phys.R, pk.c.y) * 0.15, up: V3(0, 1, 0), fov: 36)
        return blend(wide, close, Self.smooth(replayPhase))
    }

    private func orbitPose(_ c: CamContext) -> CamPose {
        var center = V3(0, 0, 0)
        if let f = orbitFocus, c.balls[f].active { center = V3(c.balls[f].p.x, Phys.R, c.balls[f].p.y) }
        let cp = cos(orbitPitch), sp = sin(orbitPitch)
        let off = V3(cos(orbitYaw) * cp, sp, sin(orbitYaw) * cp) * orbitDist
        var pos = center + off
        pos.y = max(pos.y, 0.07)
        return CamPose(pos: pos, look: center, up: V3(0, 1, 0), fov: 40)
    }

    // MARK: Kinowe najazdy

    /// intro: spokojny, krótki najazd w prostej linii z lekkiego oddalenia i wysokości do kamery gry (bez obrotu obrazu)
    private func introPose(_ t: Double, _ base: CamPose) -> CamPose {
        let u = Self.smooth(max(0, min(1, t)))
        let v = 1 - u
        let start = base.pos + V3(0, 0.45 * sc, 0) - Self.fwd(base) * (0.55 * sc)
        let pos = start * v + base.pos * u
        return CamPose(pos: pos, look: base.look, up: base.up, fov: base.fov)
    }

    /// dolly zoom: kamera odsuwa się, FOV się zawęża – tło „kurczy się” za bilą decydującą
    private func matchBallPose(_ t: Double, _ base: CamPose, _ c: CamContext) -> CamPose {
        let e = sin(Double.pi * max(0, min(1, t)))
        let e2 = e * e * (3 - 2 * e)
        let fwd = Self.fwd(base)
        let d0 = simd_length(base.look - base.pos)
        let back = 0.30 * d0 * e2
        let pos = base.pos - fwd * back
        let fov = 2 * atan(tan(base.fov / 2 * .pi / 180) * d0 / (d0 + back)) * 180 / .pi
        return CamPose(pos: pos, look: base.look, up: base.up, fov: fov)
    }

    // MARK: Pomoce

    static func smooth(_ x: Double) -> Double { let t = max(0, min(1, x)); return t * t * (3 - 2 * t) }
    static func fwd(_ p: CamPose) -> V3 { simd_normalize(p.look - p.pos) }

    static func slerp(_ a: V3, _ b: V3, _ t: Double) -> V3 {
        let d = max(-1, min(1, simd_dot(a, b)))
        let th = acos(d)
        if th < 1e-4 { return simd_normalize(a * (1 - t) + b * t) }
        let s = sin(th)
        return (a * sin((1 - t) * th) + b * sin(t * th)) / s
    }

    /// przejście bazowa → nakładana: pozycja po kwadratowej krzywej Béziera (łuk w górę), kierunek Slerp
    private func blend(_ a: CamPose, _ b: CamPose, _ u: Double) -> CamPose {
        let mid = (a.pos + b.pos) * 0.5
        let arc = simd_length(b.pos - a.pos) * 0.22
        let ctrl = mid + V3(0, arc, 0)
        let v = 1 - u
        let pos = a.pos * (v * v) + ctrl * (2 * v * u) + b.pos * (u * u)
        let dir = Self.slerp(Self.fwd(a), Self.fwd(b), u)
        let dist = simd_length(a.look - a.pos) * v + simd_length(b.look - b.pos) * u
        let up = simd_normalize(a.up * v + b.up * u)
        return CamPose(pos: pos, look: pos + dir * dist, up: up, fov: a.fov * v + b.fov * u)
    }
}


// MARK: - Wygładzanie kamery (critically damped spring, jak SmoothDamp)

struct SmoothCam {
    private var pos = V3(0, 0, 0), posV = V3(0, 0, 0)
    private var look = V3(0, 0, 0), lookV = V3(0, 0, 0)
    private var up = V3(0, 1, 0)
    private var fov = 40.0, fovV = 0.0
    private var started = false

    private static func damp(_ cur: Double, _ tgt: Double, _ vel: inout Double, _ st: Double, _ dt: Double) -> Double {
        let om = 2 / max(0.0001, st)
        let x = om * dt
        let e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let ch = cur - tgt
        let tmp = (vel + om * ch) * dt
        vel = (vel - om * tmp) * e
        var out = tgt + (ch + tmp) * e
        if abs(out - tgt) < 1e-7 { out = tgt; vel = 0 }
        return out
    }
    private static func damp3(_ cur: V3, _ tgt: V3, _ vel: inout V3, _ st: Double, _ dt: Double) -> V3 {
        V3(damp(cur.x, tgt.x, &vel.x, st, dt), damp(cur.y, tgt.y, &vel.y, st, dt), damp(cur.z, tgt.z, &vel.z, st, dt))
    }

    /// start z zadanej pozy (bez skoku, zerowe prędkości)
    mutating func seed(_ p: CamPose) {
        started = true; pos = p.pos; look = p.look; up = p.up; fov = p.fov
        posV = V3(0, 0, 0); lookV = V3(0, 0, 0); fovV = 0
    }

    mutating func step(_ t: CamPose, dt: Double, smoothTime st: Double) -> CamPose {
        if !started { started = true; pos = t.pos; look = t.look; up = t.up; fov = t.fov }
        let d = min(dt, 0.05)
        pos = Self.damp3(pos, t.pos, &posV, st, d)
        look = Self.damp3(look, t.look, &lookV, st * 0.9, d)
        fov = Self.damp(fov, t.fov, &fovV, st, d)
        let k = 1 - exp(-d / max(0.02, st * 0.5))
        up = simd_normalize(up + (t.up - up) * k)
        return CamPose(pos: pos, look: look, up: up, fov: fov)
    }
}
