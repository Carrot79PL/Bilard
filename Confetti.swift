import SceneKit
import Cocoa

// MARK: - Konfetti po wygranej: płaskie kartki opadają z kołysaniem i układają się na suknie stołu

struct ConfettiPiece {
    let node: SCNNode
    let x0: Double, z0: Double, startY: Double
    let delay: Double, vy: Double
    let swayAmp: Double, swayF: Double, phase: Double
    let tiltF: Double, tiltAmp: Double
    let yaw0: Double, spin: Double
    let layer: Double
    var state = 0                       // 0 czeka, 1 spada, 2 układa się, 3 leży
    var y = 0.0, landT = 0.0, landX = 0.0, landZ = 0.0, landTilt = 0.0, landYaw = 0.0
}

extension GameSceneController {
    func startConfetti() {
        stopConfetti()
        let sc = Phys.halfL / 1.27
        let root = SCNNode()
        let cols: [NSColor] = [NSColor(red: 1, green: 0.30, blue: 0.38, alpha: 1), NSColor(red: 1, green: 0.80, blue: 0.18, alpha: 1),
                               NSColor(red: 0.25, green: 0.82, blue: 0.50, alpha: 1), NSColor(red: 0.30, green: 0.58, blue: 1, alpha: 1),
                               NSColor(red: 0.75, green: 0.42, blue: 1, alpha: 1), NSColor(red: 1, green: 0.55, blue: 0.15, alpha: 1), .white]
        let mats: [SCNMaterial] = cols.map { c in
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = c; m.isDoubleSided = true
            return m
        }
        var g = SeededGen(s: UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFFFF)
        func r() -> Double { Double(g.next() % 100000) / 100000 }
        var pieces: [ConfettiPiece] = []
        let ex = Phys.halfL - 0.07, ez = Phys.halfW - 0.07
        for i in 0..<240 {
            let w = 0.011 + r() * 0.006, h = 0.007 + r() * 0.005
            let plane = SCNPlane(width: CGFloat(w), height: CGFloat(h))
            plane.materials = [mats[i % mats.count]]
            let n = SCNNode(geometry: plane)
            n.castsShadow = false
            n.isHidden = true
            root.addChildNode(n)
            pieces.append(ConfettiPiece(node: n, x0: (r() * 2 - 1) * ex, z0: (r() * 2 - 1) * ez, startY: (1.5 + r() * 0.6) * sc,
                                        delay: r() * 3.0, vy: 0.55 + r() * 0.4, swayAmp: 0.02 + r() * 0.05, swayF: 1.5 + r() * 2.5, phase: r() * 6.28,
                                        tiltF: 3 + r() * 5, tiltAmp: 0.6 + r() * 0.8, yaw0: r() * 6.28, spin: (r() - 0.5) * 6, layer: r() * 0.0006))
        }
        rig.addChildNode(root)
        confettiNode = root
        confettiPieces = pieces
        confettiT = 0
    }

    func stopConfetti() {
        confettiNode?.removeFromParentNode()
        confettiNode = nil
        confettiPieces.removeAll()
    }

    /// co klatkę: spadanie z kołysaniem i wyhamowaniem, potem płaskie ułożenie na suknie
    func updateConfetti(_ dt: Double) {
        guard confettiNode != nil, !confettiPieces.isEmpty else { return }
        confettiT += dt
        let t = confettiT
        let restY = (table.decals.first?.position.y ?? 0.0014) + 0.0008
        let ex = Phys.halfL - 0.05, ez = Phys.halfW - 0.05
        for i in confettiPieces.indices {
            var p = confettiPieces[i]
            switch p.state {
            case 0:
                if t >= p.delay { p.state = 1; p.y = p.startY; p.node.isHidden = false }
            case 1:
                let dtf = t - p.delay
                p.y -= p.vy * dt
                let x = max(-ex, min(ex, p.x0 + sin(dtf * p.swayF + p.phase) * p.swayAmp))
                let z = max(-ez, min(ez, p.z0 + cos(dtf * p.swayF * 0.8 + p.phase) * p.swayAmp))
                let tiltX = sin(dtf * p.tiltF + p.phase) * p.tiltAmp, tiltZ = cos(dtf * p.tiltF * 0.7 + p.phase) * p.tiltAmp
                p.node.position = SCNVector3(x, p.y, z)
                p.node.eulerAngles = SCNVector3(-.pi / 2 + tiltX, p.yaw0 + dtf * p.spin, tiltZ)
                p.landX = x; p.landZ = z; p.landTilt = tiltX; p.landYaw = p.yaw0 + dtf * p.spin
                if p.y <= restY + p.layer { p.state = 2; p.landT = 0 }
            case 2:
                p.landT += dt
                let k = min(1, p.landT / 0.35), e = 1 - (1 - k) * (1 - k)
                p.node.position = SCNVector3(p.landX, restY + p.layer, p.landZ)
                p.node.eulerAngles = SCNVector3(-.pi / 2 + p.landTilt * (1 - e), p.landYaw, 0)
                if k >= 1 { p.state = 3 }
            default:
                p.node.position.y = CGFloat(restY + p.layer)       // leży na suknie (podąża za nakładkami przy widoku z góry)
            }
            confettiPieces[i] = p
        }
    }
}

extension GameSceneController {
    /// kolejka powiadomień: jedno na raz, każde ~3,6 s
    func enqueueToast(_ t: ToastItem) {
        toastQueue.append(t)
        if !toastBusy { nextToast() }
    }
    func nextToast() {
        guard !toastQueue.isEmpty else { toastBusy = false; model.toast = nil; return }
        toastBusy = true
        model.toast = toastQueue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) { [weak self] in self?.nextToast() }
    }
}
