import SwiftUI

struct QuietAlertView: View {
    @StateObject private var engine = QuietAlertEngine()
    @State private var showDetectionBanner = false
    @State private var pulseRings = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()
            VStack(spacing: 0) {
                bannerSection
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        orbSection
                        statusSection
                        soundGridSection
                        recentDetectionsSection
                        errorSection
                        Spacer(minLength: 100)
                    }
                }
                startStopButton
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackButton(accentColor: Color(red: 0.98, green: 0.42, blue: 0.51))
            }
        }
        .onChange(of: engine.lastDetection?.timestamp) {
            withAnimation(.spring(response: 0.4)) { showDetectionBanner = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { showDetectionBanner = false }
            }
        }
    }

    // MARK: - Subviews
    @ViewBuilder
    private var bannerSection: some View {
        if let detection = engine.lastDetection, showDetectionBanner {
            DetectionBannerView(detection: detection)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var orbSection: some View {
        ZStack {
            if engine.isListening {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color(red: 0.98, green: 0.42, blue: 0.51).opacity(0.12 - Double(i) * 0.03), lineWidth: 1)
                        .frame(width: CGFloat(110 + i * 55), height: CGFloat(110 + i * 55))
                        .scaleEffect(pulseRings ? 1.25 : 1.0)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.5), value: pulseRings)
                }
            }
            Circle()
                .stroke(Color(red: 0.98, green: 0.42, blue: 0.51).opacity(engine.isListening ? 0.3 : 0.1), lineWidth: 3)
                .frame(width: 110 + CGFloat(engine.audioLevel * 20), height: 110 + CGFloat(engine.audioLevel * 20))
                .animation(.easeOut(duration: 0.1), value: engine.audioLevel)
            Circle()
                .fill(engine.isListening ? Color(red: 0.98, green: 0.42, blue: 0.51).opacity(0.15) : Color(red: 0.07, green: 0.07, blue: 0.10))
                .frame(width: 110, height: 110)
                .overlay(Circle().stroke(engine.isListening ? Color(red: 0.98, green: 0.42, blue: 0.51).opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1))
            Image(systemName: engine.isListening ? "ear.fill" : "ear")
                .font(.system(size: 40))
                .foregroundStyle(engine.isListening ? Color(red: 0.98, green: 0.42, blue: 0.51) : .gray)
        }
        .frame(height: 240)
        .padding(.top, 16)
    }

    private var statusSection: some View {
        VStack(spacing: 4) {
            Text(engine.isListening ? "Listening..." : "Tap to start")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(engine.isListening ? .white : .gray)
            if engine.isListening {
                Text("Monitoring for critical sounds")
                    .font(.system(size: 13))
                    .foregroundStyle(.gray)
            }
        }
    }

    private var soundGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MONITORED SOUNDS")
                .font(.system(size: 11, weight: .medium))
                .tracking(1.4)
                .foregroundStyle(Color.gray.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SoundCategory.all, id: \.label) { category in
                    SoundCategoryTile(
                        category: category,
                        isActive: engine.lastDetection?.label == category.label
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var recentDetectionsSection: some View {
        if !engine.recentDetections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("RECENT DETECTIONS")
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(engine.recentDetections.prefix(5), id: \.timestamp) { detection in
                    RecentDetectionRow(detection: detection)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = engine.errorMessage {
            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.51))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var startStopButton: some View {
        Button(action: toggleListening) {
            HStack(spacing: 10) {
                Image(systemName: engine.isListening ? "stop.fill" : "ear.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text(engine.isListening ? "Stop Listening" : "Start Listening")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                engine.isListening
                ? AnyView(Color(red: 0.98, green: 0.42, blue: 0.51).opacity(0.25))
                : AnyView(LinearGradient(
                    colors: [Color(red: 0.70, green: 0.18, blue: 0.22),
                             Color(red: 0.98, green: 0.42, blue: 0.51)],
                    startPoint: .leading, endPoint: .trailing))
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    private func toggleListening() {
        if engine.isListening {
            engine.stopListening()
            pulseRings = false
        } else {
            engine.startListening()
            pulseRings = true
        }
    }
}

// MARK: - Detection Banner
struct DetectionBannerView: View {
    let detection: SoundDetection
    var body: some View {
        HStack(spacing: 14) {
            Text(detection.emoji).font(.system(size: 28))
            VStack(alignment: .leading, spacing: 2) {
                Text(detection.displayName)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                Text("\(Int(detection.confidence * 100))% confidence")
                    .font(.system(size: 12)).foregroundStyle(.gray)
            }
            Spacer()
            if detection.isUrgent {
                Text("URGENT")
                    .font(.system(size: 10, weight: .bold)).tracking(1)
                    .foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.51))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(red: 0.98, green: 0.42, blue: 0.51).opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color(red: 0.10, green: 0.06, blue: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color(red: 0.98, green: 0.42, blue: 0.51).opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Sound Category
struct SoundCategory {
    let label: String; let icon: String; let name: String
    static let all: [SoundCategory] = [
        SoundCategory(label: "crackling_fire",   icon: "flame.fill",                        name: "Fire"),
        SoundCategory(label: "siren",            icon: "light.beacon.max.fill",             name: "Siren"),
        SoundCategory(label: "dog",              icon: "pawprint.fill",                     name: "Dog"),
        SoundCategory(label: "clock_alarm",      icon: "alarm.fill",                        name: "Alarm"),
        SoundCategory(label: "glass_breaking",   icon: "bolt.fill",                         name: "Glass"),
        SoundCategory(label: "crying_baby",      icon: "figure.and.child.holdinghands",     name: "Baby"),
        SoundCategory(label: "vacuum_cleaner",   icon: "wind",                              name: "Vacuum"),
        SoundCategory(label: "hand_saw",         icon: "wrench.fill",                       name: "Tools"),
        SoundCategory(label: "door_wood_knock",  icon: "door.left.hand.closed",             name: "Knock"),
    ]
}

struct SoundCategoryTile: View {
    let category: SoundCategory; let isActive: Bool
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon).font(.system(size: 14))
                .foregroundStyle(isActive ? Color(red: 0.98, green: 0.42, blue: 0.51) : .gray)
                .frame(width: 20)
            Text(category.name)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .white : .gray)
            Spacer()
            if isActive { Circle().fill(Color(red: 0.98, green: 0.42, blue: 0.51)).frame(width: 7, height: 7) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(isActive ? Color(red: 0.98, green: 0.42, blue: 0.51).opacity(0.10)
                             : Color(red: 0.07, green: 0.07, blue: 0.10))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(isActive ? Color(red: 0.98, green: 0.42, blue: 0.51).opacity(0.35)
                             : Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

struct RecentDetectionRow: View {
    let detection: SoundDetection
    var body: some View {
        HStack(spacing: 12) {
            Text(detection.emoji).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(detection.displayName).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                Text(detection.timestamp, style: .relative).font(.system(size: 11)).foregroundStyle(.gray)
            }
            Spacer()
            Text("\(Int(detection.confidence * 100))%")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(detection.isUrgent ? Color(red: 0.98, green: 0.42, blue: 0.51) : .gray)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(red: 0.07, green: 0.07, blue: 0.10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct BackButton: View {
    let accentColor: Color
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button(action: { dismiss() }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                Text("Hub").font(.system(size: 16))
            }
            .foregroundStyle(accentColor)
        }
    }
}

#Preview {
    NavigationStack { QuietAlertView() }.preferredColorScheme(.dark)
}
