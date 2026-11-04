import Foundation
import Observation
import WebKit

/// Prüft den Beitrag, der gerade in der Bildschirmmitte zu sehen ist, auf KI.
/// Quellen: KI-Kennzeichnung der Plattform, Metadaten der Bilddateien, Hashtags.
@MainActor
@Observable
final class AIScanner {
    enum Verdict: Equatable {
        /// Eindeutig als KI gekennzeichnet (Plattform oder Datei).
        case ai
        /// Es gibt Hinweise, aber keinen Beleg (z. B. #aiart).
        case hints
        /// Nichts gefunden. Heißt nicht, dass es echt ist.
        case noSigns
    }

    struct Finding: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let detail: String
    }

    struct Result: Equatable {
        var verdict: Verdict
        var headline: String
        var findings: [Finding]
        var generator: String?
        var prompt: String?
        var negativePrompt: String?
        var model: String?
        var settings: String?
        var checked: [String]
        var imageCount: Int
        var hasVideo: Bool
    }

    enum State: Equatable {
        case idle
        case scanning(String)
        case done(Result)
        case failed(String)
    }

    private(set) var state: State = .idle

    func reset() { state = .idle }

    func scan(_ webView: WKWebView?) async {
        guard let webView else { return state = .failed("Keine Seite geöffnet.") }
        state = .scanning("Beitrag wird gesucht …")

        let raw: Any?
        do {
            raw = try await webView.callAsyncJavaScript(
                "return window.__klarScan ? window.__klarScan() : null", arguments: [:], in: nil, contentWorld: .page)
        } catch {
            return state = .failed("Die Seite lässt sich gerade nicht lesen.")
        }
        guard let page = raw as? [String: Any] else {
            return state = .failed("Auf dieser Seite gibt es nichts zu prüfen. Öffne einen Beitrag und versuche es erneut.")
        }

        let labels = page["labels"] as? [String] ?? []
        let hashtags = page["hashtags"] as? [String] ?? []
        let hasVideo = page["hasVideo"] as? Bool ?? false
        let images = (page["images"] as? [[String: Any]] ?? []).compactMap { $0["src"] as? String }.compactMap(URL.init(string:))

        // Bilddateien laden und ihre Metadaten lesen.
        var reports: [MetadataReport] = []
        for (index, url) in images.enumerated() {
            state = .scanning(images.count > 1 ? "Bild \(index + 1) von \(images.count) wird geprüft …" : "Bild wird geprüft …")
            if let data = await download(url) { reports.append(MetadataInspector.inspect(data)) }
        }

        state = .done(evaluate(labels: labels, hashtags: hashtags, reports: reports,
                               imageCount: images.count, hasVideo: hasVideo))
    }

    private func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 30_000_000 else { return nil }
        return data
    }

    private func evaluate(labels: [String], hashtags: [String], reports: [MetadataReport],
                          imageCount: Int, hasVideo: Bool) -> Result {
        var findings: [Finding] = []
        let aiReport = reports.first { $0.isAI }
        let detailReport = aiReport ?? reports.first { $0.generator != nil || $0.prompt != nil }

        if !labels.isEmpty {
            findings.append(Finding(title: "Kennzeichnung der Plattform",
                                    detail: "Die Plattform markiert den Beitrag als KI: „\(labels.joined(separator: "“, „"))“."))
        }
        for report in reports {
            if report.hasContentCredentials {
                findings.append(Finding(title: "Content Credentials (C2PA)",
                                        detail: report.notes.first { $0.contains("Content Credentials") }
                                            ?? "Die Datei enthält fälschungssichere Herkunftsdaten."))
            }
            for note in report.notes where !note.contains("Content Credentials") {
                findings.append(Finding(title: "Metadaten", detail: note))
            }
            if let camera = report.camera {
                findings.append(Finding(title: "Kameradaten", detail: "Aufgenommen mit \(camera). Ein Hinweis auf ein echtes Foto, aber kein Beweis."))
            }
            if let software = report.software, report.generator == nil {
                findings.append(Finding(title: "Software", detail: software))
            }
        }
        if !hashtags.isEmpty {
            findings.append(Finding(title: "Hashtags",
                                    detail: "Der Beitrag nutzt KI-Hashtags: \(hashtags.joined(separator: " "))."))
        }

        let verdict: Verdict
        let headline: String
        if !labels.isEmpty || aiReport != nil {
            verdict = .ai
            if let generator = detailReport?.generator {
                headline = "KI-generiert mit \(generator)"
            } else {
                headline = "Als KI-generiert gekennzeichnet"
            }
        } else if !hashtags.isEmpty {
            verdict = .hints
            headline = "Hinweise auf KI"
        } else {
            verdict = .noSigns
            headline = "Keine KI-Merkmale gefunden"
        }

        var checked = ["Kennzeichnungen der Plattform im Beitrag"]
        checked.append(imageCount == 0
            ? "Keine Bilddatei im Beitrag gefunden"
            : "\(imageCount) Bilddatei\(imageCount == 1 ? "" : "en") auf Content Credentials, IPTC- und Generator-Daten")
        checked.append("Hashtags und Beschreibung")
        if hasVideo { checked.append("Videos lassen sich nur über die Kennzeichnung der Plattform prüfen") }

        return Result(verdict: verdict, headline: headline, findings: findings,
                      generator: detailReport?.generator, prompt: detailReport?.prompt,
                      negativePrompt: detailReport?.negativePrompt, model: detailReport?.model,
                      settings: detailReport?.settings, checked: checked,
                      imageCount: imageCount, hasVideo: hasVideo)
    }
}
