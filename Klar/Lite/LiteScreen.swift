import Combine
import SwiftUI

/// Vollbild für eine Seite in Slop: die Seite selbst, optional eine eigene Leiste unten
/// und ein schwebender Knopf zum Schließen.
struct LiteScreen: View {
    let site: SiteRules
    @Environment(RuleStore.self) private var rules
    @Environment(HealthMonitor.self) private var health
    @Environment(ProgressStore.self) private var progress
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var controller = WebController()
    @State private var startedAt = Date()
    @State private var searchTab: SiteTab?
    @State private var searchText = ""
    @State private var menuTab: SiteTab?
    @State private var notice: String?
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            LiteWebView(site: site, adDomains: rules.rules.adDomains, health: health, controller: controller)
            if let tabs = site.tabs, !tabs.isEmpty {
                TabBar(tabs: tabs, path: controller.path, action: perform)
            }
        }
        .overlay {
            FloatingCloseButton(bottomInset: site.tabs?.isEmpty == false ? 64 : 16) { dismiss() }
        }
        // Die Tastatur legt sich über Leiste und Knopf, statt sie nach oben zu schieben.
        // Die Seite selbst rückt ihre Eingabefelder bei offener Tastatur von allein ins Bild.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .top) {
            if let notice {
                Text(notice)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { self.notice = nil }
            }
        }
        .alert(searchTab?.label ?? "Suchen", isPresented: Binding(
            get: { searchTab != nil }, set: { if !$0 { searchTab = nil } }
        )) {
            TextField("Suchbegriff", text: $searchText)
                .submitLabel(.search)
            Button("Suchen") { runSearch() }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(menuTab?.label ?? "", isPresented: Binding(
            get: { menuTab != nil }, set: { if !$0 { menuTab = nil } }
        ), titleVisibility: .hidden) {
            ForEach(menuTab?.menu ?? [], id: \.label) { item in
                Button(item.label) { perform(item) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .onAppear {
            startedAt = Date()
            progress.beginSession()
        }
        .onReceive(minuteTimer) { _ in progress.sessionHeartbeat() }
        .onDisappear { progress.endSession(startedAt: startedAt) }
    }

    // MARK: Aktionen der eigenen Leiste

    private func perform(_ tab: SiteTab) {
        #if DEBUG
        NSLog("[Klar] tab %@", tab.id)
        #endif
        if tab.menu != nil {
            menuTab = tab
        } else if tab.search != nil {
            searchText = ""
            searchTab = tab
        } else if let selectors = tab.click {
            Task { await click(selectors, label: tab.label) }
        } else if let url = tab.url.flatMap(resolve) {
            controller.load(url)
        }
    }

    private func perform(_ item: TabMenuItem) {
        if let appURL = item.appURL.flatMap(URL.init(string:)) {
            openURL(appURL) { opened in
                if !opened { show(item.appMissing ?? "Die App ist nicht installiert.") }
            }
        } else if let selectors = item.click {
            Task { await click(selectors, label: item.label) }
        }
    }

    private func click(_ selectors: [String], label: String) async {
        if await controller.click(selectors) { return }
        health.recordIssue(site: site.id, "Knopf „\(label)“ nicht gefunden. Die Seite hat sich wahrscheinlich geändert.")
        show("„\(label)“ geht gerade nicht. Details im Kontrollzentrum.")
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let template = searchTab?.search,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
                .replacingOccurrences(of: "&", with: "%26")
                .replacingOccurrences(of: "+", with: "%2B"),
              let url = resolve(template.replacingOccurrences(of: "{q}", with: encoded)) else { return }
        controller.load(url)
    }

    /// Relative Adressen gelten relativ zur Startseite der Website.
    private func resolve(_ address: String) -> URL? {
        URL(string: address, relativeTo: URL(string: site.home))?.absoluteURL
    }

    private func show(_ message: String) {
        withAnimation { notice = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation { if notice == message { notice = nil } }
        }
    }
}

/// Schlichte Leiste unten. Der Knopf, dessen `match` zum aktuellen Pfad passt, ist hervorgehoben.
private struct TabBar: View {
    let tabs: [SiteTab]
    let path: String
    let action: (SiteTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let active = tab.match.map { path.range(of: $0, options: .regularExpression) != nil } ?? false
                Button { action(tab) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: active ? .semibold : .regular))
                            .frame(height: 24)
                        Text(tab.label)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
            }
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Divider() }
    }
}

/// Kleiner runder Knopf zum Schließen. Lässt sich verschieben, rastet am nächsten
/// Seitenrand ein und merkt sich seine Position.
private struct FloatingCloseButton: View {
    let bottomInset: CGFloat
    let close: () -> Void
    @AppStorage("closeButton.trailing") private var trailing = false
    /// Abstand vom unteren Rand in Punkten.
    @AppStorage("closeButton.fromBottom") private var fromBottom: Double = -1
    @State private var drag: CGSize = .zero
    private let size: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let bottom = fromBottom < 0 ? Double(bottomInset) : fromBottom
            let x = trailing ? geo.size.width - size / 2 - 12 : size / 2 + 12
            let y = geo.size.height - CGFloat(bottom) - size / 2

            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
                // Tippfläche größer als der sichtbare Kreis (Apple empfiehlt mind. 44 pt).
                .padding(4)
                .contentShape(Circle())
                .position(x: x + drag.width, y: y + drag.height)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { drag = $0.translation }
                        .onEnded { value in
                            let endX = x + value.translation.width
                            let endY = y + value.translation.height
                            trailing = endX > geo.size.width / 2
                            let maxFromBottom = Double(geo.size.height - size - 8)
                            fromBottom = min(max(Double(geo.size.height - endY - size / 2), 8), maxFromBottom)
                            drag = .zero
                        }
                )
                .onTapGesture(perform: close)
                .accessibilityLabel("Schließen")
                .accessibilityAddTraits(.isButton)
                .animation(.spring(duration: 0.25), value: trailing)
        }
    }
}
