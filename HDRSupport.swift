import Cocoa
import QuartzCore

/// wyjście HDR (EDR): warstwa Metal w formacie 16-bit float z rozszerzoną przestrzenią barw
enum HDRSupport {
    static var headroom: Double { Double(NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) }
    static var available: Bool { headroom > 1.05 }

    static func apply(_ on: Bool, to view: NSView) {
        guard let layer = view.layer as? CAMetalLayer else {
            if ProcessInfo.processInfo.environment["BILARD_HDRDBG"] != nil { NSLog("HDR: warstwa nie jest CAMetalLayer (%@)", String(describing: type(of: view.layer))) }
            return
        }
        let want = on && available
        layer.wantsExtendedDynamicRangeContent = want
        layer.pixelFormat = want ? .rgba16Float : .bgra8Unorm
        layer.colorspace = CGColorSpace(name: want ? CGColorSpace.extendedLinearDisplayP3 : CGColorSpace.displayP3)
        if ProcessInfo.processInfo.environment["BILARD_HDRDBG"] != nil { NSLog("HDR: on=%d available=%d headroom=%.2f format=%lu", want ? 1 : 0, available ? 1 : 0, headroom, layer.pixelFormat.rawValue) }
    }
}
