import Foundation
import Observation

/// XP, Level und Streak. Belohnt wird Zeit ohne Social Media: +10 XP pro volle Stunde,
/// in der keine Seite in Slop offen war. Der Streak zählt Tage unter dem Tagesziel.
@MainActor
@Observable
final class ProgressStore {
    private(set) var xp: Int
    /// Sekunden in Slop-Ansichten pro Tag, Schlüssel "yyyy-MM-dd".
    private(set) var usage: [String: Double]
    private let installDate: Date
    private(set) var lastReward: String?
    /// Beginn der aktuellen Zeit ohne Social Media. Volle Stunden ab hier geben XP.
    private var awayClock: Date
    private(set) var inSession = false

    private let defaults = UserDefaults.standard
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let defaults = UserDefaults.standard
        xp = defaults.integer(forKey: "progress.xp")
        usage = defaults.dictionary(forKey: "progress.usage") as? [String: Double] ?? [:]
        if let date = defaults.object(forKey: "progress.installDate") as? Date {
            installDate = date
        } else {
            installDate = Calendar.current.startOfDay(for: Date())
            defaults.set(installDate, forKey: "progress.installDate")
        }
        if let clock = defaults.object(forKey: "progress.awayClock") as? Date {
            awayClock = clock
        } else {
            awayClock = Date()
            defaults.set(awayClock, forKey: "progress.awayClock")
        }
    }

    var level: Int { xp / 200 + 1 }
    var xpInLevel: Int { xp % 200 }
    var todayMinutes: Int { Int((usage[Self.key(Date())] ?? 0) / 60) }

    /// Minuten bis zu den nächsten +10 XP.
    func minutesToNextReward(at now: Date) -> Int {
        let elapsed = max(0, now.timeIntervalSince(awayClock)).truncatingRemainder(dividingBy: 3600)
        return max(1, Int(ceil((3600 - elapsed) / 60)))
    }

    /// Tage in Folge (bis heute) unter dem Tagesziel, frühestens ab Installation.
    var streak: Int {
        let goal = Double(Config.dailyGoalMinutes * 60)
        var count = 0
        var day = Calendar.current.startOfDay(for: Date())
        while day >= installDate {
            if (usage[Self.key(day)] ?? 0) > goal { break }
            count += 1
            guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// Schreibt XP für alle vollen Stunden ohne Social Media gut. Beim Öffnen der App und jede Minute aufrufen.
    func accrueAwayTime() {
        guard !inSession else { return }
        let hours = Int(Date().timeIntervalSince(awayClock) / 3600)
        guard hours > 0 else { return }
        xp += hours * 10
        awayClock = awayClock.addingTimeInterval(Double(hours) * 3600)
        lastReward = hours == 1
            ? "+10 XP für eine Stunde ohne Social Media"
            : "+\(hours * 10) XP für \(hours) Stunden ohne Social Media"
        defaults.set(xp, forKey: "progress.xp")
        defaults.set(awayClock, forKey: "progress.awayClock")
    }

    func beginSession() {
        accrueAwayTime()
        inSession = true
        sessionHeartbeat()
    }

    /// Während einer Sitzung jede Minute aufrufen. Wird die App mitten in einer Sitzung beendet,
    /// zählt die Zeit ohne Social Media trotzdem erst ab der letzten Minute in der Sitzung.
    func sessionHeartbeat() {
        awayClock = Date()
        defaults.set(awayClock, forKey: "progress.awayClock")
    }

    func endSession(startedAt: Date) {
        inSession = false
        sessionHeartbeat()
        let seconds = Date().timeIntervalSince(startedAt)
        guard seconds > 5 else { return }
        usage[Self.key(Date()), default: 0] += seconds
        defaults.set(usage, forKey: "progress.usage")
    }

    func clearReward() { lastReward = nil }

    private static func key(_ date: Date) -> String { formatter.string(from: date) }
}
