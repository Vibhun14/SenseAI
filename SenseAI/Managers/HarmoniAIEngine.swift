import Foundation
import AVFoundation
import UIKit

// MARK: - Data Models
struct StemData: Codable {
    let energy: [Float]
    let onsets: [Int]?
    let strongOnsets: [Int]?
    let peakEnergy: Float
    enum CodingKeys: String, CodingKey {
        case energy
        case onsets
        case strongOnsets = "strong_onsets"
        case peakEnergy   = "peak_energy"
    }
}

struct SongMetadata: Codable {
    let title: String
    let durationSeconds: Double
    let sampleRate: Int
    let fps: Int
    let totalFrames: Int
    let tempoBpm: Double?
    let beatFrames: [Int]?
    enum CodingKeys: String, CodingKey {
        case title
        case durationSeconds = "duration_seconds"
        case sampleRate      = "sample_rate"
        case fps
        case totalFrames     = "total_frames"
        case tempoBpm        = "tempo_bpm"
        case beatFrames      = "beat_frames"
    }
}

struct StemsPayload: Codable {
    let drums: StemData
    let bass: StemData
    let vocals: StemData
    let other: StemData
}

struct SongStemData: Codable {
    let metadata: SongMetadata
    let stems: StemsPayload
}

// MARK: - Playback Mode
enum PlaybackMode: String, CaseIterable {
    case fullMix = "Full Mix"
    case stems   = "Stems"
}

// MARK: - Haptic Event (published so view can react)
enum HapticEvent {
    case none, soft, medium, heavy
}

// MARK: - HarmoniAI Engine
@MainActor
class HarmoniAIEngine: ObservableObject {

    @Published var isPlaying        = false
    @Published var isLoaded         = false
    @Published var currentTime: Double = 0
    @Published var duration:    Double = 0
    @Published var playbackMode: PlaybackMode = .fullMix
    @Published var errorMessage: String? = nil
    @Published var songTitle    = ""
    @Published var tempoBpm:    Double = 0

    @Published var drumsEnabled  = true
    @Published var bassEnabled   = true
    @Published var vocalsEnabled = true
    @Published var otherEnabled  = true

    @Published var drumsEnergy:  Float = 0
    @Published var bassEnergy:   Float = 0
    @Published var vocalsEnergy: Float = 0
    @Published var otherEnergy:  Float = 0
    @Published var isBeat        = false

    // Published haptic trigger — view observes this
    @Published var hapticEvent: HapticEvent = .none
    @Published var strongHit    = false  // true on heavy drum frame

    // Public fps for view frame calculations
    var fps: Double = 43.0

    private var songData: SongStemData?
    private var drumsStrongOnsets  = Set<Int>()
    private var bassStrongOnsets   = Set<Int>()
    private var vocalsStrongOnsets = Set<Int>()
    private var beatFramesSet      = Set<Int>()

    private var fullMixPlayer:  AVAudioPlayer?
    private var drumsPlayer:    AVAudioPlayer?
    private var bassPlayer:     AVAudioPlayer?
    private var vocalsPlayer:   AVAudioPlayer?
    private var otherPlayer:    AVAudioPlayer?

    private var displayLink: CADisplayLink?
    private var lastHapticFrame = -20
    private var lastStrongFrame = -20

    init() {}

    // MARK: - Load
    func loadSongData(jsonURL: URL, audioURL: URL,
                      drumsURL: URL? = nil, bassURL: URL? = nil,
                      vocalsURL: URL? = nil, otherURL: URL? = nil) {
        do {
            let data    = try Data(contentsOf: jsonURL)
            let decoded = try JSONDecoder().decode(SongStemData.self, from: data)
            songData    = decoded

            drumsStrongOnsets  = Set(decoded.stems.drums.strongOnsets  ?? [])
            bassStrongOnsets   = Set(decoded.stems.bass.strongOnsets   ?? [])
            vocalsStrongOnsets = Set(decoded.stems.vocals.strongOnsets ?? [])
            beatFramesSet      = Set(decoded.metadata.beatFrames       ?? [])

            songTitle = decoded.metadata.title
            duration  = decoded.metadata.durationSeconds
            tempoBpm  = decoded.metadata.tempoBpm ?? 0
            fps       = Double(decoded.metadata.fps)

            fullMixPlayer = try? AVAudioPlayer(contentsOf: audioURL)
            fullMixPlayer?.prepareToPlay()
            if let u = drumsURL  { drumsPlayer  = try? AVAudioPlayer(contentsOf: u); drumsPlayer?.prepareToPlay() }
            if let u = bassURL   { bassPlayer   = try? AVAudioPlayer(contentsOf: u); bassPlayer?.prepareToPlay() }
            if let u = vocalsURL { vocalsPlayer = try? AVAudioPlayer(contentsOf: u); vocalsPlayer?.prepareToPlay() }
            if let u = otherURL  { otherPlayer  = try? AVAudioPlayer(contentsOf: u); otherPlayer?.prepareToPlay() }

            isLoaded = true
            print("✅ HarmoniAI loaded: \(songTitle) @ \(fps) fps")
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    func togglePlayback() { isPlaying ? pause() : play() }

    func play() {
        guard isLoaded else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        if playbackMode == .fullMix {
            fullMixPlayer?.play()
        } else {
            let t = (drumsPlayer?.deviceCurrentTime ?? 0) + 0.1
            if drumsEnabled  { drumsPlayer?.play(atTime: t) }
            if bassEnabled   { bassPlayer?.play(atTime: t) }
            if vocalsEnabled { vocalsPlayer?.play(atTime: t) }
            if otherEnabled  { otherPlayer?.play(atTime: t) }
        }
        startDisplayLink()
        isPlaying = true
    }

    func pause() {
        fullMixPlayer?.pause()
        drumsPlayer?.pause(); bassPlayer?.pause()
        vocalsPlayer?.pause(); otherPlayer?.pause()
        stopDisplayLink()
        isPlaying = false
    }

    func seek(to time: Double) {
        fullMixPlayer?.currentTime = time
        drumsPlayer?.currentTime = time; bassPlayer?.currentTime = time
        vocalsPlayer?.currentTime = time; otherPlayer?.currentTime = time
    }

    func updateStemVolumes() {
        drumsPlayer?.volume  = drumsEnabled  ? 1 : 0
        bassPlayer?.volume   = bassEnabled   ? 1 : 0
        vocalsPlayer?.volume = vocalsEnabled ? 1 : 0
        otherPlayer?.volume  = otherEnabled  ? 1 : 0
    }

    private func startDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(onFrame))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate(); displayLink = nil
        drumsEnergy = 0; bassEnergy = 0; vocalsEnergy = 0; otherEnergy = 0
        isBeat = false; hapticEvent = .none; strongHit = false
    }

    @objc private func onFrame() {
        guard let data = songData else { return }

        let time = playbackMode == .fullMix
            ? fullMixPlayer?.currentTime ?? 0
            : drumsPlayer?.currentTime ?? 0
        currentTime = time

        let frame = Int(time * fps)
        guard frame >= 0 && frame < data.metadata.totalFrames else { return }

        let stems = data.stems
        drumsEnergy  = frame < stems.drums.energy.count  ? stems.drums.energy[frame]  : 0
        bassEnergy   = frame < stems.bass.energy.count   ? stems.bass.energy[frame]   : 0
        vocalsEnergy = frame < stems.vocals.energy.count ? stems.vocals.energy[frame] : 0
        otherEnergy  = frame < stems.other.energy.count  ? stems.other.energy[frame]  : 0
        isBeat       = beatFramesSet.contains(frame)

        // Haptics — moderate spacing, meaningful moments only
        strongHit = false
        hapticEvent = .none

        if drumsStrongOnsets.contains(frame) && frame - lastStrongFrame > 6 {
            lastStrongFrame = frame
            strongHit = true
            hapticEvent = .heavy
        } else if isBeat && bassStrongOnsets.contains(frame) && frame - lastHapticFrame > 8 {
            lastHapticFrame = frame
            hapticEvent = .medium
        } else if vocalsStrongOnsets.contains(frame) && frame - lastHapticFrame > 12 {
            lastHapticFrame = frame
            hapticEvent = .soft
        }

        if time >= data.metadata.durationSeconds { pause() }
    }

    func cleanup() {
        pause()
        fullMixPlayer = nil; drumsPlayer = nil; bassPlayer = nil
        vocalsPlayer = nil; otherPlayer = nil
        songData = nil; isLoaded = false
    }
}
