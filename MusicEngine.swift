import AVFoundation
import Foundation

// MARK: - Publiczne API

enum MusicStyle: String, CaseIterable {
    case lofi, jazz, ambient, synthwave, funk, bossa, house, off
    var title: String {
        switch self {
        case .lofi: return "Lo-fi"
        case .jazz: return "Smooth jazz"
        case .ambient: return "Ambient"
        case .synthwave: return "Synthwave"
        case .funk: return "Funk"
        case .bossa: return "Bossa lounge"
        case .house: return "Deep house"
        case .off: return "Wyłączona"
        }
    }
}

final class MusicEngine {
    private let engine: AVAudioEngine
    private let destination: AVAudioNode
    private let fmt: AVAudioFormat
    private let playerA = AVAudioPlayerNode()
    private let playerB = AVAudioPlayerNode()
    private let musicMix = AVAudioMixerNode()
    private let reverb = AVAudioUnitReverb()
    private let ambPlayer = AVAudioPlayerNode()

    private var active: AVAudioPlayerNode?
    private var cache: [MusicStyle: AVAudioPCMBuffer] = [:]
    private var rendering: Set<MusicStyle> = []
    private var wanted: MusicStyle = .off
    private var current: MusicStyle = .off
    private var started = false
    private var ambBuffer: AVAudioPCMBuffer?
    private var ambRendering = false
    private var fades: [ObjectIdentifier: Timer] = [:]

    var musicVolume: Float = 0.7 { didSet { musicVolume = min(1, max(0, musicVolume)); applyVolumes() } }
    var ambienceVolume: Float = 0.6 { didSet { ambienceVolume = min(1, max(0, ambienceVolume)); applyVolumes() } }
    var muted: Bool = false { didSet { applyVolumes() } }

    init(engine: AVAudioEngine, destination: AVAudioNode) {
        self.engine = engine
        self.destination = destination
        self.fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

        engine.attach(playerA)
        engine.attach(playerB)
        engine.attach(musicMix)
        engine.attach(reverb)
        engine.attach(ambPlayer)

        reverb.loadFactoryPreset(.mediumRoom)
        reverb.wetDryMix = 25
        playerA.volume = 0
        playerB.volume = 0

        engine.connect(playerA, to: musicMix, format: fmt)
        engine.connect(playerB, to: musicMix, format: fmt)
        engine.connect(musicMix, to: reverb, format: fmt)
        engine.connect(reverb, to: destination, format: fmt)
        engine.connect(ambPlayer, to: destination, format: fmt)
        applyVolumes()
    }

    func start() {
        guard !started else { return }
        started = true
        renderAmbience()
        apply(wanted)
    }

    func setStyle(_ s: MusicStyle) {
        wanted = s
        guard started else { return }
        apply(s)
    }

    // MARK: Prywatne

    private func applyVolumes() {
        musicMix.outputVolume = muted ? 0 : musicVolume * musicVolume
        ambPlayer.volume = muted ? 0 : ambienceVolume * ambienceVolume
    }

    private func ensureEngineRunning() -> Bool {
        if !engine.isRunning { try? engine.start() }
        return engine.isRunning
    }

    private func apply(_ style: MusicStyle) {
        if style == .off {
            if let a = active {
                fade(a, to: 0, duration: 0.6) { [weak self, weak a] in
                    if let a = a, self?.active !== a { a.stop() }
                    if self?.current == .off { a?.stop() }
                }
            }
            current = .off
            return
        }
        if style == current { return }
        if let buf = cache[style] {
            swap(style, buf)
        } else if !rendering.contains(style) {
            rendering.insert(style)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let t0 = Date()
                let buf = MusicRender.makeMusic(style)
                if let b = buf, ProcessInfo.processInfo.environment["BILARD_MUSIC_LOG"] != nil {
                    MusicRender.logStats(style, b, seconds: Date().timeIntervalSince(t0))
                }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.rendering.remove(style)
                    if let buf = buf {
                        self.cache[style] = buf
                        if self.wanted == style && self.started { self.apply(style) }
                    }
                }
            }
        }
    }

    private func swap(_ style: MusicStyle, _ buf: AVAudioPCMBuffer) {
        guard ensureEngineRunning() else { return }
        let old = active
        let new = (old === playerA) ? playerB : playerA
        fades[ObjectIdentifier(new)]?.invalidate()
        fades[ObjectIdentifier(new)] = nil
        new.stop()
        new.volume = 0
        switch style {
        case .ambient:
            reverb.loadFactoryPreset(.largeRoom); reverb.wetDryMix = 32
        case .jazz, .bossa:
            reverb.loadFactoryPreset(.mediumRoom); reverb.wetDryMix = 24
        case .synthwave:
            reverb.loadFactoryPreset(.largeHall); reverb.wetDryMix = 26
        case .funk:
            reverb.loadFactoryPreset(.smallRoom); reverb.wetDryMix = 16
        default:
            reverb.loadFactoryPreset(.mediumRoom); reverb.wetDryMix = 22
        }
        new.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        new.play()
        fade(new, to: 1, duration: 0.6)
        if let o = old {
            fade(o, to: 0, duration: 0.6) { [weak self, weak o] in
                if let o = o, self?.active !== o { o.stop() }
            }
        }
        active = new
        current = style
    }

    private func fade(_ p: AVAudioPlayerNode, to target: Float, duration: Double, completion: (() -> Void)? = nil) {
        let key = ObjectIdentifier(p)
        fades[key]?.invalidate()
        let from = p.volume
        let steps = max(1, Int(duration / 0.03))
        var k = 0
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self, weak p] t in
            k += 1
            guard let p = p else { t.invalidate(); return }
            let f = Float(k) / Float(steps)
            p.volume = from + (target - from) * f
            if k >= steps {
                t.invalidate()
                self?.fades[key] = nil
                completion?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fades[key] = timer
    }

    private func renderAmbience() {
        if ambBuffer != nil {
            playAmbience()
            return
        }
        guard !ambRendering else { return }
        ambRendering = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let buf = MusicRender.makeAmbience()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.ambRendering = false
                self.ambBuffer = buf
                if self.started { self.playAmbience() }
            }
        }
    }

    private func playAmbience() {
        guard let buf = ambBuffer, ensureEngineRunning() else { return }
        ambPlayer.stop()
        ambPlayer.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
        ambPlayer.play()
    }
}

// MARK: - Generator losowy (prywatny)

private let kSR: Double = 44100

private struct MEGen {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 0x1234567 }
    mutating func nextU64() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(nextU64() >> 40) / Float(1 << 24) }
    mutating func noise() -> Float { unit() * 2 - 1 }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * unit() }
    mutating func chance(_ p: Float) -> Bool { unit() < p }
    mutating func int(_ n: Int) -> Int { Int(nextU64() % UInt64(max(1, n))) }
}

private func mtof(_ m: Int) -> Double { 440.0 * pow(2.0, Double(m - 69) / 12.0) }

private struct StereoBuf {
    let n: Int
    var l: [Float]
    var r: [Float]
    init(seconds: Double) {
        n = Int(seconds * kSR)
        l = [Float](repeating: 0, count: n)
        r = l
    }
    mutating func add(_ x: [Float], at start: Int, pan: Float, gain: Float) {
        let a = (max(-1, min(1, pan)) + 1) * 0.25 * Float.pi
        let gl = cos(a) * gain, gr = sin(a) * gain
        var idx = ((start % n) + n) % n
        for v in x {
            l[idx] += v * gl
            r[idx] += v * gr
            idx += 1
            if idx == n { idx = 0 }
        }
    }
    mutating func addAt(_ x: [Float], time: Double, pan: Float, gain: Float) {
        add(x, at: Int(time * kSR), pan: pan, gain: gain)
    }
}

// MARK: - Synteza

private let kTableSize = 2048
private let kTable: [Float] = {
    var t = [Float](repeating: 0, count: kTableSize)
    let weights: [Float] = [1, 0.45, 0.28, 0.16, 0.09, 0.05]
    var peak: Float = 0
    for i in 0..<kTableSize {
        var s: Float = 0
        for (h, w) in weights.enumerated() {
            s += w * sin(2 * Float.pi * Float(h + 1) * Float(i) / Float(kTableSize))
        }
        t[i] = s
        peak = max(peak, abs(s))
    }
    for i in 0..<kTableSize { t[i] /= peak }
    return t
}()

private enum Synth {
    static func rhodes(freq: Double, dur: Double, vel: Float, bright: Float = 1) -> [Float] {
        let n = Int((dur + 0.4) * kSR)
        var out = [Float](repeating: 0, count: n)
        let w = 2 * Double.pi * freq
        let decay = 1.0 + 2.0 / (1 + freq / 250)
        let tine = freq < 900
        for i in 0..<n {
            let t = Double(i) / kSR
            let att = min(1, Float(t / 0.004))
            let env = Float(exp(-t * decay)) * att
            let idx = Double(vel * bright) * (1.7 * exp(-t * 5.0) + 0.25)
            let body = Float(sin(w * t + idx * sin(w * t)))
            var s = body * env
            if tine { s += 0.10 * vel * Float(sin(w * 14.0 * t) * exp(-t * 30.0)) }
            let rel: Float = t > dur ? Float(exp(-(t - dur) * 12.0)) : 1
            out[i] = s * vel * rel
        }
        return out
    }

    static func bass(freq: Double, dur: Double, vel: Float, pluck: Bool) -> [Float] {
        let n = Int((dur + 0.15) * kSR)
        var out = [Float](repeating: 0, count: n)
        let w = 2 * Double.pi * freq
        for i in 0..<n {
            let t = Double(i) / kSR
            let att = min(1, Float(t / 0.008))
            let dec = Float(exp(-t * (pluck ? 3.0 : 1.6)))
            let rel: Float = t > dur ? Float(exp(-(t - dur) * 25.0)) : 1
            let s = Float(sin(w * t)) + 0.28 * Float(sin(2 * w * t)) * Float(exp(-t * 6))
            out[i] = s * att * dec * rel * vel
        }
        return out
    }

    static func kick(vel: Float, fat: Bool) -> [Float] {
        let n = Int(0.5 * kSR)
        var out = [Float](repeating: 0, count: n)
        var ph = 0.0
        for i in 0..<n {
            let t = Double(i) / kSR
            let f = 42 + 85 * exp(-t * 26)
            ph += 2 * Double.pi * f / kSR
            var s = Float(sin(ph)) * Float(exp(-t * (fat ? 6.5 : 9)))
            s += 0.2 * Float(exp(-t * 400))
            out[i] = tanh(s * (fat ? 2.2 : 1.3)) * vel
        }
        return out
    }

    static func snare(gen: inout MEGen, vel: Float, soft: Bool) -> [Float] {
        let n = Int(0.28 * kSR)
        var out = [Float](repeating: 0, count: n)
        var lp: Float = 0
        for i in 0..<n {
            let t = Double(i) / kSR
            let w = gen.noise()
            lp += (soft ? 0.35 : 0.6) * (w - lp)
            let tone = Float(sin(2 * Double.pi * 185 * t) * exp(-t * 30))
            out[i] = (lp * Float(exp(-t * 16)) * 0.8 + tone * 0.4) * vel
        }
        return out
    }

    static func hat(gen: inout MEGen, vel: Float, open: Bool) -> [Float] {
        let n = Int((open ? 0.2 : 0.06) * kSR)
        var out = [Float](repeating: 0, count: n)
        var prev: Float = 0
        for i in 0..<n {
            let t = Double(i) / kSR
            let w = gen.noise()
            let hp = w - prev
            prev = w
            out[i] = hp * Float(exp(-t * (open ? 16 : 80))) * vel * 0.4
        }
        return out
    }

    static func brush(gen: inout MEGen, dur: Double, vel: Float, swell: Bool) -> [Float] {
        let n = Int(dur * kSR)
        var out = [Float](repeating: 0, count: n)
        var prev: Float = 0, lp: Float = 0
        for i in 0..<n {
            let t = Double(i) / kSR
            let w = gen.noise()
            let hp = w - 0.7 * prev
            prev = w
            lp += 0.45 * (hp - lp)
            let x = Float(t / dur)
            let env: Float = swell ? sin(Float.pi * min(1, x * 0.9 + 0.05)) * (1 - x * 0.5)
                                   : min(1, x * 20) * Float(exp(-t * 14))
            out[i] = lp * env * vel * 0.35
        }
        return out
    }

    static func pad(freq: Double, dur: Double, attack: Double, release: Double, gen: inout MEGen) -> [Float] {
        let n = Int((dur + release) * kSR)
        var out = [Float](repeating: 0, count: n)
        let cents: [Double] = [-10, -4, 0, 4, 9]
        var phases = cents.map { _ in Double(gen.unit()) * Double(kTableSize) }
        let incs = cents.map { freq * pow(2.0, $0 / 1200.0) * Double(kTableSize) / kSR }
        let lfoRate = Double(gen.range(0.08, 0.25))
        let lfoPh = Double(gen.unit()) * 2 * Double.pi
        let size = Double(kTableSize)
        for i in 0..<n {
            let t = Double(i) / kSR
            var s: Float = 0
            for k in 0..<5 {
                let p = phases[k]
                let i0 = Int(p) % kTableSize
                let i1 = (i0 + 1) % kTableSize
                let fr = Float(p - floor(p))
                s += kTable[i0] * (1 - fr) + kTable[i1] * fr
                phases[k] = p + incs[k]
                if phases[k] >= size { phases[k] -= size }
            }
            var env: Double
            if t < attack { let x = t / attack; env = x * x * (3 - 2 * x) } else { env = 1 }
            if t > dur { let x = min(1, (t - dur) / release); env *= 1 - x * x * (3 - 2 * x) }
            let trem = 0.85 + 0.15 * sin(2 * Double.pi * lfoRate * t + lfoPh)
            out[i] = s * 0.2 * Float(env * trem)
        }
        return out
    }

    static func bell(freq: Double, vel: Float, decay: Double) -> [Float] {
        let n = Int(decay * 3.5 * kSR)
        var out = [Float](repeating: 0, count: n)
        let w = 2 * Double.pi * freq
        for i in 0..<n {
            let t = Double(i) / kSR
            let idx = Double(vel) * 2.2 * exp(-t * 1.6)
            let s = sin(w * t + idx * sin(w * 3.5 * t))
            let att = min(1, t / 0.003)
            out[i] = Float(s * exp(-t / decay) * att) * vel
        }
        return out
    }

    // MARK: efekty na całych buforach (okresowe -> bezszwowe)

    static func lowpass(_ x: inout [Float], cutoff: Double) {
        let a = Float(1 - exp(-2 * Double.pi * cutoff / kSR))
        var y: Float = 0
        let n = x.count
        let prime = min(n, 8000)
        for i in (n - prime)..<n { y += a * (x[i] - y) }
        for i in 0..<n { y += a * (x[i] - y); x[i] = y }
    }

    static func wow(_ b: inout StereoBuf, depth: Double, wowCycles: Int, flutterCycles: Int) {
        let n = b.n
        let srcL = b.l, srcR = b.r
        for i in 0..<n {
            let ph = Double(i) / Double(n)
            let d = depth * sin(2 * Double.pi * Double(wowCycles) * ph)
                  + depth * 0.06 * sin(2 * Double.pi * Double(flutterCycles) * ph)
            var pos = Double(i) + d
            pos = pos.truncatingRemainder(dividingBy: Double(n))
            if pos < 0 { pos += Double(n) }
            let i0 = Int(pos)
            let i1 = (i0 + 1) % n
            let f = Float(pos - Double(i0))
            b.l[i] = srcL[i0] * (1 - f) + srcL[i1] * f
            b.r[i] = srcR[i0] * (1 - f) + srcR[i1] * f
        }
    }

    static func normalize(_ b: inout StereoBuf, peak: Float) {
        var m: Float = 0.0001
        for i in 0..<b.n { m = max(m, abs(b.l[i]), abs(b.r[i])) }
        let g = peak / m
        for i in 0..<b.n { b.l[i] *= g; b.r[i] *= g }
    }
}

// MARK: - Renderowanie stylów

private struct Chord {
    let bass: Int
    let third: Int
    let voicing: [Int]
}

private enum MusicRender {
    static func pcm(_ b: StereoBuf) -> AVAudioPCMBuffer? {
        guard let f = AVAudioFormat(standardFormatWithSampleRate: kSR, channels: 2),
              let buf = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(b.n)),
              let ch = buf.floatChannelData else { return nil }
        buf.frameLength = AVAudioFrameCount(b.n)
        b.l.withUnsafeBufferPointer { ch[0].update(from: $0.baseAddress!, count: b.n) }
        b.r.withUnsafeBufferPointer { ch[1].update(from: $0.baseAddress!, count: b.n) }
        return buf
    }

    static func makeMusic(_ s: MusicStyle) -> AVAudioPCMBuffer? {
        switch s {
        case .lofi: return pcm(lofi())
        case .jazz: return pcm(jazz())
        case .ambient: return pcm(ambient())
        case .synthwave: return pcm(synthwave())
        case .funk: return pcm(funk())
        case .bossa: return pcm(bossa())
        case .house: return pcm(house())
        case .off: return nil
        }
    }

    static func makeAmbience() -> AVAudioPCMBuffer? { pcm(ambience()) }

    /// Diagnostyka (BILARD_MUSIC_LOG=1): czas renderu, poziomy, skok na szwie pętli
    static func logStats(_ s: MusicStyle, _ b: AVAudioPCMBuffer, seconds: Double) {
        guard let ch = b.floatChannelData else { return }
        let n = Int(b.frameLength)
        var peak: Float = 0, sum: Double = 0, maxJump: Float = 0
        for i in 0..<n {
            let v = ch[0][i]; peak = max(peak, abs(v)); sum += Double(v * v)
            if i > 0 { maxJump = max(maxJump, abs(v - ch[0][i - 1])) }
        }
        let seam = abs(ch[0][0] - ch[0][n - 1])
        print(String(format: "[music] %@ render=%.2fs len=%.1fs peak=%.3f rms=%.3f seam=%.4f maxStep=%.4f",
                     s.rawValue, seconds, Double(n) / kSR, peak, (sum / Double(n)).squareRoot(), seam, maxJump))
    }

    // MARK: Lo-fi

    static func lofi() -> StereoBuf {
        var g = MEGen(seed: 7781)
        let bpm = 78.0, beat = 60.0 / bpm, bars = 16
        let dur = Double(bars) * 4 * beat
        var b = StereoBuf(seconds: dur)
        let prog: [Chord] = [
            Chord(bass: 38, third: 3, voicing: [53, 57, 60, 64]),   // Dm9
            Chord(bass: 43, third: 4, voicing: [53, 59, 62, 64]),   // G13
            Chord(bass: 36, third: 4, voicing: [52, 55, 59, 62]),   // Cmaj9
            Chord(bass: 45, third: 3, voicing: [55, 60, 64, 67])    // Am7
        ]
        let pent = [72, 74, 76, 79, 81, 84]
        let swing = 0.12
        func et(_ bar: Int, _ e: Int) -> Double {
            Double(bar) * 4 * beat + Double(e / 2) * beat + (e % 2 == 1 ? beat * (0.5 + swing) : 0)
        }
        for bar in 0..<bars {
            let ch = prog[bar % 4]
            // Rhodes
            var hits = [(0, 1.7, Float(0.55))]
            if g.chance(0.55) { hits.append((5, 1.0, Float(0.4))) }
            if bar % 4 == 3 && g.chance(0.5) { hits.append((7, 0.5, Float(0.35))) }
            for h in hits {
                let t0 = et(bar, h.0) + Double(g.range(-0.008, 0.008))
                for (k, m) in ch.voicing.enumerated() {
                    let x = Synth.rhodes(freq: mtof(m), dur: h.1 * beat, vel: h.2 * g.range(0.85, 1.05), bright: 0.8)
                    b.addAt(x, time: t0 + Double(k) * 0.011, pan: -0.3 + Float(k) * 0.2, gain: 0.5)
                }
            }
            // bas
            b.addAt(Synth.bass(freq: mtof(ch.bass), dur: 1.3 * beat, vel: 0.9, pluck: false), time: et(bar, 0), pan: 0, gain: 0.7)
            if g.chance(0.5) {
                let m = ch.bass + (g.chance(0.5) ? 0 : 7)
                b.addAt(Synth.bass(freq: mtof(m), dur: 0.5 * beat, vel: 0.7, pluck: false), time: et(bar, 5), pan: 0, gain: 0.6)
            }
            // perkusja
            b.addAt(Synth.kick(vel: 1, fat: true), time: et(bar, 0), pan: 0, gain: 0.8)
            if g.chance(0.6) { b.addAt(Synth.kick(vel: 0.8, fat: true), time: et(bar, 5), pan: 0, gain: 0.7) }
            if bar % 4 == 3 && g.chance(0.5) { b.addAt(Synth.kick(vel: 0.7, fat: true), time: et(bar, 7), pan: 0, gain: 0.7) }
            for e in [2, 6] {
                b.addAt(Synth.snare(gen: &g, vel: g.range(0.5, 0.7), soft: true), time: et(bar, e) + 0.004, pan: 0.05, gain: 0.35)
            }
            for e in 0..<8 {
                let v: Float = (e % 2 == 0 ? 0.55 : 0.35) * g.range(0.7, 1.1)
                b.addAt(Synth.hat(gen: &g, vel: v, open: e == 7 && g.chance(0.25)), time: et(bar, e),
                        pan: 0.25, gain: 0.35)
            }
            // melodia
            if bar % 2 == 1 && g.chance(0.65) {
                let e = [0, 2, 3, 4, 5][g.int(5)]
                let m = pent[g.int(pent.count)]
                b.addAt(Synth.rhodes(freq: mtof(m), dur: Double(g.range(0.6, 1.2)) * beat, vel: 0.4, bright: 1.0),
                        time: et(bar, e), pan: Float(g.range(-0.2, 0.4)), gain: 0.5)
            }
        }
        // winyl: szum + trzaski
        var lpL: Float = 0, lpR: Float = 0
        for i in 0..<b.n {
            lpL += 0.3 * (g.noise() - lpL)
            lpR += 0.3 * (g.noise() - lpR)
            b.l[i] += lpL * 0.006
            b.r[i] += lpR * 0.006
        }
        for _ in 0..<Int(dur * 6) {
            let pos = g.int(b.n)
            let pan = g.range(-0.8, 0.8)
            let amp = g.range(0.01, 0.05)
            let len = 1 + g.int(3)
            var x = [Float](repeating: 0, count: len)
            for k in 0..<len { x[k] = (k % 2 == 0 ? 1 : -0.6) * amp }
            b.add(x, at: pos, pan: pan, gain: 1)
        }
        for _ in 0..<Int(dur / 3) {
            let n = Int(0.012 * kSR)
            var x = [Float](repeating: 0, count: n)
            for k in 0..<n { x[k] = g.noise() * Float(exp(-Double(k) / kSR * 400)) * 0.08 }
            b.add(x, at: g.int(b.n), pan: g.range(-0.7, 0.7), gain: 1)
        }
        Synth.wow(&b, depth: 20, wowCycles: max(1, Int(0.6 * dur)), flutterCycles: max(1, Int(6.5 * dur)))
        Synth.lowpass(&b.l, cutoff: 4200)
        Synth.lowpass(&b.r, cutoff: 4200)
        Synth.normalize(&b, peak: 0.5)
        return b
    }

    // MARK: Smooth jazz

    static func jazz() -> StereoBuf {
        var g = MEGen(seed: 4242)
        let bpm = 72.0, beat = 60.0 / bpm, bars = 16
        let dur = Double(bars) * 4 * beat
        var b = StereoBuf(seconds: dur)
        let prog: [Chord] = [
            Chord(bass: 38, third: 3, voicing: [53, 57, 60, 64]),   // Dm7
            Chord(bass: 43, third: 4, voicing: [53, 59, 62, 64]),   // G7
            Chord(bass: 36, third: 4, voicing: [52, 59, 62, 67]),   // Cmaj7
            Chord(bass: 36, third: 4, voicing: [55, 57, 62, 64])    // C6/9
        ]
        let keys = [0, 5, -2, 0]
        let pent = [67, 69, 72, 74, 76, 79, 81]
        let swing = 0.17
        func et(_ bar: Int, _ e: Int) -> Double {
            Double(bar) * 4 * beat + Double(e / 2) * beat + (e % 2 == 1 ? beat * (0.5 + swing) : 0)
        }
        func chord(_ bar: Int) -> (Chord, Int) { (prog[bar % 4], keys[(bar / 4) % 4]) }
        for bar in 0..<bars {
            let (ch, tr) = chord(bar)
            let (nch, ntr) = chord(bar + 1)
            // Rhodes comping (Charleston)
            var hits: [(Int, Double, Float)] = [(0, 1.3, 0.5)]
            if g.chance(0.8) { hits.append((3, 0.8, 0.42)) }
            if g.chance(0.25) { hits.append((7, 0.6, 0.35)) }
            for h in hits {
                let t0 = et(bar, h.0) + Double(g.range(-0.01, 0.01))
                for (k, m) in ch.voicing.enumerated() {
                    let x = Synth.rhodes(freq: mtof(m + tr), dur: h.1 * beat, vel: h.2 * g.range(0.85, 1.05), bright: 0.9)
                    b.addAt(x, time: t0 + Double(k) * 0.012, pan: -0.35 + Float(k) * 0.22, gain: 0.5)
                }
            }
            // kontrabas walking-lite
            let root = ch.bass + tr
            let approach = nch.bass + ntr + (g.chance(0.5) ? 1 : -1)
            let walk = [root, root + ch.third, root + 7, approach]
            for (k, m) in walk.enumerated() {
                let t = Double(bar) * 4 * beat + Double(k) * beat + Double(g.range(-0.006, 0.006))
                b.addAt(Synth.bass(freq: mtof(m), dur: 0.85 * beat, vel: k == 0 ? 0.95 : 0.8, pluck: true),
                        time: t, pan: -0.05, gain: 0.75)
            }
            // szczotki
            for k in 0..<4 {
                let t = Double(bar) * 4 * beat + Double(k) * beat
                b.addAt(Synth.brush(gen: &g, dur: 0.22, vel: g.range(0.5, 0.8), swell: false), time: t, pan: 0.3, gain: 0.5)
            }
            for e in [3, 7] {
                b.addAt(Synth.brush(gen: &g, dur: 0.16, vel: g.range(0.3, 0.5), swell: false), time: et(bar, e), pan: 0.3, gain: 0.5)
            }
            for e in [2, 6] {
                b.addAt(Synth.brush(gen: &g, dur: beat * 0.9, vel: g.range(0.5, 0.7), swell: true), time: et(bar, e), pan: -0.15, gain: 0.5)
            }
            if g.chance(0.5) { b.addAt(Synth.kick(vel: 0.35, fat: false), time: et(bar, 0), pan: 0, gain: 0.5) }
            // rzadka melodia
            if g.chance(0.38) {
                let cnt = 1 + g.int(2)
                var e = [0, 2, 3, 4, 6][g.int(5)]
                for _ in 0..<cnt {
                    let m = pent[g.int(pent.count)] + tr
                    b.addAt(Synth.rhodes(freq: mtof(m), dur: Double(g.range(0.7, 1.4)) * beat, vel: 0.42, bright: 1.2),
                            time: et(bar, min(e, 7)), pan: Float(g.range(-0.1, 0.4)), gain: 0.5)
                    e += 2
                }
            }
        }
        Synth.lowpass(&b.l, cutoff: 6500)
        Synth.lowpass(&b.r, cutoff: 6500)
        Synth.normalize(&b, peak: 0.5)
        return b
    }

    // MARK: Ambient

    static func ambient() -> StereoBuf {
        var g = MEGen(seed: 9090)
        let chordLen = 6.0, count = 8
        let dur = chordLen * Double(count)
        var b = StereoBuf(seconds: dur)
        let prog: [[Int]] = [
            [41, 53, 57, 60, 64],   // Fmaj7
            [45, 57, 60, 64, 67],   // Am7
            [38, 57, 60, 64, 65],   // Dm9
            [43, 55, 60, 62, 67]    // Gsus
        ]
        for c in 0..<count {
            let notes = prog[c % 4]
            for (k, m) in notes.enumerated() {
                let x = Synth.pad(freq: mtof(m), dur: chordLen + 1.0, attack: Double(g.range(2.0, 4.0)),
                                  release: Double(g.range(2.5, 4.0)), gen: &g)
                let pan: Float = (k % 2 == 0 ? -1 : 1) * Float(k) * 0.12
                b.addAt(x, time: Double(c) * chordLen + Double(g.range(0, 0.6)), pan: pan, gain: 0.9)
            }
        }
        let bells = [72, 74, 77, 79, 81, 84, 86]
        for _ in 0..<12 {
            let m = bells[g.int(bells.count)]
            b.addAt(Synth.bell(freq: mtof(m), vel: g.range(0.25, 0.5), decay: Double(g.range(2.0, 3.5))),
                    time: Double(g.range(0, Float(dur))), pan: g.range(-0.8, 0.8), gain: 0.35)
        }
        Synth.lowpass(&b.l, cutoff: 7000)
        Synth.lowpass(&b.r, cutoff: 7000)
        Synth.normalize(&b, peak: 0.5)
        return b
    }

    // MARK: Otoczenie klubu

    static func scaleRMS(_ x: inout [Float], target: Float) {
        var s: Double = 0
        for v in x { s += Double(v * v) }
        let rms = Float((s / Double(max(1, x.count))).squareRoot())
        let g = target / max(rms, 1e-6)
        for i in 0..<x.count { x[i] *= g }
    }

    static func peakScale(_ x: inout [Float], peak: Float) {
        var m: Float = 1e-6
        for v in x { m = max(m, abs(v)) }
        let g = peak / m
        for i in 0..<x.count { x[i] *= g }
    }

    static func loopify(_ x: [Float], n: Int) -> [Float] {
        let f = x.count - n
        var out = Array(x[0..<n])
        for i in 0..<f {
            let a = Float(i) / Float(f) * Float.pi / 2
            out[i] = x[i] * sin(a) + x[n + i] * cos(a)
        }
        return out
    }

    static func roomNoise(seed: UInt64, n: Int, cycles: Int) -> [Float] {
        var g = MEGen(seed: seed)
        let f = 44100
        let m = n + f
        var pink = [Float](repeating: 0, count: m)
        var brown = [Float](repeating: 0, count: m)
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, br: Float = 0
        for i in 0..<m {
            let w = g.noise()
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            b2 = 0.57000 * b2 + w * 1.0526913
            pink[i] = b0 + b1 + b2 + w * 0.1848
            br = (br + 0.02 * w) / 1.02
            brown[i] = br
        }
        Synth.lowpass(&pink, cutoff: 1400)
        var p = loopify(pink, n: n)
        var q = loopify(brown, n: n)
        scaleRMS(&p, target: 0.018)
        scaleRMS(&q, target: 0.03)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let ph = 2 * Double.pi * Double(cycles) * Double(i) / Double(n)
            let swell = Float(1 + 0.15 * sin(ph))
            out[i] = (p[i] + q[i]) * swell
        }
        return out
    }

    static func murmur(dur: Double, f0: Double, shift: Float, rate: Double, gen: inout MEGen) -> [Float] {
        let n = Int(dur * kSR)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var lo1: Float = 0, bp1: Float = 0, lo2: Float = 0, bp2: Float = 0, lp: Float = 0
        var sylLeft = 0, sylLen = 1
        var f1: Float = 500, f2: Float = 1500, f1t: Float = 500, f2t: Float = 1500
        var sylAmp: Float = 1
        var fric = false
        var pitchMul = 1.0
        let q: Float = 0.25
        let sr = Float(kSR)
        for i in 0..<n {
            let t = Double(i) / kSR
            if sylLeft <= 0 {
                sylLen = max(200, Int(kSR / rate * Double(gen.range(0.7, 1.4))))
                sylLeft = sylLen
                sylAmp = gen.chance(0.15) ? 0 : gen.range(0.5, 1)
                f1t = gen.range(350, 800) * shift
                f2t = gen.range(900, 2300) * shift
                fric = gen.chance(0.2)
                pitchMul = Double(gen.range(0.9, 1.12))
            }
            let ph = 1 - Float(sylLeft) / Float(sylLen)
            let env = pow(max(0, sin(Float.pi * ph)), 1.3) * sylAmp
            sylLeft -= 1
            f1 += (f1t - f1) * 0.002
            f2 += (f2t - f2) * 0.002
            phase += f0 * pitchMul * (1 + 0.05 * sin(2 * Double.pi * 0.7 * t)) / kSR
            phase -= floor(phase)
            let src: Float = fric ? gen.noise() * 0.6 : (Float(phase) * 2 - 1) * 0.8 + gen.noise() * 0.05
            let g1 = 2 * sin(Float.pi * f1 / sr)
            lo1 += g1 * bp1
            let hi1 = src - lo1 - q * bp1
            bp1 += g1 * hi1
            let g2 = 2 * sin(Float.pi * f2 / sr)
            lo2 += g2 * bp2
            let hi2 = src - lo2 - q * bp2
            bp2 += g2 * hi2
            let s = bp1 + 0.6 * bp2
            lp += 0.25 * (s - lp)
            let phr = Float(min(1, min(t / 0.25, (dur - t) / 0.35)))
            out[i] = lp * env * max(0, phr)
        }
        return out
    }

    static func clink(freq: Double, vel: Float) -> [Float] {
        let n = Int(1.0 * kSR)
        var out = [Float](repeating: 0, count: n)
        let ratios: [Double] = [1, 2.32, 4.17, 6.43]
        let amps: [Double] = [1, 0.6, 0.35, 0.2]
        for i in 0..<n {
            let t = Double(i) / kSR
            var s = 0.0
            for k in 0..<4 {
                s += amps[k] * sin(2 * Double.pi * freq * ratios[k] * t) * exp(-t * (7 + Double(k) * 6))
            }
            out[i] = Float(s) * vel * min(1, Float(t / 0.0008))
        }
        return out
    }

    static func knock(gen: inout MEGen, vel: Float) -> [Float] {
        let n = Int(0.09 * kSR)
        var out = [Float](repeating: 0, count: n)
        var bp: Float = 0, lo: Float = 0
        let gg = 2 * sin(Float.pi * 1900 / Float(kSR))
        for i in 0..<n {
            let t = Double(i) / kSR
            let w = gen.noise()
            lo += gg * bp
            let hi = w - lo - 0.3 * bp
            bp += gg * hi
            let tone = Float(sin(2 * Double.pi * 950 * t) * exp(-t * 90))
            out[i] = (bp * 0.25 * Float(exp(-t * 110)) + tone * 0.5) * vel
        }
        return out
    }

    static func ambience() -> StereoBuf {
        let dur = 30.0
        var b = StereoBuf(seconds: dur)
        let n = b.n
        b.l = roomNoise(seed: 11, n: n, cycles: 2)
        b.r = roomNoise(seed: 12, n: n, cycles: 3)
        var g = MEGen(seed: 555)
        // odległe rozmowy
        let phrases: [(Double, Double)] = [(1.5, 4.5), (9.0, 3.5), (13.5, 5.0), (20.0, 3.0), (24.5, 4.5)]
        for (start, len) in phrases {
            let voices = 1 + g.int(2)
            for _ in 0..<voices {
                let f0 = Double(g.range(95, 230))
                let shift: Float = f0 > 160 ? g.range(1.1, 1.3) : g.range(0.85, 1.05)
                var x = murmur(dur: len, f0: f0, shift: shift, rate: Double(g.range(3.0, 5.0)), gen: &g)
                peakScale(&x, peak: Float(g.range(0.05, 0.09)))
                b.addAt(x, time: start + Double(g.range(0, 1.5)), pan: g.range(-0.8, 0.8), gain: 1)
            }
        }
        // brzęk szkła
        for t in [6.2, 17.4, 27.1] {
            let pan = g.range(-0.7, 0.7)
            let f = Double(g.range(2400, 3800))
            b.addAt(clink(freq: f, vel: 0.06), time: t, pan: pan, gain: 1)
            if g.chance(0.6) {
                b.addAt(clink(freq: f * Double(g.range(1.1, 1.3)), vel: 0.045), time: t + 0.11, pan: pan, gain: 1)
            }
        }
        // odległe stuknięcia bil
        for t in [3.4, 11.2, 15.9, 22.3, 28.4] {
            let pan = g.range(-0.8, 0.8)
            b.addAt(knock(gen: &g, vel: g.range(0.07, 0.11)), time: t, pan: pan, gain: 1)
            if g.chance(0.4) {
                b.addAt(knock(gen: &g, vel: 0.05), time: t + Double(g.range(0.12, 0.3)), pan: pan, gain: 1)
            }
        }
        for i in 0..<n {
            b.l[i] = max(-0.95, min(0.95, b.l[i]))
            b.r[i] = max(-0.95, min(0.95, b.r[i]))
        }
        return b
    }
}

// MARK: - Nowe brzmienia (synthwave / funk / bossa / house)

extension StereoBuf {
    /// Dodaje dźwięk z echem (delay ping-pong)
    mutating func echo(_ x: [Float], time: Double, pan: Float, gain: Float, delay: Double, fb: Float, taps: Int) {
        var g = gain
        for k in 0...taps {
            let p: Float = k == 0 ? pan : (k % 2 == 1 ? -0.65 : 0.65)
            addAt(x, time: time + Double(k) * delay, pan: p, gain: g)
            g *= fb
        }
    }
    /// Sidechain: przyciszenie po każdym uderzeniu stopy (okresowe -> bezszwowe)
    mutating func duck(beat: Double, depth: Float, speed: Double) {
        for i in 0..<n {
            let t = Double(i) / kSR
            let tb = t.truncatingRemainder(dividingBy: beat)
            let g = 1 - depth * Float(exp(-tb * speed))
            l[i] *= g; r[i] *= g
        }
    }
    mutating func mix(_ o: StereoBuf, gain: Float) {
        for i in 0..<min(n, o.n) { l[i] += o.l[i] * gain; r[i] += o.r[i] * gain }
    }
}

extension Synth {
    private static func blep(_ t: Double, _ dt: Double) -> Double {
        if t < dt { let x = t / dt; return x + x - x * x - 1 }
        if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
        return 0
    }

    /// Analogowy saw/pulse (polyBLEP, kilka odstrojonych głosów) + filtr 2-biegunowy z obwiednią
    static func analog(freq: Double, dur: Double, vel: Float, attack: Double = 0.005, release: Double = 0.15,
                       detune: [Double] = [0], cutoff: Double = 2000, filterEnv: Double = 0, filterDecay: Double = 6,
                       reso: Float = 0.25, ampDecay: Double = 0, pulse: Bool = false, gen: inout MEGen) -> [Float] {
        let n = Int((dur + release) * kSR)
        var out = [Float](repeating: 0, count: n)
        var ph = detune.map { _ in Double(gen.unit()) }
        let inc = detune.map { freq * pow(2.0, $0 / 1200.0) / kSR }
        let norm = Float(1.0 / Double(detune.count).squareRoot())
        var lp1: Float = 0, lp2: Float = 0, a: Float = 0
        for i in 0..<n {
            let t = Double(i) / kSR
            if i % 16 == 0 {
                let fc = min(15000, cutoff + filterEnv * exp(-t * filterDecay))
                a = Float(1 - exp(-2 * Double.pi * fc / kSR))
            }
            var s: Float = 0
            for k in 0..<ph.count {
                let p = ph[k], dt = inc[k]
                var v = 2 * p - 1 - blep(p, dt)
                if pulse {
                    var p2 = p + 0.5; if p2 >= 1 { p2 -= 1 }
                    v -= 2 * p2 - 1 - blep(p2, dt)
                    v *= 0.5
                }
                s += Float(v)
                ph[k] = p + dt; if ph[k] >= 1 { ph[k] -= 1 }
            }
            s *= norm
            lp1 += a * (s - lp1 + reso * (lp1 - lp2))
            lp2 += a * (lp1 - lp2)
            var env = min(1, t / attack)
            if ampDecay > 0 { env *= exp(-t * ampDecay) }
            if t > dur { env *= exp(-(t - dur) / max(0.01, release) * 6) }
            out[i] = lp2 * Float(env) * vel
        }
        return out
    }

    /// Gitara nylonowa – Karplus-Strong z allpassem (strojenie ułamkowe)
    static func pluck(freq: Double, dur: Double, vel: Float, bright: Float = 0.5, gen: inout MEGen) -> [Float] {
        let n = Int((dur + 0.1) * kSR)
        var out = [Float](repeating: 0, count: n)
        let period = kSR / freq
        let N = max(2, Int(period - 0.6))
        let d = period - 0.5 - Double(N)
        let C = Float((1 - d) / (1 + d))
        var line = [Float](repeating: 0, count: N)
        var lp: Float = 0
        for k in 0..<N { lp += bright * (gen.noise() - lp); line[k] = lp }
        var mean: Float = 0
        for v in line { mean += v }
        mean /= Float(N)
        for k in 0..<N { line[k] -= mean }
        var idx = 0, prevX: Float = 0, apX: Float = 0, apY: Float = 0, body: Float = 0
        let damp: Float = 0.9965
        for i in 0..<n {
            let t = Double(i) / kSR
            let x = line[idx]
            let avg = 0.5 * (x + prevX) * damp
            prevX = x
            let y = C * avg + apX - C * apY
            apX = avg; apY = y
            line[idx] = y
            idx += 1; if idx == N { idx = 0 }
            body += 0.35 * (x - body)
            let rel: Float = t > dur ? Float(exp(-(t - dur) * 40)) : 1
            out[i] = body * rel * vel * 2.2
        }
        return out
    }

    /// Klawinet (funk) – FM z szybkim zanikiem jasności
    static func clav(freq: Double, dur: Double, vel: Float) -> [Float] {
        let n = Int((dur + 0.05) * kSR)
        var out = [Float](repeating: 0, count: n)
        let w = 2 * Double.pi * freq
        for i in 0..<n {
            let t = Double(i) / kSR
            let idx = 2.4 * exp(-t * 20) + 0.7
            let s = tanh(2.2 * sin(w * t + idx * sin(2 * w * t)))
            let att = min(1, t / 0.002)
            let rel = t > dur ? exp(-(t - dur) * 90) : 1
            out[i] = Float(s * exp(-t * 4) * att * rel) * vel
        }
        return out
    }

    /// Slap bas – jasny atak, „pop” na oktawie
    static func slap(freq: Double, dur: Double, vel: Float, pop: Bool) -> [Float] {
        let n = Int((dur + 0.06) * kSR)
        var out = [Float](repeating: 0, count: n)
        let w = 2 * Double.pi * freq
        for i in 0..<n {
            let t = Double(i) / kSR
            let idx = (pop ? 3.2 : 2.0) * exp(-t * 16) + 0.35
            var s = sin(w * t + idx * sin(w * t))
            s += 0.5 * sin(w * t)
            let att = min(1, t / 0.0015)
            let rel = t > dur ? exp(-(t - dur) * 60) : 1
            out[i] = Float(tanh(1.6 * s) * exp(-t * (pop ? 5 : 2.6)) * att * rel) * vel
        }
        return out
    }

    /// Wibrafon – sinus + alikwota, tremolo
    static func vibes(freq: Double, vel: Float) -> [Float] {
        let n = Int(2.6 * kSR)
        var out = [Float](repeating: 0, count: n)
        let w = 2 * Double.pi * freq
        for i in 0..<n {
            let t = Double(i) / kSR
            let s = sin(w * t) + 0.22 * sin(4 * w * t) * exp(-t * 7) + 0.06 * sin(10 * w * t) * exp(-t * 30)
            let trem = 0.78 + 0.22 * sin(2 * Double.pi * 5.2 * t)
            let att = min(1, t / 0.002)
            out[i] = Float(s * exp(-t * 1.4) * trem * att) * vel
        }
        return out
    }

    static func clap(gen: inout MEGen, vel: Float) -> [Float] {
        let n = Int(0.3 * kSR)
        var out = [Float](repeating: 0, count: n)
        var lp: Float = 0, prev: Float = 0
        for i in 0..<n {
            let t = Double(i) / kSR
            let w = gen.noise()
            let hp = w - prev; prev = w
            lp += 0.5 * (hp - lp)
            var env = 0.0
            for k in 0..<3 { let tk = t - Double(k) * 0.011; if tk >= 0 { env = max(env, exp(-tk * 180)) } }
            if t > 0.022 { env = max(env, 0.6 * exp(-(t - 0.022) * 16)) }
            out[i] = lp * Float(env) * vel
        }
        return out
    }

    static func shaker(gen: inout MEGen, vel: Float) -> [Float] {
        let n = Int(0.09 * kSR)
        var out = [Float](repeating: 0, count: n)
        var prev: Float = 0, lp: Float = 0
        for i in 0..<n {
            let t = Double(i) / kSR
            let w = gen.noise()
            let hp = w - prev; prev = w
            lp += 0.6 * (hp - lp)
            out[i] = lp * Float(min(1, t / 0.012) * exp(-t * 45)) * vel * 0.4
        }
        return out
    }

    static func rim(vel: Float) -> [Float] {
        let n = Int(0.06 * kSR)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / kSR
            out[i] = Float((sin(2 * Double.pi * 1650 * t) * 0.7 + sin(2 * Double.pi * 520 * t) * 0.5) * exp(-t * 110)) * vel
        }
        return out
    }

    /// Werbel z „bramkowanym pogłosem” lat 80.
    static func gatedSnare(gen: inout MEGen, vel: Float) -> [Float] {
        var out = snare(gen: &gen, vel: vel, soft: false)
        let n = Int(0.32 * kSR)
        if out.count < n { out += [Float](repeating: 0, count: n - out.count) }
        var lp: Float = 0
        for i in 0..<n {
            let t = Double(i) / kSR
            lp += 0.4 * (gen.noise() - lp)
            let env = min(1, t / 0.01) * (t < 0.22 ? 1 : exp(-(t - 0.22) * 60))
            out[i] += lp * Float(env) * vel * 0.32
        }
        return out
    }
}

private struct MNote { let step: Int; let midi: Int; let len: Int }

extension MusicRender {

    // MARK: Synthwave

    static func synthwave() -> StereoBuf {
        var g = MEGen(seed: 1984)
        let bpm = 96.0, beat = 60.0 / bpm, bars = 16, st = beat / 4
        let dur = Double(bars) * 4 * beat
        var mus = StereoBuf(seconds: dur), drm = StereoBuf(seconds: dur)
        func t(_ bar: Int, _ s: Int) -> Double { Double(bar * 16 + s) * st }
        let prog: [(Int, [Int])] = [(33, [57, 60, 64, 69]), (29, [57, 60, 65, 69]), (36, [55, 60, 64, 67]), (31, [55, 59, 62, 67])]
        for bar in 0..<bars {
            let (root, v) = prog[(bar / 2) % 4]
            if bar % 2 == 0 {   // pad na 2 takty
                for (k, m) in v.enumerated() {
                    let x = Synth.analog(freq: mtof(m), dur: 8 * beat - 0.3, vel: 0.22, attack: 0.5, release: 0.9,
                                         detune: [-14, -5, 6, 13], cutoff: 1300, filterEnv: 900, filterDecay: 0.8, gen: &g)
                    mus.addAt(x, time: t(bar, 0), pan: -0.6 + Float(k) * 0.4, gain: 0.5)
                }
            }
            for e in 0..<8 {    // bas oktawowy ósemkami
                let m = root + (e % 2 == 1 ? 12 : 0) + 12
                let x = Synth.analog(freq: mtof(m), dur: 0.42 * beat, vel: 0.9, release: 0.05, detune: [-4, 4],
                                     cutoff: 260, filterEnv: 1300, filterDecay: 16, reso: 0.35, gen: &g)
                mus.addAt(x, time: t(bar, e * 2), pan: 0, gain: 0.5)
            }
            let ext = v + v.map { $0 + 12 }   // arpeggio 16-tkami
            let pat = [0, 1, 2, 3, 4, 3, 2, 1]
            for s in 0..<16 {
                let m = ext[pat[s % 8]]
                let x = Synth.analog(freq: mtof(m), dur: 0.22 * beat, vel: 0.32, release: 0.06, cutoff: 900,
                                     filterEnv: 2600, filterDecay: 14, ampDecay: 5, pulse: true, gen: &g)
                mus.echo(x, time: t(bar, s), pan: 0.25, gain: s % 4 == 0 ? 0.5 : 0.38, delay: 0.75 * beat, fb: 0.32, taps: 2)
            }
            // perkusja
            for s in [0, 8] { drm.addAt(Synth.kick(vel: 1, fat: false), time: t(bar, s), pan: 0, gain: 0.85) }
            if bar % 4 == 3 { drm.addAt(Synth.kick(vel: 0.8, fat: false), time: t(bar, 14), pan: 0, gain: 0.7) }
            for s in [4, 12] { drm.addAt(Synth.gatedSnare(gen: &g, vel: 0.8), time: t(bar, s), pan: 0, gain: 0.5) }
            for s in stride(from: 0, to: 16, by: 2) {
                drm.addAt(Synth.hat(gen: &g, vel: s % 4 == 2 ? 0.7 : 0.4, open: false), time: t(bar, s), pan: 0.3, gain: 0.35)
            }
        }
        // melodia prowadząca w drugiej połowie (takty 8–15)
        let lead: [MNote] = [
            MNote(step: 0, midi: 76, len: 6), MNote(step: 6, midi: 77, len: 2), MNote(step: 8, midi: 76, len: 4), MNote(step: 12, midi: 74, len: 4),
            MNote(step: 16, midi: 72, len: 12), MNote(step: 28, midi: 71, len: 4),
            MNote(step: 32, midi: 72, len: 6), MNote(step: 38, midi: 74, len: 2), MNote(step: 40, midi: 72, len: 4), MNote(step: 44, midi: 69, len: 4),
            MNote(step: 48, midi: 69, len: 14),
            MNote(step: 64, midi: 67, len: 6), MNote(step: 70, midi: 72, len: 2), MNote(step: 72, midi: 76, len: 8), MNote(step: 80, midi: 79, len: 8),
            MNote(step: 88, midi: 76, len: 8),
            MNote(step: 96, midi: 74, len: 6), MNote(step: 102, midi: 76, len: 2), MNote(step: 104, midi: 74, len: 4), MNote(step: 108, midi: 71, len: 4),
            MNote(step: 112, midi: 71, len: 8), MNote(step: 120, midi: 74, len: 4), MNote(step: 124, midi: 72, len: 4)
        ]
        for nt in lead {
            let x = Synth.analog(freq: mtof(nt.midi), dur: Double(nt.len) * st * 0.92, vel: 0.3, attack: 0.02, release: 0.25,
                                 detune: [-7, 0, 7], cutoff: 1800, filterEnv: 1800, filterDecay: 3, gen: &g)
            mus.echo(x, time: t(8, nt.step), pan: 0, gain: 0.55, delay: 0.75 * beat, fb: 0.38, taps: 3)
        }
        mus.duck(beat: beat, depth: 0.35, speed: 9)
        mus.mix(drm, gain: 1)
        Synth.lowpass(&mus.l, cutoff: 9000); Synth.lowpass(&mus.r, cutoff: 9000)
        Synth.normalize(&mus, peak: 0.42)
        return mus
    }

    // MARK: Funk

    static func funk() -> StereoBuf {
        var g = MEGen(seed: 1973)
        let bpm = 102.0, beat = 60.0 / bpm, bars = 16, st = beat / 4
        let dur = Double(bars) * 4 * beat
        var b = StereoBuf(seconds: dur)
        func t(_ bar: Int, _ s: Int) -> Double { Double(bar * 16 + s) * st + (s % 2 == 1 ? st * 0.09 : 0) }
        // (bas, klawinet, dęciaki)
        let em = (40, [55, 62, 66], [64, 67, 71, 74])
        let a13 = (45, [55, 61, 66], [61, 66, 67, 71])
        let bassPat: [(Int, Int, Bool, Int)] = [(0, 0, false, 2), (3, 0, false, 1), (4, 12, true, 1), (6, 10, false, 1), (7, 12, true, 1),
                                                (10, 0, false, 2), (12, 7, false, 1), (14, 12, true, 1), (15, 10, false, 1)]
        for bar in 0..<bars {
            let ch = (bar % 4) < 2 ? em : a13
            for (s, iv, pop, len) in bassPat {
                if bar % 4 == 3 && s >= 12 { continue }
                let x = Synth.slap(freq: mtof(ch.0 + iv), dur: Double(len) * st * 0.85, vel: pop ? 0.75 : 0.95, pop: pop)
                b.addAt(x, time: t(bar, s), pan: 0, gain: 0.5)
            }
            if bar % 4 == 3 {   // przejście basu
                for (k, m) in [52, 50, 47, 45].enumerated() {
                    b.addAt(Synth.slap(freq: mtof(m - 12 + (bar % 8 == 7 ? 0 : 0)), dur: st * 0.8, vel: 0.85, pop: false), time: t(bar, 12 + k), pan: 0, gain: 0.5)
                }
            }
            // klawinet: akcenty + „chicken scratch”
            let hits: Set<Int> = bar % 2 == 0 ? [2, 5, 7, 10, 13, 15] : [2, 5, 8, 10, 13]
            for s in 0..<16 {
                let on = hits.contains(s)
                if !on && s % 2 == 0 { continue }
                for (k, m) in ch.1.enumerated() {
                    let x = Synth.clav(freq: mtof(m), dur: on ? st * 0.7 : 0.025, vel: on ? 0.42 : 0.12)
                    b.addAt(x, time: t(bar, s) + Double(k) * 0.003, pan: -0.45, gain: 0.5)
                }
            }
            // sekcja dęta: stab na końcu frazy
            let stabs: [(Int, Double)] = bar % 4 == 1 ? [(14, 1.5)] : (bar % 4 == 3 ? [(6, 1.5), (8, 2.5)] : [])
            for (s, len) in stabs {
                for (k, m) in ch.2.enumerated() {
                    let x = Synth.analog(freq: mtof(m), dur: len * st, vel: 0.24, attack: 0.012, release: 0.12, detune: [-9, 0, 8],
                                         cutoff: 700, filterEnv: 3800, filterDecay: 9, gen: &g)
                    b.addAt(x, time: t(bar, s), pan: 0.5 - Float(k) * 0.25, gain: 0.55)
                }
            }
            // perkusja
            let kicks = bar % 2 == 0 ? [0, 7, 10] : [0, 3, 10, 11]
            for s in kicks { b.addAt(Synth.kick(vel: s == 0 ? 1 : 0.8, fat: false), time: t(bar, s), pan: 0, gain: 0.8) }
            for s in [4, 12] { b.addAt(Synth.snare(gen: &g, vel: 0.85, soft: false), time: t(bar, s), pan: 0.05, gain: 0.5) }
            for s in [6, 9, 15] where g.chance(0.7) {
                b.addAt(Synth.snare(gen: &g, vel: 0.2, soft: true), time: t(bar, s), pan: 0.05, gain: 0.4)
            }
            for s in 0..<16 {
                let open = s == 14 && bar % 2 == 1
                let v: Float = (s % 4 == 0 ? 0.6 : (s % 2 == 0 ? 0.45 : 0.28)) * g.range(0.85, 1.1)
                b.addAt(Synth.hat(gen: &g, vel: v, open: open), time: t(bar, s), pan: 0.3, gain: 0.35)
            }
        }
        // Rhodes – długie akordy w drugiej połowie dla oddechu
        for bar in stride(from: 8, to: bars, by: 2) {
            let v = (bar % 4) < 2 ? [62, 66, 69, 71] : [61, 66, 67, 71]
            for (k, m) in v.enumerated() {
                b.addAt(Synth.rhodes(freq: mtof(m), dur: 6 * beat, vel: 0.35, bright: 0.6), time: t(bar, 0) + Double(k) * 0.01, pan: 0.4, gain: 0.35)
            }
        }
        Synth.normalize(&b, peak: 0.46)
        return b
    }

    // MARK: Bossa lounge

    static func bossa() -> StereoBuf {
        var g = MEGen(seed: 1962)
        let bpm = 138.0, beat = 60.0 / bpm, bars = 16, e8 = beat / 2
        let dur = Double(bars) * 4 * beat
        var b = StereoBuf(seconds: dur)
        func t(_ bar: Int, _ e: Int) -> Double { Double(bar * 8 + e) * e8 }
        // (pryma, kwinta, akord)
        let prog: [(Int, Int, [Int])] = [
            (38, 45, [53, 57, 60, 64]), (43, 38, [53, 57, 59, 64]), (36, 43, [52, 55, 59, 62]), (36, 43, [52, 55, 59, 62]),
            (41, 36, [52, 57, 60, 64]), (46, 41, [50, 56, 60, 65]), (40, 47, [50, 55, 59, 62]), (45, 40, [49, 55, 58, 61])
        ]
        for bar in 0..<bars {
            let (r, f, v) = prog[bar % 8]
            // gitara: kciuk na 1 i 3
            for (e, m) in [(0, r), (4, f)] {
                b.addAt(Synth.pluck(freq: mtof(m), dur: 1.6 * beat, vel: 0.5, bright: 0.35, gen: &g), time: t(bar, e), pan: -0.1, gain: 0.55)
            }
            // akordy w rytmie bossy
            let pat = bar % 2 == 0 ? [0, 2, 5, 7] : [1, 4, 6]
            for e in pat {
                for (k, m) in v.enumerated() {
                    let x = Synth.pluck(freq: mtof(m), dur: 0.85 * beat, vel: 0.3 * g.range(0.85, 1.05), bright: 0.45, gen: &g)
                    b.addAt(x, time: t(bar, e) + Double(k) * 0.007, pan: -0.25 + Float(k) * 0.05, gain: 0.5)
                }
            }
            // kontrabas
            for (e, m, l) in [(0, r, 1.4), (3, r, 0.45), (4, f, 1.4), (7, f, 0.45)] {
                b.addAt(Synth.bass(freq: mtof(m - 12 + (m < 40 ? 12 : 0)), dur: l * beat, vel: 0.85, pluck: true), time: t(bar, e), pan: 0.05, gain: 0.55)
            }
            // perkusja: rimshot (clave), shaker, miękka stopa
            for e in (bar % 2 == 0 ? [0, 3, 6] : [2, 5]) {
                b.addAt(Synth.rim(vel: 0.5), time: t(bar, e), pan: 0.35, gain: 0.3)
            }
            for s in 0..<16 {
                b.addAt(Synth.shaker(gen: &g, vel: s % 2 == 0 ? 0.55 : 0.85), time: Double(bar * 16 + s) * e8 / 2, pan: 0.45, gain: 0.35)
            }
            for (e, v) in [(0, Float(0.7)), (3, 0.35), (4, 0.6), (7, 0.35)] {
                b.addAt(Synth.kick(vel: v, fat: true), time: t(bar, e), pan: 0, gain: 0.45)
            }
            if bar % 4 == 0 { b.addAt(Synth.brush(gen: &g, dur: 4 * beat, vel: 0.5, swell: true), time: t(bar, 0), pan: -0.2, gain: 0.5) }
        }
        // wibrafon: delikatne frazy w 1. połowie, temat w 2.
        let intro: [MNote] = [MNote(step: 14, midi: 72, len: 2), MNote(step: 22, midi: 71, len: 2), MNote(step: 30, midi: 69, len: 2),
                             MNote(step: 46, midi: 68, len: 2), MNote(step: 52, midi: 67, len: 2), MNote(step: 54, midi: 69, len: 2)]
        let theme: [MNote] = [
            MNote(step: 0, midi: 69, len: 3), MNote(step: 3, midi: 72, len: 3), MNote(step: 6, midi: 76, len: 2),
            MNote(step: 8, midi: 77, len: 4), MNote(step: 12, midi: 76, len: 2), MNote(step: 14, midi: 74, len: 2),
            MNote(step: 16, midi: 71, len: 6), MNote(step: 22, midi: 72, len: 2), MNote(step: 24, midi: 74, len: 4), MNote(step: 28, midi: 76, len: 4),
            MNote(step: 32, midi: 76, len: 3), MNote(step: 35, midi: 72, len: 3), MNote(step: 38, midi: 69, len: 2),
            MNote(step: 40, midi: 74, len: 4), MNote(step: 44, midi: 72, len: 2), MNote(step: 46, midi: 68, len: 2),
            MNote(step: 48, midi: 67, len: 3), MNote(step: 51, midi: 71, len: 3), MNote(step: 54, midi: 74, len: 2),
            MNote(step: 56, midi: 73, len: 4), MNote(step: 60, midi: 70, len: 2), MNote(step: 62, midi: 69, len: 2)
        ]
        for nt in intro { b.addAt(Synth.vibes(freq: mtof(nt.midi), vel: 0.35), time: Double(nt.step) * e8, pan: 0.3, gain: 0.5) }
        for nt in theme { b.addAt(Synth.vibes(freq: mtof(nt.midi), vel: 0.5), time: t(8, nt.step), pan: 0.25, gain: 0.5) }
        Synth.lowpass(&b.l, cutoff: 8000); Synth.lowpass(&b.r, cutoff: 8000)
        Synth.normalize(&b, peak: 0.48)
        return b
    }

    // MARK: Deep house

    static func house() -> StereoBuf {
        var g = MEGen(seed: 1987)
        let bpm = 120.0, beat = 60.0 / bpm, bars = 16, st = beat / 4
        let dur = Double(bars) * 4 * beat
        var mus = StereoBuf(seconds: dur), drm = StereoBuf(seconds: dur)
        func t(_ bar: Int, _ s: Int) -> Double { Double(bar * 16 + s) * st + (s % 2 == 1 ? st * 0.07 : 0) }
        let prog: [(Int, [Int])] = [(45, [55, 59, 60, 64]), (38, [53, 57, 60, 64]), (41, [52, 55, 57, 60]), (40, [50, 54, 55, 59])]
        let pent = [69, 72, 74, 76, 79, 81]
        for bar in 0..<bars {
            let (root, v) = prog[(bar / 2) % 4]
            if bar % 2 == 0 {
                for (k, m) in v.enumerated() {
                    let x = Synth.analog(freq: mtof(m + 12), dur: 8 * beat - 0.4, vel: 0.12, attack: 1.2, release: 1.2,
                                         detune: [-10, 0, 10], cutoff: 1100, gen: &g)
                    mus.addAt(x, time: t(bar, 0), pan: -0.5 + Float(k) * 0.33, gain: 0.5)
                }
            }
            // akordy (organowy Rhodes) synkopowane z echem
            for s in (bar % 2 == 0 ? [3, 6, 11, 14] : [3, 6, 10]) {
                for (k, m) in v.enumerated() {
                    let x = Synth.rhodes(freq: mtof(m), dur: 0.35 * beat, vel: 0.45, bright: 0.55)
                    mus.echo(x, time: t(bar, s) + Double(k) * 0.004, pan: -0.15, gain: 0.45, delay: 0.75 * beat, fb: 0.28, taps: 2)
                }
            }
            // bas
            for (s, iv) in [(2, 0), (6, 0), (10, 12), (13, 0)] {
                mus.addAt(Synth.bass(freq: mtof(root - 12 + iv + 12), dur: 0.4 * beat, vel: 0.95, pluck: false), time: t(bar, s), pan: 0, gain: 0.65)
            }
            // dzwoneczki w 2. połowie
            if bar >= 8 {
                for s in [0, 6, 10] where g.chance(0.55) {
                    mus.echo(Synth.bell(freq: mtof(pent[g.int(pent.count)]), vel: 0.3, decay: 0.35), time: t(bar, s),
                             pan: 0.3, gain: 0.35, delay: 0.75 * beat, fb: 0.4, taps: 3)
                }
            }
            // perkusja: four-on-the-floor
            for s in [0, 4, 8, 12] { drm.addAt(Synth.kick(vel: 1, fat: true), time: t(bar, s), pan: 0, gain: 0.85) }
            for s in [4, 12] { drm.addAt(Synth.clap(gen: &g, vel: 0.7), time: t(bar, s) + 0.003, pan: 0.05, gain: 0.45) }
            for s in [2, 6, 10, 14] { drm.addAt(Synth.hat(gen: &g, vel: 0.6, open: true), time: t(bar, s), pan: 0.25, gain: 0.3) }
            for s in 0..<16 where s % 2 == 1 || bar % 2 == 1 {
                drm.addAt(Synth.shaker(gen: &g, vel: s % 2 == 1 ? 0.7 : 0.4), time: t(bar, s), pan: -0.35, gain: 0.35)
            }
        }
        mus.duck(beat: beat, depth: 0.45, speed: 8)
        mus.mix(drm, gain: 1)
        Synth.normalize(&mus, peak: 0.3)
        return mus
    }
}
