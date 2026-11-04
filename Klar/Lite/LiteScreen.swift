import SwiftUI

/// Vollbild für eine Lite-Seite mit schlichter Leiste oben.
struct LiteScreen: View {
    let site: SiteRules
    @Environment(RuleStore.self) private var rules
    @Environment(HealthMonitor.self) private var health
    @Environment(ProgressStore.self) private var progress
    @Environment(\.dismiss) private var dismiss
    @State private var canGoBack = false
    @State private var startedAt = Date()
    // Neue ID = WebView neu aufbauen (Neu-laden-Knopf).
    @State private var reloadID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Schließen")
                Spacer()
                Text(site.name).font(.headline)
                Spacer()
                Button { reloadID = UUID() } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Neu laden")
            }
            .padding(.horizontal, 6)
            .foregroundStyle(.primary)

            Divider()

            LiteWebView(site: site, adDomains: rules.rules.adDomains, health: health, canGoBack: $canGoBack)
                .id(reloadID)
        }
        .onAppear { startedAt = Date() }
        .onDisappear { progress.endSession(startedAt: startedAt) }
    }
}
