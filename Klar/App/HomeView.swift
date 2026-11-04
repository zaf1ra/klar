import Combine
import SwiftUI

/// Startseite: schlicht, schwarz-weiß, keine Badges.
struct HomeView: View {
    @Environment(RuleStore.self) private var rules
    @Environment(HealthMonitor.self) private var health
    @Environment(ProgressStore.self) private var progress
    @Environment(\.scenePhase) private var scenePhase
    @State private var openSite: SiteRules?
    @State private var showControlCenter = false
    @State private var now = Date()
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(progress.todayMinutes) von \(Config.dailyGoalMinutes) min")
                            .font(.system(size: 34, weight: .medium))
                        Text("heute mit Social Media")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Pill(text: progress.streak == 1 ? "1 Tag Streak" : "\(progress.streak) Tage Streak", systemImage: "flame")
                            Pill(text: "Level \(progress.level)", systemImage: "star")
                        }
                        .padding(.top, 4)
                        ProgressView(value: Double(progress.xpInLevel), total: 200)
                            .tint(.primary)
                            .padding(.top, 4)
                        Text("+10 XP in \(progress.minutesToNextReward(at: now)) min ohne Social Media")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                if let reward = progress.lastReward {
                    Section {
                        Label(reward, systemImage: "sparkles")
                            .onTapGesture { progress.clearReward() }
                    }
                }

                Section {
                    ForEach(rules.rules.sites) { site in
                        Button { openSite = site } label: {
                            Row(title: site.name, systemImage: site.icon)
                        }
                    }
                }

                Section {
                    Button { showControlCenter = true } label: {
                        Row(title: "Kontrollzentrum",
                            systemImage: "stethoscope",
                            trailing: health.problemCount == 0 ? "Alles ok" : "\(health.problemCount) zu beheben")
                    }
                }
            }
            .navigationTitle("Slop")
            .fullScreenCover(item: $openSite) { site in
                LiteScreen(site: site)
            }
            .sheet(isPresented: $showControlCenter) {
                ControlCenterView()
            }
        }
        .tint(.primary)
        .onAppear { refresh() }
        .onReceive(minuteTimer) { _ in refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onChange(of: openSite) { _, site in
            // Nach dem Schließen einer Seite sofort die neue Restzeit zeigen.
            if site == nil { refresh() }
        }
    }

    private func refresh() {
        now = Date()
        progress.accrueAwayTime()
    }
}

private struct Row: View {
    let title: String
    let systemImage: String
    var trailing: String?

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            if let trailing {
                Text(trailing).foregroundStyle(.secondary).font(.subheadline)
            }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.footnote)
        }
        .foregroundStyle(.primary)
    }
}

private struct Pill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(.secondarySystemFill), in: Capsule())
    }
}
