import SwiftUI

struct SenseModule: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let description: String
    let icon: String
    let tags: [String]
    let modelBadge: String
    let accentColor: Color
    let gradientColors: [Color]
    let destination: AnyView
}

extension SenseModule {
    static let all: [SenseModule] = [
        SenseModule(
            name: "BridgeAI",
            subtitle: "Communication",
            description: "ASL sign language & lip reading — real-time translation to text and speech.",
            icon: "hand.raised.fill",
            tags: ["Sign language", "Lip reading", "Live camera"],
            modelBadge: "MediaPipe + LipNet · Core ML",
            accentColor: Color(red: 0.60, green: 0.40, blue: 0.98),
            gradientColors: [
                Color(red: 0.10, green: 0.06, blue: 0.25),
                Color(red: 0.06, green: 0.10, blue: 0.19)
            ],
            destination: AnyView(BridgeAIView())
        ),
        SenseModule(
            name: "HarmoniAI",
            subtitle: "Music Experience",
            description: "Feel music through sight and touch — stem separation drives synced visuals and haptics.",
            icon: "music.note",
            tags: ["Stem separation", "Visuals", "Haptics"],
            modelBadge: "Demucs · Core ML",
            accentColor: Color(red: 0.20, green: 0.83, blue: 0.60),
            gradientColors: [
                Color(red: 0.05, green: 0.12, blue: 0.08),
                Color(red: 0.10, green: 0.16, blue: 0.06)
            ],
            destination: AnyView(HarmoniAIView())
        ),
        SenseModule(
            name: "QuietAlert",
            subtitle: "Sound Detection",
            description: "Always-on sound detection — fire alarms, sirens, and custom alerts pushed instantly.",
            icon: "bell.badge.fill",
            tags: ["Always on", "Haptic alerts", "Custom sounds"],
            modelBadge: "Audio Classifier · Core ML",
            accentColor: Color(red: 0.98, green: 0.42, blue: 0.51),
            gradientColors: [
                Color(red: 0.12, green: 0.05, blue: 0.05),
                Color(red: 0.17, green: 0.06, blue: 0.06)
            ],
            destination: AnyView(QuietAlertView())
        )
    ]
}
