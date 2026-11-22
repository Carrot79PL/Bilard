import Cocoa
import CoreImage

/// definicje panoram HDRI (Assets/<id>/<id>_2k.hdr, Poly Haven CC0) i własny plik gracza
struct HDRIDef: Identifiable, Equatable {
    let id: String, name: String
    static let all: [HDRIDef] = [
        HDRIDef(id: "billiard_hall", name: "Sala bilardowa"),
        HDRIDef(id: "abandoned_games_room_01", name: "Sala gier"),
        HDRIDef(id: "ballroom", name: "Sala balowa"),
        HDRIDef(id: "bush_restaurant", name: "Restauracja"),
        HDRIDef(id: "brown_photostudio_02", name: "Studio"),
        HDRIDef(id: "anniversary_lounge", name: "Lounge"),
    ]
    static var customDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bilard", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static var customURL: URL? {
        for e in ["hdr", "exr"] { let u = customDir.appendingPathComponent("custom_hdri.\(e)"); if FileManager.default.fileExists(atPath: u.path) { return u } }
        return nil
    }
    static var hasCustom: Bool { customURL != nil }

    /// mnożnik natężenia światła z panoramy: wyrównuje średnią jasność do sali bilardowej (0,68)
    static func envMul(id: String, url: URL) -> Double {
        let known: [String: Double] = ["billiard_hall": 1, "abandoned_games_room_01": 1.2, "ballroom": 1.4, "bush_restaurant": 1.6,
                                       "brown_photostudio_02": 0.95, "anniversary_lounge": 1.05]
        if let k = known[id] { return k }
        guard var img = CIImage(contentsOf: url) else { return 1 }
        img = img.applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0), "inputMaxComponents": CIVector(x: 30, y: 30, z: 30, w: 1)])
        let avg = img.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: img.extent)])
        var px = [Float](repeating: 0, count: 4)
        CIContext().render(avg, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.linearSRGB))
        let lum = Double(0.2126 * px[0] + 0.7152 * px[1] + 0.0722 * px[2])
        return lum.isFinite && lum > 0.01 ? max(0.5, min(2.0, 0.678 / lum)) : 1
    }

    /// wybór własnego pliku .hdr / .exr (kopiowany do Application Support)
    static func pickCustom(done: @escaping (Bool) -> Void) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.init(filenameExtension: "hdr"), .init(filenameExtension: "exr")].compactMap { $0 }
        p.allowsMultipleSelection = false
        p.message = "Wybierz panoramę HDRI (równoprostokątną, .hdr lub .exr)"
        guard p.runModal() == .OK, let src = p.url else { done(false); return }
        let ext = src.pathExtension.lowercased() == "exr" ? "exr" : "hdr"
        guard CIImage(contentsOf: src) != nil else { done(false); return }
        for e in ["hdr", "exr"] { try? FileManager.default.removeItem(at: customDir.appendingPathComponent("custom_hdri.\(e)")) }
        do { try FileManager.default.copyItem(at: src, to: customDir.appendingPathComponent("custom_hdri.\(ext)")); done(true) } catch { done(false) }
    }
}

/// tło z panoramy: rozmycie, jasność, kolor mgły dopasowany do horyzontu
enum HDRIBackground {
    private static var cache: (key: String, img: CGImage, fog: NSColor)?
    private static let ctx = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB) as Any])

    static func make(url: URL, blur: Double, brightness: Double) -> (CGImage, NSColor)? {
        let key = "\(url.path)|\(blur)|\(brightness)"
        if let c = cache, c.key == key { return (c.img, c.fog) }
        guard var img = CIImage(contentsOf: url) else { return nil }
        let full = img.extent
        let scale = blur > 0.01 ? 0.5 : 1.0                               // rozmyte: mniejsza rozdzielczość = szybciej
        if scale < 1 { img = img.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        let ext = img.extent
        if blur > 0.01 {
            img = img.clampedToExtent().applyingGaussianBlur(sigma: blur * 40 * scale).cropped(to: ext)
        }
        let ev = log2(max(0.02, brightness)) - 1.2                         // bazowo ciemniej: tło ma nie przyćmiewać stołu
        img = img.applyingFilter("CIExposureAdjust", parameters: ["inputEV": ev])
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = ctx.createCGImage(img, from: ext, format: .RGBA8, colorSpace: sRGB) else { return nil }
        // średni kolor pasa wokół horyzontu → kolor mgły (podłoga zlewa się z tłem)
        let band = img.cropped(to: CGRect(x: ext.minX, y: ext.minY + ext.height * 0.40, width: ext.width, height: ext.height * 0.16))
        let avg = band.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: band.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        ctx.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: sRGB)
        let fog = NSColor(srgbRed: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
        _ = full
        cache = (key, cg, fog)
        return (cg, fog)
    }
}
