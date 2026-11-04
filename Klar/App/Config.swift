import Foundation

enum Config {
    /// Ersetze DEIN-GITHUB-NAME durch deinen GitHub-Benutzernamen, sobald das Repo "klar" öffentlich auf GitHub liegt.
    /// Dann lädt Klar neue Filterregeln, ohne dass du die App neu bauen musst.
    static let remoteRulesURL = "https://raw.githubusercontent.com/zaf1ra/klar/main/Klar/Rules/rules.json"

    static var remoteRulesConfigured: Bool { !remoteRulesURL.contains("DEIN-GITHUB-NAME") }

    /// Tagesziel für die Zeit in den Lite-Ansichten. Bleibst du darunter, wächst dein Streak.
    static let dailyGoalMinutes = 30

    /// Sitzungen, die kürzer als das sind, geben XP.
    static let mindfulSessionMinutes = 15

    /// Mobile-Safari-Kennung, damit Instagram und YouTube die volle mobile Webseite ausliefern.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}
