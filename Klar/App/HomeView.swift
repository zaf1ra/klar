import Combine
import SwiftUI

/// Startseite: Glas auf ruhigem Grund, keine Badges, keine roten Punkte.
struct HomeView: View {
    @Environment(RuleStore.self) private var rules
    @Environment(HealthMonitor.self) private var health
    @Environment(ProgressStore.self) private var progress
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var zoom
    @State private var openSite: SiteRules?
    @State private var showControlCenter = false
    @State private var now = Date()
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statsCard
                if let reward = progress.lastReward {
                    rewardBanner(reward)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                removal: .scale(scale: 0.9).combined(with: .opacity)))
                }
                appsGrid
                controlCenterButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
            .animation(.smooth(duration: 0.4), value: progress.lastReward)
        }
        .scrollIndicators(.hidden)
        .background { SlopBackground() }
        .tint(.primary)
        .fullScreenCover(item: $openSite) { site in
            LiteScreen(site: site)
                .zoomTransition(id: site.id, in: zoom)
        }
        .sheet(isPresented: $showControlCenter) {
            ControlCenterView()
                .presentationDetents([.medium, .large])
        }
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

    // MARK: Bausteine

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.system(size: 12, weight: .semibold).width(.expanded))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text("SLOP")
                .font(.system(size: 64, weight: .black).width(.expanded))
                .tracking(-1.5)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.top, 24)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(progress.todayMinutes)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("von \(Config.dailyGoalMinutes) min")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text("heute mit Social Media")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Pill(text: progress.streak == 1 ? "1 Tag Streak" : "\(progress.streak) Tage Streak", systemImage: "flame")
                Pill(text: "Level \(progress.level)", systemImage: "star")
            }
            .padding(.top, 2)

            XPBar(value: Double(progress.xpInLevel) / 200)
                .padding(.top, 4)
            Text("+10 XP in \(progress.minutesToNextReward(at: now)) min ohne Social Media")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.smooth, value: progress.todayMinutes)
        .animation(.smooth, value: progress.xp)
    }

    private func rewardBanner(_ reward: String) -> some View {
        Button { progress.clearReward() } label: {
            Label(reward, systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
                .symbolEffect(.bounce, value: reward)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(in: Capsule(), interactive: true)
        }
        .buttonStyle(PressableStyle())
    }

    private var appsGrid: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(rules.rules.sites) { site in
                Button { openSite = site } label: {
                    VStack(spacing: 8) {
                        AppIconView(site: site, size: 64)
                            .zoomSource(id: site.id, in: zoom)
                        Text(site.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(site.name)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .glass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var controlCenterButton: some View {
        Button { showControlCenter = true } label: {
            HStack(spacing: 12) {
                Image(systemName: health.problemCount == 0 ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(health.problemCount == 0 ? Color.secondary : Color.orange)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Kontrollzentrum").font(.body.weight(.medium))
                    Text(health.problemCount == 0 ? "Alles ok" : "\(health.problemCount) zu beheben")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glass(in: Capsule(), interactive: true)
        }
        .buttonStyle(PressableStyle())
    }

    private func refresh() {
        withAnimation(.smooth) {
            now = Date()
            progress.accrueAwayTime()
        }
    }
}

private struct Pill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

/// Schlanker XP-Balken, der weich mitwächst.
private struct XPBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.primary)
                    .frame(width: max(6, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }
}
