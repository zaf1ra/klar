import Foundation
import Observation

/// Lädt die Filterregeln: zuerst Cache oder mitgelieferte Datei, dann neuere Version von GitHub.
@MainActor
@Observable
final class RuleStore {
    enum Source: String { case bundled = "mitgeliefert", cached = "gespeichert", remote = "GitHub" }

    private(set) var rules: Rules
    private(set) var source: Source
    private(set) var lastFetch: Date?
    private(set) var lastFetchError: String?

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("rules.json")
    }

    init() {
        let bundled = Self.loadBundled()
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cached = try? JSONDecoder().decode(Rules.self, from: data),
           cached.version >= bundled.version {
            rules = cached
            source = .cached
        } else {
            rules = bundled
            source = .bundled
        }
        lastFetch = UserDefaults.standard.object(forKey: "rules.lastFetch") as? Date
    }

    func site(_ id: String) -> SiteRules? { rules.sites.first { $0.id == id } }

    func refreshFromRemote() async {
        guard Config.remoteRulesConfigured, let url = URL(string: Config.remoteRulesURL) else {
            lastFetchError = "Kein GitHub-Repo eingetragen"
            return
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let remote = try JSONDecoder().decode(Rules.self, from: data)
            lastFetch = Date()
            lastFetchError = nil
            UserDefaults.standard.set(lastFetch, forKey: "rules.lastFetch")
            if remote.version > rules.version {
                rules = remote
                source = .remote
                try? data.write(to: Self.cacheURL)
            }
        } catch {
            lastFetchError = error.localizedDescription
        }
    }

    private static func loadBundled() -> Rules {
        guard let url = Bundle.main.url(forResource: "rules", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rules = try? JSONDecoder().decode(Rules.self, from: data) else {
            return Rules(version: 0, updated: "-", adDomains: [], sites: [])
        }
        return rules
    }
}
