import Cocoa
import SceneKit
import SpriteKit
import SwiftUI

// MARK: - Intro BLUEROOT na SKView, potem gra

final class IntroView: SKView {
    var onDone: (() -> Void)?
    var finished = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with e: NSEvent) { finish() }
    override func keyDown(with e: NSEvent) { finish() }
    func finish() {
        guard !finished else { return }
        finished = true
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.6; self.animator().alphaValue = 0 }) { [weak self] in
            self?.removeFromSuperview()
            self?.onDone?()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var controller: GameSceneController!
    var container: NSView!
    let env = ProcessInfo.processInfo.environment

    func applicationDidFinishLaunching(_ n: Notification) {
        let testMode = env["BILARD_SHOT"] != nil || env["BILARD_AUTOSTART"] != nil
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Bilard 8-Ball"
        window.backgroundColor = nsc(0x0B0A0C)
        window.center()
        window.collectionBehavior = [.fullScreenPrimary]

        container = NSView(frame: frame)
        container.autoresizingMask = [.width, .height]
        window.contentView = container

        controller = GameSceneController(frame: frame)
        let scn = controller.scnView
        scn.frame = container.bounds
        scn.autoresizingMask = [.width, .height]
        container.addSubview(scn)

        let hud = HUDHostingView(model: controller.model)
        hud.frame = container.bounds
        hud.autoresizingMask = [.width, .height]
        if env["BILARD_NOHUD"] == nil { container.addSubview(hud) }
        applyScale()

        // synteza tekstur 4K w tle (równolegle), potem budowa sceny
        let model = controller.model
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pack: TexturePack
            if let cached = TexturePack.loadCached() { pack = cached }
            else {
                pack = TextureFactory.generate { p, text in
                    DispatchQueue.main.async { model.loading = min(0.99, p); model.loadText = text }
                }
                pack.saveCache()
            }
            DispatchQueue.main.async {
                self?.controller.buildScene(pack)
                model.loading = 1
            }
        }

        buildMenu()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(scn)
        NSApp.activate(ignoringOtherApps: true)
        controller.demoPending = !testMode || env["BILARD_DEMO"] != nil
        controller.start()

        if testMode {
            window.setContentSize(NSSize(width: Double(env["BILARD_W"] ?? "") ?? 1280, height: Double(env["BILARD_H"] ?? "") ?? 800))
            if env["BILARD_FS"] != nil { window.toggleFullScreen(nil) }
            return
        }
        window.toggleFullScreen(nil)
        showIntro()
    }

    func applyScale() {
        // pełna rozdzielczość Retina / 4K
        controller.applyRenderScale()
    }

    func showIntro() {
        let sk = IntroView(frame: container.bounds)
        sk.autoresizingMask = [.width, .height]
        sk.wantsLayer = true
        container.addSubview(sk)
        let scene = SKScene(size: container.bounds.size)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = nsc(BluerootIntro.bg)
        let node = BluerootIntro.node(size: container.bounds.size, scale: window.backingScaleFactor)
        scene.addChild(node)
        sk.presentScene(scene)
        sk.onDone = { [weak self] in self?.window.makeFirstResponder(self?.controller.scnView) }
        node.run(.sequence([.wait(forDuration: BluerootIntro.hold), .run { DispatchQueue.main.async { sk.finish() } }]))
        window.makeFirstResponder(sk)
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Zakończ Bilard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let v = NSMenu(title: "Widok")
        v.addItem(withTitle: "Pełny ekran", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        viewItem.submenu = v
        NSApp.mainMenu = main
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
