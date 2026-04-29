import Foundation
import AVFoundation
import CoreML
import CoreHaptics

// MARK: - Detection Result
struct SoundDetection {
    let label: String
    let confidence: Float
    let timestamp: Date

    var displayName: String {
        label.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var emoji: String {
        switch label {
        case "crackling_fire":  return "🔥"
        case "siren":           return "🚨"
        case "dog":             return "🐕"
        case "clock_alarm":     return "⏰"
        case "glass_breaking":  return "🪟"
        case "crying_baby":     return "👶"
        case "vacuum_cleaner":  return "🧹"
        case "hand_saw":        return "🪚"
        case "door_wood_knock": return "🚪"
        default:                return "🔊"
        }
    }

    var isUrgent: Bool {
        ["crackling_fire", "siren", "glass_breaking"].contains(label)
    }
}

// MARK: - QuietAlert Engine
@MainActor
class QuietAlertEngine: ObservableObject {

    // MARK: Published state
    @Published var isListening        = false
    @Published var lastDetection: SoundDetection? = nil
    @Published var recentDetections: [SoundDetection] = []
    @Published var audioLevel: Float  = 0.0
    @Published var errorMessage: String? = nil

    // MARK: Audio engine
    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }

    // MARK: ML Model
    private var model: QuietAlertClassifier?

    // MARK: Audio settings — must match training
    private let sampleRate:   Double = 22050
    private let duration:     Double = 5.0
    private let totalSamples: Int    = 110250  // 22050 * 5
    private var audioBuffer:  [Float] = []

    // MARK: Haptics
    private var hapticEngine: CHHapticEngine?

    // MARK: Confidence threshold
    private let confidenceThreshold: Float = 0.40

    // MARK: Label map
    private lazy var labelMap: [Int: String] = {
        guard let url  = Bundle.main.url(forResource: "label_map", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw  = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            print("❌ label_map.json not found in bundle")
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v -> (Int, String)? in
            guard let i = Int(k) else { return nil }
            return (i, v)
        })
    }()

    // MARK: - Init
    init() {
        loadModel()
        prepareHaptics()
    }

    // MARK: - Load Model
    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            model = try QuietAlertClassifier(configuration: config)
            print("✅ QuietAlertClassifier loaded")
        } catch {
            errorMessage = "Failed to load model: \(error.localizedDescription)"
            print("❌ Model load error: \(error)")
        }
    }

    // MARK: - Start Listening
    func startListening() {
        guard !isListening else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setPreferredSampleRate(sampleRate)
            try session.setActive(true)

            let inputFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 11025, format: inputFormat) {
                [weak self] buffer, _ in
                self?.processAudioBuffer(buffer, inputFormat: inputFormat)
            }

            audioBuffer = []
            try audioEngine.start()
            isListening = true
            print("🎙️ QuietAlert listening...")

        } catch {
            errorMessage = "Microphone error: \(error.localizedDescription)"
        }
    }

    // MARK: - Stop Listening
    func stopListening() {
        guard isListening else { return }
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        isListening = false
        audioLevel  = 0
        audioBuffer = []
        print("⏹️ QuietAlert stopped")
    }

    // MARK: - Process Incoming Audio
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer,
                                     inputFormat: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)

        // Resample to 22050 Hz if needed
        var samples: [Float]
        if inputFormat.sampleRate != sampleRate {
            samples = resample(
                Array(UnsafeBufferPointer(start: channelData, count: frameCount)),
                from: inputFormat.sampleRate,
                to: sampleRate
            )
        } else {
            samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
        }

        // Update audio level meter
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        Task { @MainActor in self.audioLevel = min(rms * 10, 1.0) }

        // Accumulate into rolling buffer
        audioBuffer.append(contentsOf: samples)

        // Run inference once we have 5 seconds, with 50% overlap
        if audioBuffer.count >= totalSamples {
            let chunk = Array(audioBuffer.prefix(totalSamples))
            audioBuffer = Array(audioBuffer.dropFirst(totalSamples / 2))
            Task { await runInference(on: chunk) }
        }
    }

    // MARK: - Run Inference
    // Model has spectrogram baked in — just feed raw audio samples directly
    private func runInference(on samples: [Float]) async {
        guard let model = model else {
            print("❌ No model loaded")
            return
        }

        guard let inputArray = try? MLMultiArray(
            shape: [1, NSNumber(value: totalSamples)],
            dataType: .float32
        ) else {
            print("❌ MLMultiArray creation failed")
            return
        }

        // Fill array — pad with zeros if short
        for i in 0..<min(samples.count, totalSamples) {
            inputArray[[0, i] as [NSNumber]] = NSNumber(value: samples[i])
        }

        do {
            let input  = QuietAlertClassifierInput(audio: inputArray)
            let output = try await model.prediction(input: input)
            let probs  = softmax(output.classLogits)

            // Debug output
            print("📊 Probabilities:")
            for i in 0..<probs.count {
                print("   \(String(format: "%.1f", probs[i] * 100))% — \(labelMap[i] ?? "unknown")")
            }

            let maxIdx     = probs.indices.max(by: { probs[$0] < probs[$1] }) ?? 0
            let confidence = probs[maxIdx]
            print("🏆 Best: \(labelMap[maxIdx] ?? "?") at \(Int(confidence * 100))%")

            guard confidence >= confidenceThreshold,
                  let label = labelMap[maxIdx] else {
                print("⚠️ Below threshold or unknown label")
                return
            }

            let detection = SoundDetection(label: label,
                                           confidence: confidence,
                                           timestamp: Date())
            await MainActor.run {
                self.lastDetection = detection
                self.recentDetections.insert(detection, at: 0)
                if self.recentDetections.count > 20 {
                    self.recentDetections.removeLast()
                }
            }

            triggerHaptic(for: detection)
            print("✅ Detection fired: \(label) \(Int(confidence * 100))%")

        } catch {
            print("❌ Inference error: \(error)")
        }
    }

    // MARK: - Softmax
    private func softmax(_ array: MLMultiArray) -> [Float] {
        let count  = array.count
        var floats = (0..<count).map { array[$0].floatValue }
        let maxVal = floats.max() ?? 0
        floats     = floats.map { exp($0 - maxVal) }
        let sum    = floats.reduce(0, +)
        return floats.map { $0 / (sum + 1e-8) }
    }

    // MARK: - Resample
    private func resample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        let ratio    = to / from
        let outCount = Int(Double(samples.count) * ratio)
        var output   = [Float](repeating: 0, count: outCount)
        for i in 0..<outCount {
            let srcIdx = Double(i) / ratio
            let lower  = Int(srcIdx)
            let upper  = min(lower + 1, samples.count - 1)
            let frac   = Float(srcIdx - Double(lower))
            output[i]  = samples[lower] * (1 - frac) + samples[upper] * frac
        }
        return output
    }

    // MARK: - Haptics
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()
        } catch {
            print("Haptic engine error: \(error)")
        }
    }

    private func triggerHaptic(for detection: SoundDetection) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = hapticEngine else { return }

        let events: [CHHapticEvent]

        if detection.isUrgent {
            events = (0..<4).map { i in
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                    ],
                    relativeTime: Double(i) * 0.2
                )
            }
        } else {
            events = [CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: 0
            )]
        }

        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player  = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Haptic play error: \(error)")
        }
    }
}
