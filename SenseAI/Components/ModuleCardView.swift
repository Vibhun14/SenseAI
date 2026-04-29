import SwiftUI

struct ModuleCardView: View {
    let module: SenseModule

    var body: some View {
        ZStack(alignment: .topTrailing) {

            // Card background
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: module.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(module.accentColor.opacity(0.20), lineWidth: 1)
                )

            // Glow blob top-right
            Circle()
                .fill(
                    RadialGradient(
                        colors: [module.accentColor.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .offset(x: 40, y: -40)

            // Card content
            VStack(alignment: .leading, spacing: 0) {

                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(module.accentColor.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: module.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(module.accentColor)
                }
                .padding(.bottom, 14)

                // Title
                Text(module.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.bottom, 4)

                // Description
                Text(module.description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.gray)
                    .lineSpacing(3)
                    .padding(.bottom, 16)

                // Tags
                FlowTagsView(tags: module.tags, accentColor: module.accentColor)
                    .padding(.bottom, 12)

                // Model badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.83, blue: 0.60))
                        .frame(width: 5, height: 5)
                    Text(module.modelBadge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.gray.opacity(0.55))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(red: 0.07, green: 0.07, blue: 0.10))
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .padding(22)

            // Arrow only — no pulse dot
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .padding(20)
        }
    }
}

// MARK: - Flow Tags
struct FlowTagsView: View {
    let tags: [String]
    let accentColor: Color

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()
        ModuleCardView(module: SenseModule.all[0])
            .padding(24)
    }
}
