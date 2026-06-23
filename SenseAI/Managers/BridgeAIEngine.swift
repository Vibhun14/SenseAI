import Foundation
import AVFoundation
import Vision
import CoreML
import CoreHaptics
import UIKit
import Photos
import CoreImage

// MARK: - ASL Prediction Result
struct ASLPrediction {
    let letter: String
    let confidence: Float
    let timestamp: Date

    var isHighConfidence: Bool { confidence >= 0.85 }
}

// MARK: - Recording State
enum RecordingState {
    case idle
    case recording
    case processing
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

    // MARK: - Recording State
    @Published var recordingState: RecordingState = .idle
    @Published var recordWithAudio: Bool = true
    @Published var recordingDuration: TimeInterval = 0
    @Published var processingProgress: Double = 0
    @Published var showShareSheet: Bool = false
    @Published var recordedVideoURL: URL? = nil
    @Published var recordingError: String? = nil
    @Published var isVideoReadyToShare: Bool = false

    private var recordingTimer: Timer?
    private var recordingStartTime: Date?
    private var processingTimer: Timer?

    // MARK: - Camera
    private let captureSession    = AVCaptureSession()
    private let videoOutput       = AVCaptureVideoDataOutput()
    private let audioOutput       = AVCaptureAudioDataOutput()
    private let sessionQueue      = DispatchQueue(label: "com.senseai.bridge.session")
    private var audioInputConfigured = false

    // MARK: - Vision
    private var handPoseRequest   = VNDetectHumanHandPoseRequest()

    // MARK: - Video Recording
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var firstPresentationTime: CMTime?
    private let recordingSize = CGSize(width: 720, height: 1280)
    private let ciContext = CIContext()

    // MARK: - Core ML
    private var model: ASLClassifier?

    // MARK: - Smoothing
    private var predictionBuffer: [String] = []
    private let smoothingWindow   = 5
    private let confirmThreshold  = 4
    private var lastConfirmedLetter = ""
    private var holdFrames        = 0
    private let holdRequired      = 15

    // MARK: - Confidence
    private let confidenceThreshold: Float = 0.75

    // MARK: - Label map (26 letters)
    private let labelMap: [Int: String] = {
        guard let url  = Bundle.main.url(forResource: "asl_label_map", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw  = try? JSONDecoder().decode([String: String].self, from: data)
        else {
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
        // Stop recording first if active
        if recordingState == .recording {
            stopRecording()
        }
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
        if !captureSession.inputs.isEmpty || !captureSession.outputs.isEmpty {
            captureSession.commitConfiguration()
            return
        }
        captureSession.sessionPreset = .medium

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                    for: .video,
                                                    position: .front),
              let input  = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            Task { @MainActor [weak self] in
                self?.errorMessage = "Camera unavailable"
            }
            return
        }

        captureSession.addInput(input)

        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        configureAudioCaptureIfAllowed()

        if let connection = videoOutput.connection(with: .video) {
            connection.videoRotationAngle = 90
            connection.isVideoMirrored = true
        }

        captureSession.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        Task { @MainActor [weak self] in
            self?.previewLayer = layer
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard recordingState == .idle else { return }
        recordingError = nil
        isVideoReadyToShare = false
        recordedVideoURL = nil
        processingProgress = 0

        if recordWithAudio {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized:
                sessionQueue.async { [weak self] in
                    guard let self else { return }
                    self.captureSession.beginConfiguration()
                    self.configureAudioCaptureIfAllowed()
                    self.captureSession.commitConfiguration()
                }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if granted {
                            self.startRecording()
                        } else {
                            self.recordingError = "Microphone access is needed to record with audio. Turn audio off or allow microphone access in Settings."
                        }
                    }
                }
                return
            default:
                recordingError = "Microphone access is needed to record with audio. Turn audio off or allow microphone access in Settings."
                return
            }
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BridgeAI_\(Int(Date().timeIntervalSince1970)).mp4")

        do {
            try prepareWriter(outputURL: outputURL)
        } catch {
            recordingError = "Could not prepare recording: \(error.localizedDescription)"
            return
        }

        recordingState = .recording
        recordingStartTime = Date()

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        }
    }

    func stopRecording() {
        guard recordingState == .recording else { return }
        recordingState = .processing
        beginProcessingProgress()
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0

        videoWriterInput?.markAsFinished()
        if recordWithAudio {
            audioWriterInput?.markAsFinished()
        }

        assetWriter?.finishWriting { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processingTimer?.invalidate()
                self.processingTimer = nil
                self.recordingState = .idle
                self.processingProgress = 1

                if self.assetWriter?.status == .completed {
                    self.isVideoReadyToShare = self.recordedVideoURL != nil
                } else {
                    let message = self.assetWriter?.error?.localizedDescription ?? "Unknown export error"
                    self.recordingError = "Recording failed: \(message)"
                }

                self.assetWriter = nil
                self.videoWriterInput = nil
                self.audioWriterInput = nil
                self.pixelBufferAdaptor = nil
                self.firstPresentationTime = nil
            }
        }
    }

    func shareRecording() {
        guard recordedVideoURL != nil, recordingState == .idle else { return }
        showShareSheet = true
    }

    private func prepareWriter(outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(recordingSize.width),
            AVVideoHeightKey: Int(recordingSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(recordingSize.width),
                kCVPixelBufferHeightKey as String: Int(recordingSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )

        guard writer.canAdd(videoInput) else {
            throw NSError(domain: "BridgeAIRecording", code: 1, userInfo: [NSLocalizedDescriptionKey: "Video writer input is unavailable."])
        }
        writer.add(videoInput)

        if recordWithAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 96_000
            ]
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true
            if writer.canAdd(audioInput) {
                writer.add(audioInput)
                audioWriterInput = audioInput
            }
        }

        guard writer.startWriting() else {
            throw writer.error ?? NSError(domain: "BridgeAIRecording", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not start the MP4 writer."])
        }

        assetWriter = writer
        videoWriterInput = videoInput
        pixelBufferAdaptor = adaptor
        recordedVideoURL = outputURL
    }

    private func beginProcessingProgress() {
        processingProgress = 0.12
        processingTimer?.invalidate()
        processingTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.recordingState == .processing else { return }
                self.processingProgress = min(0.92, self.processingProgress + 0.035)
            }
        }
    }

    private func configureAudioCaptureIfAllowed() {
        guard !audioInputConfigured,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input)
        else { return }

        captureSession.addInput(input)
        audioOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        if captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(audioOutput)
        }
        audioInputConfigured = true
    }

    func saveVideoToPhotos(url: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, _ in
                DispatchQueue.main.async { completion(success) }
            }
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

        if let landmarks = extractNormalizedLandmarks(from: observation) {
            runInference(landmarks: landmarks)
        }
    }

    // MARK: - Extract & Normalize Landmarks
    private func extractNormalizedLandmarks(from observation: VNHumanHandPoseObservation) -> [Float]? {
        let jointNames: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        var coords = [[Float]](repeating: [0, 0, 0], count: 21)
        for (i, joint) in jointNames.enumerated() {
            if let point = points[joint], point.confidence > 0.3 {
                coords[i][0] = Float(point.location.x)
                coords[i][1] = 1.0 - Float(point.location.y)
                coords[i][2] = 0.0
            }
        }

        let chirality = observation.chirality
        if chirality == .left {
            for i in 0..<21 { coords[i][0] = 1.0 - coords[i][0] }
        }

        let wristX = coords[0][0], wristY = coords[0][1], wristZ = coords[0][2]
        for i in 0..<21 {
            coords[i][0] -= wristX
            coords[i][1] -= wristY
            coords[i][2] -= wristZ
        }

        var maxDist: Float = 0
        for i in 0..<21 {
            maxDist = max(maxDist, abs(coords[i][0]))
            maxDist = max(maxDist, abs(coords[i][1]))
            maxDist = max(maxDist, abs(coords[i][2]))
        }

        if maxDist > 0 {
            for i in 0..<21 {
                coords[i][0] /= maxDist
                coords[i][1] /= maxDist
                coords[i][2] /= maxDist
            }
        }

        return coords.flatMap { $0 }
    }

    // MARK: - Run Core ML Inference
    private func runInference(landmarks: [Float]) {
        guard let model = model else { return }
        guard let inputArray = try? MLMultiArray(shape: [1, 63], dataType: .float32) else { return }
        for i in 0..<63 { inputArray[[0, i] as [NSNumber]] = NSNumber(value: landmarks[i]) }

        do {
            let input  = ASLClassifierInput(landmarks: inputArray)
            let output = try model.prediction(input: input)
            let probs  = softmax(output.classLogits)
            let maxIdx = probs.indices.max(by: { probs[$0] < probs[$1] }) ?? 0
            smoothAndUpdate(letter: labelMap[maxIdx] ?? "?", confidence: probs[maxIdx])
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

        predictionBuffer.append(letter)
        if predictionBuffer.count > smoothingWindow { predictionBuffer.removeFirst() }

        let counts = Dictionary(predictionBuffer.map { ($0, 1) }, uniquingKeysWith: +)
        guard let (topLetter, topCount) = counts.max(by: { $0.value < $1.value }),
              topCount >= confirmThreshold
        else {
            Task { @MainActor [weak self] in self?.currentLetter = "" }
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentLetter = topLetter
            self.lastPrediction = ASLPrediction(letter: topLetter, confidence: confidence, timestamp: Date())

            if topLetter == self.lastConfirmedLetter {
                self.holdFrames += 1
                if self.holdFrames == self.holdRequired { self.translatedText += topLetter }
            } else {
                self.lastConfirmedLetter = topLetter
                self.holdFrames = 0
            }
        }
    }

    // MARK: - Text Controls
    func clearText() { translatedText = "" }
    func addSpace() { translatedText += " " }
    func deleteLastChar() { if !translatedText.isEmpty { translatedText.removeLast() } }

    // MARK: - Recording Frames
    private func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer, pixelBuffer: CVPixelBuffer) {
        guard recordingState == .recording,
              let writer = assetWriter,
              let videoInput = videoWriterInput,
              let adaptor = pixelBufferAdaptor,
              videoInput.isReadyForMoreMediaData
        else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if firstPresentationTime == nil {
            firstPresentationTime = presentationTime
            writer.startSession(atSourceTime: presentationTime)
        }

        guard let composedBuffer = makeComposedPixelBuffer(
            from: pixelBuffer,
            letter: currentLetter,
            translation: translatedText
        ) else { return }

        adaptor.append(composedBuffer, withPresentationTime: presentationTime)
    }

    private func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard recordingState == .recording,
              recordWithAudio,
              firstPresentationTime != nil,
              let audioInput = audioWriterInput,
              audioInput.isReadyForMoreMediaData
        else { return }

        audioInput.append(sampleBuffer)
    }

    private func makeComposedPixelBuffer(from sourceBuffer: CVPixelBuffer, letter: String, translation: String) -> CVPixelBuffer? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: recordingSize, format: format)
        let image = renderer.image { context in
            let cgContext = context.cgContext
            UIColor(red: 0.04, green: 0.04, blue: 0.07, alpha: 1).setFill()
            cgContext.fill(CGRect(origin: .zero, size: recordingSize))

            drawCameraFrame(from: sourceBuffer, in: cgContext)
            drawRecordingOverlay(letter: letter, translation: translation, in: cgContext)
        }

        return makePixelBuffer(from: image)
    }

    private func drawCameraFrame(from sourceBuffer: CVPixelBuffer, in context: CGContext) {
        let cameraRect = CGRect(x: 0, y: 0, width: recordingSize.width, height: 860)
        let ciImage = CIImage(cvPixelBuffer: sourceBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        context.saveGState()
        context.addPath(UIBezierPath(roundedRect: cameraRect.insetBy(dx: 28, dy: 28), cornerRadius: 28).cgPath)
        context.clip()

        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = max(cameraRect.width / sourceSize.width, cameraRect.height / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = CGRect(
            x: cameraRect.midX - drawSize.width / 2,
            y: cameraRect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        UIImage(cgImage: cgImage).draw(in: drawRect)
        context.restoreGState()

        UIColor.white.withAlphaComponent(0.14).setStroke()
        let strokePath = UIBezierPath(roundedRect: cameraRect.insetBy(dx: 28, dy: 28), cornerRadius: 28)
        strokePath.lineWidth = 2
        strokePath.stroke()
    }

    private func drawRecordingOverlay(letter: String, translation: String, in context: CGContext) {
        let letterText = letter.isEmpty ? "-" : letter
        let letterRect = CGRect(x: recordingSize.width - 166, y: 676, width: 110, height: 110)
        UIColor.black.withAlphaComponent(0.62).setFill()
        UIBezierPath(roundedRect: letterRect, cornerRadius: 18).fill()

        let letterAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let letterSize = letterText.size(withAttributes: letterAttributes)
        letterText.draw(
            at: CGPoint(x: letterRect.midX - letterSize.width / 2, y: letterRect.midY - letterSize.height / 2),
            withAttributes: letterAttributes
        )

        let captionRect = CGRect(x: 36, y: 908, width: recordingSize.width - 72, height: 300)
        UIColor(red: 0.07, green: 0.07, blue: 0.10, alpha: 1).setFill()
        UIBezierPath(roundedRect: captionRect, cornerRadius: 24).fill()

        let title = "FULL TRANSLATION"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: UIColor(white: 1, alpha: 0.45)
        ]
        title.draw(at: CGPoint(x: captionRect.minX + 28, y: captionRect.minY + 26), withAttributes: titleAttributes)

        let body = translation.isEmpty ? "Translation will appear here as signs are detected." : translation
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 6
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: translation.isEmpty ? 30 : 40, weight: .medium),
            .foregroundColor: translation.isEmpty ? UIColor(white: 1, alpha: 0.42) : UIColor.white,
            .paragraphStyle: paragraph
        ]
        body.draw(
            with: captionRect.insetBy(dx: 28, dy: 78),
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: bodyAttributes,
            context: nil
        )
    }

    private func makePixelBuffer(from image: UIImage) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(recordingSize.width),
            Int(recordingSize.height),
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(recordingSize.width),
            height: Int(recordingSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ), let cgImage = image.cgImage else { return nil }

        context.draw(cgImage, in: CGRect(origin: .zero, size: recordingSize))
        return pixelBuffer
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
extension BridgeAIEngine: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                    didOutput sampleBuffer: CMSampleBuffer,
                                    from connection: AVCaptureConnection) {
        if output is AVCaptureAudioDataOutput {
            Task { await self.appendAudioSampleBuffer(sampleBuffer) }
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        Task {
            await self.processFrame(pixelBuffer)
            await self.appendVideoSampleBuffer(sampleBuffer, pixelBuffer: pixelBuffer)
        }
    }
}
