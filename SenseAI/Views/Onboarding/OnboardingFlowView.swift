import SwiftUI

// MARK: - Onboarding Flow Controller
struct OnboardingFlowView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var permissionsManager: PermissionsManager
    @State private var currentStep: OnboardingStep = .welcome

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case bridge
        case harmoni
        case quietAlert
        case permissions
        case ready
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()

            switch currentStep {
            case .welcome:
                OnboardingWelcomeView { advance() }
            case .bridge:
                OnboardingFeatureView(
                    feature: .bridge,
                    onNext: { advance() },
                    onSkip: { currentStep = .permissions }
                )
            case .harmoni:
                OnboardingFeatureView(
                    feature: .harmoni,
                    onNext: { advance() },
                    onSkip: { currentStep = .permissions }
                )
            case .quietAlert:
                OnboardingFeatureView(
                    feature: .quietAlert,
                    onNext: { advance() },
                    onSkip: { currentStep = .permissions }
                )
            case .permissions:
                OnboardingPermissionsView { advance() }
            case .ready:
                OnboardingReadyView {
                    appState.completeOnboarding()
                }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: currentStep)
    }

    private func advance() {
        let all = OnboardingStep.allCases
        if let idx = all.firstIndex(of: currentStep), idx + 1 < all.count {
            currentStep = all[idx + 1]
        }
    }
}

// MARK: - Step Dots
struct OnboardingStepDots: View {
    let total: Int
    let current: Int
    var accentColor: Color = Color(red: 0.67, green: 0.55, blue: 0.98)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i == current ? accentColor : Color.white.opacity(0.15))
                    .frame(width: i == current ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.4), value: current)
            }
        }
    }
}

// MARK: - Welcome Screen
struct OnboardingWelcomeView: View {
    let onNext: () -> Void
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo mark
            ZStack {
                Circle()
                    .fill(Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.12))
                    .frame(width: 120, height: 120)
                Circle()
                    .fill(Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.08))
                    .frame(width: 160, height: 160)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.67, green: 0.55, blue: 0.98),
                                Color(red: 0.38, green: 0.64, blue: 0.98)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .scaleEffect(appear ? 1 : 0.6)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: appear)
            .padding(.bottom, 40)

            // Title
            VStack(spacing: 10) {
                Text("SenseAI")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.67, green: 0.55, blue: 0.98),
                                Color(red: 0.38, green: 0.64, blue: 0.98)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text("Accessibility, reimagined.")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 16)
            .animation(.easeOut(duration: 0.5).delay(0.25), value: appear)
            .padding(.bottom, 24)

            // Tagline
            Text("Breaking communication barriers for the deaf, hard-of-hearing, and visually impaired — through AI that works entirely on your device.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 40)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)
                .animation(.easeOut(duration: 0.5).delay(0.35), value: appear)

            Spacer()

            // CTA
            VStack(spacing: 16) {
                Button(action: onNext) {
                    Text("Get Started")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.67, green: 0.55, blue: 0.98),
                                    Color(red: 0.38, green: 0.64, blue: 0.98)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Text("No account required · Works offline")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray.opacity(0.5))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
            .animation(.easeOut(duration: 0.5).delay(0.45), value: appear)
        }
        .onAppear { appear = true }
    }
}

// MARK: - Feature Screen
struct OnboardingFeatureView: View {
    enum Feature {
        case bridge, harmoni, quietAlert

        var icon: String {
            switch self {
            case .bridge:     return "hand.raised.fill"
            case .harmoni:    return "music.note.list"
            case .quietAlert: return "bell.badge.fill"
            }
        }
        var name: String {
            switch self {
            case .bridge:     return "BridgeAI"
            case .harmoni:    return "HarmoniAI"
            case .quietAlert: return "QuietAlert"
            }
        }
        var headline: String {
            switch self {
            case .bridge:     return "Sign language & lip reading, in real time."
            case .harmoni:    return "Feel music like never before."
            case .quietAlert: return "Never miss a critical sound again."
            }
        }
        var description: String {
            switch self {
            case .bridge:
                return "Point your camera at someone signing or speaking. BridgeAI translates ASL hand signs and lip movements into text and speech — instantly, on-device."
            case .harmoni:
                return "HarmoniAI separates any song into its individual stems — vocals, drums, bass, melody — and maps each one to pulsing visuals and haptic patterns you can feel."
            case .quietAlert:
                return "QuietAlert listens in the background for fire alarms, sirens, school bells, and custom sounds you record. When it detects one, it vibrates your phone and flashes an alert."
            }
        }
        var bullets: [String] {
            switch self {
            case .bridge:
                return ["26 ASL letters + common words", "Lip reading in noisy environments", "Text-to-speech output"]
            case .harmoni:
                return ["Stem separation via AI", "Real-time visual sync", "Customizable haptic patterns"]
            case .quietAlert:
                return ["Fire alarms, sirens, bells", "Custom recordable sounds", "Background listening mode"]
            }
        }
        var accentColor: Color {
            switch self {
            case .bridge:     return Color(red: 0.67, green: 0.55, blue: 0.98)
            case .harmoni:    return Color(red: 0.20, green: 0.83, blue: 0.60)
            case .quietAlert: return Color(red: 0.98, green: 0.42, blue: 0.51)
            }
        }
        var stepIndex: Int {
            switch self {
            case .bridge: return 1
            case .harmoni: return 2
            case .quietAlert: return 3
            }
        }
    }

    let feature: Feature
    let onNext: () -> Void
    let onSkip: () -> Void
    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {

            // Top bar
            HStack {
                OnboardingStepDots(total: 4, current: feature.stepIndex, accentColor: feature.accentColor)
                Spacer()
                Button("Skip", action: onSkip)
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(feature.accentColor.opacity(0.10))
                    .frame(width: 130, height: 130)
                Image(systemName: feature.icon)
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(feature.accentColor)
            }
            .scaleEffect(appear ? 1 : 0.7)
            .opacity(appear ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.05), value: appear)
            .padding(.bottom, 32)

            // Name + headline
            VStack(spacing: 8) {
                Text(feature.name)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(feature.accentColor)

                Text(feature.headline)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 32)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 12)
            .animation(.easeOut(duration: 0.4).delay(0.15), value: appear)
            .padding(.bottom, 20)

            // Description
            Text(feature.description)
                .font(.system(size: 15))
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 36)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 10)
                .animation(.easeOut(duration: 0.4).delay(0.22), value: appear)
                .padding(.bottom, 28)

            // Bullet points
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(feature.bullets.enumerated()), id: \.offset) { i, bullet in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(feature.accentColor)
                            .frame(width: 6, height: 6)
                        Text(bullet)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(x: appear ? 0 : -10)
                    .animation(.easeOut(duration: 0.35).delay(0.3 + Double(i) * 0.07), value: appear)
                }
            }
            .padding(.horizontal, 48)

            Spacer()

            // Next button
            Button(action: onNext) {
                HStack(spacing: 10) {
                    Text("Next")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(feature.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
            .animation(.easeOut(duration: 0.4).delay(0.4), value: appear)
        }
        .onAppear { appear = true }
        .onDisappear { appear = false }
    }
}

// MARK: - Permissions Screen
struct OnboardingPermissionsView: View {
    @EnvironmentObject var permissionsManager: PermissionsManager
    let onNext: () -> Void
    @State private var appear = false
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 0) {

            // Step dots
            HStack {
                OnboardingStepDots(total: 4, current: 0, accentColor: Color(red: 0.67, green: 0.55, blue: 0.98))
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Spacer()

            // Header
            VStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(red: 0.67, green: 0.55, blue: 0.98))
                    .padding(.bottom, 12)

                Text("A few permissions")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Text("SenseAI needs access to your camera, microphone, and notifications to work. Everything stays on-device — nothing is sent to the cloud.")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 36)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 14)
            .animation(.easeOut(duration: 0.45).delay(0.1), value: appear)
            .padding(.bottom, 40)

            // Permission rows
            VStack(spacing: 12) {
                PermissionRow(
                    icon: "camera.fill",
                    title: "Camera",
                    subtitle: "Used by BridgeAI for ASL & lip reading",
                    status: permissionsManager.cameraStatus
                )
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Used by QuietAlert to detect sounds",
                    status: permissionsManager.microphoneStatus
                )
                PermissionRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    subtitle: "Used by QuietAlert to send instant alerts",
                    status: permissionsManager.notificationsStatus
                )
            }
            .padding(.horizontal, 28)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 14)
            .animation(.easeOut(duration: 0.45).delay(0.2), value: appear)

            Spacer()

            // Action buttons
            VStack(spacing: 12) {
                if permissionsManager.allGranted {
                    Button(action: onNext) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                            Text("All set — Continue")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Color(red: 0.20, green: 0.83, blue: 0.60))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                } else {
                    Button(action: {
                        isRequesting = true
                        Task { @MainActor in
                            await permissionsManager.requestAll()
                            isRequesting = false
                        }
                    }) {
                        HStack(spacing: 10) {
                            if isRequesting {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.85)
                            }
                            Text(isRequesting ? "Requesting..." : "Grant Permissions")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.67, green: 0.55, blue: 0.98),
                                    Color(red: 0.38, green: 0.64, blue: 0.98)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(isRequesting)

                    Button(action: onNext) {
                        Text("Skip for now")
                            .font(.system(size: 15))
                            .foregroundStyle(.gray)
                    }
                }

                // If any denied, show settings link
                if permissionsManager.cameraStatus == .denied ||
                   permissionsManager.microphoneStatus == .denied ||
                   permissionsManager.notificationsStatus == .denied {
                    Button(action: { permissionsManager.openAppSettings() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gear")
                                .font(.system(size: 12))
                            Text("Open Settings to fix denied permissions")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.51).opacity(0.8))
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
            .opacity(appear ? 1 : 0)
            .animation(.easeOut(duration: 0.45).delay(0.3), value: appear)
        }
        .onAppear {
            appear = true
            permissionsManager.checkAllStatuses()
        }
    }
}

// MARK: - Permission Row
struct PermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: PermissionsManager.PermissionStatus

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(red: 0.67, green: 0.55, blue: 0.98))
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }

            Spacer()

            // Status indicator
            Image(systemName: status.icon)
                .font(.system(size: 20))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(red: 0.07, green: 0.07, blue: 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Ready Screen
struct OnboardingReadyView: View {
    let onFinish: () -> Void
    @State private var appear = false
    @State private var sparkle = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle()
                    .fill(Color(red: 0.20, green: 0.83, blue: 0.60).opacity(0.08))
                    .frame(width: 180, height: 180)
                    .scaleEffect(sparkle ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: sparkle)

                Circle()
                    .fill(Color(red: 0.20, green: 0.83, blue: 0.60).opacity(0.12))
                    .frame(width: 130, height: 130)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60))
                    .scaleEffect(appear ? 1 : 0.4)
                    .opacity(appear ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: appear)
            }
            .padding(.bottom, 40)

            VStack(spacing: 10) {
                Text("You're all set.")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)

                Text("SenseAI is ready to bridge the gap.")
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(.gray)
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 14)
            .animation(.easeOut(duration: 0.45).delay(0.25), value: appear)
            .padding(.bottom, 16)

            Text("Select any module from the hub to begin. You can change permissions and preferences anytime in Settings.")
                .font(.system(size: 14))
                .foregroundStyle(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 44)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.45).delay(0.35), value: appear)

            Spacer()

            Button(action: onFinish) {
                Text("Open SenseAI")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.67, green: 0.55, blue: 0.98),
                                Color(red: 0.38, green: 0.64, blue: 0.98)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 52)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
            .animation(.easeOut(duration: 0.4).delay(0.45), value: appear)
        }
        .onAppear {
            appear = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sparkle = true }
        }
    }
}

#Preview("Welcome") {
    OnboardingWelcomeView {}
        .preferredColorScheme(.dark)
}

#Preview("Feature - BridgeAI") {
    OnboardingFeatureView(feature: .bridge, onNext: {}, onSkip: {})
        .preferredColorScheme(.dark)
}

#Preview("Permissions") {
    OnboardingPermissionsView {}
        .environmentObject(PermissionsManager())
        .preferredColorScheme(.dark)
}

#Preview("Ready") {
    OnboardingReadyView {}
        .preferredColorScheme(.dark)
}
