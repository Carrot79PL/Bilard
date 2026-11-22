import AVFoundation
import simd

// MARK: - Dźwięk 3D syntezowany proceduralnie + generowana muzyka lounge
// AVAudioEngine: efekty -> AVAudioEnvironmentNode -> mixer -> PeakLimiter -> wyjście
//                muzyka -> pogłos -> mixer

final class GameAudio {
    private let engine = AVAudioEngine()
    private let env = AVAudioEnvironmentNode()
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private var music: MusicEngine?
    private let rollPlayer = AVAudioPlayerNode()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private let sr = 44100.0
    private let format: AVAudioFormat
    private var clicks: [[AVAudioPCMBuffer]] = []   // [poziom][wariant]
    private var thuds: [[AVAudioPCMBuffer]] = []
    private var cueTaps: [AVAudioPCMBuffer] = []
    private var drops: [AVAudioPCMBuffer] = []
    private var started = false
    private var applauseBuf: AVAudioPCMBuffer?
    private var rollLevel: Float = 0

    /// M: wycisza całość (efekty i muzykę)
    var enabled = true

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        var rng = SeededGen(s: 12345)
        for lvl in 0..<8 { clicks.append((0..<3).map { _ in makeClick(Double(lvl) / 7, &rng) }) }
        for lvl in 0..<4 { thuds.append((0..<2).map { _ in makeThud(Double(lvl) / 3, &rng) }) }
        cueTaps = (0..<3).map { _ in makeCueTap(&rng) }
        drops = (0..<2).map { _ in makePocketDrop(&rng) }
        let rollBuf = makeRoll(&rng)

        engine.attach(env)
        env.renderingAlgorithm = .equalPowerPanning
        env.distanceAttenuationParameters.referenceDistance = 0.6
        env.distanceAttenuationParameters.maximumDistance = 20
        env.distanceAttenuationParameters.rolloffFactor = 0.5
        env.reverbParameters.enable = false
        engine.attach(limiter)
        engine.connect(env, to: engine.mainMixerNode, format: nil)
        engine.connect(engine.mainMixerNode, to: limiter, format: nil)
        engine.connect(limiter, to: engine.outputNode, format: nil)
        for _ in 0..<20 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: env, format: format)
            p.renderingAlgorithm = .equalPowerPanning
            players.append(p)
        }
        // toczenie po suknie
        engine.attach(rollPlayer)
        engine.connect(rollPlayer, to: env, format: format)
        rollPlayer.position = AVAudio3DPoint(x: 0, y: 0.05, z: 0)
        rollPlayer.volume = 0
        engine.prepare()
        do { try engine.start(); started = true } catch { started = false }
        for p in players { p.play() }
        rollPlayer.scheduleBuffer(rollBuf, at: nil, options: .loops, completionHandler: nil)
        rollPlayer.play()
        let me = MusicEngine(engine: engine, destination: engine.mainMixerNode)
        music = me
        me.start()
    }

    // MARK: Odtwarzanie
    private func play(_ buf: AVAudioPCMBuffer, at pos: SIMD3<Float>, volume: Float) {
        guard enabled, started else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.position = AVAudio3DPoint(x: pos.x, y: pos.y, z: pos.z)
        p.volume = max(0, min(1.5, volume))
        p.scheduleBuffer(buf, at: nil, options: .interrupts, completionHandler: nil)
        if !p.isPlaying { p.play() }
    }

    func setListener(position: SIMD3<Float>, forward: SIMD3<Float>) {
        env.listenerPosition = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        let yaw = atan2(-forward.x, -forward.z) * 180 / .pi
        let pitch = asin(max(-1, min(1, forward.y))) * 180 / .pi
        env.listenerAngularOrientation = AVAudio3DAngularOrientation(yaw: yaw, pitch: pitch, roll: 0)
    }

    /// level 0…1 – najszybsza toczona bila (cichy szum po suknie)
    func setRolling(_ level: Double) {
        guard started else { return }
        let target = Float(0.16 * pow(max(0, min(1, level)), 1.3))
        rollLevel += (target - rollLevel) * 0.12
        rollPlayer.volume = enabled ? rollLevel : 0
    }

    /// zderzenie bil; speed – prędkość zbliżania [m/s]
    func ballHit(speed: Double, at p: V2) {
        let l = max(0, min(1, speed / 5.0))
        let lvl = Int((l * 7).rounded())
        let buf = clicks[lvl][Int.random(in: 0..<3)]
        play(buf, at: SIMD3(Float(p.x), 0.03, Float(p.y)), volume: Float(0.07 + 0.85 * pow(l, 1.25)))
    }
    func cushion(speed: Double, at p: V2) {
        let l = max(0, min(1, speed / 4.0))
        play(thuds[Int((l * 3).rounded())][Int.random(in: 0..<2)], at: SIMD3(Float(p.x), 0.03, Float(p.y)),
             volume: Float(0.10 + 0.6 * pow(l, 1.1)))
    }
    func cueHit(power: Double, at p: V2) {
        play(cueTaps[Int.random(in: 0..<3)], at: SIMD3(Float(p.x), 0.05, Float(p.y)), volume: Float(0.30 + 0.6 * power))
    }
    func pocket(at p: V2) {
        play(drops[Int.random(in: 0..<2)], at: SIMD3(Float(p.x), -0.02, Float(p.y)), volume: 0.8)
    }

    /// oklaski publiczności po wygranej (~6 s, syntezowane: tło szumu + setki pojedynczych klaśnięć)
    func applause() {
        guard enabled, started else { return }
        if applauseBuf == nil { applauseBuf = makeApplause() }
        play(applauseBuf!, at: SIMD3(0, 0.8, 0), volume: 1.3)
    }
    /// Publiczność: setki pojedynczych klaśnięć (rezonans 1,2–3 kHz, 6–12 ms), mruczenie tłumu, kilka okrzyków („ooo!”)
    /// z formantami głosu i pogłos hali. Gęstość klaskania faluje, jak przy prawdziwych brawach.
    private func makeApplause() -> AVAudioPCMBuffer {
        var r = SeededGen(s: 4711)
        func u() -> Double { Double(r.next() % 100000) / 100000 }
        let dur = 8.0, n = Int(dur * sr)
        var dry = [Double](repeating: 0, count: n)
        func env(_ t: Double) -> Double { min(1, t / 0.8) * (t < 4.2 ? 1 : exp(-(t - 4.2) * 0.95)) }
        // 1) mruczenie tłumu: szum pasmowy 700–3500 Hz
        var lp1 = 0.0, lp2 = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let x = u() * 2 - 1
            lp1 += 0.35 * (x - lp1)                 // dolnoprzepustowy ~3 kHz
            lp2 += 0.03 * (lp1 - lp2)               // wycina poniżej ~250 Hz
            dry[i] += (lp1 - lp2) * 0.10 * env(t) * (0.85 + 0.15 * sin(t * 9.3))
        }
        // 2) pojedyncze klaśnięcia, gęstość z falowaniem
        var placed = 0
        while placed < 2600 {
            let t0 = u() * 6.6
            let dens = env(t0) * (0.65 + 0.35 * sin(2 * .pi * 2.1 * t0 + 1.3) * sin(2 * .pi * 0.35 * t0 + 0.4) + 0.2)
            if u() > dens { continue }
            placed += 1
            let i0 = Int(t0 * sr)
            let f0 = 1200 + u() * 1800, rr = 0.90 + u() * 0.07, decay = (0.006 + u() * 0.007) * sr
            let amp = 0.05 + pow(u(), 2.2) * 0.6
            let a1 = 2 * rr * cos(2 * .pi * f0 / sr), a2 = -rr * rr
            var y1 = 0.0, y2 = 0.0
            let len = Int(decay * 5)
            for k in 0..<len where i0 + k < n {
                let x = k < 6 ? (u() * 2 - 1) * 1.6 : (u() * 2 - 1) * 0.5          // ostry początek + ogon
                let y = a1 * y1 + a2 * y2 + x * 0.25
                y2 = y1; y1 = y
                dry[i0 + k] += y * amp * exp(-Double(k) / decay)
            }
        }
        // 3) okrzyki: harmoniczne z glissandem i formantami samogłoski „o/u”
        for _ in 0..<7 {
            let t0 = 0.5 + u() * 3.2, len = Int((0.55 + u() * 0.5) * sr), i0 = Int(t0 * sr)
            let base = 170 + u() * 190, rise = 1.15 + u() * 0.35, amp = 0.045 + u() * 0.04
            let f1 = 330 + u() * 120, f2 = 800 + u() * 250
            var ph = 0.0
            for k in 0..<len where i0 + k < n {
                let tt = Double(k) / Double(len)
                let f = base * (1 + (rise - 1) * sin(tt * .pi / 2)) * (1 + 0.012 * sin(Double(k) / sr * 36))     // glissando + wibrato
                ph += 2 * .pi * f / sr
                var s = 0.0
                var h = 1
                while Double(h) * f < 3800 {
                    let hf = Double(h) * f
                    let form = exp(-pow((hf - f1) / 220, 2)) + 0.6 * exp(-pow((hf - f2) / 350, 2)) + 0.08
                    s += sin(Double(h) * ph) * form / Double(h)
                    h += 1
                }
                let e = min(1, tt / 0.12) * pow(1 - tt, 1.3)
                dry[i0 + k] += s * amp * e
            }
        }
        // 4) pogłos hali: cztery grzebienie + dwa all-passy
        func comb(_ x: [Double], _ ms: Double, _ g: Double) -> [Double] {
            let d = Int(ms * sr / 1000); var o = [Double](repeating: 0, count: x.count)
            for i in 0..<x.count { o[i] = x[i] + (i >= d ? o[i - d] * g : 0) }
            return o
        }
        var wet = [Double](repeating: 0, count: n)
        for (ms, g) in [(29.7, 0.80), (37.1, 0.78), (41.1, 0.76), (43.7, 0.74), (53.3, 0.72)] {
            let c = comb(dry, ms, g)
            for i in 0..<n { wet[i] += c[i] * 0.2 }
        }
        var out = [Float](repeating: 0, count: n)
        var wl = 0.0
        for i in 0..<n { wl += 0.45 * (wet[i] - wl); out[i] = Float(dry[i] * 0.6 + wl * 0.5) }
        let fade = Int(0.4 * sr)
        for k in 0..<fade { out[n - 1 - k] *= Float(k) / Float(fade) }
        let peak = max(0.001, out.map { abs($0) }.max() ?? 1)
        let g = Float(0.85) / peak
        return make(dur) { _, i in out[i] * g }
    }

    // MARK: Synteza efektów
    private func make(_ dur: Double, _ gen: (Double, Int) -> Float) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(dur * sr)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        b.frameLength = n
        let d = b.floatChannelData![0]
        for i in 0..<Int(n) { d[i] = gen(Double(i) / sr, i) }
        return b
    }
    private func nz(_ r: inout SeededGen) -> Double { Double(r.next() % 20001) / 10000 - 1 }

    /// Bila–bila: żywica fenolowa. Krótki (~3 ms) nietonalny „klik”: szum wysokoprzepustowy
    /// + dwa mocno stłumione rezonanse 3–8 kHz. Im mocniej, tym jaśniej. Brak długiego tonu.
    private func makeClick(_ l: Double, _ r: inout SeededGen) -> AVAudioPCMBuffer {
        let det = 1 + (Double(r.next() % 100) / 100 - 0.5) * 0.16
        let f1 = (3300 + 1500 * l) * det, f2 = (5600 + 2400 * l) * det
        var lp = 0.0, hp = 0.0, out = 0.0
        let cut = 0.35 + 0.5 * l                 // jasność zależna od siły
        return make(0.03) { t, _ in
            let n = nz(&r)
            hp += 0.25 * (n - hp)                // n - hp = szum bez niskich
            var s = (n - hp) * exp(-t / 0.00045)
            s += 0.55 * sin(2 * .pi * f1 * t) * exp(-t / 0.00055)
            s += 0.35 * sin(2 * .pi * f2 * t) * exp(-t / 0.00035)
            s += 0.12 * sin(2 * .pi * 900 * t) * exp(-t / 0.0012)   // minimalny „ciałek”
            s *= min(1, t / 0.00008)
            lp += cut * (s - lp)
            out = lp
            return Float(out * 0.8)
        }
    }
    /// Banda: miękki, gumowy stuk – szum dolnoprzepustowy + krótki, wysoki (150–230 Hz) ton, bez basu.
    private func makeThud(_ l: Double, _ r: inout SeededGen) -> AVAudioPCMBuffer {
        var lp = 0.0, lp2 = 0.0
        let a = 0.05 + 0.07 * l
        return make(0.09) { t, _ in
            let n = nz(&r)
            lp += a * (n - lp)
            lp2 += a * (lp - lp2)                // 2-biegunowy LP – miękko
            var s = 3.2 * lp2 * exp(-t / 0.012)
            s += 0.28 * sin(2 * .pi * (170 + 50 * l) * t) * exp(-t / 0.012)
            s *= min(1, t / 0.0012)
            return Float(s * 0.55)
        }
    }
    /// Kij–bila: krótkie, tłumione „tok” skórzanej końcówki.
    private func makeCueTap(_ r: inout SeededGen) -> AVAudioPCMBuffer {
        var lp = 0.0, lp2 = 0.0
        return make(0.045) { t, _ in
            let n = nz(&r)
            lp += 0.22 * (n - lp)
            lp2 += 0.35 * (lp - lp2)
            var s = 2.0 * lp2 * exp(-t / 0.0022)
            s += 0.55 * sin(2 * .pi * 1250 * t) * exp(-t / 0.0028)
            s += 0.40 * sin(2 * .pi * 380 * t) * exp(-t / 0.007)
            s *= min(1, t / 0.0003)
            return Float(s * 0.55)
        }
    }
    /// Łuza: głuche stuknięcie i kilka coraz cichszych, coraz gęstszych stuknięć w koszu.
    private func makePocketDrop(_ r: inout SeededGen) -> AVAudioPCMBuffer {
        var lp = 0.0, lp2 = 0.0
        let knocks: [(Double, Double)] = [(0.0, 1.0), (0.17, 0.55), (0.30, 0.38), (0.39, 0.26), (0.46, 0.17), (0.51, 0.1)]
        return make(0.8) { t, _ in
            let n = nz(&r)
            lp += 0.10 * (n - lp)
            lp2 += 0.10 * (lp - lp2)
            var s = 0.0
            for (t0, a) in knocks where t >= t0 {
                let tt = t - t0
                s += a * (2.4 * lp2 * exp(-tt / 0.018) + 0.3 * sin(2 * .pi * (200 - 12 * t0 * 10) * tt) * exp(-tt / 0.02))
            }
            // cichy toczący się szum w koszu
            s += 0.9 * lp2 * exp(-t / 0.25) * min(1, t / 0.05)
            return Float(s * 0.5)
        }
    }
    /// Zapętlony cichy szum toczenia po suknie (pasmowy, ~150–1500 Hz), zamknięty crossfadem.
    private func makeRoll(_ r: inout SeededGen) -> AVAudioPCMBuffer {
        let dur = 2.0
        let n = Int(dur * sr)
        var raw = [Double](repeating: 0, count: n)
        var lp = 0.0, lp2 = 0.0, hp = 0.0
        for i in 0..<n {
            let x = nz(&r)
            lp += 0.14 * (x - lp)
            lp2 += 0.14 * (lp - lp2)
            hp += 0.02 * (lp2 - hp)
            raw[i] = lp2 - hp
        }
        let xf = Int(0.1 * sr)
        let len = n - xf
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(len))!
        b.frameLength = AVAudioFrameCount(len)
        let d = b.floatChannelData![0]
        for i in 0..<len {
            var v = raw[i]
            if i < xf {
                let w = Double(i) / Double(xf)           // początek wchodzi, ogon wychodzi
                v = v * w + raw[len + i] * (1 - w)
            }
            d[i] = Float(v * 2.2)
        }
        return b
    }

    /// tryb demo: całość ciszej (efekty + muzyka), bez zmiany ustawień gracza
    func setQuiet(_ q: Bool) { engine.mainMixerNode.outputVolume = q ? 0.3 : 1 }

    // MARK: Ustawienia dźwięku (suwaki, styl, wyciszenie)
    func apply(_ st: Settings) {
        let mute = st.muted
        env.outputVolume = mute ? 0 : Float(st.sfxVol * st.sfxVol * 1.4)
        if mute { rollPlayer.volume = 0 }
        music?.muted = mute
        music?.musicVolume = Float(st.musicVol)
        music?.ambienceVolume = Float(st.ambVol)
        music?.setStyle(MusicStyle(rawValue: st.musicStyle) ?? .jazz)
    }
}
