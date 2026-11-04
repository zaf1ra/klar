import SwiftUI

/// Zeigt Fehler, Warnungen und Status der App mit Ampelfarben.
struct ControlCenterView: View {
    @Environment(RuleStore.self) private var rules
    @Environment(HealthMonitor.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var refreshing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        count(.ok, "ok", "ok")
                        count(.warning, "Warnung", "Warnungen")
                        count(.error, "Fehler", "Fehler")
                    }
                }

                Section {
                    ForEach(health.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(item.level))
                                .foregroundStyle(color(item.level))
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(item.detail).font(.footnote).foregroundStyle(.secondary)
                                if let fix = item.fix {
                                    Button(fixLabel(fix)) { perform(fix) }
                                        .font(.footnote.weight(.medium))
                                        .buttonStyle(.borderless)
                                        .padding(.top, 2)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .swipeActions {
                            if let dismissal = item.dismissal {
                                Button("Erledigt") {
                                    withAnimation(.smooth) { health.dismiss(dismissal) }
                                }
                                .tint(.green)
                            }
                        }
                    }
                } footer: {
                    Text("Meldungen nach links wischen, um sie als erledigt zu markieren.")
                }
            }
            .navigationTitle("Kontrollzentrum")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await refresh() } } label: {
                        if refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .accessibilityLabel("Erneut prüfen")
                }
            }
        }
    }

    private func count(_ level: HealthMonitor.Level, _ singular: String, _ plural: String) -> some View {
        let n = health.items.filter { level == .ok ? $0.level <= .info : $0.level == level }.count
        return Text("\(n) \(n == 1 ? singular : plural)")
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(color(level))
            .background(color(level).opacity(0.12), in: Capsule())
    }

    private func refresh() async {
        refreshing = true
        await rules.refreshFromRemote()
        await health.runChecks()
        refreshing = false
    }

    private func perform(_ fix: HealthMonitor.Fix) {
        switch fix {
        case .reloadRules: Task { await refresh() }
        case .openGitHubHelp: openURL(URL(string: "https://github.com/new")!)
        }
    }

    private func fixLabel(_ fix: HealthMonitor.Fix) -> String {
        switch fix {
        case .reloadRules: "Regeln neu laden"
        case .openGitHubHelp: "GitHub-Repo anlegen"
        }
    }

    private func icon(_ level: HealthMonitor.Level) -> String {
        switch level {
        case .ok: "checkmark.circle"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func color(_ level: HealthMonitor.Level) -> Color {
        switch level {
        case .ok: .green
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
