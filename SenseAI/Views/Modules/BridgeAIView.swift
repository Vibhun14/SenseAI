import SwiftUI
import AVFoundation

struct BridgeAIView: View {
    @StateObject private var engine = BridgeAIEngine()
    @State private var selectedMode: BridgeMode = .sign
    @State private var appear = false
    @State private var showSavedConfirmation = false
    @State private var showAudioPicker = false

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

            // Saved to Photos toast
            if showSavedConfirmation {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60))
                        Text("Saved to Photos")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .sheet(isPresented: $engine.showShareSheet) {
            if let url = engine.recordedVideoURL {
                ShareSheet(items: [url]) { saved in
                    if saved {
                        withAnimation(.spring()) { showSavedConfirmation = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { showSavedConfirmation = false }
                        }
                    }
                }
            }
        }
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {

                // Camera feed
                ZStack {
                    CameraPreviewView(previewLayer: engine.previewLayer)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    recordingStrokeColor,
                                    lineWidth: engine.recordingState == .recording ? 2.5 : (engine.handDetected ? 2 : 1)
                                )
                                .animation(.easeInOut(duration: 0.3), value: engine.recordingState == .recording)
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

                    // Overlays on camera
                    VStack {
                        // Recording badge at top
                        if engine.recordingState == .recording {
                            HStack {
                                Spacer()
                                RecordingBadge(duration: engine.recordingDuration, hasAudio: engine.recordWithAudio)
                                    .padding(.top, 12)
                                    .padding(.trailing, 12)
                            }
                        } else if engine.recordingState == .processing {
                            HStack {
                                Spacer()
                                ProcessingBadge()
                                    .padding(.top, 12)
                                    .padding(.trailing, 12)
                            }
                        }

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

                // Error messages
                Group {
                    if let error = engine.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.51))
                            .padding(.horizontal, 20)
                    }
                    if let recError = engine.recordingError {
                        Text(recError)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.51))
                            .padding(.horizontal, 20)
                    }
                }

                recordingExportPanel
                    .padding(.horizontal, 20)

                // Bottom controls
                bottomControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
    }

    private var recordingExportPanel: some View {
        Group {
            if engine.recordingState == .processing {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Processing video")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int(engine.processingProgress * 100))%")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.gray)
                    }

                    ProgressView(value: engine.processingProgress)
                        .tint(Color(red: 0.67, green: 0.55, blue: 0.98))
                }
                .padding(14)
                .background(Color(red: 0.07, green: 0.07, blue: 0.10))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            } else if engine.isVideoReadyToShare {
                Button(action: { engine.shareRecording() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Share Recording")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(red: 0.20, green: 0.83, blue: 0.60))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Bottom Controls
    private var bottomControls: some View {
        VStack(spacing: 10) {
            // Record row — audio toggle + record button
            HStack(spacing: 10) {
                // Audio toggle
                Button(action: {
                    guard engine.recordingState == .idle else { return }
                    engine.recordWithAudio.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: engine.recordWithAudio ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(engine.recordWithAudio ? "Audio On" : "Audio Off")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(engine.recordingState != .idle
                                     ? Color.gray.opacity(0.4)
                                     : (engine.recordWithAudio
                                        ? Color(red: 0.67, green: 0.55, blue: 0.98)
                                        : Color.gray))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color(red: 0.07, green: 0.07, blue: 0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                engine.recordWithAudio && engine.recordingState == .idle
                                ? Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.35)
                                : Color.white.opacity(0.06),
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(engine.recordingState != .idle)

                // Record / Stop recording button
                Button(action: {
                    if engine.recordingState == .recording {
                        engine.stopRecording()
                    } else if engine.recordingState == .idle {
                        engine.startRecording()
                    }
                }) {
                    HStack(spacing: 8) {
                        recordButtonIcon
                        Text(recordButtonLabel)
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(recordButtonForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(recordButtonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!engine.isRunning || engine.recordingState == .processing)
            }

            // Start/Stop camera button
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
        }
    }

    // MARK: - Record button helpers
    private var recordButtonIcon: some View {
        Group {
            switch engine.recordingState {
            case .idle:
                Image(systemName: "record.circle")
                    .font(.system(size: 15, weight: .semibold))
            case .recording:
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
            case .processing:
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.8)
            }
        }
    }

    private var recordButtonLabel: String {
        switch engine.recordingState {
        case .idle:      return "Record"
        case .recording: return "Stop Recording"
        case .processing: return "Saving…"
        }
    }

    private var recordButtonForeground: Color {
        switch engine.recordingState {
        case .idle:       return engine.isRunning ? .white : .gray
        case .recording:  return .white
        case .processing: return .white
        }
    }

    private var recordButtonBackground: some View {
        Group {
            switch engine.recordingState {
            case .idle:
                Color(red: 0.10, green: 0.10, blue: 0.14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(engine.isRunning
                                    ? Color(red: 0.92, green: 0.28, blue: 0.36).opacity(0.6)
                                    : Color.white.opacity(0.06), lineWidth: 1)
                    )
            case .recording:
                Color(red: 0.92, green: 0.28, blue: 0.36).opacity(0.85)
                    .overlay(EmptyView())
            case .processing:
                Color(red: 0.15, green: 0.15, blue: 0.20)
                    .overlay(EmptyView())
            }
        }
    }

    private var recordingStrokeColor: Color {
        if engine.recordingState == .recording {
            return Color(red: 0.92, green: 0.28, blue: 0.36)
        }
        return engine.handDetected
            ? Color(red: 0.67, green: 0.55, blue: 0.98).opacity(0.8)
            : Color.white.opacity(0.1)
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

// MARK: - Recording Badge
struct RecordingBadge: View {
    let duration: TimeInterval
    let hasAudio: Bool

    private var formattedTime: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 0.92, green: 0.28, blue: 0.36))
                .frame(width: 8, height: 8)
                .opacity(1)
                .animation(
                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                    value: duration
                )
            Text("REC \(formattedTime)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
            if hasAudio {
                Image(systemName: "mic.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.65))
        .clipShape(Capsule())
    }
}

// MARK: - Processing Badge
struct ProcessingBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .tint(.white)
                .scaleEffect(0.75)
            Text("Saving…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.65))
        .clipShape(Capsule())
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onSavedToPhotos: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { activityType, completed, _, _ in
            if completed, activityType == .saveToCameraRoll {
                onSavedToPhotos?(true)
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

            Text(text.isEmpty ? "Start signing — letters will appear here..." : text)
                .font(.system(size: text.isEmpty ? 14 : 22, weight: text.isEmpty ? .regular : .medium))
                .foregroundStyle(text.isEmpty ? Color.gray.opacity(0.4) : .white)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .padding(12)
                .background(Color(red: 0.05, green: 0.05, blue: 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

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
