import SwiftUI

struct HomeView: View {
    @State private var appearAnimation = false
    private let greeting = Calendar.current.component(.hour, from: Date())

    var greetingText: String {
        switch greeting {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.07)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {

                        // MARK: Header
                        VStack(alignment: .leading, spacing: 4) {
                            Text(greetingText.uppercased())
                                .font(.system(size: 11, weight: .medium))
                                .tracking(2)
                                .foregroundStyle(.gray)

                            Text("Welcome to")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(.white)

                            Text("SenseAI")
                                .font(.system(size: 34, weight: .bold))
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
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 28)
                        .opacity(appearAnimation ? 1 : 0)
                        .offset(y: appearAnimation ? 0 : 12)
                        .animation(.easeOut(duration: 0.5), value: appearAnimation)

                        // MARK: Stats Row
                        StatsRowView()
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                            .opacity(appearAnimation ? 1 : 0)
                            .offset(y: appearAnimation ? 0 : 12)
                            .animation(.easeOut(duration: 0.5).delay(0.1), value: appearAnimation)

                        // MARK: Section Label
                        Text("Choose a module".uppercased())
                            .font(.system(size: 11, weight: .medium))
                            .tracking(2)
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 14)
                            .opacity(appearAnimation ? 1 : 0)
                            .animation(.easeOut(duration: 0.5).delay(0.15), value: appearAnimation)

                        // MARK: Module Cards
                        VStack(spacing: 14) {
                            ForEach(Array(SenseModule.all.enumerated()), id: \.element.id) { index, module in
                                NavigationLink(destination: module.destination) {
                                    ModuleCardView(module: module)
                                }
                                .buttonStyle(ScrollableCardButtonStyle())
                                .opacity(appearAnimation ? 1 : 0)
                                .offset(y: appearAnimation ? 0 : 20)
                                .animation(
                                    .easeOut(duration: 0.5).delay(0.2 + Double(index) * 0.08),
                                    value: appearAnimation
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            appearAnimation = true
        }
    }
}

// MARK: - Stats Row
struct StatsRowView: View {
    var body: some View {
        HStack(spacing: 10) {
            StatPillView(value: "3", label: "Modules")
            StatPillView(value: "3", label: "AI Models")
            StatPillView(value: "Local", label: "Inference")
        }
    }
}

struct StatPillView: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(1)
                .foregroundStyle(Color.gray.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(red: 0.07, green: 0.07, blue: 0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ScrollableCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .allowsHitTesting(true)
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
