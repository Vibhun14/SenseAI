import SwiftUI
import AVFoundation

struct BridgeAIView: View {
    @StateObject private var engine = BridgeAIEngine()
    @State private var selectedMode: BridgeMode = .sign
    @State private var appear = false

    enum BridgeMode: String, CaseIterable {
        case sign = "Sign Language"
        case lip  = "Lip Reading"
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()

            VStack(spacing: 0) {
                modePicker
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if selectedMode == .sign {
                    signModeContent
                } else {
                    lipModeContent
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackButton(accentColor: Color(red: 0.67, green: 0.55, blue: 0.98))
            }
        }
        .onDisappear { engine.stopCamera() }
    }

    // MARK: - Mode Picker
    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(BridgeMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedMode = mode }
                    if mode == .sign { engine.startCamera() } else { engine.stopCamera() }
                }) {
                    Text(mode.rawValue)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(selectedMode == mode ? .white : Color.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedMode == mode
                                    ? Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.2)
                                    : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(4)
        .background(Color(red: 0.07, green: 0.07, blue: 0.10))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Sign Mode
    private var signModeContent: some View {
        VStack(spacing: 12) {

            // Camera feed
            ZStack {
                // Camera preview
                CameraPreviewView(previewLayer: engine.previewLayer)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                engine.handDetected
                                ? Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.8)
                                : Color.white.opacity(0.1),
                                lineWidth: engine.handDetected ? 2 : 1
                            )
                    )

                // No camera state
                if engine.previewLayer == nil {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(red: 0.07, green: 0.07, blue: 0.10))
                        .overlay(
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.4))
                                Text("Tap Start to begin")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.gray)
                            }
                        )
                }

                // Current letter overlay
                VStack {
                    Spacer()
                    HStack {
                        // Hand status indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(engine.handDetected
                                      ? Color(red: 0.67, green: 0.55, blue: 0.98)
                                      : .gray)
                                .frame(width: 8, height: 8)
                            Text(engine.handDetected ? "Hand detected" : "No hand")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(engine.handDetected ? .white : .gray)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())

                        Spacer()

                        // Big letter display
                        if !engine.currentLetter.isEmpty {
                            Text(engine.currentLetter)
                                .font(.system(size: 64, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 90, height: 90)
                                .background(.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(12)
                }
            }
            .frame(height: 300)
            .padding(.horizontal, 20)

            // Confidence bar
            if let pred = engine.lastPrediction {
                ConfidenceBar(letter: pred.letter, confidence: pred.confidence)
                    .padding(.horizontal, 20)
            }

            // Text output box
            TextOutputBox(
                text: engine.translatedText,
                onDelete: { engine.deleteLastChar() },
                onSpace: { engine.addSpace() },
                onClear: { engine.clearText() }
            )
            .padding(.horizontal, 20)

            // Error message
            if let error = engine.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.51))
                    .padding(.horizontal, 20)
            }

            Spacer()

            // Start/Stop button
            Button(action: {
                if engine.isRunning { engine.stopCamera() }
                else { engine.startCamera() }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: engine.isRunning ? "stop.fill" : "camera.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(engine.isRunning ? "Stop Camera" : "Start Camera")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    engine.isRunning
                    ? Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.4)
                    : Color(red: 0.67, green: 0.55, blue: 0.98)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Lip Mode (placeholder)
    private var lipModeContent: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "mouth.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.5))
                Text("Lip Reading")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text("Coming soon — LipNet model\nin development.")
                    .font(.system(size: 15))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            guard let layer = previewLayer else { return }
            layer.frame = uiView.bounds
            if layer.superlayer == nil {
                uiView.layer.addSublayer(layer)
            }
        }
    }
}

// MARK: - Confidence Bar
struct ConfidenceBar: View {
    let letter: String
    let confidence: Float

    var body: some View {
        HStack(spacing: 12) {
            Text("Confidence")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.gray)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(confidenceColor)
                        .frame(width: geo.size.width * CGFloat(confidence))
                        .animation(.easeOut(duration: 0.15), value: confidence)
                }
            }
            .frame(height: 8)

            Text("\(Int(confidence * 100))%")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(confidenceColor)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 0.07, green: 0.07, blue: 0.10))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    var confidenceColor: Color {
        if confidence >= 0.85 { return Color(red: 0.20, green: 0.83, blue: 0.60) }
        if confidence >= 0.65 { return Color(red: 0.98, green: 0.73, blue: 0.20) }
        return Color(red: 0.98, green: 0.42, blue: 0.51)
    }
}

// MARK: - Text Output Box
struct TextOutputBox: View {
    let text: String
    let onDelete: () -> Void
    let onSpace:  () -> Void
    let onClear:  () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("OUTPUT")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(Color.gray.opacity(0.5))
                Spacer()
                Button(action: onClear) {
                    Text("Clear")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.8))
                }
            }

            // Text display
            Text(text.isEmpty ? "Start signing — letters will appear here..." : text)
                .font(.system(size: text.isEmpty ? 14 : 22, weight: text.isEmpty ? .regular : .medium))
                .foregroundStyle(text.isEmpty ? Color.gray.opacity(0.4) : .white)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .padding(12)
                .background(Color(red: 0.05, green: 0.05, blue: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Control buttons
            HStack(spacing: 10) {
                ControlButton(icon: "space", label: "Space", action: onSpace)
                ControlButton(icon: "delete.left.fill", label: "Delete", action: onDelete)
            }
        }
        .padding(14)
        .background(Color(red: 0.07, green: 0.07, blue: 0.10))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct ControlButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

#Preview {
    NavigationStack { BridgeAIView() }
        .preferredColorScheme(.dark)
}
