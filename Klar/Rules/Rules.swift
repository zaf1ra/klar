import Foundation

/// Spiegelt rules.json. Die gleiche Datei wird mitgeliefert und von GitHub nachgeladen.
struct Rules: Codable, Equatable {
    var version: Int
    var updated: String
    var adDomains: [String]
    var sites: [SiteRules]
}

struct SiteRules: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var home: String
    /// Hosts, die in Slop geöffnet werden dürfen (inkl. Subdomains). Alles andere geht nach Safari.
    var allowedHosts: [String]
    /// Pfade, die sofort zurück zur Startseite umgeleitet werden (Reels, Shorts, Explore ...).
    var blockedPaths: [String]
    var redirects: [Redirect]
    var hideSelectors: [String]
    /// Ganze Container ausblenden, wenn sie einen Text oder ein Element enthalten (z. B. "Gesponsert").
    var containerRules: [ContainerRule]
    var skipVideoAds: SkipVideoAds?
    /// Elemente, die auf der echten Seite vorhanden sein müssen. Fehlen sie, hat die Seite sich wahrscheinlich geändert.
    var probes: [Probe]
    var loginCookie: String
    var ciCheck: CICheck?
    /// Seite als Desktop-Browser laden (z. B. Snapchat, das mobil nur auf die App verweist).
    var desktopMode: Bool?
    /// Eigene Leiste unten statt der Leiste der Website. Fehlt sie, bleibt die Leiste der Website.
    var tabs: [SiteTab]?
    /// Erkennt die Original-Leiste unten an einem Link darin (z. B. zu den Nachrichten),
    /// um sie auszublenden, wenn `tabs` gesetzt ist.
    var siteBarContains: [String]?
}

/// Ein Knopf in der eigenen Leiste unten. Genau eins von url, search, click oder menu ist gesetzt.
struct SiteTab: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    /// SF-Symbol-Name
    var icon: String
    /// Ziel-Adresse, absolut oder relativ zur Startseite.
    var url: String?
    /// Regex auf den Pfad: Wann ist dieser Knopf aktiv markiert?
    var match: String?
    /// Suchadresse mit Platzhalter {q}. Der Knopf öffnet dann ein Suchfeld.
    var search: String?
    /// CSS-Selektoren eines Knopfs der Website, der angeklickt wird. Der erste gefundene zählt.
    var click: [String]?
    /// Auswahlmenü mit mehreren Aktionen.
    var menu: [TabMenuItem]?
}

struct TabMenuItem: Codable, Equatable {
    var label: String
    var icon: String
    var click: [String]?
    /// Öffnet eine andere App, z. B. instagram://story-camera.
    var appURL: String?
    /// Meldung, wenn die App nicht installiert ist.
    var appMissing: String?
}

struct Redirect: Codable, Equatable {
    var path: String
    var unlessQuery: String?
    var to: String
}

struct ContainerRule: Codable, Equatable {
    var id: String
    var label: String
    var container: String
    var text: [String]?
    var has: String?
}

struct SkipVideoAds: Codable, Equatable {
    var adShowing: String
    var skipButtons: String
}

struct Probe: Codable, Equatable {
    var id: String
    var label: String
    var selector: String
    var path: String
    var requiresLogin: Bool
    /// true: Das Element soll da sein, aber unsichtbar (z. B. Shorts). false: soll sichtbar bleiben (z. B. Beiträge).
    var expectHidden: Bool
}

struct CICheck: Codable, Equatable {
    var url: String
    var cookieEnv: String?
    var cookieName: String?
    var cookieDomain: String?
    var probes: [String]
}
