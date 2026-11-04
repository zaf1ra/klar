import SwiftUI
import WebKit

/// Steuert die WebView von außen (eigene Leiste unten): laden, Knöpfe der Seite anklicken,
/// aktuellen Pfad kennen.
@MainActor
@Observable
final class WebController {
    @ObservationIgnored weak var webView: WKWebView?
    /// Pfad der aktuell angezeigten Seite, auch bei Seitenwechseln ohne Neuladen.
    var path = "/"

    func load(_ url: URL) {
        #if DEBUG
        NSLog("[Klar] load %@", url.absoluteString)
        #endif
        webView?.load(URLRequest(url: url))
    }

    /// Klickt den ersten gefundenen Knopf der Seite an. false, wenn keiner gefunden wurde.
    func click(_ selectors: [String]) async -> Bool {
        guard let webView else { return false }
        let result = try? await webView.callAsyncJavaScript(
            "return window.__klarClick ? window.__klarClick(selectors) : false",
            arguments: ["selectors": selectors], in: nil, contentWorld: .page)
        return result as? Bool ?? false
    }
}

/// Ein WKWebView, der eine Seite (Instagram, YouTube ...) mit den Slop-Filtern lädt.
struct LiteWebView: UIViewRepresentable {
    let site: SiteRules
    let adDomains: [String]
    let health: HealthMonitor
    let controller: WebController

    func makeCoordinator() -> Coordinator {
        Coordinator(site: site, health: health, controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Nichts startet von selbst: Videos laufen erst, wenn du tippst.
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.websiteDataStore = .default()
        let desktop = site.desktopMode == true
        config.defaultWebpagePreferences.preferredContentMode = desktop ? .desktop : .mobile

        let userContent = config.userContentController
        userContent.add(context.coordinator, name: "klar")
        userContent.addUserScript(WKUserScript(
            source: Self.makeScript(for: site),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = desktop ? Config.desktopUserAgent : Config.userAgent
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Nach unten ziehen lädt neu (ersetzt den früheren Neu-laden-Knopf).
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.reload), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        controller.webView = webView
        context.coordinator.observe(webView)

        var start = site.home
        #if DEBUG
        // Zum Testen: Start mit -klarStartURL <url> öffnet direkt diese Seite.
        if let debugURL = UserDefaults.standard.string(forKey: "klarStartURL"),
           site.allowedHosts.contains(where: { debugURL.contains($0) }) {
            start = debugURL
        }
        #endif
        AdBlocker.ruleList(for: adDomains, health: health) { list in
            if let list { userContent.add(list) }
            if let url = URL(string: start) { webView.load(URLRequest(url: url)) }
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "klar")
    }

    static func makeScript(for site: SiteRules) -> String {
        let rulesJSON = (try? String(data: JSONEncoder().encode(site), encoding: .utf8)) ?? "{}"
        let filter = Bundle.main.url(forResource: "filter", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return "window.__klarRules = \(rulesJSON);\n\(filter)"
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let site: SiteRules
        let health: HealthMonitor
        let controller: WebController
        private var urlObservation: NSKeyValueObservation?

        init(site: SiteRules, health: HealthMonitor, controller: WebController) {
            self.site = site
            self.health = health
            self.controller = controller
        }

        func observe(_ webView: WKWebView) {
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                let path = webView.url?.path ?? "/"
                #if DEBUG
                NSLog("[Klar] url %@", webView.url?.absoluteString ?? "-")
                #endif
                Task { @MainActor in self?.controller.path = path.isEmpty ? "/" : path }
            }
        }

        @objc func reload() {
            controller.webView?.reload()
        }

        func userContentController(_ userContent: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            #if DEBUG
            NSLog("[Klar] %@: %@", site.id, String(describing: body))
            #endif
            switch type {
            case "probe":
                let results = body["results"] as? [String: Int] ?? [:]
                let visible = body["visible"] as? [String: Int] ?? [:]
                health.recordProbe(site: site, results: results, visible: visible)
            case "hidden":
                health.recordHidden(rule: body["rule"] as? String ?? "?")
            case "blocked":
                health.recordBlocked(site: site.id)
            case "jsError":
                health.recordIssue(site: site.id, "JavaScript-Fehler: \(body["message"] as? String ?? "?")")
            case "badSelector":
                health.recordIssue(site: site.id, "Ungültige Filterregel: \(body["selector"] as? String ?? "?")")
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            // App-Links wie instagram:// würden die echte App öffnen.
            guard url.scheme == "https" || url.scheme == "http" || url.scheme == "about" || url.scheme == "blob" else {
                return decisionHandler(.cancel)
            }
            let isMainFrame = action.targetFrame?.isMainFrame ?? true
            if isMainFrame, let host = url.host, !site.allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                UIApplication.shared.open(url)
                return decisionHandler(.cancel)
            }
            // Zweite Sperre neben filter.js: greift schon, bevor die Seite lädt.
            if isMainFrame, site.blockedPaths.contains(where: { url.path.range(of: $0, options: .regularExpression) != nil }) {
                health.recordBlocked(site: site.id)
                decisionHandler(.cancel)
                if let home = URL(string: site.home) { webView.load(URLRequest(url: home)) }
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            Task { await health.checkLogin(site: site) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            if (error as NSError).code == NSURLErrorCancelled { return }
            health.recordIssue(site: site.id, "Seite lädt nicht: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            if (error as NSError).code == NSURLErrorCancelled { return }
            health.recordIssue(site: site.id, "Seite lädt nicht: \(error.localizedDescription)")
        }
    }
}

/// Werbung blocken über WebKits eingebaute Inhaltsregeln (gleiche Technik wie Safari-Werbeblocker).
@MainActor
enum AdBlocker {
    private static var cached: (domains: [String], list: WKContentRuleList)?

    static func ruleList(for domains: [String], health: HealthMonitor, completion: @escaping (WKContentRuleList?) -> Void) {
        if let cached, cached.domains == domains { return completion(cached.list) }
        let rules = domains.map { domain -> [String: Any] in
            let escaped = NSRegularExpression.escapedPattern(for: domain)
            return ["trigger": ["url-filter": "^https?://([^/]+\\.)?\(escaped)[:/]"], "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return completion(nil) }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "klar-ads", encodedContentRuleList: json) { list, error in
            Task { @MainActor in
                if let list {
                    cached = (domains, list)
                    health.adBlockerDomains = domains.count
                    health.adBlockerError = nil
                } else {
                    health.adBlockerError = error?.localizedDescription ?? "Unbekannter Fehler"
                }
                completion(list)
            }
        }
    }
}
