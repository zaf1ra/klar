import Combine
import SwiftUI
import WebKit

/// Vollbild für eine Seite in Slop: die Seite selbst, optional eine eigene Leiste unten
/// und schwebende Knöpfe für den KI-Scanner und zum Schließen.
struct LiteScreen: View {
    let site: SiteRules
    @Environment(RuleStore.self) private var rules
    @Environment(HealthMonitor.self) private var health
    @Environment(ProgressStore.self) private var progress
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var controller = WebController()
    @State private var scanner = AIScanner()
    @State private var showScanner = false
    @State private var startedAt = Date()
    @State private var searchTab: SiteTab?
    @State private var searchText = ""
    @State private var menuTab: SiteTab?
    @State private var notice: String?
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var controller = controller
        VStack(spacing: 0) {
            LiteWebView(site: site, adDomains: rules.rules.adDomains, health: health, controller: controller)
            if let tabs = site.tabs, !tabs.isEmpty {
                TabBar(tabs: tabs, path: controller.path, action: perform)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .background { SlopBackground() }
            }
        }
        .overlay {
            FloatingControls(bottomInset: site.tabs?.isEmpty == false ? 78 : 20,
                             scan: startScan, close: { dismiss() })
        }
        // Die Tastatur legt sich über Leiste und Knöpfe, statt sie nach oben zu schieben.
        // Die Seite selbst rückt ihre Eingabefelder bei offener Tastatur von allein ins Bild.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .top) {
            if let notice {
                Text(notice)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .glass(in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.smooth) { self.notice = nil } }
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
        // Anmelde-Fenster, z. B. „Mit Google anmelden“.
        .sheet(item: $controller.popup) { popup in
            PopupSheet(webView: popup.webView) { controller.popup = nil }
        }
        .sheet(isPresented: $showScanner, onDismiss: { scanner.reset() }) {
            AIScanSheet(scanner: scanner, rescan: startScan)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            startedAt = Date()
            progress.beginSession()
        }
        .onReceive(minuteTimer) { _ in progress.sessionHeartbeat() }
        .onDisappear { progress.endSession(startedAt: startedAt) }
    }

    private func startScan() {
        showScanner = true
        Task { await scanner.scan(controller.webView) }
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
        withAnimation(.smooth) { notice = message }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.smooth) { if notice == message { notice = nil } }
        }
    }
}

/// Schwebende Glasleiste unten. Der aktive Knopf bekommt eine Markierung, die beim
/// Wechsel weich zum neuen Knopf gleitet.
private struct TabBar: View {
    let tabs: [SiteTab]
    let path: String
    let action: (SiteTab) -> Void
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let active = tab.match.map { path.range(of: $0, options: .regularExpression) != nil } ?? false
                Button { action(tab) } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: active ? .semibold : .regular))
                            .frame(height: 22)
                            .symbolEffect(.bounce, value: active)
                        Text(tab.label)
                            .font(.system(size: 10, weight: active ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .background {
                        if active {
                            Capsule()
                                .fill(Color.primary.opacity(0.09))
                                .matchedGeometryEffect(id: "active", in: highlight)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(5)
        .glass(in: Capsule(), interactive: true)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: path)
    }
}

/// Zwei Glasknöpfe übereinander: KI-Scanner und Schließen. Lassen sich gemeinsam verschieben,
/// rasten am nächsten Seitenrand ein und merken sich ihre Position.
private struct FloatingControls: View {
    let bottomInset: CGFloat
    let scan: () -> Void
    let close: () -> Void
    @AppStorage("closeButton.trailing") private var trailing = false
    /// Abstand vom unteren Rand in Punkten.
    @AppStorage("closeButton.fromBottom") private var fromBottom: Double = -1
    @State private var drag: CGSize = .zero
    private let width: CGFloat = 48
    private let height: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            let bottom = fromBottom < 0 ? Double(bottomInset) : fromBottom
            let x = trailing ? geo.size.width - width / 2 - 10 : width / 2 + 10
            let y = geo.size.height - CGFloat(bottom) - height / 2

            GlassGroup(spacing: 0) {
                VStack(spacing: 0) {
                    controlButton("sparkle.magnifyingglass", label: "KI-Scanner", action: scan)
                    Divider().frame(width: 24).opacity(0.5)
                    controlButton("xmark", label: "Schließen", action: close)
                }
                .frame(width: width, height: height)
                .glass(in: Capsule(), interactive: true)
            }
            .position(x: x + drag.width, y: y + drag.height)
            .highPriorityGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { drag = $0.translation }
                    .onEnded { value in
                        let endX = x + value.translation.width
                        let endY = y + value.translation.height
                        let maxFromBottom = Double(geo.size.height - height - 8)
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                            trailing = endX > geo.size.width / 2
                            fromBottom = min(max(Double(geo.size.height - endY - height / 2), 8), maxFromBottom)
                            drag = .zero
                        }
                    }
            )
        }
    }

    private func controlButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: width, height: height / 2 - 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Anmelde-Fenster einer Seite (window.open), z. B. für „Mit Google anmelden“.
private struct PopupSheet: View {
    let webView: WKWebView
    let close: () -> Void

    var body: some View {
        NavigationStack {
            PopupWebView(webView: webView)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(webView.url?.host ?? "Anmelden")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Abbrechen", action: close)
                    }
                }
        }
        .interactiveDismissDisabled()
    }
}

private struct PopupWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
