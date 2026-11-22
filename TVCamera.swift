import Foundation
import simd

// MARK: - Kamera telewizyjna (tryb demo, później menu)
// Samodzielny „realizator”: wybiera ujęcia jak w transmisji TV i trzyma każde 3–6 s.
// Cięcia twarde albo krótkie przejście (0,6 s). Wszystkie ujęcia są bezpieczne:
// • „niskie” (y < 0,72) – pod kloszami lamp (klosze zaczynają się na 1,0 m), lampy widoczne,
// • „wysokie” (y ≥ 0,9) – lampy ukryte maską kategorii (updateCamera, próg 0,80),
//   przejście płynne tylko w obrębie jednego pasma, więc lampy nigdy nie „wskakują” w kadr,
// • nad suknem zawsze powyżej bandy, a za białą – ponad linią kija (cueVisElev + zapas).
// Wywołanie update() nic nie alokuje; losowanie tylko w chwili cięcia.

enum TVStage { case idle, thinking, aiming, rolling }

struct TVInput {
    var dt: Double
    var balls: [Ball]
    var stage: TVStage
    var cue: V3                 // środek białej
    var aimDir: V2              // kierunek kija
    var cueElev: Double         // widoczne nachylenie kija (rad)
    var focusBall: Int?         // bila, na którą idzie zagranie
    var focusPocket: Int?       // łuza docelowa
    var aspect: Double
}

final class TVCamera {
    enum Shot: String { case wide, behindCue, pocket, rail, orbit, pushIn, overhead, fixed }

    private(set) var shot: Shot = .wide
    private(set) var shotT = 0.0             // czas trwania bieżącego ujęcia
    var log = false
    var minHold = 3.0, maxHold = 6.0

    private var stage: TVStage = .idle
    private var stageT = 0.0
    private var smooth = SmoothCam()
    private var last = CamPose(pos: V3(0, 1, 2), look: V3(0, 0, 0), up: V3(0, 1, 0), fov: 40)
    private var blendFrom: CamPose? = nil
    private var blendT = 0.0, blendDur = 0.6
    private var pendingEstablish = false
    private var lastEstablish: Shot = .overhead

    // parametry ujęcia losowane przy cięciu
    private var side = 1.0, corner = V2(1, 1), ang0 = 0.0, angDir = 1.0, pocketIdx = 0
    private var railBall = 0, focusDir = V3(1, 0, 0), focusP = V3(0, 0, 0)
    private var fixedPose = CamPose(pos: V3(0, 1, 2), look: V3(0, 0, 0), up: V3(0, 1, 0), fov: 40)
    private var track = V3(0, 0, 0)

    /// ujęcie „z góry”: menu/scena mogą podmienić (np. zNear, nakładki)
    var overhead: Bool { shot == .overhead }

    func reset() {
        stage = .idle; stageT = 0; blendFrom = nil; pendingEstablish = false
        cut(.orbit, hard: true)
    }

    /// stałe ujęcie zadane z zewnątrz (np. przejazd do stołu w menu)
    func frame(_ p: CamPose, blend: Double = 0.6) {
        fixedPose = p
        cut(.fixed, hard: blend <= 0, dur: blend)
    }

    // MARK: Cięcia

    private static func high(_ s: Shot) -> Bool { s == .wide || s == .orbit || s == .pushIn || s == .overhead }

    private func cut(_ s: Shot, hard: Bool, dur: Double = 0.6) {
        let soft = !hard && s != .overhead && shot != .overhead && Self.high(s) == Self.high(shot)
        blendFrom = soft ? last : nil
        blendT = 0; blendDur = dur
        if !soft { smooth = SmoothCam() }
        shot = s; shotT = 0
        angDir = Bool.random() ? 1 : -1
        if log { print("TV cut \(s.rawValue) \(soft ? "blend" : "hard")") }
    }

    private func establish(_ i: TVInput) {
        var opts: [Shot] = [.orbit, .pushIn, .wide, .orbit, .pushIn, .wide, .overhead]
        opts.removeAll { $0 == lastEstablish }
        let s = opts.randomElement() ?? .wide
        lastEstablish = s
        corner = V2(Bool.random() ? 1 : -1, Bool.random() ? 1 : -1)
        ang0 = Double.random(in: 0..<(2 * .pi))
        focusP = i.cue
        let a = Double.random(in: 0..<(2 * .pi))
        focusDir = V3(cos(a), 0, sin(a))
        cut(s, hard: Bool.random())
    }

    private func pickRolling(_ i: TVInput) {
        if let b = i.focusBall, b < i.balls.count, i.balls[b].active, i.balls[b].speed > 0.15 {
            pocketIdx = i.focusPocket ?? CameraDirector.bestPocket(from: i.balls[b].p, dir: simd_normalize(i.balls[b].v + V2(1e-9, 0)))
            railBall = b
            cut(.pocket, hard: true)
        } else {
            railBall = 0
            side = i.balls[0].p.y >= 0 ? 1 : -1
            cut(.rail, hard: true)
        }
    }

    // MARK: Aktualizacja

    func update(_ i: TVInput) -> CamPose {
        let dt = i.dt
        shotT += dt
        if i.stage != stage {
            let prev = stage
            stage = i.stage; stageT = 0
            if stage == .thinking || stage == .idle && prev != .idle { pendingEstablish = true }
        } else { stageT += dt }
        updateTrack(i)

        // reżyseria
        switch stage {
        case .thinking, .idle:
            if pendingEstablish && shotT >= minHold * 0.6 { pendingEstablish = false; establish(i) }
            else if stage == .idle && shotT > maxHold + 2 { establish(i) }
        case .aiming:
            if pendingEstablish && shotT >= minHold * 0.6 { pendingEstablish = false; establish(i) }
            else if shot != .behindCue && Self.high(shot) && shotT >= minHold && !pendingEstablish { cut(.behindCue, hard: true) }
            else if shot != .behindCue && !Self.high(shot) && shotT >= minHold { cut(.behindCue, hard: true) }
        case .rolling:
            pendingEstablish = false
            if shot == .behindCue && stageT > 0.5 && shotT >= minHold { pickRolling(i) }
            else if (shot == .pocket || shot == .rail) && shotT > maxHold { focusP = track; cut(.wide, hard: false) }
            else if shot == .pocket && shotT > minHold && !(railBall < i.balls.count && i.balls[railBall].active) { cut(.wide, hard: true) }
            else if Self.high(shot) && shot != .wide && shotT > maxHold { cut(.wide, hard: true) }
        }

        var p = pose(i)
        p = safe(p, i)
        // wygładzanie: śledzenie jest miękkie, ujęcia statyczne i tak stoją
        let st: Double
        switch shot { case .behindCue: st = 0.32; case .pocket, .rail: st = 0.30; case .overhead, .fixed: st = 0.0001; default: st = 0.4 }
        var out = smooth.step(p, dt: dt, smoothTime: st)
        if let f = blendFrom {
            blendT += dt
            let u = CameraDirector.smooth(blendT / blendDur)
            out = Self.blend(f, out, u)
            if u >= 1 { blendFrom = nil }
        }
        last = out
        return out
    }

    private func updateTrack(_ i: TVInput) {
        var want = V3(0, 0, 0)
        if stage == .rolling {
            var sx = 0.0, sz = 0.0, sw = 0.0
            for b in i.balls where b.active {
                let v = b.speed
                if v < 0.05 { continue }
                let w = v * v + 0.02
                sx += b.p.x * w; sz += b.p.y * w; sw += w
            }
            if sw > 0 { want = V3(sx / sw, 0, sz / sw) * 0.75 }
        }
        track += (want - track) * (1 - exp(-i.dt * 1.2))
    }

    // MARK: Ujęcia

    private func pose(_ i: TVInput) -> CamPose {
        let sc = Phys.halfL / 1.27
        let hl = Phys.halfL, hw = Phys.halfW
        let up = V3(0, 1, 0)
        switch shot {
        case .wide:
            // z rogu sali, lekki dryf boczny
            let drift = V3(-corner.y, 0, corner.x) * (0.035 * shotT * angDir)
            let pos = V3(corner.x * hl * 1.2, 1.05 * sc, corner.y * hw * 2.7) + drift
            return CamPose(pos: pos, look: track * 0.6, up: up, fov: 40)
        case .orbit:
            let a = ang0 + angDir * 0.085 * shotT
            let pos = V3(cos(a) * 2.15 * sc, 1.0 * sc, sin(a) * 1.55 * sc)
            return CamPose(pos: pos, look: V3(0, -0.05, 0), up: up, fov: 40)
        case .pushIn:
            // najazd na białą z wysoka
            let u = CameraDirector.smooth(shotT / 5.0)
            let f = V3(i.cue.x, 0, i.cue.z) * 0.6
            let far = f + focusDir * (2.2 * sc) + V3(0, 1.3 * sc, 0)
            let near = f + focusDir * (1.35 * sc) + V3(0, 0.95 * sc, 0)
            return CamPose(pos: far + (near - far) * u, look: f, up: up, fov: 40 - 4 * u)
        case .overhead:
            let fovTop = 38.0
            let th = tan(fovTop / 2 * .pi / 180)
            let H = max((hl + 0.30) / (th * i.aspect), (hw + 0.30) / th)
            return CamPose(pos: V3(0, H, 0.0001), look: V3(0, 0, 0), up: V3(0, 0, -1), fov: fovTop)
        case .behindCue:
            // zza pleców gracza, wzdłuż linii kija; powolny najazd
            let d = V3(i.aimDir.x, 0, i.aimDir.y)
            let right = V3(-d.z, 0, d.x)
            let h = (1.05 - 0.15 * CameraDirector.smooth(shotT / 4)) * sc
            var pos = i.cue - d * h + right * (0.10 * angDir)
            pos.y = 0.40
            let look = i.cue + d * (0.55 * sc) - V3(0, Phys.R, 0)
            return CamPose(pos: pos, look: look, up: up, fov: 42)
        case .pocket:
            // nisko zza łuzy, patrzymy na nadjeżdżającą bilę
            let pk = BilliardPhysics.pockets[min(pocketIdx, BilliardPhysics.pockets.count - 1)]
            let n = simd_length(pk.c) > 1e-6 ? simd_normalize(pk.c) : V2(1, 0)
            let pos = V3(pk.c.x + n.x * 0.72, 0.26, pk.c.y + n.y * 0.72)
            var b = V3(pk.c.x, Phys.R, pk.c.y) * 0.5
            if railBall < i.balls.count, i.balls[railBall].active { b = V3(i.balls[railBall].p.x, Phys.R, i.balls[railBall].p.y) }
            let look = b * 0.75 + V3(pk.c.x, Phys.R, pk.c.y) * 0.25
            return CamPose(pos: pos, look: look, up: up, fov: 38)
        case .rail:
            // wózek wzdłuż długiej bandy, śledzi białą (bez obrotów o 180°)
            let b = i.balls[min(railBall, i.balls.count - 1)]
            let bp = b.active ? V3(b.p.x, Phys.R, b.p.y) : track
            let pos = V3(bp.x * 0.8, 0.46, side * (hw + 0.62))
            return CamPose(pos: pos, look: bp, up: up, fov: 36)
        case .fixed:
            return fixedPose
        }
    }

    /// bezpieczeństwo: nad stołem zawsze ponad bandą, za białą ponad kijem
    private func safe(_ p0: CamPose, _ i: TVInput) -> CamPose {
        var p = p0
        let ox = TableBuilder.X + TableBuilder.railW + 0.05, oz = TableBuilder.Y + TableBuilder.railW + 0.05
        if abs(p.pos.x) < ox && abs(p.pos.z) < oz { p.pos.y = max(p.pos.y, TableBuilder.railTop + 0.12) }
        if shot == .behindCue {
            // wysokość kija w odległości kamery od białej (kij ~1,47 m) + zapas
            let rel = V2(p.pos.x - i.cue.x, p.pos.z - i.cue.z)
            let along = -simd_dot(rel, i.aimDir)
            if along > 0 && along < 1.6 {
                let need = Phys.R + along * tan(max(0, i.cueElev)) + 0.12
                if need > p.pos.y { p.pos.y = need < 0.72 ? need : max(need, 0.9) }
            }
        }
        p.pos.y = max(p.pos.y, 0.09)
        return p
    }

    private static func blend(_ a: CamPose, _ b: CamPose, _ u: Double) -> CamPose {
        let v = 1 - u
        let pos = a.pos * v + b.pos * u
        let dir = CameraDirector.slerp(CameraDirector.fwd(a), CameraDirector.fwd(b), u)
        let dist = simd_length(a.look - a.pos) * v + simd_length(b.look - b.pos) * u
        let up = simd_normalize(a.up * v + b.up * u)
        return CamPose(pos: pos, look: pos + dir * dist, up: up, fov: a.fov * v + b.fov * u)
    }
}
