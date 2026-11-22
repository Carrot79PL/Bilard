import Foundation
import SwiftUI

// MARK: - Wyzwania dzienne i tygodniowe oraz trofea (postęp w Application Support/Bilard/challenges.json)

enum Metric: String, Codable {
    case pots, wins, winsAI, games, streak, doubles, flawless, winsClub, winsMaster, winsNine, modes
}

struct ChallengeDef: Identifiable {
    let id: String, title: String, goal: Int, metric: Metric, xp: Int
}

struct PeriodState: Codable {
    var key = ""
    var m: [String: Int] = [:]
    var done: [String] = []
    var modes: [String] = []
}

struct Stats: Codable {
    var games = 0, wins = 0, winsAI = 0, pots = 0, bestStreak = 0, doubles = 0, flawless = 0, tourWins = 0
    var dailyDone = 0, weeklyDone = 0, xp = 0
    var winsByMode: [String: Int] = [:]
    var winsByLevel: [String: Int] = [:]
    var lastDay = "", loginStreak = 0, bestLogin = 0
    var trophies: [String: String] = [:]      // id → data zdobycia
    var daily = PeriodState()
    var weekly = PeriodState()
}

struct TrophyDef: Identifiable {
    let id: String, name: String, desc: String
    let tier: Int                              // 0 brąz, 1 srebro, 2 złoto, 3 platyna
    let symbol: String
    let goal: Int
    let value: (Stats) -> Int
    var xp: Int { [40, 100, 250, 500][tier] }
    var color: Color { [Color(red: 0.80, green: 0.50, blue: 0.20), Color(red: 0.78, green: 0.80, blue: 0.84), Color(red: 1, green: 0.82, blue: 0.20), Color(red: 0.55, green: 0.90, blue: 1)][tier] }
    var tierName: String { ["Brąz", "Srebro", "Złoto", "Platyna"][tier] }
}

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let title: String, sub: String, symbol: String
}

final class Challenges: ObservableObject {
    static let shared = Challenges()
    @Published private(set) var stats = Stats()
    var onToast: (ToastItem) -> Void = { _ in }
    private var gameFouls = 0, streakCur = 0

    // MARK: definicje
    static let dailyPool: [ChallengeDef] = [
        ChallengeDef(id: "d_pots", title: "Wbij 15 bil", goal: 15, metric: .pots, xp: 50),
        ChallengeDef(id: "d_win", title: "Wygraj partię z komputerem", goal: 1, metric: .winsAI, xp: 60),
        ChallengeDef(id: "d_streak", title: "Wbij 5 bil z rzędu bez pudła", goal: 5, metric: .streak, xp: 60),
        ChallengeDef(id: "d_flawless", title: "Wygraj partię bez faulu", goal: 1, metric: .flawless, xp: 70),
        ChallengeDef(id: "d_games", title: "Zagraj 3 partie", goal: 3, metric: .games, xp: 40),
        ChallengeDef(id: "d_club", title: "Pokonaj Klubowicza lub Mistrza", goal: 1, metric: .winsClub, xp: 80),
        ChallengeDef(id: "d_double", title: "Wbij 2 bile jednym uderzeniem", goal: 1, metric: .doubles, xp: 60),
        ChallengeDef(id: "d_nine", title: "Wygraj partię 9-Ball", goal: 1, metric: .winsNine, xp: 60),
    ]
    static let weeklyPool: [ChallengeDef] = [
        ChallengeDef(id: "w_wins", title: "Wygraj 10 partii", goal: 10, metric: .wins, xp: 200),
        ChallengeDef(id: "w_pots", title: "Wbij 100 bil", goal: 100, metric: .pots, xp: 200),
        ChallengeDef(id: "w_modes", title: "Wygraj w 3 różnych trybach", goal: 3, metric: .modes, xp: 250),
        ChallengeDef(id: "w_master", title: "Pokonaj Mistrza", goal: 1, metric: .winsMaster, xp: 250),
        ChallengeDef(id: "w_games", title: "Zagraj 15 partii", goal: 15, metric: .games, xp: 150),
    ]
    static let trophies: [TrophyDef] = {
        func t(_ id: String, _ name: String, _ desc: String, _ tier: Int, _ sym: String, _ goal: Int, _ v: @escaping (Stats) -> Int) -> TrophyDef {
            TrophyDef(id: id, name: name, desc: desc, tier: tier, symbol: sym, goal: goal, value: v)
        }
        func mode(_ id: String, _ name: String) -> TrophyDef { t("m_\(id)", name, "Wygraj partię w tym trybie", 1, "flag.checkered", 1) { $0.winsByMode[id] ?? 0 } }
        return [
            t("w1", "Pierwsza wygrana", "Wygraj pierwszą partię", 0, "star.fill", 1) { $0.wins },
            t("w10", "Zawodnik", "Wygraj 10 partii", 0, "star.fill", 10) { $0.wins },
            t("w50", "Weteran", "Wygraj 50 partii", 1, "star.circle.fill", 50) { $0.wins },
            t("w100", "Mistrz stołu", "Wygraj 100 partii", 2, "crown.fill", 100) { $0.wins },
            t("w500", "Legenda", "Wygraj 500 partii", 3, "crown.fill", 500) { $0.wins },
            t("p100", "Pierwsza setka", "Wbij 100 bil", 0, "circle.circle.fill", 100) { $0.pots },
            t("p500", "Snajper", "Wbij 500 bil", 1, "scope", 500) { $0.pots },
            t("p2000", "Maszyna", "Wbij 2000 bil", 2, "scope", 2000) { $0.pots },
            t("p10000", "Dziesięć tysięcy", "Wbij 10 000 bil", 3, "scope", 10000) { $0.pots },
            t("g25", "Stały bywalec", "Zagraj 25 partii", 0, "person.fill", 25) { $0.games },
            t("g100", "Bywalec klubu", "Zagraj 100 partii", 1, "person.2.fill", 100) { $0.games },
            t("g500", "Dusza towarzystwa", "Zagraj 500 partii", 2, "person.3.fill", 500) { $0.games },
            mode("8ball", "Mistrz ósemki"), mode("9ball", "Mistrz dziewiątki"), mode("10ball", "Mistrz dziesiątki"),
            mode("straight", "Mistrz 14/1"), mode("snooker", "Mistrz snookera"),
            t("allmodes", "Wszechstronny", "Wygraj we wszystkich 5 trybach", 2, "square.grid.3x3.fill", 5) { $0.winsByMode.values.filter { $0 > 0 }.count },
            t("l0", "Pogromca Amatora", "Pokonaj komputer na poziomie Amator", 0, "desktopcomputer", 1) { $0.winsByLevel["0"] ?? 0 },
            t("l1", "Pogromca Klubowicza", "Pokonaj komputer na poziomie Klubowicz", 1, "desktopcomputer", 1) { $0.winsByLevel["1"] ?? 0 },
            t("l2", "Pogromca Mistrza", "Pokonaj komputer na poziomie Mistrz", 2, "desktopcomputer", 1) { $0.winsByLevel["2"] ?? 0 },
            t("s10", "Seria 10", "Wbij 10 bil z rzędu bez pudła", 1, "flame.fill", 10) { $0.bestStreak },
            t("s20", "Seria 20", "Wbij 20 bil z rzędu bez pudła", 2, "flame.fill", 20) { $0.bestStreak },
            t("f1", "Czysta gra", "Wygraj partię bez faulu", 1, "checkmark.seal.fill", 1) { $0.flawless },
            t("f10", "Dżentelmen", "Wygraj 10 partii bez faulu", 2, "checkmark.seal.fill", 10) { $0.flawless },
            t("dbl1", "Dublet", "Wbij 2 bile jednym uderzeniem", 0, "bolt.fill", 1) { $0.doubles },
            t("dbl25", "Mistrz dubletów", "Wbij 25 dubletów", 1, "bolt.fill", 25) { $0.doubles },
            t("dd10", "Dzienna rutyna", "Ukończ 10 wyzwań dziennych", 1, "calendar", 10) { $0.dailyDone },
            t("dd50", "Pracowity", "Ukończ 50 wyzwań dziennych", 2, "calendar", 50) { $0.dailyDone },
            t("wd5", "Tygodniowy cel", "Ukończ 5 wyzwań tygodniowych", 1, "calendar.badge.clock", 5) { $0.weeklyDone },
            t("wd20", "Maraton", "Ukończ 20 wyzwań tygodniowych", 2, "calendar.badge.clock", 20) { $0.weeklyDone },
            t("lg7", "Tydzień z kijem", "Graj 7 dni z rzędu", 1, "sunrise.fill", 7) { $0.bestLogin },
            t("lg30", "Miesiąc przy stole", "Graj 30 dni z rzędu", 3, "sun.max.fill", 30) { $0.bestLogin },
            t("t1", "Turniejowy zwycięzca", "Wygraj mecz turniejowy", 1, "trophy.fill", 1) { $0.tourWins },
            t("t10", "Król turniejów", "Wygraj 10 meczów turniejowych", 2, "trophy.fill", 10) { $0.tourWins },
        ]
    }()

    // MARK: okresy i wybór wyzwań
    private static func dayKey(_ d: Date = Date()) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    private static func weekKey(_ d: Date = Date()) -> String {
        let c = Calendar(identifier: .iso8601)
        return "\(c.component(.yearForWeekOfYear, from: d))-W\(c.component(.weekOfYear, from: d))"
    }
    private static func pick(_ pool: [ChallengeDef], key: String, n: Int) -> [ChallengeDef] {
        var h: UInt64 = 5381
        for u in key.unicodeScalars { h = h &* 33 &+ UInt64(u.value) }
        var g = SeededGen(s: h)
        var a = pool
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, Int(g.next() % UInt64(i + 1))) }
        return Array(a.prefix(n))
    }
    var daily: [ChallengeDef] { Self.pick(Self.dailyPool, key: stats.daily.key, n: 3) }
    var weekly: [ChallengeDef] { Self.pick(Self.weeklyPool, key: stats.weekly.key, n: 3) }

    func progress(_ c: ChallengeDef, daily isDaily: Bool) -> Int {
        let p = isDaily ? stats.daily : stats.weekly
        return min(c.goal, c.metric == .modes ? p.modes.count : (p.m[c.metric.rawValue] ?? 0))
    }
    func isDone(_ c: ChallengeDef, daily isDaily: Bool) -> Bool { (isDaily ? stats.daily : stats.weekly).done.contains(c.id) }

    /// czas do odnowienia (tekst)
    func resetText(daily isDaily: Bool) -> String {
        let cal = Calendar.current
        let next: Date
        if isDaily { next = cal.startOfDay(for: Date().addingTimeInterval(86400)) }
        else {
            var iso = Calendar(identifier: .iso8601); iso.timeZone = cal.timeZone
            next = iso.dateInterval(of: .weekOfYear, for: Date())?.end ?? Date().addingTimeInterval(7 * 86400)
        }
        let h = Int(max(0, next.timeIntervalSinceNow) / 3600)
        return h >= 24 ? "odnowi się za \(h / 24) d \(h % 24) h" : "odnowi się za \(h) h"
    }

    // MARK: zapis
    private var url: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bilard", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.appendingPathComponent("challenges.json")
    }
    private init() {
        if ProcessInfo.processInfo.environment["BILARD_NOSAVE"] == nil,
           let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Stats.self, from: d) { stats = s }
        rollover()
    }
    private func save() {
        guard ProcessInfo.processInfo.environment["BILARD_NOSAVE"] == nil else { return }
        if let d = try? JSONEncoder().encode(stats) { try? d.write(to: url, options: .atomic) }
    }

    /// nowy dzień / tydzień: reset okresów, seria dni
    func rollover() {
        let today = Self.dayKey(), week = Self.weekKey()
        var changed = false
        if stats.lastDay != today {
            let y = Self.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
            stats.loginStreak = stats.lastDay == y ? stats.loginStreak + 1 : 1
            stats.bestLogin = max(stats.bestLogin, stats.loginStreak)
            stats.lastDay = today; changed = true
        }
        if stats.daily.key != today { stats.daily = PeriodState(key: today); changed = true }
        if stats.weekly.key != week { stats.weekly = PeriodState(key: week); changed = true }
        if changed { save(); evaluate() }
    }

    // MARK: zdarzenia z gry
    func gameStart() { gameFouls = 0; streakCur = 0; rollover() }

    func shot(pots: Int, foul: Bool, human: Bool) {
        guard human else { return }
        rollover()
        if foul { gameFouls += 1 }
        if pots > 0 { streakCur += pots } else { streakCur = 0 }
        stats.pots += pots
        stats.bestStreak = max(stats.bestStreak, streakCur)
        bump(.pots, pots); bumpMax(.streak, streakCur)
        if pots >= 2 { stats.doubles += 1; bump(.doubles) }
        evaluate()
    }

    func gameEnd(humanWon: Bool, vsAI: Bool, level: Int, mode: GameMode, tournament: Bool) {
        rollover()
        stats.games += 1; bump(.games)
        if humanWon {
            stats.wins += 1; bump(.wins)
            stats.winsByMode[mode.rawValue, default: 0] += 1
            if !stats.daily.modes.contains(mode.rawValue) { stats.daily.modes.append(mode.rawValue) }
            if !stats.weekly.modes.contains(mode.rawValue) { stats.weekly.modes.append(mode.rawValue) }
            if mode == .nine { bump(.winsNine) }
            if vsAI {
                stats.winsAI += 1; bump(.winsAI)
                stats.winsByLevel[String(level), default: 0] += 1
                if level >= 1 { bump(.winsClub) }
                if level >= 2 { bump(.winsMaster) }
            }
            if gameFouls == 0 { stats.flawless += 1; bump(.flawless) }
            if tournament { stats.tourWins += 1 }
        }
        evaluate()
    }

    private func bump(_ m: Metric, _ n: Int = 1) {
        stats.daily.m[m.rawValue, default: 0] += n
        stats.weekly.m[m.rawValue, default: 0] += n
    }
    private func bumpMax(_ m: Metric, _ v: Int) {
        stats.daily.m[m.rawValue] = max(stats.daily.m[m.rawValue] ?? 0, v)
        stats.weekly.m[m.rawValue] = max(stats.weekly.m[m.rawValue] ?? 0, v)
    }

    private func evaluate() {
        for (isDaily, list) in [(true, daily), (false, weekly)] {
            for c in list where !isDone(c, daily: isDaily) && progress(c, daily: isDaily) >= c.goal {
                if isDaily { stats.daily.done.append(c.id); stats.dailyDone += 1 } else { stats.weekly.done.append(c.id); stats.weeklyDone += 1 }
                stats.xp += c.xp
                toast(ToastItem(title: "Wyzwanie ukończone", sub: "\(c.title) · +\(c.xp) XP", symbol: "checkmark.circle.fill"))
            }
        }
        for t in Self.trophies where stats.trophies[t.id] == nil && t.value(stats) >= t.goal {
            stats.trophies[t.id] = Self.dayKey()
            stats.xp += t.xp
            toast(ToastItem(title: "Nowe trofeum: \(t.name)", sub: "\(t.tierName) · +\(t.xp) XP", symbol: t.symbol))
        }
        save()
        objectWillChange.send()
    }

    private func toast(_ t: ToastItem) { DispatchQueue.main.async { self.onToast(t) } }

    var level: Int { 1 + stats.xp / 300 }
    var levelProgress: Double { Double(stats.xp % 300) / 300 }
}

// MARK: - Powiadomienie (toast) o osiągnięciu

struct AchievementToast: View {
    let t: ToastItem
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: t.symbol).font(.system(size: 20, weight: .semibold)).foregroundColor(UI.menuAccent)
                .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 13, weight: .bold)).foregroundColor(UI.text)
                Text(t.sub).font(.system(size: 11)).foregroundColor(UI.dim)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .panel(14, tint: 0.35)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - Zakładka „Wyzwania” w menu

struct ChallengesTab: View {
    @ObservedObject var c = Challenges.shared

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                header
                section("Dzienne", daily: true, list: c.daily)
                section("Tygodniowe", daily: false, list: c.weekly)
                Spacer(minLength: 0)
            }.frame(width: 360)
            VStack(alignment: .leading, spacing: 8) {
                Caps("Trofea  \(c.stats.trophies.count) / \(Challenges.trophies.count)", size: 9)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Challenges.trophies) { t in tile(t) }
                }
                Text("Najedź na trofeum, by zobaczyć opis. Kolory: brąz, srebro, złoto, platyna.")
                    .font(.system(size: 9.5)).foregroundColor(UI.faint)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity)
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Poziom \(c.level)").font(.system(size: 15, weight: .bold)).foregroundColor(UI.text)
                Spacer()
                Label("seria dni: \(c.stats.loginStreak)", systemImage: "flame.fill").font(.system(size: 10.5)).foregroundColor(UI.dim)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(UI.menuAccent).frame(width: 360 * max(0.02, c.levelProgress))
            }.frame(width: 360, height: 5)
            Text("\(c.stats.xp) XP · wygrane \(c.stats.wins) · wbite bile \(c.stats.pots)").font(.system(size: 10)).foregroundColor(UI.faint)
        }
    }

    func section(_ title: String, daily: Bool, list: [ChallengeDef]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Caps(title, size: 9); Spacer(); Text(c.resetText(daily: daily)).font(.system(size: 9.5)).foregroundColor(UI.faint) }
            ForEach(list) { ch in row(ch, daily: daily) }
        }
    }

    func row(_ ch: ChallengeDef, daily: Bool) -> some View {
        let p = c.progress(ch, daily: daily), done = c.isDone(ch, daily: daily)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 12)).foregroundColor(done ? UI.menuAccent : UI.faint)
                Text(ch.title).font(.system(size: 11.5, weight: .medium)).foregroundColor(done ? UI.dim : UI.text)
                Spacer()
                Text("\(p)/\(ch.goal)").font(.system(size: 10.5, design: .rounded).monospacedDigit()).foregroundColor(UI.dim)
                Text("+\(ch.xp)").font(.system(size: 10, weight: .bold)).foregroundColor(UI.menuAccent)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(done ? UI.menuAccent : UI.menuAccent.opacity(0.7)).frame(width: 336 * Double(p) / Double(max(1, ch.goal)))
            }.frame(width: 336, height: 3.5)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(done ? 0.03 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(done ? 0.12 : 0.22), lineWidth: 1))
    }

    func tile(_ t: TrophyDef) -> some View {
        let got = c.stats.trophies[t.id] != nil
        let v = min(t.goal, t.value(c.stats))
        return VStack(spacing: 2) {
            Image(systemName: got ? t.symbol : "lock.fill").font(.system(size: 19, weight: .semibold))
                .foregroundColor(got ? t.color : Color.white.opacity(0.22))
            Text(got ? t.name : "\(v)/\(t.goal)").font(.system(size: 7.5)).foregroundColor(got ? UI.dim : UI.faint).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity).frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 8).fill(got ? t.color.opacity(0.12) : Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(got ? t.color.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
        .help("\(t.name) (\(t.tierName)) — \(t.desc)\(got ? "" : " · \(v)/\(t.goal)")")
    }
}
