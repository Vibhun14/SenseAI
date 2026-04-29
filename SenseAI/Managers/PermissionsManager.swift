import SwiftUI
import AVFoundation
import AVFAudio
import UserNotifications

@MainActor
class PermissionsManager: ObservableObject {

    @Published var cameraStatus: PermissionStatus = .unknown
    @Published var microphoneStatus: PermissionStatus = .unknown
    @Published var notificationsStatus: PermissionStatus = .unknown

    enum PermissionStatus {
        case unknown, granted, denied, restricted

        var isGranted: Bool { self == .granted }

        var icon: String {
            switch self {
            case .unknown:    return "circle.dotted"
            case .granted:    return "checkmark.circle.fill"
            case .denied:     return "xmark.circle.fill"
            case .restricted: return "minus.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .unknown:    return Color(red: 0.4, green: 0.4, blue: 0.4)
            case .granted:    return Color(red: 0.20, green: 0.83, blue: 0.60)
            case .denied:     return Color(red: 0.98, green: 0.42, blue: 0.51)
            case .restricted: return Color(red: 0.98, green: 0.73, blue: 0.20)
            }
        }
    }

    // MARK: - Check statuses (no dialogs)
    func checkAllStatuses() {
        // Camera
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    cameraStatus = .granted
        case .denied:        cameraStatus = .denied
        case .restricted:    cameraStatus = .restricted
        default:             cameraStatus = .unknown
        }

        // Microphone
        switch AVAudioApplication.shared.recordPermission {
        case .granted:       microphoneStatus = .granted
        case .denied:        microphoneStatus = .denied
        default:             microphoneStatus = .unknown
        }

        // Notifications
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.notificationsStatus = .granted
                case .denied:
                    self.notificationsStatus = .denied
                default:
                    self.notificationsStatus = .unknown
                }
            }
        }
    }

    // MARK: - Request all (called from MainActor Task only)
    func requestAll() async {
        await requestCamera()
        await requestMicrophone()
        await requestNotifications()
    }

    private func requestCamera() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraStatus = granted ? .granted : .denied
    }

    private func requestMicrophone() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        microphoneStatus = granted ? .granted : .denied
    }

    private func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notificationsStatus = granted ? .granted : .denied
        } catch {
            notificationsStatus = .denied
        }
    }

    // MARK: - Open Settings
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    var allGranted: Bool {
        cameraStatus.isGranted && microphoneStatus.isGranted && notificationsStatus.isGranted
    }
}
