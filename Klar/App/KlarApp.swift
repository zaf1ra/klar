import SwiftUI

@main
struct KlarApp: App {
    @State private var rules = RuleStore()
    @State private var health = HealthMonitor()
    @State private var progress = ProgressStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(rules)
                .environment(health)
                .environment(progress)
                .task {
                    health.attach(rules: rules)
                    await rules.refreshFromRemote()
                    await health.runChecks()
                }
        }
    }
}
