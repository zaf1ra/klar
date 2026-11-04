import Foundation
import Observation
import WebKit

/// Sammelt alles, was im Kontrollzentrum angezeigt wird.
@MainActor
@Observable
final class HealthMonitor {
    enum Level: Int, Comparable {
        case ok, info, warning, error
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    struct Item: Identifiable {
        let id: String
        let level: Level
        let title: String
        let detail: String
        var fix: Fix?
        /// Gesetzt, wenn die Meldung im Kontrollzentrum weggewischt werden kann.
        var dismissal: Dismissal?
    }

    enum Fix { case reloadRules, openGitHubHelp }

    enum Dismissal {
        case issue(site: String, message: String)
        case probe(site: String, probe: String)
    }

    /// Meldung als erledigt markieren. Tritt das Problem erneut auf, erscheint sie wieder.
    func dismiss(_ dismissal: Dismissal) {
        switch dismissal {
        case let .issue(site, message):
            issues[site]?.removeAll { $0 == message }
        case let .probe(site, probe):
            probeMax[site]?[probe] = nil
            probeRuns[site]?[probe] = nil
        }
    }

    private weak var rules: RuleStore?

    var adBlockerDomains = 0
    var adBlockerError: String?
    private(set) var loggedIn: [String: Bool] = [:]
    private(set) var hiddenToday = 0
    private(set) var blockedToday = 0
    private(set) var signingExpiry: Date?
    private(set) var isSimulator = false
    /// Höchster Probe-Wert und Anzahl der Messungen je Website und Probe.
    private var probeMax: [String: [String: Int]] = [:]
    private var probeRuns: [String: [String: Int]] = [:]
    private(set) var issues: [String: [String]] = [:]

    func attach(rules: RuleStore) { self.rules = rules }

    // MARK: Meldungen aus den Seiten

    func recordProbe(site: SiteRules, results: [String: Int], visible: [String: Int]) {
        for (id, count) in results {
            probeMax[site.id, default: [:]][id] = max(probeMax[site.id]?[id] ?? 0, count)
            probeRuns[site.id, default: [:]][id, default: 0] += 1
        }
        for (id, count) in visible where count > 0 {
            guard let probe = site.probes.first(where: { $0.id == id }), probe.expectHidden else { continue }
            recordIssue(site: site.id, "„\(probe.label)“ ist trotz Filter sichtbar (\(count)×). Regel muss angepasst werden.")
        }
    }

    func recordHidden(rule: String) { hiddenToday += 1 }
    func recordBlocked(site: String) { blockedToday += 1 }

    func recordIssue(site: String, _ message: String) {
        var list = issues[site, default: []]
        guard !list.contains(message) else { return }
        list.append(message)
        issues[site] = Array(list.suffix(5))
    }

    func checkLogin(site: SiteRules) async {
        // Ohne bekanntes Login-Cookie lässt sich der Status nicht prüfen.
        guard !site.loginCookie.isEmpty else { return }
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let host = site.allowedHosts.first ?? ""
        loggedIn[site.id] = cookies.contains { $0.name == site.loginCookie && $0.domain.hasSuffix(host) }
    }

    // MARK: Prüfungen beim Start

    func runChecks() async {
        #if targetEnvironment(simulator)
        isSimulator = true
        #endif
        signingExpiry = Self.readSigningExpiry()
        for site in rules?.rules.sites ?? [] { await checkLogin(site: site) }
    }

    /// Ablaufdatum der Signatur aus embedded.mobileprovision (kostenloses Konto: 7 Tage).
    private static func readSigningExpiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<?xml"),
              let end = raw.range(of: "</plist>") else { return nil }
        let plistString = String(raw[start.lowerBound..<end.upperBound])
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(plistString.utf8), format: nil) as? [String: Any] else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    // MARK: Ergebnis fürs Kontrollzentrum

    var items: [Item] {
        var result: [Item] = []
        guard let store = rules else { return result }

        for site in store.rules.sites {
            let isLoggedIn = loggedIn[site.id] ?? false
            if !site.loginCookie.isEmpty {
                result.append(isLoggedIn
                    ? Item(id: "\(site.id)-login", level: .ok, title: "\(site.name): eingeloggt", detail: "Alles bereit")
                    : Item(id: "\(site.id)-login", level: .info, title: "\(site.name): nicht eingeloggt", detail: "Öffne \(site.name) und melde dich an."))
            }

            for probe in site.probes {
                let runs = probeRuns[site.id]?[probe.id] ?? 0
                guard runs >= 2, !probe.requiresLogin || isLoggedIn else { continue }
                if (probeMax[site.id]?[probe.id] ?? 0) == 0 {
                    result.append(Item(
                        id: "\(site.id)-\(probe.id)", level: .error,
                        title: "\(site.name): Filter findet „\(probe.label)“ nicht",
                        detail: "Die Seite hat sich wahrscheinlich geändert. Neue Regeln laden oder auf GitHub anpassen.",
                        fix: .reloadRules, dismissal: .probe(site: site.id, probe: probe.id)))
                }
            }

            for message in issues[site.id] ?? [] {
                result.append(Item(id: "\(site.id)-\(message)", level: .warning, title: site.name, detail: message,
                                   dismissal: .issue(site: site.id, message: message)))
            }
        }

        let age = store.lastFetch.map { Date().timeIntervalSince($0) / 86_400 }
        if !Config.remoteRulesConfigured {
            result.append(Item(id: "rules-remote", level: .warning, title: "Automatische Regel-Updates aus",
                               detail: "Trage deinen GitHub-Namen in Config.swift ein.", fix: .openGitHubHelp))
        } else if let error = store.lastFetchError {
            result.append(Item(id: "rules-remote", level: .warning, title: "Regeln konnten nicht geladen werden",
                               detail: error, fix: .reloadRules))
        } else if let age, age > 3 {
            result.append(Item(id: "rules-remote", level: .warning, title: "Regeln seit \(Int(age)) Tagen nicht geprüft",
                               detail: "Slop ist offline oder GitHub nicht erreichbar.", fix: .reloadRules))
        }
        result.append(Item(id: "rules-version", level: .ok, title: "Filterregeln v\(store.rules.version)",
                           detail: "Stand \(store.rules.updated), Quelle: \(store.source.rawValue)"))

        if let adBlockerError {
            result.append(Item(id: "ads", level: .error, title: "Werbeblocker aus", detail: adBlockerError))
        } else if adBlockerDomains > 0 {
            result.append(Item(id: "ads", level: .ok, title: "Werbeblocker aktiv",
                               detail: "\(adBlockerDomains) Werbe-Domains gesperrt, \(hiddenToday) Elemente ausgeblendet"))
        }

        if isSimulator {
            result.append(Item(id: "signing", level: .info, title: "Simulator", detail: "Keine Signatur nötig"))
        } else if let expiry = signingExpiry {
            let days = Int(ceil(expiry.timeIntervalSinceNow / 86_400))
            result.append(Item(
                id: "signing", level: days <= 2 ? (days <= 0 ? .error : .warning) : .ok,
                title: days > 0 ? "App läuft in \(days) Tagen ab" : "App-Signatur abgelaufen",
                detail: "Mit Xcode neu installieren, um weitere 7 Tage zu bekommen."))
        }

        return result.sorted { $0.level > $1.level }
    }

    var problemCount: Int { items.filter { $0.level >= .warning }.count }
}
