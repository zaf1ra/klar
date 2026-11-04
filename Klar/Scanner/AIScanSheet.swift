import SwiftUI
import UIKit

/// Ergebnis des KI-Scanners als Blatt über der Seite.
struct AIScanSheet: View {
    let scanner: AIScanner
    let rescan: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch scanner.state {
                    case .idle, .scanning:
                        scanning
                    case let .done(result):
                        resultView(result)
                    case let .failed(message):
                        failed(message)
                    }
                }
                .padding(20)
                .animation(.smooth(duration: 0.35), value: scanner.state)
            }
            .navigationTitle("KI-Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { rescan() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Erneut prüfen")
                        .disabled(isScanning)
                }
            }
        }
    }

    private var isScanning: Bool {
        if case .scanning = scanner.state { return true }
        return false
    }

    // MARK: Zustände

    private var scanning: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 44, weight: .light))
                .symbolEffect(.pulse, options: .repeating)
            if case let .scanning(step) = scanner.state {
                Text(step)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func failed(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func resultView(_ result: AIScanner.Result) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            verdictCard(result)

            if result.generator != nil || result.prompt != nil || result.model != nil {
                card("Aus den Metadaten") {
                    if let generator = result.generator { detailRow("KI", generator) }
                    if let model = result.model { detailRow("Modell", model) }
                    if let prompt = result.prompt { detailRow("Prompt", prompt, copyable: true) }
                    if let negative = result.negativePrompt { detailRow("Negativ-Prompt", negative, copyable: true) }
                    if let settings = result.settings { detailRow("Einstellungen", settings) }
                }
            }

            if !result.findings.isEmpty {
                card("Gefunden") {
                    ForEach(result.findings) { finding in
                        detailRow(finding.title, finding.detail)
                    }
                }
            }

            card("Geprüft") {
                ForEach(result.checked, id: \.self) { item in
                    Label(item, systemImage: "checkmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Instagram, YouTube und Co. entfernen beim Hochladen meist die Metadaten. Unsichtbare Wasserzeichen wie Googles SynthID kann nur der Hersteller selbst prüfen. „Keine KI-Merkmale“ heißt deshalb nicht, dass etwas echt ist.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func verdictCard(_ result: AIScanner.Result) -> some View {
        let (icon, tint): (String, Color) = switch result.verdict {
        case .ai: ("cpu", .red)
        case .hints: ("questionmark.circle", .orange)
        case .noSigns: ("checkmark.seal", .green)
        }
        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: result.headline)
            VStack(alignment: .leading, spacing: 3) {
                Text(result.headline).font(.headline)
                Text(subtitle(result))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func subtitle(_ result: AIScanner.Result) -> String {
        switch result.verdict {
        case .ai: "Belegt durch Kennzeichnung oder Dateidaten."
        case .hints: "Kein Beleg, nur Hinweise im Beitrag."
        case .noSigns: result.imageCount == 0 && !result.hasVideo
            ? "Kein Bild oder Video in der Bildschirmmitte gefunden."
            : "Weder Kennzeichnung noch KI-Daten in der Datei."
        }
    }

    // MARK: Bausteine

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold).width(.expanded))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func detailRow(_ title: String, _ value: String, copyable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
            if copyable {
                Button("Kopieren") { UIPasteboard.general.string = value }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.borderless)
            }
        }
    }
}
