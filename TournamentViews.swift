import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Awatar (zdjęcie albo generowany z inicjałami)

struct AvatarView: View {
    let img: NSImage?
    let name: String
    var size: CGFloat = 30
    var body: some View {
        ZStack {
            if let img {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                let h = Double(abs(name.hashValue) % 360) / 360
                LinearGradient(colors: [Color(hue: h, saturation: 0.55, brightness: 0.75), Color(hue: h, saturation: 0.7, brightness: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(name.split(separator: " ").prefix(2).compactMap { $0.first }).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold)).foregroundColor(.white.opacity(0.95))
            }
        }
        .frame(width: size, height: size).clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Zakładka Turniej: drabinka + gracze

struct TournamentTab: View {
    @ObservedObject var m: GameModel
    @ObservedObject var ps = ProfileStore.shared
    @ObservedObject var ts = TournamentStore.shared
    @ObservedObject var rec = RecordStore.shared
    @State private var sub = 0
    @State private var size = 4
    @State private var mode: GameMode = .eight
    @State private var picked: Set<String> = []

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Chip(title: "Drabinka", selected: sub == 0) { sub = 0 }
                Chip(title: "Gracze i statystyki", selected: sub == 1) { sub = 1 }
            }
            if sub == 0 { (ts.t == nil ? AnyView(setupView) : AnyView(bracketView)) } else { playersView }
            Spacer(minLength: 0)
        }
    }

    // MARK: Nowy turniej
    var setupView: some View {
        VStack(alignment: .leading, spacing: 9) {
            Row(label: "Tryb gry") {
                ForEach([GameMode.eight, .nine, .ten, .straight, .snooker], id: \.self) { g in Chip(title: g.title, selected: mode == g) { mode = g } }
            }
            Row(label: "Liczba graczy") {
                ForEach([4, 8], id: \.self) { n in Chip(title: "\(n)", selected: size == n, width: 48) { size = n; picked = Set(picked.prefix(n)) } }
                Text("Uczestnicy: \(picked.count)/\(size)").font(.system(size: 11)).foregroundColor(picked.count == size ? UI.good : UI.dim)
            }
            Caps("Wybierz uczestników (profile z zakładki „Gracze”)", size: 9)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(ps.list) { p in
                        let on = picked.contains(p.id)
                        Button {
                            if on { picked.remove(p.id) } else if picked.count < size { picked.insert(p.id) }
                        } label: {
                            HStack(spacing: 8) {
                                AvatarView(img: ps.face(p.id), name: p.name, size: 26)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(p.name).font(.system(size: 12, weight: .semibold)).foregroundColor(UI.text).lineLimit(1)
                                    Text(p.isAI ? "Komputer · \(AILevel(rawValue: p.level)?.title ?? "")" : "Człowiek").font(.system(size: 9.5)).foregroundColor(UI.dim)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundColor(on ? UI.menuAccent : UI.faint)
                            }
                            .padding(.horizontal, 8).frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(on ? 0.14 : 0.06)))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 200)
            HStack(spacing: 10) {
                Chip(title: "Uzupełnij losowo", selected: false) {
                    for p in ps.list.shuffled() where picked.count < size { picked.insert(p.id) }
                }
                Chip(title: "Wyczyść", selected: false) { picked = [] }
                Spacer()
                Button {
                    var ids = Array(picked)
                    for p in ps.list.shuffled() where ids.count < size && !ids.contains(p.id) { ids.append(p.id) }
                    guard ids.count == size else { return }
                    ts.create(mode: mode, ids: ids)
                } label: {
                    Text("Rozpocznij turniej").font(.system(size: 13, weight: .semibold)).foregroundColor(UI.ink)
                        .padding(.horizontal, 18).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(UI.menuAccent))
                }.buttonStyle(.plain).disabled(ps.list.count < size)
            }
            if ps.list.count < size { Text("Za mało profili – dodaj graczy w zakładce „Gracze”.").font(.system(size: 10)).foregroundColor(UI.foul) }
        }
    }

    // MARK: Drabinka
    var bracketView: some View {
        let t = ts.t!
        return VStack(spacing: 10) {
            HStack {
                Text("Turniej pucharowy · \(GameMode(rawValue: t.mode)?.title ?? "") · \(t.size) graczy").font(.system(size: 12.5, weight: .semibold)).foregroundColor(UI.text)
                Spacer()
            }
            HStack(alignment: .center, spacing: 12) {
                ForEach(t.rounds.indices, id: \.self) { r in
                    VStack(spacing: 8) {
                        Caps(roundName(r, of: t.rounds.count), color: UI.dim, size: 9)
                        Spacer(minLength: 0)
                        ForEach(t.rounds[r].indices, id: \.self) { i in matchCell(t.rounds[r][i], current: ts.nextPlayable().map { $0 == (r, i) } ?? false) }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 250)
            if let c = t.champion, let p = ps.profile(c) {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill").foregroundColor(UI.menuAccent)
                    AvatarView(img: ps.face(c), name: p.name, size: 30)
                    Text("Mistrz turnieju: \(p.name)").font(.system(size: 14, weight: .bold)).foregroundColor(UI.text)
                    Spacer()
                    Chip(title: "Zakończ i zacznij nowy", selected: true) { ts.abandon(); picked = [] }
                }
            } else {
                HStack(spacing: 10) {
                    Button { playNext() } label: {
                        Text(nextLabel).font(.system(size: 13, weight: .semibold)).foregroundColor(UI.ink)
                            .padding(.horizontal, 18).frame(height: 34).background(RoundedRectangle(cornerRadius: 10).fill(UI.menuAccent))
                    }.buttonStyle(.plain)
                    Spacer()
                    Chip(title: "Porzuć turniej", selected: false) { ts.abandon(); picked = [] }
                }
            }
        }
    }

    var nextLabel: String {
        guard let t = ts.t, let (r, i) = ts.nextPlayable() else { return "Dalej" }
        let m = t.rounds[r][i]
        if m.a != nil, m.b != nil, !(ts.isHuman(m.a) || ts.isHuman(m.b)) { return "Symuluj mecze komputerów" }
        return "Zagraj następny mecz"
    }

    func playNext() {
        if let (r, i) = ts.advanceAI() { m.onStartMatch(r, i) }
    }

    func roundName(_ r: Int, of n: Int) -> String {
        if r == n - 1 { return "Finał" }
        if r == n - 2 { return "Półfinał" }
        return "Ćwierćfinał"
    }

    func matchCell(_ mt: TMatch, current: Bool) -> some View {
        VStack(spacing: 0) {
            slot(mt.a, win: mt.winner != nil && mt.winner == mt.a)
            Rectangle().fill(UI.line).frame(height: 1)
            slot(mt.b, win: mt.winner != nil && mt.winner == mt.b)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(current ? UI.menuAccent : Color.white.opacity(0.1), lineWidth: current ? 1.5 : 1))
    }

    func slot(_ id: String?, win: Bool) -> some View {
        HStack(spacing: 5) {
            if let id, let p = ps.profile(id) {
                AvatarView(img: ps.face(id), name: p.name, size: 18)
                Text(p.name).font(.system(size: 10.5, weight: win ? .bold : .regular)).foregroundColor(win ? UI.menuAccent : UI.text).lineLimit(1)
                if !p.isAI { Image(systemName: "person.fill").font(.system(size: 7)).foregroundColor(UI.dim) }
            } else {
                Text("—").font(.system(size: 10.5)).foregroundColor(UI.faint)
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 6).frame(height: 24)
    }

    // MARK: Gracze
    var playersView: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(ps.list) { p in playerRow(p) }
                }.padding(.trailing, 6)
            }.frame(height: 320)
            HStack(spacing: 8) {
                Chip(title: "+ Człowiek", selected: false) { ps.add(ai: false) }
                Chip(title: "+ Komputer", selected: false) { ps.add(ai: true) }
                Spacer()
            }
        }
    }

    func playerRow(_ p: Profile) -> some View {
        let tot = ps.totals(p.name)
        let pct = tot.games == 0 ? 0 : Int((Double(tot.wins) / Double(tot.games) * 100).rounded())
        return HStack(spacing: 10) {
            AvatarView(img: ps.face(p.id), name: p.name, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                TextField("Imię", text: Binding(get: { p.name }, set: { var q = p; q.name = String($0.prefix(16)); ps.update(q) }))
                    .textFieldStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundColor(UI.text).frame(width: 130)
                Text("\(tot.games) meczów · \(tot.wins) wygranych · \(pct)% · \(p.titles) pucharów").font(.system(size: 10)).foregroundColor(UI.dim)
            }
            Spacer(minLength: 4)
            if p.isAI {
                ForEach(AILevel.allCases, id: \.rawValue) { l in
                    Chip(title: l.title, selected: p.level == l.rawValue) { var q = p; q.level = l.rawValue; ps.update(q) }
                }
            } else {
                Text("Człowiek").font(.system(size: 11)).foregroundColor(UI.dim)
            }
            Button { pickPhoto(p) } label: { Image(systemName: "photo").foregroundColor(UI.dim) }.buttonStyle(.plain).help("Wybierz zdjęcie")
            if p.id != "you" { Button { ps.remove(p.id) } label: { Image(systemName: "trash").foregroundColor(UI.foul.opacity(0.8)) }.buttonStyle(.plain) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }

    func pickPhoto(_ p: Profile) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Wybierz zdjęcie dla gracza \(p.name)"
        if panel.runModal() == .OK, let u = panel.url { ps.setFace(p.id, from: u) }
    }
}
