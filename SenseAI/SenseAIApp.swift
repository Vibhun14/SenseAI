import SwiftUI

@main
struct SenseAIApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var permissionsManager = PermissionsManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.hasCompletedOnboarding {
                    ContentView()
                        .transition(.opacity)
                } else {
                    OnboardingFlowView()
                        .transition(.opacity)
                }
            }
            .environmentObject(appState)
            .environmentObject(permissionsManager)
            .preferredColorScheme(.dark)
            .animation(.easeInOut(duration: 0.4), value: appState.hasCompletedOnboarding)
        }
    }
}
