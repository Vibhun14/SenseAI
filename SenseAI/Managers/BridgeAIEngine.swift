import Foundation
import AVFoundation
import Vision
import CoreML
import CoreHaptics
import UIKit

// MARK: - ASL Prediction Result
struct ASLPrediction {
    let letter: String
    let confidence: Float
    let timestamp: Date

    var isHighConfidence: Bool { confidence >= 0.85 }
}

// MARK: - BridgeAI Engine
@MainActor
class BridgeAIEngine: NSObject, ObservableObject {

    // MARK: - Published State
    @Published var isRunning          = false
    @Published var lastPrediction: ASLPrediction? = nil
    @Published var translatedText     = ""
    @Published var currentLetter      = ""
    @Published var handDetected       = false
    @Published var errorMessage: String? = nil
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    // MARK: - Camera
    private let captureSession    = AVCaptureSession()
    private let videoOutput       = AVCaptureVideoDataOutput()
    private let sessionQueue      = DispatchQueue(label: "com.senseai.bridge.session")

    // MARK: - Vision
    private var handPoseRequest   = VNDetectHumanHandPoseRequest()

    // MARK: - Core ML
    private var model: ASLClassifier?

    // MARK: - Smoothing — require same letter N times before accepting
    private var predictionBuffer: [String] = []
    private let smoothingWindow   = 5     // frames
    private let confirmThreshold  = 4     // must appear 4/5 times
    private var lastConfirmedLetter = ""
    private var holdFrames        = 0
    private let holdRequired      = 15    // frames to hold before appending to text

    // MARK: - Confidence
    private let confidenceThreshold: Float = 0.75

    // MARK: - Label map (26 letters)
    private let labelMap: [Int: String] = {
        guard let url  = Bundle.main.url(forResource: "asl_label_map", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw  = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            // Fallback hardcoded
            return Dictionary(uniqueKeysWithValues: (0..<26).map {
                ($0, String(UnicodeScalar(65 + $0)!))
            })
        }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v -> (Int, String)? in
            guard let i = Int(k) else { return nil }
            return (i, v)
        })
    }()

    // MARK: - Init
    override init() {
        super.init()
        loadModel()
        handPoseRequest.maximumHandCount = 2
    }

    // MARK: - Load Model
    private func loadModel() {
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            model = try ASLClassifier(configuration: config)
            print("✅ ASLClassifier loaded — \(labelMap.count) classes")
        } catch {
            errorMessage = "Failed to load ASL model: \(error.localizedDescription)"
            print("❌ Model error: \(error)")
        }
    }

    // MARK: - Start Camera
    func startCamera() {
        guard !isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.configureSession()
            self?.captureSession.startRunning()
            Task { @MainActor [weak self] in
                self?.isRunning = true
            }
        }
    }

    // MARK: - Stop Camera
    func stopCamera() {
        guard isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            Task { @MainActor [weak self] in
                self?.isRunning = false
                self?.handDetected = false
                self?.currentLetter = ""
            }
        }
    }

    // MARK: - Configure Camera Session
    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        // Front camera for self-signing
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .front),
              let input  = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input)
        else {
            Task { @MainActor [weak self] in
                self?.errorMessage = "Camera unavailable"
            }
            return
        }

        captureSession.addInput(input)

        // Video output
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Set portrait orientation
        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
            connection.isVideoMirrored = true
        }

        captureSession.commitConfiguration()

        // Preview layer
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        Task { @MainActor [weak self] in
            self?.previewLayer = layer
        }
    }

    // MARK: - Process Frame with Vision
    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: [:])
        do {
            try handler.perform([handPoseRequest])
        } catch {
            return
        }

        guard let observation = handPoseRequest.results?
            .max(by: { a, b in
                let confA = (try? a.recognizedPoints(.all))?.values.map(\.confidence).reduce(0, +) ?? 0
                let confB = (try? b.recognizedPoints(.all))?.values.map(\.confidence).reduce(0, +) ?? 0
                return confA < confB
            }) else {
            Task { @MainActor [weak self] in
                self?.handDetected = false
                self?.currentLetter = ""
            }
            predictionBuffer.removeAll()
            return
        }

        Task { @MainActor [weak self] in self?.handDetected = true }

        // Extract landmarks → normalize → predict
        if let landmarks = extractNormalizedLandmarks(from: observation) {
            runInference(landmarks: landmarks)
        }
    }

    // MARK: - Extract & Normalize Landmarks
    // THIS IS THE CRITICAL STEP — must exactly match training normalization
    private func extractNormalizedLandmarks(from observation: VNHumanHandPoseObservation) -> [Float]? {

        // All 21 hand joints in MediaPipe order
        let jointNames: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        // Build raw coordinate array [21 x 3] — Vision gives x, y; z = 0
//        var coords = [[Float]](repeating: [0, 0, 0], count: 21)
//        for (i, joint) in jointNames.enumerated() {
//            if let point = points[joint], point.confidence > 0.3 {
//                coords[i][0] = Float(point.location.x)
//                coords[i][1] = Float(point.location.y)
//                coords[i][2] = 0.0  // Vision doesn't provide Z; training used z=0 for static images
//            }
//        }
        var coords = [[Float]](repeating: [0, 0, 0], count: 21)
        for (i, joint) in jointNames.enumerated() {
            if let point = points[joint], point.confidence > 0.3 {
                coords[i][0] = Float(point.location.x)
                coords[i][1] = 1.0 - Float(point.location.y)  // flip Y to match training
                coords[i][2] = 0.0
            }
        }
        
        // Mirror left hand to match right-hand training data
        let chirality = observation.chirality
        if chirality == .left {
            for i in 0..<21 {
                coords[i][0] = 1.0 - coords[i][0]
            }
        }

        // ── NORMALIZATION (must match training exactly) ──

        // Step 1: Subtract wrist (index 0) from all 21 points
        let wristX = coords[0][0]
        let wristY = coords[0][1]
        let wristZ = coords[0][2]
        for i in 0..<21 {
            coords[i][0] -= wristX
            coords[i][1] -= wristY
            coords[i][2] -= wristZ
        }

        // Step 2: Find max absolute value across all coordinates
        var maxDist: Float = 0
        for i in 0..<21 {
            maxDist = max(maxDist, abs(coords[i][0]))
            maxDist = max(maxDist, abs(coords[i][1]))
            maxDist = max(maxDist, abs(coords[i][2]))
        }

        // Step 3: Divide by max distance (scale-invariant)
        if maxDist > 0 {
            for i in 0..<21 {
                coords[i][0] /= maxDist
                coords[i][1] /= maxDist
                coords[i][2] /= maxDist
            }
        }

        // Flatten to [63] — x0,y0,z0, x1,y1,z1, ...
        return coords.flatMap { $0 }
    }

    // MARK: - Run Core ML Inference
    private func runInference(landmarks: [Float]) {
        guard let model = model else { return }

        guard let inputArray = try? MLMultiArray(shape: [1, 63], dataType: .float32) else {
            return
        }

        for i in 0..<63 {
            inputArray[[0, i] as [NSNumber]] = NSNumber(value: landmarks[i])
        }

        do {
            let input  = ASLClassifierInput(landmarks: inputArray)
            let output = try model.prediction(input: input)
            let probs  = softmax(output.classLogits)

            let maxIdx     = probs.indices.max(by: { probs[$0] < probs[$1] }) ?? 0
            let confidence = probs[maxIdx]
            let letter     = labelMap[maxIdx] ?? "?"

            // Smooth predictions
            smoothAndUpdate(letter: letter, confidence: confidence)

        } catch {
            print("❌ Inference error: \(error)")
        }
    }

    // MARK: - Smoothing & Text Building
    private func smoothAndUpdate(letter: String, confidence: Float) {
        guard confidence >= confidenceThreshold else {
            predictionBuffer.removeAll()
            Task { @MainActor [weak self] in self?.currentLetter = "" }
            return
        }

        // Add to rolling buffer
        predictionBuffer.append(letter)
        if predictionBuffer.count > smoothingWindow {
            predictionBuffer.removeFirst()
        }

        // Count occurrences of most common letter
        let counts = Dictionary(predictionBuffer.map { ($0, 1) }, uniquingKeysWith: +)
        guard let (topLetter, topCount) = counts.max(by: { $0.value < $1.value }),
              topCount >= confirmThreshold
        else {
            Task { @MainActor [weak self] in self?.currentLetter = "" }
            return
        }

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.currentLetter = topLetter

            let prediction = ASLPrediction(
                letter: topLetter,
                confidence: confidence,
                timestamp: Date()
            )
            self.lastPrediction = prediction

            // Hold detection — append letter to text after holding long enough
            if topLetter == self.lastConfirmedLetter {
                self.holdFrames += 1
                if self.holdFrames == self.holdRequired {
                    // Special: space bar gesture could be added later
                    self.translatedText += topLetter
                }
            } else {
                self.lastConfirmedLetter = topLetter
                self.holdFrames = 0
            }
        }
    }

    // MARK: - Text Controls
    func clearText() { translatedText = "" }
    func addSpace() { translatedText += " " }
    func deleteLastChar() {
        if !translatedText.isEmpty { translatedText.removeLast() }
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
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension BridgeAIEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                    didOutput sampleBuffer: CMSampleBuffer,
                                    from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task { await self.processFrame(pixelBuffer) }
    }
}
