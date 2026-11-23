import SwiftUI
import AppKit
import SceneKit

// MARK: - HUD (SwiftUI nałożony na widok 3D) – styl transmisji sportowej

struct RectKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    func interactive() -> some View {
        background(GeometryReader { g in Color.clear.preference(key: RectKey.self, value: [g.frame(in: .named("hud"))]) })
    }
}

// MARK: - Motyw

enum UI {
    static let accent = Color(red: 0.95, green: 0.73, blue: 0.32)      // stonowany bursztyn
    /// menu w stylu nadruku na suknie: biały zamiast bursztynu
    static var menuOn: Bool { Settings.shared.clothMenu }
    static var menuAccent: Color { menuOn ? .white : accent }
    static let foul   = Color(red: 0.92, green: 0.34, blue: 0.31)
    static let good   = Color(red: 0.38, green: 0.80, blue: 0.58)
    static let info   = Color(red: 0.45, green: 0.68, blue: 0.95)
    static let text   = Color.white
    static let dim    = Color.white.opacity(0.62)
    static let faint  = Color.white.opacity(0.34)
    static let line   = Color.white.opacity(0.10)
    static let ink    = Color(red: 0.06, green: 0.07, blue: 0.08)

    static func label(_ s: CGFloat = 10) -> Font { .system(size: s, weight: .semibold) }
    static func title(_ s: CGFloat) -> Font { .system(size: s, weight: .bold) }
    static func number(_ s: CGFloat) -> Font { .system(size: s, weight: .bold, design: .rounded).monospacedDigit() }
}

struct Panel: ViewModifier {
    var radius: CGFloat = 14
    var tint: Double = 0.30
    var glass: Double = 1
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial).opacity(glass)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black.opacity(tint)))
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}

extension View {
    func panel(_ radius: CGFloat = 14, tint: Double = 0.30, glass: Double = 1) -> some View { modifier(Panel(radius: radius, tint: tint, glass: glass)) }
    @ViewBuilder func panelIf(_ on: Bool, _ radius: CGFloat = 14, tint: Double = 0.30) -> some View { if on { modifier(Panel(radius: radius, tint: tint)) } else { self.shadow(color: .black.opacity(0.55), radius: 5) } }
}

/// Nagłówek sekcji: małe wersaliki z rozstrzeleniem
struct Caps: View {
    let text: String
    var color: Color = UI.faint
    var size: CGFloat = 9.5
    init(_ t: String, color: Color = UI.faint, size: CGFloat = 9.5) { text = t; self.color = color; self.size = size }
    var body: some View { Text(text.uppercased()).font(UI.label(size)).tracking(1.4).foregroundColor(color) }
}

struct KeyCap: View {
    let k: String
    var body: some View {
        Text(k).font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundColor(UI.dim)
            .padding(.horizontal, 5).frame(minWidth: 17, minHeight: 16)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8))
    }
}

// MARK: - Bile

func ballColor(_ n: Int) -> Color {
    let h = Tex.ballColors[n <= 8 ? n : n - 8]
    return Color(red: Double((h >> 16) & 255) / 255, green: Double((h >> 8) & 255) / 255, blue: Double(h & 255) / 255)
}

struct BallChip: View {
    let n: Int
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Circle().fill(n >= 9 ? Color(white: 0.95) : ballColor(n))
            if n >= 9 { Rectangle().fill(ballColor(n)).frame(width: size, height: size * 0.52) }
            Circle().fill(Color(white: 0.97)).frame(width: size * 0.5, height: size * 0.5)
            Text("\(n)").font(.system(size: size * 0.32, weight: .heavy, design: .rounded)).foregroundColor(.black.opacity(0.85))
            // cieniowanie kuli i odblask
            Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.42)], center: .init(x: 0.38, y: 0.32), startRadius: size * 0.18, endRadius: size * 0.62))
            Ellipse().fill(Color.white.opacity(0.55)).frame(width: size * 0.26, height: size * 0.16).offset(x: -size * 0.16, y: -size * 0.24).blur(radius: size * 0.03)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
    }
}

/// puste miejsce po wbitej bili
struct BallSlot: View {
    var size: CGFloat = 16
    var body: some View {
        Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            .background(Circle().fill(Color.black.opacity(0.25)))
            .frame(width: size, height: size)
    }
}

// MARK: - Tablica wyników

struct PlayerPanel: View {
    @ObservedObject var m: GameModel
    let idx: Int
    var mirrored: Bool { idx == 1 }

    var active: Bool { m.current == idx && m.phase != .menu && m.phase != .gameOver }
    var score: Int { m.groups[idx].map { g in m.pocketed.filter { g.range.contains($0) }.count } ?? 0 }
    var onEight: Bool { m.groups[idx].map { g in g.range.allSatisfy { m.pocketed.contains($0) } } ?? false }

    var body: some View {
        VStack(alignment: mirrored ? .trailing : .leading, spacing: 7) {
            HStack(spacing: 8) {
                if mirrored { groupTag; Spacer(minLength: 6); nameBlock } else { nameBlock; Spacer(minLength: 6); groupTag }
            }
            HStack(spacing: 4) {
                if mirrored { eightSlot }
                balls
                if !mirrored { eightSlot }
            }
            .frame(maxWidth: .infinity, alignment: mirrored ? .trailing : .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(width: 292)
        .background(
            ZStack(alignment: .top) {
                if active {
                    LinearGradient(colors: [UI.accent.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                    Rectangle().fill(UI.accent).frame(height: 2.5)
                }
            }
        )
        .animation(.easeInOut(duration: 0.3), value: active)
    }

    var nameBlock: some View {
        VStack(alignment: mirrored ? .trailing : .leading, spacing: 2) {
            HStack(spacing: 6) {
                if !mirrored { turnDot }
                if m.showFaces && !mirrored { AvatarView(img: m.faces[idx], name: m.names[idx], size: 28) }
                Text(m.names[idx]).font(.system(size: 15, weight: .semibold)).foregroundColor(active ? UI.text : UI.dim).lineLimit(1)
                if m.showFaces && mirrored { AvatarView(img: m.faces[idx], name: m.names[idx], size: 28) }
                if mirrored { turnDot }
            }
            Caps(status, color: active ? UI.accent : UI.faint, size: 8.5)
        }
    }

    var status: String {
        if !active { return "Czeka" }
        if m.vsAI && idx == 1 && m.thinking { return "Myśli…" }
        if m.phase == .placing { return "Biała w ręce" }
        if m.phase == .rolling || m.phase == .striking { return "Uderzenie" }
        return onEight ? "Gra na czarną" : "Na ruchu"
    }

    var turnDot: some View {
        Circle().fill(active ? UI.accent : Color.white.opacity(0.18)).frame(width: 7, height: 7)
            .shadow(color: active ? UI.accent.opacity(0.9) : .clear, radius: 4)
    }

    var groupTag: some View {
        Text((m.mode == .nine || m.mode == .ten ? (m.hints[idx].isEmpty ? "—" : m.hints[idx]) : (m.groups[idx]?.name ?? "Stół otwarty")).uppercased())
            .font(UI.label(8.5)).tracking(1.1)
            .foregroundColor(m.groups[idx] == nil ? UI.faint : UI.dim)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
    }

    @ViewBuilder var balls: some View {
        if m.mode == .nine || m.mode == .ten {
            ForEach(1...m.mode.ballCount, id: \.self) { n in
                if m.pocketed.contains(n) { BallSlot() } else { BallChip(n: n, size: 16) }
            }
        } else if let g = m.groups[idx] {
            let list = mirrored ? Array(g.range).reversed() : Array(g.range)
            ForEach(list, id: \.self) { n in
                if m.pocketed.contains(n) { BallSlot() } else { BallChip(n: n, size: 16).transition(.scale.combined(with: .opacity)) }
            }
        } else {
            ForEach(0..<7, id: \.self) { _ in BallSlot().opacity(0.6) }
        }
    }

    var eightSlot: some View {
        BallChip(n: 8, size: 16)
            .opacity(onEight ? 1 : 0.28)
            .overlay(Circle().strokeBorder(UI.accent, lineWidth: onEight && active ? 1.4 : 0).padding(-2.5))
            .padding(.horizontal, 4)
    }
}

struct Scoreboard: View {
    @ObservedObject var m: GameModel
    var body: some View {
        HStack(spacing: 0) {
            PlayerPanel(m: m, idx: 0)
            centre
            PlayerPanel(m: m, idx: 1)
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .panel(14, tint: 0.42)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: m.pocketed)
    }

    func score(_ i: Int) -> Int { m.groups[i].map { g in m.pocketed.filter { g.range.contains($0) }.count } ?? 0 }

    var centre: some View {
        VStack(spacing: 3) {
            Caps(m.mode.title, color: UI.faint, size: 8.5)
            HStack(spacing: 8) {
                Text("\(score(0))").font(UI.number(24)).foregroundColor(m.current == 0 ? UI.text : UI.dim)
                Text(":").font(UI.number(16)).foregroundColor(UI.faint).offset(y: -1)
                Text("\(score(1))").font(UI.number(24)).foregroundColor(m.current == 1 ? UI.text : UI.dim)
            }
            .contentTransition(.numericText())
            Caps("\(m.mode.ballCount - m.pocketed.count) na stole", color: UI.faint, size: 8)
        }
        .frame(width: 96).frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.28))
        .overlay(HStack { Rectangle().fill(UI.line).frame(width: 1); Spacer(); Rectangle().fill(UI.line).frame(width: 1) })
    }
}

// MARK: - Komunikaty tur i fauli

struct Toast: Equatable {
    enum Kind { case foul, win, turn, good, info }
    let id = UUID()
    let text: String
    var kind: Kind {
        if text.hasPrefix("Faul") { return .foul }
        if text.contains("wygrywa") { return .win }
        if text.hasPrefix("Zmiana gracza") { return .turn }
        if text.hasPrefix("Rozbicie") || text.hasPrefix("Zadeklaruj") { return .info }
        return .good
    }
    var duration: Double { kind == .foul ? 4.6 : 3.0 }
}

struct ToastView: View {
    @ObservedObject var m: GameModel
    let t: Toast

    var color: Color {
        switch t.kind { case .foul: return UI.foul; case .win: return UI.accent; case .turn, .info: return UI.info; case .good: return UI.good }
    }
    var icon: String {
        switch t.kind {
        case .foul: return "exclamationmark.triangle.fill"
        case .win: return "trophy.fill"
        case .turn: return "arrow.left.arrow.right"
        case .info: return "circle.grid.3x3.fill"
        case .good: return "checkmark"
        }
    }
    var parts: (String, String, String?) {
        switch t.kind {
        case .foul:
            let body = t.text.replacingOccurrences(of: "Faul: ", with: "")
            let s = body.components(separatedBy: ". Biała w ręce dla: ")
            return ("Faul", s[0], s.count > 1 ? "Biała w ręce · \(s[1])" : nil)
        case .turn: return ("Zmiana gracza", "Na ruchu: \(m.names[m.current])", nil)
        case .info: return ("Rozbicie", t.text.replacingOccurrences(of: "Rozbicie – ", with: "Zaczyna: "), nil)
        case .win: return ("Koniec frejma", t.text, nil)
        case .good:
            if let r = t.text.range(of: " – ") { return (String(t.text[..<r.lowerBound]), String(t.text[r.upperBound...]), nil) }
            return (t.text, "", nil)
        }
    }

    var body: some View {
        let (title, sub, detail) = parts
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.18))
                Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundColor(color)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Caps(title, color: color, size: 10)
                if !sub.isEmpty { Text(sub).font(.system(size: 14, weight: .semibold)).foregroundColor(UI.text) }
                if let d = detail { Text(d).font(.system(size: 11.5, weight: .medium)).foregroundColor(UI.dim) }
            }
            .fixedSize()
        }
        .padding(.leading, 10).padding(.trailing, 18).padding(.vertical, 9)
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3).padding(.vertical, 8) }
        .panel(12, tint: 0.42)
    }
}

// MARK: - Sterowanie

/// Biała bila 3D (SceneKit, oświetlenie z HDRI sali) z punktem uderzenia na powierzchni
struct SpinBall: View {
    @ObservedObject var m: GameModel
    var size: CGFloat = 92
    var body: some View {
        ZStack {
            SpinBall3D(spin: m.spin).allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .background(Ellipse().fill(Color.black.opacity(0.35)).frame(width: size * 0.8, height: size * 0.16)
                        .blur(radius: 5).offset(y: size * 0.47))
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            var x = (v.location.x - size / 2) / (size / 2), y = -(v.location.y - size / 2) / (size / 2)
            let l = sqrt(x * x + y * y)
            if l > 0.85 { x *= 0.85 / l; y *= 0.85 / l }
            m.spin = CGPoint(x: x, y: y)
        })
        .onTapGesture(count: 2) { m.spin = .zero }
        .help("Przeciągnij, aby ustawić punkt uderzenia. Dwuklik – środek.")
    }

    static func describe(_ s: CGPoint) -> String {
        var parts: [String] = []
        if s.y > 0.15 { parts.append("górna") } else if s.y < -0.15 { parts.append("dolna") }
        if s.x > 0.15 { parts.append("prawa") } else if s.x < -0.15 { parts.append("lewa") }
        return parts.isEmpty ? "Środek" : parts.joined(separator: " · ").capitalizedFirst
    }
}

extension String { var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() } }

/// Segmentowy miernik z przeciąganiem
struct SegmentMeter: View {
    let value: Double                // 0…1
    var segments = 28
    var colored = true
    var width: CGFloat = 300
    var height: CGFloat = 14
    var marker: Double? = nil        // znacznik wartości odniesienia (np. poprzednia siła)
    var onDrag: ((Double) -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                let f = Double(i + 1) / Double(segments)
                let on = f <= value + 0.0001 || (i == 0 && value > 0.01)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(on ? color(f) : Color.white.opacity(0.07))
                    .shadow(color: on && colored && f > 0.8 ? color(f).opacity(0.6) : .clear, radius: 3)
            }
        }
        .frame(width: width, height: height)
        .padding(3)
        .drawingGroup()   // 1 warstwa zamiast 2×28 cieni CA (offscreen w WindowServer co klatkę → 30 FPS)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.black.opacity(0.35)))
        .overlay(alignment: .leading) {
            if let mk = marker, mk > 0.02 {
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 2, height: height + 8)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .offset(x: 3 + width * min(1, mk) - 1)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            onDrag?(max(0, min(1, (v.location.x - 3) / width)))
        })
    }

    func color(_ f: Double) -> Color {
        guard colored else { return Color.white.opacity(0.75) }
        return Color(hue: 0.36 * (1 - f) + 0.0, saturation: 0.62, brightness: 0.92)
    }
}

struct ShootButton: View {
    @ObservedObject var m: GameModel
    @State private var hover = false
    var enabled: Bool { m.phase == .aiming && !m.names.isEmpty && !(m.vsAI && m.current == 1) }
    var body: some View {
        Button { m.onShoot() } label: {
            VStack(spacing: 5) {
                Text("UDERZ").font(.system(size: 15, weight: .heavy)).tracking(1.5)
                KeyCapDark(k: "Spacja")
            }
            .foregroundColor(UI.ink)
            .frame(width: 104, height: 70)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [UI.accent.opacity(hover ? 1 : 0.95), UI.accent.opacity(0.78)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: UI.accent.opacity(hover && enabled ? 0.45 : 0), radius: 10)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.38)
        .onHover { hover = $0 }
    }
}

struct KeyCapDark: View {
    let k: String
    var body: some View {
        Text(k).font(.system(size: 9, weight: .semibold, design: .rounded))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 3.5).fill(Color.black.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 3.5).strokeBorder(Color.black.opacity(0.25), lineWidth: 0.7))
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1).animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ControlDock: View {
    @ObservedObject var m: GameModel
    @ObservedObject var st = Settings.shared
    var human: Bool { !(m.vsAI && m.current == 1) && (m.phase == .aiming || m.phase == .placing) }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 7) {
                SpinBall(m: m)
                Text(SpinBall.describe(m.spin)).font(.system(size: 10.5, weight: .medium)).foregroundColor(UI.dim)
            }
            .frame(width: 100)

            Rectangle().fill(UI.line).frame(width: 1, height: 96)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Caps("Siła uderzenia")
                        Spacer()
                        if m.lastPower > 0.02 { Text("ostatnio \(Int(m.lastPower * 100)) %").font(.system(size: 9.5, weight: .medium)).foregroundColor(UI.faint).padding(.trailing, 6) }
                        Text("\(Int(m.power * 100))").font(UI.number(15)).foregroundColor(UI.text)
                        + Text(" %").font(.system(size: 10, weight: .semibold)).foregroundColor(UI.faint)
                    }
                    SegmentMeter(value: m.power, marker: m.lastPower) { v in m.power = max(0.04, v) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Caps("Nachylenie kija")
                        HStack(spacing: 2) { KeyCap(k: "↑"); KeyCap(k: "↓") }.scaleEffect(0.9)
                        Spacer()
                        Text("\(Int(m.elevation))").font(UI.number(15)).foregroundColor(UI.text)
                        + Text(" °").font(.system(size: 10, weight: .semibold)).foregroundColor(UI.faint)
                    }
                    SegmentMeter(value: m.elevation / 55, segments: 28, colored: false, height: 6) { v in m.elevation = (v * 55).rounded() }
                }
            }
            .frame(width: 306)

            Rectangle().fill(UI.line).frame(width: 1, height: 96)

            ShootButton(m: m)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .panelIf(st.dockBg, 18, tint: 0.48)
        .opacity(human ? 1 : 0.72)
        .allowsHitTesting(human)          // w turze komputera nie da się zmieniać siły, kąta ani rotacji
        .animation(.easeInOut(duration: 0.25), value: human)
    }
}

struct ToolButton: View {
    let icon: String
    let label: String
    let key: String?
    var on = false
    var disabled = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 16)
                    .foregroundColor(on ? UI.accent : UI.text)
                Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(UI.text)
                if let key { KeyCap(k: key) }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(hover && !disabled ? 0.10 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { hover = $0 }
    }
}

/// Okrągły przycisk z ikoną; pod spodem po najechaniu – etykieta z klawiszem (styl HUD)
struct IconTool: View {
    let icon: String
    let label: String
    let key: String?
    var on = false
    var disabled = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(on ? UI.accent : (hover ? UI.text : UI.dim))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(hover && !disabled ? 0.12 : (on ? 0.07 : 0))))
                .overlay(Circle().strokeBorder(on ? UI.accent.opacity(0.45) : Color.clear, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
        .overlay(alignment: .top) {
            if hover {
                HStack(spacing: 6) {
                    Text(label).font(.system(size: 11, weight: .medium)).foregroundColor(UI.text).fixedSize()
                    if let key { KeyCap(k: key) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .panel(9, tint: 0.55)
                .offset(y: 50)
                .transition(.opacity.combined(with: .offset(y: -4)))
                .allowsHitTesting(false)
            }
        }
        .zIndex(hover ? 1 : 0)
    }
}

// MARK: - Przyciski menu

struct MenuButton: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var primary = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)).frame(width: 20) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 11)).opacity(0.65) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).opacity(hover ? 0.8 : 0.35)
                    .offset(x: hover ? 2 : 0)
            }
            .foregroundColor(primary && !UI.menuOn ? UI.ink : UI.text)
            .padding(.horizontal, 16).frame(width: 300, height: subtitle == nil ? 44 : 52)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(primary && UI.menuOn ? AnyShapeStyle(Color.white.opacity(hover ? 0.24 : 0.16))
                      : primary ? AnyShapeStyle(LinearGradient(colors: [UI.accent, UI.accent.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.white.opacity(hover ? 0.12 : 0.06))))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(UI.menuOn ? (primary ? 0.9 : 0.3) : (primary ? 0.35 : 0.12)), lineWidth: UI.menuOn && primary ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

// MARK: - Powtórki (oprawa telewizyjna)

/// tryb demo: dyskretna plakietka i zachęta (statyczne – zero kosztu na klatkę)
struct DemoOverlay: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color.black.opacity(0.45), .clear], center: .center, startRadius: 60, endRadius: 560)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                HStack(spacing: -22) {
                    BallChip(n: 1, size: 96).offset(y: 10)
                    BallChip(n: 8, size: 116).zIndex(1)
                    BallChip(n: 9, size: 96).offset(y: 10)
                }
                Text("BILARD").font(.system(size: 120, weight: .heavy)).tracking(34).foregroundColor(UI.text)
                    .shadow(color: .black.opacity(0.6), radius: 18, y: 4)
            }
            .padding(.horizontal, 40).padding(.vertical, 26)
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Circle().fill(UI.accent).frame(width: 7, height: 7)
                        Text("DEMO").font(UI.label(12)).tracking(2.5).foregroundColor(UI.dim)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .overlay(Capsule().strokeBorder(UI.line, lineWidth: 1))
                    .padding(.top, 22).padding(.trailing, 24)
                }
                Spacer()
                Text("Naciśnij dowolny klawisz / kliknij")
                    .font(UI.label(13)).tracking(1.6).foregroundColor(UI.dim)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .overlay(Capsule().strokeBorder(UI.line, lineWidth: 1))
                    .padding(.bottom, 34)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ReplayOverlay: View {
    let label: String
    @State private var pulse = false
    var body: some View {
        ZStack {
            RadialGradient(colors: [.clear, .black.opacity(0.62)], center: .center, startRadius: 280, endRadius: 900)
                .ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                Rectangle().fill(Color.black.opacity(0.55)).frame(height: 34)
                Spacer()
                Rectangle().fill(Color.black.opacity(0.55)).frame(height: 34)
            }.ignoresSafeArea().allowsHitTesting(false)
            VStack {
                HStack {
                    Spacer()
                    VStack(spacing: 5) {
                        Text("R").font(.system(size: 30, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color(red: 0.82, green: 0.10, blue: 0.12)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                            .shadow(color: Color.red.opacity(pulse ? 0.8 : 0), radius: 10)
                            .opacity(pulse ? 1 : 0.18)
                        Text(label).font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundColor(UI.accent)
                            .shadow(color: .black.opacity(0.8), radius: 3)
                    }
                    .padding(.top, 46).padding(.trailing, 28)
                }
                Spacer()
                Text("Spacja / Esc – pomiń powtórkę").font(.system(size: 11, weight: .medium)).tracking(1)
                    .foregroundColor(.white.opacity(0.65)).padding(.bottom, 44)
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

struct ReplayPicker: View {
    @ObservedObject var m: GameModel
    var body: some View {
        HStack(spacing: 6) {
            Caps("Powtórki")
            Spacer()
            ForEach(ReplayMode.allCases, id: \.self) { rm in
                let sel = m.replayMode == rm
                Button { m.replayMode = rm } label: {
                    Text(rm.title).font(.system(size: 10.5, weight: .medium)).foregroundColor(sel ? UI.text : UI.dim)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(sel ? 0.12 : 0.03)))
                        .overlay(Capsule().strokeBorder(sel ? UI.accent.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
                }.buttonStyle(PressStyle())
            }
        }
        .frame(width: 300)
    }
}

struct ClothPicker: View {
    @ObservedObject var m: GameModel
    var body: some View {
        HStack(spacing: 10) {
            Caps("Sukno")
            Spacer()
            swatch(blue: true)
            swatch(blue: false)
        }
        .frame(width: 300)
    }
    func swatch(blue: Bool) -> some View {
        let sel = m.blueCloth == blue
        return Button { if !sel { m.onToggleCloth() } } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(blue ? Color(red: 0.13, green: 0.33, blue: 0.62) : Color(red: 0.10, green: 0.42, blue: 0.24))
                    .frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.7))
                Text(blue ? "Turniejowe" : "Klasyczne").font(.system(size: 11.5, weight: .medium)).foregroundColor(sel ? UI.text : UI.dim)
            }
            .padding(.horizontal, 9).frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(sel ? 0.12 : 0.03)))
            .overlay(Capsule().strokeBorder(sel ? UI.accent.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - HUD

struct HUDView: View {
    @ObservedObject var m: GameModel
    @ObservedObject var st = Settings.shared
    @State private var toast: Toast? = nil
    @State private var showKeys = true

    var playing: Bool { m.phase != .menu && m.phase != .gameOver }
    static let studioLogo: NSImage? = Bundle.main.url(forResource: "podpis_logo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        ZStack {
            if m.phase != .menu && !m.demo {
                // góra: tablica wyników + komunikaty
                VStack(spacing: 10) {
                    if m.mode.isPoints { PointsBoard(m: m) } else { Scoreboard(m: m) }
                    if m.phase == .aiming || m.phase == .placing {
                        TargetCard(m: m).transition(.opacity)
                    }
                    ZStack {
                        if let t = toast, playing {
                            ToastView(m: m, t: t)
                                .id(t.id)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92)),
                                                        removal: .opacity.combined(with: .scale(scale: 0.96))))
                        }
                    }
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // lewy górny: pasek narzędzi – ikony w szklanej kapsule (jak tablica wyników), etykieta po najechaniu
                HStack(spacing: 4) {
                    IconTool(icon: "pause.fill", label: "Pauza", key: "Esc") { withAnimation(.easeOut(duration: 0.2)) { m.paused = true } }
                    Rectangle().fill(UI.line).frame(width: 1, height: 22).padding(.horizontal, 3)
                    IconTool(icon: "video.fill", label: m.cameraName, key: "V") { m.onCycleCamera() }
                    IconTool(icon: m.topView ? "cube.fill" : "square.grid.3x3.fill", label: m.topView ? "Widok 3D" : "Widok z góry", key: "C", on: m.topView) { m.onToggleView() }
                    IconTool(icon: "paintpalette.fill", label: "Sukno: \(m.settings.cloth.name)", key: "T") { m.onToggleCloth() }
                    IconTool(icon: m.settings.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: m.settings.muted ? "Dźwięk wyłączony" : "Dźwięk włączony", key: "M", on: m.settings.muted) { m.settings.muted.toggle() }
                    if m.phase == .aiming || m.phase == .placing {
                        IconTool(icon: "hand.point.up.left.fill", label: "Ustaw białą", key: "P", on: m.phase == .placing, disabled: m.phase == .placing) { m.onReposition() }
                    }
                }
                .padding(5)
                .panel(23, tint: 0.42)
                .interactive()
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // dół: dok sterowania + podpowiedź
                VStack(spacing: 10) {
                    hintBar
                    ControlDock(m: m).interactive()
                }
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                // lewy dolny: dyskretna ściąga klawiszy
                shortcuts
                    .opacity(showKeys ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8), value: showKeys)
                    .onAppear { hideKeysLater() }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                // prawy dolny: mały podpis studia
                if let logo = Self.studioLogo {
                    Image(nsImage: logo).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 150)
                        .opacity(0.6)
                        .padding(.trailing, 20).padding(.bottom, 16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .allowsHitTesting(false)
                }
            }

            if let l = m.replayLabel { ReplayOverlay(label: l).transition(.opacity) }
            if m.paused && playing && !m.demo { pauseOverlay.transition(.opacity) }
            if m.demo && !m.clothMenu { DemoOverlay().transition(.opacity) }
            if !m.fpsText.isEmpty {
                HStack(spacing: 4) {
                    Text(m.fpsText).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(UI.text)
                    Text("FPS").font(.system(size: 9, weight: .semibold)).tracking(1.2).foregroundColor(UI.faint)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .panel(9, tint: 0.5)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
            }
            if (m.phase == .menu && !m.demo && !m.clothMenu) || (m.clothMenu && m.demo && m.panelOpen) { menuOverlay.transition(.opacity) }
            if m.phase == .gameOver && !m.demo { gameOverOverlay.transition(.opacity.combined(with: .scale(scale: 0.97))) }
            if let t = m.toast {
                AchievementToast(t: t).id(t.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 110)
                    .transition(.move(edge: .top).combined(with: .opacity)).allowsHitTesting(false)
            }
            if m.loading < 1 { loadingView.transition(.opacity) }
        }
        .environment(\.colorScheme, .dark)
        .coordinateSpace(name: "hud")
        .onPreferenceChange(RectKey.self) { r in
            DispatchQueue.main.async { m.interactiveRects = r }
        }
        .onReceive(m.$message) { msg in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { toast = msg.isEmpty ? nil : Toast(text: msg) }
        }
        .onReceive(m.$phase) { p in
            if p == .menu || p == .gameOver { DispatchQueue.main.async { m.paused = false } }
        }
        .task(id: toast?.id) {
            guard let t = toast else { return }
            try? await Task.sleep(nanoseconds: UInt64(t.duration * 1e9))
            if toast?.id == t.id { withAnimation(.easeIn(duration: 0.3)) { toast = nil } }
        }
        .animation(.easeInOut(duration: 0.3), value: m.phase)
        .animation(.easeInOut(duration: 0.2), value: m.paused)
    }

    // MARK: podpowiedź

    var hint: String {
        switch m.phase {
        case .placing: return "Przesuń myszą i kliknij, aby ustawić białą bilę"
        case .aiming:
            if m.needsCall && !m.callText.isEmpty && !(m.vsAI && m.current == 1) {
                return m.callBall != nil && m.callPocket != nil ? m.callText + " · Spacja = uderzenie" : m.callText
            }
            if m.vsAI && m.current == 1 { return m.needsCall && !m.callText.isEmpty ? "Komputer – \(m.callText)" : "Komputer przygotowuje uderzenie…" }
            return m.topView ? "Kliknij lub przeciągnij, aby wycelować" : "Przeciągnij, aby obrócić kij · przytrzymaj Spację, aby nabrać siły"
        case .rolling, .striking: return m.needsCall && m.callBall != nil ? m.callText : "Bile w ruchu…"
        default: return ""
        }
    }

    @ViewBuilder var hintBar: some View {
        if !hint.isEmpty {
            HStack(spacing: 8) {
                if m.phase == .placing { Image(systemName: "hand.point.up.left.fill").foregroundColor(UI.accent) }
                else if m.vsAI && m.current == 1 && m.phase == .aiming { ProgressView().controlSize(.mini) }
                Text(hint).font(.system(size: 11.5, weight: .medium)).foregroundColor(UI.dim)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.38)))
            .id(hint)
            .transition(.opacity)
        }
    }

    func hideKeysLater() {
        showKeys = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) { showKeys = false }
    }

    var shortcuts: some View {
        let rows: [(String, String)] = [("← →", "celowanie (⇧ dokładnie)"), ("↑ ↓", "nachylenie"), ("+ −", "przybliżenie"),
                                         ("K", "kreda"), ("R", "reset kamery"), ("M", "dźwięk"), ("N", "nowa gra"), ("Esc", "menu")]
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.0) { r in
                HStack(spacing: 7) {
                    KeyCap(k: r.0).frame(minWidth: 34, alignment: .leading)
                    Text(r.1).font(.system(size: 10.5)).foregroundColor(UI.faint)
                }
            }
        }
        .opacity(0.75)
        .allowsHitTesting(false)
    }

    // MARK: ekrany

    var loadingView: some View {
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 18) {
                emblem(size: 34)
                VStack(spacing: 4) {
                    Text("BILARD").font(.system(size: 34, weight: .heavy)).tracking(10).foregroundColor(UI.text)
                    Caps("Generowanie tekstur PBR 4K", color: UI.faint)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(UI.accent).frame(width: max(6, 280 * m.loading))
                        .animation(.easeOut(duration: 0.25), value: m.loading)
                }
                .frame(width: 280, height: 4)
                Text(m.loadText).font(.system(size: 11)).foregroundColor(UI.faint).monospacedDigit()
            }
        }
    }

    func emblem(size: CGFloat) -> some View {
        HStack(spacing: -size * 0.28) {
            BallChip(n: 1, size: size).offset(y: size * 0.12)
            BallChip(n: 8, size: size * 1.18).zIndex(1)
            BallChip(n: 9, size: size).offset(y: size * 0.12)
        }
    }

    func backdrop(_ o: Double, vignette: Double = 0.55) -> some View {
        ZStack {
            Color.black.opacity(o)
            RadialGradient(colors: [.clear, .black.opacity(vignette)], center: .center, startRadius: 200, endRadius: 900)
        }
        .ignoresSafeArea()
    }

    var menuOverlay: some View { MenuRoot(m: m, s: m.settings, rec: m.records) }

    func hk(_ k: String, _ t: String) -> some View {
        HStack(spacing: 4) { KeyCap(k: k); Text(t).font(.system(size: 10.5)).foregroundColor(UI.faint) }
    }

    var pauseOverlay: some View {
        ZStack {
            if m.pauseCine { pauseCineOverlay.transition(.opacity) } else { pausePanel.transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.6), value: m.pauseCine)
    }

    /// pauza „na wygaszaczu”: zbliżenia na bile, tylko dyskretny napis
    var pauseCineOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001)
            VStack(spacing: 6) {
                Text("PAUZA").font(.system(size: 15, weight: .heavy)).tracking(6).foregroundColor(UI.text)
                Caps("Kliknij lub naciśnij dowolny klawisz", color: UI.dim, size: 9)
            }
            .padding(.horizontal, 22).padding(.vertical, 12)
            .panel(14, tint: 0.4)
            .padding(.bottom, 40)
        }
        .contentShape(Rectangle())
        .onTapGesture { m.pauseCine = false }
        .interactive()
    }

    var pausePanel: some View {
        ZStack {
            backdrop(0.10, vignette: 0.32)
            VStack(spacing: 0) {
                Image(systemName: "pause.circle").font(.system(size: 30, weight: .light)).foregroundColor(UI.dim)
                Text("PAUZA").font(.system(size: 28, weight: .heavy)).tracking(8).foregroundColor(UI.text).padding(.top, 8)
                Caps("\(m.names[0])  \(score(0)) : \(score(1))  \(m.names[1])", color: UI.dim, size: 10).padding(.top, 4)
                if m.savePicker != 0 {
                    SaveSlotsView(m: m, saving: m.savePicker == 1) { m.savePicker = 0 }.padding(.top, 20)
                    MenuButton(title: "Wróć", icon: "chevron.left") { m.savePicker = 0 }.padding(.top, 10)
                } else {
                VStack(spacing: 10) {
                    MenuButton(title: "Wznów grę", icon: "play.fill", primary: true) { m.paused = false }
                    if !m.tournamentActive {
                        MenuButton(title: "Zapisz grę", subtitle: (m.phase == .aiming || m.phase == .placing) ? "3 sloty" : "możliwe, gdy bile stoją", icon: "square.and.arrow.down") { m.savePicker = 1 }
                            .disabled(!(m.phase == .aiming || m.phase == .placing)).opacity((m.phase == .aiming || m.phase == .placing) ? 1 : 0.5)
                    }
                    MenuButton(title: "Zacznij od nowa", icon: "arrow.counterclockwise") { m.paused = false; m.onNewGame(m.vsAI) }
                    MenuButton(title: "Menu główne", subtitle: "kończy bieżącą grę", icon: "house.fill") { m.paused = false; m.onBackToMenu() }
                }
                .padding(.top, 24)
                }
                Rectangle().fill(UI.line).frame(width: 300, height: 1).padding(.vertical, 18)
                ClothPicker(m: m)
            }
            .padding(.horizontal, 40).padding(.vertical, 32)
            .panel(24, tint: 0.05, glass: 0.3)
        }
        .interactive()
    }

    func score(_ i: Int) -> Int {
        if m.mode.isPoints { return m.scores[i] }
        return m.groups[i].map { g in m.pocketed.filter { g.range.contains($0) }.count } ?? 0
    }

    var gameOverOverlay: some View {
        ZStack {
            backdrop(0.12, vignette: 0.32).allowsHitTesting(false)
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(UI.accent.opacity(0.14)).frame(width: 74, height: 74)
                    Circle().strokeBorder(UI.accent.opacity(0.5), lineWidth: 1).frame(width: 74, height: 74)
                    Image(systemName: "trophy.fill").font(.system(size: 30)).foregroundColor(UI.accent)
                }
                Caps("Koniec frejma", color: UI.accent, size: 10.5).padding(.top, 16)
                Text(m.winner.map { "Wygrywa \(m.names[$0])" } ?? "Koniec gry")
                    .font(.system(size: 30, weight: .bold)).foregroundColor(UI.text).padding(.top, 4)
                Text(m.message).font(.system(size: 13)).foregroundColor(UI.dim)
                    .multilineTextAlignment(.center).frame(maxWidth: 320).padding(.top, 6)

                HStack(spacing: 0) {
                    resultCol(0)
                    Rectangle().fill(UI.line).frame(width: 1, height: 54)
                    resultCol(1)
                }
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
                .frame(width: 300)
                .padding(.top, 22)

                VStack(spacing: 10) {
                    if m.tournamentActive {
                        MenuButton(title: "Dalej w turnieju", icon: "trophy.fill", primary: true) { m.menuTab = 3; m.onBackToMenu() }
                    } else {
                        MenuButton(title: "Rewanż", icon: "arrow.counterclockwise", primary: true) { m.onNewGame(m.vsAI) }
                        MenuButton(title: m.vsAI ? "Dwóch graczy" : "Gra z komputerem", icon: m.vsAI ? "person.2.fill" : "desktopcomputer") { m.onNewGame(!m.vsAI) }
                        MenuButton(title: "Menu główne", icon: "house.fill") { m.onBackToMenu() }
                    }
                }
                .padding(.top, 22)
                ClothPicker(m: m).padding(.top, 16)
            }
            .padding(.horizontal, 40).padding(.vertical, 32)
            .panel(24, tint: 0.05, glass: 0.3)
            .interactive()
        }
    }

    func resultCol(_ i: Int) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                if m.winner == i { Image(systemName: "crown.fill").font(.system(size: 9)).foregroundColor(UI.accent) }
                Text(m.names[i]).font(.system(size: 12, weight: .semibold)).foregroundColor(m.winner == i ? UI.text : UI.dim)
            }
            Text("\(score(i))").font(UI.number(24)).foregroundColor(UI.text)
            Caps(m.groups[i]?.name ?? "—", size: 8.5)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tablica punktowa (14/1, snooker)

struct PointsBoard: View {
    @ObservedObject var m: GameModel
    var body: some View {
        HStack(spacing: 0) {
            panel(0)
            centre
            panel(1)
        }
        .fixedSize()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .panel(14, tint: 0.42)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: m.scores)
    }

    func panel(_ i: Int) -> some View {
        let active = m.current == i && m.phase != .menu && m.phase != .gameOver
        let mir = i == 1
        return VStack(alignment: mir ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 6) {
                if !mir { Circle().fill(active ? UI.accent : Color.white.opacity(0.18)).frame(width: 7, height: 7) }
                if m.showFaces && !mir { AvatarView(img: m.faces[i], name: m.names[i], size: 28) }
                Text(m.names[i]).font(.system(size: 15, weight: .semibold)).foregroundColor(active ? UI.text : UI.dim).lineLimit(1)
                if m.showFaces && mir { AvatarView(img: m.faces[i], name: m.names[i], size: 28) }
                if mir { Circle().fill(active ? UI.accent : Color.white.opacity(0.18)).frame(width: 7, height: 7) }
            }
            Text("\(m.scores[i])").font(UI.number(34)).foregroundColor(active ? UI.text : UI.dim).contentTransition(.numericText())
            Caps(active ? (m.mode == .snooker ? "nast. bila: \(m.hints[i])" : (m.needsCall ? "deklaruj bilę i łuzę" : "na ruchu")) : "czeka",
                 color: active ? UI.accent : UI.faint, size: 8.5)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .frame(width: 230, alignment: mir ? .trailing : .leading)
        .background(
            ZStack(alignment: .top) {
                if active {
                    LinearGradient(colors: [UI.accent.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom)
                    Rectangle().fill(UI.accent).frame(height: 2.5)
                }
            }
        )
    }

    var centre: some View {
        VStack(spacing: 4) {
            Caps(m.mode.title, color: UI.faint, size: 8.5)
            Caps(m.mode == .snooker ? "czerwone: \(m.tableCount)" : "do \(m.target) · na stole \(m.tableCount)", color: UI.dim, size: 8.5)
            Caps("seria \(m.curBreak)", color: UI.dim, size: 8.5)
            Caps("najw. seria \(m.highBreak)", color: UI.faint, size: 8)
        }
        .frame(width: 130).frame(maxHeight: .infinity)
        .background(Color.black.opacity(0.28))
        .overlay(HStack { Rectangle().fill(UI.line).frame(width: 1); Spacer(); Rectangle().fill(UI.line).frame(width: 1) })
    }
}

/// Widok hostujący: przepuszcza zdarzenia myszy do widoku 3D poza elementami interaktywnymi
final class HUDHostingView: NSHostingView<HUDView> {
    let model: GameModel
    init(model: GameModel) {
        self.model = model
        super.init(rootView: HUDView(m: model))
    }
    @MainActor required init(rootView: HUDView) { fatalError() }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        let y = isFlipped ? p.y : bounds.height - p.y
        for r in model.interactiveRects where r.insetBy(dx: -4, dy: -4).contains(CGPoint(x: p.x, y: y)) {
            return super.hitTest(point)
        }
        return nil
    }
}


/// Mała scena SceneKit: lakierowana biała bila + czerwony znacznik punktu uderzenia.
/// Renderuje tylko przy zmianie (bez pętli), więc nie kosztuje klatek gry.
final class PassThroughSCNView: SCNView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }

struct SpinBall3D: NSViewRepresentable {
    var spin: CGPoint
    final class Coord { var marker = SCNNode(); var halo = SCNNode(); var ball = SCNNode() }
    func makeCoordinator() -> Coord { Coord() }

    func makeNSView(context: Context) -> SCNView {
        let v = PassThroughSCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = false
        v.allowsCameraControl = false
        let sc = SCNScene()
        if let u = Scans.hdriURL { sc.lightingEnvironment.contents = u; sc.lightingEnvironment.intensity = 1.6 }
        let c = context.coordinator
        let ball = SCNSphere(radius: 1); ball.segmentCount = 72
        let mb = ball.firstMaterial!
        mb.lightingModel = .physicallyBased
        mb.diffuse.contents = NSColor(white: 0.93, alpha: 1)
        mb.roughness.contents = 0.12; mb.metalness.contents = 0.0
        mb.clearCoat.contents = 1.0; mb.clearCoatRoughness.contents = 0.04
        c.ball.geometry = ball
        sc.rootNode.addChildNode(c.ball)
        // znacznik: czerwona kropka na powierzchni + półprzezroczysta otoczka
        let dot = SCNCylinder(radius: 0.13, height: 0.02)
        dot.firstMaterial!.lightingModel = .physicallyBased
        dot.firstMaterial!.diffuse.contents = NSColor(red: 0.90, green: 0.18, blue: 0.16, alpha: 1)
        dot.firstMaterial!.roughness.contents = 0.35
        c.marker.geometry = dot
        let ring = SCNTube(innerRadius: 0.15, outerRadius: 0.24, height: 0.012)
        ring.firstMaterial!.lightingModel = .constant
        ring.firstMaterial!.diffuse.contents = NSColor(red: 0.95, green: 0.3, blue: 0.28, alpha: 0.35)
        ring.firstMaterial!.writesToDepthBuffer = false
        c.halo.geometry = ring
        sc.rootNode.addChildNode(c.marker); sc.rootNode.addChildNode(c.halo)
        // delikatne światło kierunkowe z góry-lewej dla wyraźnego blasku
        let l = SCNNode(); l.light = SCNLight(); l.light!.type = .directional; l.light!.intensity = 350
        l.simdEulerAngles = SIMD3(-0.7, -0.5, 0); sc.rootNode.addChildNode(l)
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera!.usesOrthographicProjection = true; cam.camera!.orthographicScale = 1.04
        cam.camera!.wantsHDR = true; cam.camera!.wantsExposureAdaptation = false
        cam.position = SCNVector3(0, 0, 5); sc.rootNode.addChildNode(cam)
        v.scene = sc; v.pointOfView = cam
        place(c, animated: false)
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) { place(context.coordinator, animated: true) }

    private func place(_ c: Coord, animated: Bool) {
        let x = Double(spin.x), y = Double(spin.y)
        let z = sqrt(max(0, 1 - x * x - y * y))
        let n = SIMD3<Float>(Float(x), Float(y), Float(z))
        SCNTransaction.begin(); SCNTransaction.animationDuration = animated ? 0.12 : 0
        for (node, out) in [(c.marker, Float(1.0)), (c.halo, Float(1.002))] {
            node.simdPosition = n * out
            // oś cylindra (Y) wzdłuż normalnej powierzchni
            node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(n))
        }
        SCNTransaction.commit()
    }
}


// MARK: Karta „cel”: bile do wbicia w 3D

struct TargetCard: View {
    @ObservedObject var m: GameModel
    var body: some View {
        VStack(spacing: 4) {
            if !m.targetIDs.isEmpty {
                TargetBalls3D(ids: m.targetIDs, geo: m.ballGeometry, mode: m.mode.rawValue)
                    .frame(width: CGFloat(m.targetIDs.count) * 62 + 12, height: 62)
            }
            Text(m.targetTitle.uppercased()).font(UI.label(15)).tracking(1.6).foregroundColor(UI.text)
                .shadow(color: .black.opacity(0.7), radius: 4)
            Text(m.targetSub).font(.system(size: 12, weight: .medium)).foregroundColor(UI.dim)
                .shadow(color: .black.opacity(0.7), radius: 4)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: m.targetIDs)
    }
}

struct TargetBalls3D: NSViewRepresentable {
    var ids: [Int]
    var geo: (Int) -> SCNGeometry?
    var mode: String
    final class Coord { var key = ""; var holder = SCNNode() }
    func makeCoordinator() -> Coord { Coord() }

    func makeNSView(context: Context) -> SCNView {
        let v = PassThroughSCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 30
        v.allowsCameraControl = false
        let sc = SCNScene()
        if let u = Scans.hdriURL { sc.lightingEnvironment.contents = u; sc.lightingEnvironment.intensity = 1.6 }
        sc.rootNode.addChildNode(context.coordinator.holder)
        let l = SCNNode(); l.light = SCNLight(); l.light!.type = .directional; l.light!.intensity = 350
        l.simdEulerAngles = SIMD3(-0.7, -0.5, 0); sc.rootNode.addChildNode(l)
        let cam = SCNNode(); cam.camera = SCNCamera()
        cam.camera!.usesOrthographicProjection = true; cam.camera!.orthographicScale = 1.15
        cam.camera!.wantsHDR = true; cam.camera!.wantsExposureAdaptation = false
        cam.position = SCNVector3(0, 0, 8); sc.rootNode.addChildNode(cam)
        v.scene = sc; v.pointOfView = cam
        rebuild(context.coordinator)
        return v
    }

    func updateNSView(_ v: SCNView, context: Context) { rebuild(context.coordinator) }

    private func rebuild(_ c: Coord) {
        let key = mode + ids.map(String.init).joined(separator: ",")
        guard key != c.key else { return }
        c.key = key
        c.holder.childNodes.forEach { $0.removeFromParentNode() }
        let n = ids.count
        for (i, id) in ids.enumerated() {
            guard let g = geo(id) else { continue }
            let b = SCNNode(geometry: g)
            b.scale = SCNVector3(1 / Phys.R, 1 / Phys.R, 1 / Phys.R)
            let slot = SCNNode()
            slot.position = SCNVector3((Double(i) - Double(n - 1) / 2) * 2.2 * 1.0, 0, 0)
            b.eulerAngles = SCNVector3(0.35, Double(i) * 0.9, 0.2)
            b.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 7 + Double(i % 3))))
            slot.addChildNode(b)
            c.holder.addChildNode(slot)
        }
    }
}
