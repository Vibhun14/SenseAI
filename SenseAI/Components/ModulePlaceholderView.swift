import SwiftUI

struct ModulePlaceholderView: View {
    let title: String
    let subtitle: String
    let icon: String
    let accentColor: Color
    let description: String
    let ctaLabel: String
    let ctaIcon: String

    @Environment(\.dismiss) private var dismiss
    @State private var appear = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07)
                .ignoresSafeArea()

            // Background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accentColor.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 600)
                .offset(y: -100)

            VStack(spacing: 0) {
                Spacer()

                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 88, height: 88)
                    Image(systemName: icon)
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(accentColor)
                }
                .padding(.bottom, 28)
                .scaleEffect(appear ? 1 : 0.7)
                .opacity(appear ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: appear)

                // Title
                Text(title)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 6)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: appear)

                Text(subtitle.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(accentColor.opacity(0.8))
                    .padding(.bottom, 24)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 10)
                    .animation(.easeOut(duration: 0.4).delay(0.25), value: appear)

                // Description
                Text(description)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 48)
                    .opacity(appear ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: appear)

                // CTA Button
                Button {
                    // Module action will be wired here
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: ctaIcon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(ctaLabel)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 10)
                .animation(.easeOut(duration: 0.4).delay(0.35), value: appear)

                // Coming soon tag
                Text("Module in development")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray.opacity(0.4))
                    .padding(.top, 16)
                    .opacity(appear ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.4), value: appear)

                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Hub")
                            .font(.system(size: 16))
                    }
                    .foregroundStyle(accentColor)
                }
            }
        }
        .onAppear { appear = true }
    }
}

#Preview {
    NavigationStack {
        ModulePlaceholderView(
            title: "BridgeAI",
            subtitle: "Communication",
            icon: "hand.raised.fill",
            accentColor: Color(red: 0.60, green: 0.40, blue: 0.98),
            description: "Point your camera at someone signing or speaking.",
            ctaLabel: "Start Camera",
            ctaIcon: "camera.fill"
        )
    }
    .preferredColorScheme(.dark)
}
