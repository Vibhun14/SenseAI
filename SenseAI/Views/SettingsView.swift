import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var permissionsManager: PermissionsManager

    @AppStorage("hapticEnabled") var hapticEnabled = true
    @AppStorage("alwaysOnListening") var alwaysOnListening = false
    @AppStorage("highContrastMode") var highContrastMode = false
    @AppStorage("selectedLanguage") var selectedLanguage = "English"

    let languages = ["English", "Spanish", "French", "Mandarin", "ASL (US)"]

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()

            Form {
                Section("Accessibility") {
                    Toggle("Haptic Feedback", isOn: $hapticEnabled)
                    Toggle("High Contrast Mode", isOn: $highContrastMode)
                }

                Section("QuietAlert") {
                    Toggle("Always-On Listening", isOn: $alwaysOnListening)
                }

                Section("BridgeAI") {
                    Picker("Output Language", selection: $selectedLanguage) {
                        ForEach(languages, id: \.self) { Text($0) }
                    }
                }

                Section("Permissions") {
                    PermissionSettingsRow(icon: "camera.fill", title: "Camera", status: permissionsManager.cameraStatus)
                    PermissionSettingsRow(icon: "mic.fill", title: "Microphone", status: permissionsManager.microphoneStatus)
                    PermissionSettingsRow(icon: "bell.fill", title: "Notifications", status: permissionsManager.notificationsStatus)

                    Button(action: { permissionsManager.openAppSettings() }) {
                        Label("Open App Settings", systemImage: "gear")
                            .foregroundStyle(Color(red: 0.67, green: 0.55, blue: 0.98))
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundStyle(.gray)
                    }
                    HStack {
                        Text("Models")
                        Spacer()
                        Text("Core ML · On-device").foregroundStyle(.gray)
                    }
                }

                Section("Developer") {
                    Button(role: .destructive, action: { appState.resetOnboarding() }) {
                        Label("Replay Onboarding", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Settings")
        }
        .onAppear { permissionsManager.checkAllStatuses() }
    }
}

struct PermissionSettingsRow: View {
    let icon: String
    let title: String
    let status: PermissionsManager.PermissionStatus

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(status.color)
                Text(statusLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(status.color)
            }
        }
    }

    var statusLabel: String {
        switch status {
        case .granted:    return "Granted"
        case .denied:     return "Denied"
        case .restricted: return "Restricted"
        case .unknown:    return "Not asked"
        }
    }
}
