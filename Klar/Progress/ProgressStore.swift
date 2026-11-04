import Foundation
import Observation

/// XP, Level und Streak. Belohnt wird bewusste Nutzung: kurze Sitzungen und Tage unter dem Ziel.
@MainActor
@Observable
final class ProgressStore {
    private(set) var xp: Int
    /// Sekunden in Lite-Ansichten pro Tag, Schlüssel "yyyy-MM-dd".
    private(set) var usage: [String: Double]
    private let installDate: Date
    private(set) var lastReward: String?

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
    }

    var level: Int { xp / 200 + 1 }
    var xpInLevel: Int { xp % 200 }
    var todayMinutes: Int { Int((usage[Self.key(Date())] ?? 0) / 60) }

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

    func endSession(startedAt: Date) {
        let seconds = Date().timeIntervalSince(startedAt)
        guard seconds > 5 else { return }
        let key = Self.key(Date())
        usage[key, default: 0] += seconds
        defaults.set(usage, forKey: "progress.usage")

        if seconds < Double(Config.mindfulSessionMinutes * 60) {
            xp += 10
            lastReward = "+10 XP für eine kurze Sitzung"
        } else {
            lastReward = nil
        }
        defaults.set(xp, forKey: "progress.xp")
    }

    func clearReward() { lastReward = nil }

    private static func key(_ date: Date) -> String { formatter.string(from: date) }
}
