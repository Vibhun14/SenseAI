import SwiftUI
import UIKit
import Combine

// MARK: - Visual Entities

struct Comet {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: Double        // 1.0 → 0.0
    var maxLife: Double
    var thickness: CGFloat
    var color: Color
    var trail: [CGPoint]    // history of positions for trail
    var trailLength: Int
}

struct Shockwave {
    var x: CGFloat
    var y: CGFloat
    var radius: CGFloat
    var maxRadius: CGFloat
    var life: Double        // 1.0 → 0.0
    var color: Color
    var thickness: CGFloat
}

struct AuroraStreak {
    var points: [CGPoint]   // S-curve control points
    var life: Double
    var maxLife: Double
    var color: Color
    var width: CGFloat
    var phase: Double       // for animating the curve
}

struct GlowOrb {
    var x: CGFloat
    var y: CGFloat
    var radius: CGFloat
    var targetRadius: CGFloat
    var life: Double
    var color: Color
    var vx: CGFloat
    var vy: CGFloat
}

// MARK: - HarmoniAI View
struct HarmoniAIView: View {
    @StateObject private var engine = HarmoniAIEngine()

    // State
    @State private var phase:       Double = 0
    @State private var moodHue:     Double = 0.55
    @State private var comets:      [Comet]       = []
    @State private var shockwaves:  [Shockwave]   = []
    @State private var auroras:     [AuroraStreak] = []
    @State private var orbs:        [GlowOrb]     = []

    @State private var smoothBass:   Double = 0
    @State private var smoothDrums:  Double = 0
    @State private var smoothVocals: Double = 0
    @State private var smoothOther:  Double = 0

    // Throttle spawning
    @State private var frameCount: Int = 0
    @State private var lastCometFrame    = -30
    @State private var lastShockFrame    = -10
    @State private var lastAuroraFrame   = -60

    // Import
    @State private var showImporter  = false
    @State private var importSession = HarmoniImportSession()

    private let heavyGen  = UIImpactFeedbackGenerator(style: .heavy)
    private let mediumGen = UIImpactFeedbackGenerator(style: .medium)
    private let softGen   = UIImpactFeedbackGenerator(style: .soft)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── CANVAS ──
                GeometryReader { geo in
                    Canvas { ctx, size in
                        drawBackground(ctx: ctx, size: size)
                        drawAuroras(ctx: ctx, size: size)
                        drawOrbs(ctx: ctx, size: size)
                        drawComets(ctx: ctx, size: size)
                        drawShockwaves(ctx: ctx, size: size)
                    }
                }
                .frame(maxHeight: .infinity)
                .ignoresSafeArea(edges: .top)

                // ── SPECTRUM BARS ──
                spectrumBars
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                // ── CONTROLS ──
                controlsSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackButton(accentColor: hueColor(moodHue, s: 0.8, b: 1.0))
            }
        }
        .sheet(isPresented: $showImporter) { importerSheet }
        .onDisappear { engine.cleanup() }
        .onAppear {
            heavyGen.prepare()
            mediumGen.prepare()
            softGen.prepare()
        }
        .onChange(of: engine.hapticEvent) { event in
            switch event {
            case .heavy:  heavyGen.impactOccurred()
            case .medium: mediumGen.impactOccurred()
            case .soft:   softGen.impactOccurred()
            case .none:   break
            }
        }
        .onReceive(Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()) { _ in
            tick()
        }
    }

    // MARK: - Helper: Color from hue
    private func hueColor(_ h: Double, s: Double = 0.9, b: Double = 1.0,
                           a: Double = 1.0) -> Color {
        Color(hue: h.truncatingRemainder(dividingBy: 1.0), saturation: s, brightness: b)
            .opacity(a)
    }

    // MARK: - Draw: Background plasma
    private func drawBackground(ctx: GraphicsContext, size: CGSize) {
        let energy = smoothBass + smoothDrums * 0.5

        // Pure black → deep color wash based on energy
        let bgHue = (moodHue + 0.02).truncatingRemainder(dividingBy: 1.0)
        let bgAlpha = min(0.45 + energy * 0.12, 0.7)

        // Ambient glow pool at bottom (where bass lives)
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: size.width * 0.1,
                y: size.height * 0.55,
                width: size.width * 0.8,
                height: size.height * 0.6
            )),
            with: .radialGradient(
                Gradient(colors: [
                    hueColor(bgHue, s: 0.9, b: 0.6, a: bgAlpha * Double(smoothBass)),
                    hueColor(bgHue, s: 0.7, b: 0.3, a: 0)
                ]),
                center: CGPoint(x: size.width / 2, y: size.height * 0.85),
                startRadius: 0,
                endRadius: size.width * 0.6
            )
        )

        // Ambient glow at top (where treble/other lives)
        let topHue = (moodHue + 0.15).truncatingRemainder(dividingBy: 1.0)
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: size.width * 0.1, y: -size.height * 0.1,
                width: size.width * 0.8, height: size.height * 0.5
            )),
            with: .radialGradient(
                Gradient(colors: [
                    hueColor(topHue, s: 0.8, b: 0.5, a: 0.3 * Double(smoothOther)),
                    hueColor(topHue, s: 0.6, b: 0.2, a: 0)
                ]),
                center: CGPoint(x: size.width / 2, y: 0),
                startRadius: 0,
                endRadius: size.width * 0.55
            )
        )
    }

    // MARK: - Draw: Aurora streaks
    private func drawAuroras(ctx: GraphicsContext, size: CGSize) {
        for aurora in auroras {
            guard aurora.points.count >= 4 else { continue }
            let t = aurora.life / aurora.maxLife
            // Fade in first 20%, hold, fade out last 30%
            let alpha: Double
            if t > 0.8      { alpha = (1.0 - t) / 0.2 }
            else if t < 0.3 { alpha = t / 0.3 }
            else             { alpha = 1.0 }

            // Draw multiple passes for glow effect
            for pass in 0..<3 {
                let passWidth = aurora.width * CGFloat(pass + 1) * 0.8
                let passAlpha = alpha * (0.6 - Double(pass) * 0.18)
                guard passAlpha > 0 else { continue }

                var path = Path()
                let p    = aurora.points
                path.move(to: p[0])

                // Cubic bezier through all points
                var i = 0
                while i + 3 < p.count {
                    let animOffset = CGFloat(sin(aurora.phase + Double(i) * 0.8) * 8)
                    let cp1 = CGPoint(x: p[i+1].x, y: p[i+1].y + animOffset)
                    let cp2 = CGPoint(x: p[i+2].x, y: p[i+2].y - animOffset)
                    path.addCurve(to: p[i+3], control1: cp1, control2: cp2)
                    i += 3
                }

                ctx.stroke(
                    path,
                    with: .color(aurora.color.opacity(passAlpha)),
                    style: StrokeStyle(lineWidth: passWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Draw: Glow orbs
    private func drawOrbs(ctx: GraphicsContext, size: CGSize) {
        for orb in orbs {
            let t     = orb.life
            let alpha = t < 0.2 ? t / 0.2 : (t > 0.7 ? (1 - t) / 0.3 : 1.0)
            guard alpha > 0 else { continue }

            // Multi-layer glow
            for layer in 0..<3 {
                let lr = orb.radius * CGFloat(layer + 1) * 0.7
                let la = alpha * (0.5 - Double(layer) * 0.12)
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: orb.x - lr, y: orb.y - lr,
                        width: lr * 2, height: lr * 2
                    )),
                    with: .radialGradient(
                        Gradient(colors: [
                            orb.color.opacity(la),
                            orb.color.opacity(0)
                        ]),
                        center: CGPoint(x: orb.x, y: orb.y),
                        startRadius: 0,
                        endRadius: lr
                    )
                )
            }
        }
    }

    // MARK: - Draw: Comets with trails
    private func drawComets(ctx: GraphicsContext, size: CGSize) {
        for comet in comets {
            guard comet.trail.count > 1 else { continue }
            let alpha = comet.life / comet.maxLife

            // Draw trail — tapers from thick at head to thin at tail
            for i in 1..<comet.trail.count {
                let t0 = comet.trail[i - 1]
                let t1 = comet.trail[i]
                let progress = Double(i) / Double(comet.trail.count)
                let trailAlpha = alpha * progress * 0.9
                let trailWidth = comet.thickness * CGFloat(progress) * 0.8

                var seg = Path()
                seg.move(to: t0)
                seg.addLine(to: t1)
                ctx.stroke(
                    seg,
                    with: .color(comet.color.opacity(trailAlpha)),
                    style: StrokeStyle(lineWidth: trailWidth, lineCap: .round)
                )
            }

            // Draw comet head — bright core + glow
            if let head = comet.trail.last {
                let headR = comet.thickness * 1.8
                // Glow
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: head.x - headR * 2, y: head.y - headR * 2,
                        width: headR * 4, height: headR * 4
                    )),
                    with: .radialGradient(
                        Gradient(colors: [comet.color.opacity(alpha * 0.6), comet.color.opacity(0)]),
                        center: head, startRadius: 0, endRadius: headR * 2.5
                    )
                )
                // Core
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: head.x - headR * 0.5, y: head.y - headR * 0.5,
                        width: headR, height: headR
                    )),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
    }

    // MARK: - Draw: Shockwaves
    private func drawShockwaves(ctx: GraphicsContext, size: CGSize) {
        for wave in shockwaves {
            let progress = 1.0 - wave.life  // 0→1 as it expands
            let alpha    = wave.life * wave.life  // quad ease-out

            // Multiple rings per shockwave for depth
            for ring in 0..<3 {
                let rOffset = wave.radius - CGFloat(ring) * 12
                guard rOffset > 0 else { continue }
                let ringAlpha = alpha * (1.0 - Double(ring) * 0.3)
                let lineW     = wave.thickness * (1.0 - CGFloat(ring) * 0.3)

                var path = Path()
                path.addEllipse(in: CGRect(
                    x: wave.x - rOffset, y: wave.y - rOffset,
                    width: rOffset * 2, height: rOffset * 2
                ))
                ctx.stroke(path,
                           with: .color(wave.color.opacity(ringAlpha)),
                           style: StrokeStyle(lineWidth: lineW, lineCap: .round))
            }

            // Inner fill flash at start of shockwave
            if progress < 0.2 {
                let flashAlpha = (0.2 - progress) / 0.2 * 0.4
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: wave.x - wave.radius * 0.5, y: wave.y - wave.radius * 0.5,
                        width: wave.radius, height: wave.radius
                    )),
                    with: .radialGradient(
                        Gradient(colors: [wave.color.opacity(flashAlpha), wave.color.opacity(0)]),
                        center: CGPoint(x: wave.x, y: wave.y),
                        startRadius: 0, endRadius: wave.radius * 0.6
                    )
                )
            }
        }
    }

    // MARK: - 60fps Tick
    private func tick() {
        guard engine.isPlaying else { return }
        frameCount += 1
        phase += 0.02

        let d = Double(engine.drumsEnergy)
        let b = Double(engine.bassEnergy)
        let v = Double(engine.vocalsEnergy)
        let o = Double(engine.otherEnergy)

        // Exponential smoothing
        smoothDrums  += (d - smoothDrums)  * 0.3
        smoothBass   += (b - smoothBass)   * 0.22
        smoothVocals += (v - smoothVocals) * 0.18
        smoothOther  += (o - smoothOther)  * 0.15

        let energy = smoothBass + smoothDrums + smoothVocals + smoothOther

        // Mood hue drift
        moodHue = (moodHue + 0.001 + smoothBass * 0.002 + (engine.isBeat ? 0.005 : 0))
            .truncatingRemainder(dividingBy: 1.0)

        let size = CGSize(width: 390, height: 600)  // approximate canvas size

        // ── SPAWN: Comets on vocals ──
        // Vocals = comets shooting across the screen
        if smoothVocals > 0.2 && frameCount - lastCometFrame > max(8, Int(40 - smoothVocals * 30)) {
            lastCometFrame = frameCount
            spawnComet(size: size, energy: smoothVocals)
        }

        // ── SPAWN: Shockwave on drum hits ──
        if engine.strongHit && frameCount - lastShockFrame > 5 {
            lastShockFrame = frameCount
            spawnShockwave(size: size, intensity: CGFloat(smoothDrums))
        } else if engine.isBeat && frameCount - lastShockFrame > 15 {
            lastShockFrame = frameCount
            spawnShockwave(size: size, intensity: CGFloat(smoothBass) * 0.6)
        }

        // ── SPAWN: Aurora streaks on bass ──
        // Long sweeping streaks that persist through sustained bass
        if smoothBass > 0.3 && frameCount - lastAuroraFrame > max(25, Int(80 - smoothBass * 60)) {
            lastAuroraFrame = frameCount
            spawnAurora(size: size, energy: smoothBass)
        }

        // ── SPAWN: Orbs during quiet vocal moments ──
        if smoothVocals > 0.15 && smoothDrums < 0.3 && frameCount % 20 == 0 {
            spawnOrb(size: size, energy: smoothVocals)
        }

        // ── TICK: Update all entities ──
        tickComets()
        tickShockwaves()
        tickAuroras()
        tickOrbs()
    }

    // MARK: - Spawn Functions

    private func spawnComet(size: CGSize, energy: Double) {
        // Random edge origin
        let edge = Int.random(in: 0...3)
        let x: CGFloat
        let y: CGFloat
        let speed = CGFloat(energy * 8 + 4) * CGFloat.random(in: 0.8...1.4)

        switch edge {
        case 0: x = CGFloat.random(in: 0...size.width); y = -20
        case 1: x = size.width + 20; y = CGFloat.random(in: 0...size.height)
        case 2: x = CGFloat.random(in: 0...size.width); y = size.height + 20
        default: x = -20; y = CGFloat.random(in: 0...size.height)
        }

        // Aim roughly toward opposite area of screen
        let targetX = size.width - x + CGFloat.random(in: -100...100)
        let targetY = size.height - y + CGFloat.random(in: -100...100)
        let dx = targetX - x
        let dy = targetY - y
        let dist = sqrt(dx*dx + dy*dy)
        let vx = (dx / dist) * speed
        let vy = (dy / dist) * speed

        let hue = (moodHue + Double.random(in: -0.1...0.1)).truncatingRemainder(dividingBy: 1.0)
        let maxLife = Double.random(in: 1.5...3.0)

        comets.append(Comet(
            x: x, y: y,
            vx: vx, vy: vy,
            life: maxLife, maxLife: maxLife,
            thickness: CGFloat(energy * 4 + 2),
            color: hueColor(hue, s: 0.7, b: 1.0),
            trail: [CGPoint(x: x, y: y)],
            trailLength: Int(energy * 20 + 15)
        ))

        if comets.count > 12 { comets.removeFirst() }
    }

    private func spawnShockwave(size: CGSize, intensity: CGFloat) {
        // Spawn at random position — stronger hits = larger wave
        let x = CGFloat.random(in: size.width * 0.2 ... size.width * 0.8)
        let y = CGFloat.random(in: size.height * 0.2 ... size.height * 0.8)
        let maxR = size.width * (0.3 + intensity * 0.4)
        let hue  = (moodHue + 0.05).truncatingRemainder(dividingBy: 1.0)

        shockwaves.append(Shockwave(
            x: x, y: y,
            radius: 20,
            maxRadius: maxR,
            life: 1.0,
            color: hueColor(hue, s: 0.6, b: 1.0),
            thickness: 2 + intensity * 3
        ))

        if shockwaves.count > 8 { shockwaves.removeFirst() }
    }

    private func spawnAurora(size: CGSize, energy: Double) {
        // Horizontal sweeping S-curve across full width
        let y = CGFloat.random(in: size.height * 0.15 ... size.height * 0.85)
        let amplitude = CGFloat(energy * 60 + 20)
        let hue = (moodHue + Double.random(in: -0.08...0.08)).truncatingRemainder(dividingBy: 1.0)

        let points: [CGPoint] = [
            CGPoint(x: -40,              y: y + CGFloat.random(in: -amplitude...amplitude)),
            CGPoint(x: size.width * 0.1, y: y + CGFloat.random(in: -amplitude...amplitude)),
            CGPoint(x: size.width * 0.25,y: y + CGFloat.random(in: -amplitude...amplitude)),
            CGPoint(x: size.width * 0.5, y: y + CGFloat.random(in: -amplitude...amplitude)),
            CGPoint(x: size.width * 0.75,y: y + CGFloat.random(in: -amplitude...amplitude)),
            CGPoint(x: size.width * 0.9, y: y + CGFloat.random(in: -amplitude...amplitude)),
            CGPoint(x: size.width + 40,  y: y + CGFloat.random(in: -amplitude...amplitude))
        ]

        let maxLife = Double.random(in: (1.5 + energy)...(3.0 + energy * 1.5))

        auroras.append(AuroraStreak(
            points: points,
            life: maxLife,
            maxLife: maxLife,
            color: hueColor(hue, s: 0.8, b: 0.9),
            width: CGFloat(energy * 12 + 4),
            phase: Double.random(in: 0...Double.pi * 2)
        ))

        if auroras.count > 6 { auroras.removeFirst() }
    }

    private func spawnOrb(size: CGSize, energy: Double) {
        let hue = (moodHue + Double.random(in: -0.12...0.12)).truncatingRemainder(dividingBy: 1.0)
        let r   = CGFloat(energy * 30 + 15)

        orbs.append(GlowOrb(
            x: CGFloat.random(in: 60...330),
            y: CGFloat.random(in: 80...500),
            radius: 5,
            targetRadius: r,
            life: 1.0,
            color: hueColor(hue, s: 0.6, b: 1.0),
            vx: CGFloat.random(in: -0.4...0.4),
            vy: CGFloat.random(in: -0.8 ... -0.2)
        ))

        if orbs.count > 10 { orbs.removeFirst() }
    }

    // MARK: - Tick Functions

    private func tickComets() {
        let dt: Double = 1.0 / 60.0
        comets = comets.compactMap { c in
            var comet = c
            comet.life -= dt
            guard comet.life > 0 else { return nil }

            // Move
            comet.x += comet.vx
            comet.y += comet.vy

            // Add to trail
            comet.trail.append(CGPoint(x: comet.x, y: comet.y))
            if comet.trail.count > comet.trailLength {
                comet.trail.removeFirst()
            }

            return comet
        }
    }

    private func tickShockwaves() {
        let dt: Double = 1.0 / 60.0
        shockwaves = shockwaves.compactMap { w in
            var wave = w
            wave.life -= dt * 1.2
            guard wave.life > 0 else { return nil }
            let progress = 1.0 - wave.life
            wave.radius  = 20 + wave.maxRadius * CGFloat(progress)
            return wave
        }
    }

    private func tickAuroras() {
        let dt: Double = 1.0 / 60.0
        auroras = auroras.compactMap { a in
            var aurora = a
            aurora.life  -= dt
            aurora.phase += 0.04  // animate the S-curve wiggle
            guard aurora.life > 0 else { return nil }
            return aurora
        }
    }

    private func tickOrbs() {
        let dt: Double = 1.0 / 60.0
        orbs = orbs.compactMap { o in
            var orb = o
            orb.life -= dt * 0.4
            guard orb.life > 0 else { return nil }
            orb.x      += orb.vx
            orb.y      += orb.vy
            orb.radius += (orb.targetRadius - orb.radius) * 0.08
            return orb
        }
    }

    // MARK: - Spectrum Bars
    private var spectrumBars: some View {
        HStack(alignment: .bottom, spacing: 6) {
            SpectrumBar(label: "DRUMS",  energy: engine.drumsEnergy,
                        color: Color(red: 0.95, green: 0.95, blue: 0.95))
            SpectrumBar(label: "BASS",   energy: engine.bassEnergy,
                        color: hueColor(moodHue, s: 0.8, b: 1.0))
            SpectrumBar(label: "VOCALS", energy: engine.vocalsEnergy,
                        color: hueColor((moodHue + 0.15).truncatingRemainder(dividingBy: 1), s: 0.8, b: 1.0))
            SpectrumBar(label: "OTHER",  energy: engine.otherEnergy,
                        color: hueColor((moodHue + 0.3).truncatingRemainder(dividingBy: 1), s: 0.7, b: 0.9))
        }
        .frame(height: 68)
        .padding(14)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Controls
    private var controlsSection: some View {
        VStack(spacing: 12) {
            if engine.isLoaded {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.songTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 6) {
                            if engine.tempoBpm > 0 {
                                Text("\(Int(engine.tempoBpm)) BPM")
                                    .font(.system(size: 12))
                                    .foregroundStyle(hueColor(moodHue, s: 0.8, b: 1.0))
                            }
                        }
                    }
                    Spacer()
                    if engine.playbackMode == .stems {
                        HStack(spacing: 6) {
                            CompactStemDot(label: "D", isOn: $engine.drumsEnabled,
                                           color: Color(red: 0.95, green: 0.95, blue: 0.95))
                            CompactStemDot(label: "B", isOn: $engine.bassEnabled,
                                           color: Color(red: 0.38, green: 0.64, blue: 0.98))
                            CompactStemDot(label: "V", isOn: $engine.vocalsEnabled,
                                           color: Color(red: 0.98, green: 0.65, blue: 0.35))
                            CompactStemDot(label: "O", isOn: $engine.otherEnabled,
                                           color: Color(red: 0.20, green: 0.83, blue: 0.60))
                        }
                        .onChange(of: engine.drumsEnabled)  { _, _ in engine.updateStemVolumes() }
                        .onChange(of: engine.bassEnabled)   { _, _ in engine.updateStemVolumes() }
                        .onChange(of: engine.vocalsEnabled) { _, _ in engine.updateStemVolumes() }
                        .onChange(of: engine.otherEnabled)  { _, _ in engine.updateStemVolumes() }
                    }
                }

                SeekBar(currentTime: engine.currentTime,
                        duration: engine.duration) { engine.seek(to: $0) }

                HStack(spacing: 10) {
                    Button(action: {
                        engine.playbackMode = engine.playbackMode == .fullMix ? .stems : .fullMix
                    }) {
                        Text(engine.playbackMode == .fullMix ? "Mix" : "Stems")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(hueColor(moodHue))
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(hueColor(moodHue).opacity(0.12))
                            .clipShape(Capsule())
                    }

                    Button(action: { engine.togglePlayback() }) {
                        HStack(spacing: 8) {
                            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text(engine.isPlaying ? "Pause" : "Play")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(hueColor(moodHue))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: { showImporter = true }) {
                        Image(systemName: "folder").font(.system(size: 15))
                            .foregroundStyle(hueColor(moodHue))
                            .frame(width: 46, height: 46)
                            .background(hueColor(moodHue).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

            } else {
                Button(action: { showImporter = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Import Song + Stem Data")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color(red: 0.20, green: 0.83, blue: 0.60))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text("Process a song in the HarmoniAI Colab notebook first")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.gray.opacity(0.4))
                    .multilineTextAlignment(.center)
            }

            if let error = engine.errorMessage {
                Text(error).font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.51))
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Importer Sheet
    private var importerSheet: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text("Load a Song")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white).padding(.top, 32)
                    HarmoniImportView(session: $importSession) {
                        guard let json = importSession.jsonURL,
                              let audio = importSession.audioURL else { return }
                        engine.loadSongData(
                            jsonURL: json, audioURL: audio,
                            drumsURL: importSession.drumsURL,
                            bassURL: importSession.bassURL,
                            vocalsURL: importSession.vocalsURL,
                            otherURL: importSession.otherURL
                        )
                        showImporter = false
                    }
                    .padding(.horizontal, 20).padding(.bottom, 40)
                }
            }
        }
    }
}

// MARK: - Spectrum Bar
struct SpectrumBar: View {
    let label: String
    let energy: Float
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [color, color.opacity(0.4)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(height: max(3, geo.size.height * CGFloat(energy)))
                        .animation(.easeOut(duration: 0.05), value: energy)
                }
            }
            Text(label)
                .font(.system(size: 7, weight: .semibold)).tracking(0.5)
                .foregroundStyle(color.opacity(0.8))
        }
    }
}

// MARK: - Compact Stem Dot
struct CompactStemDot: View {
    let label: String
    @Binding var isOn: Bool
    let color: Color
    var body: some View {
        Button(action: { isOn.toggle() }) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOn ? .black : color.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(isOn ? color : color.opacity(0.1))
                .clipShape(Circle())
                .animation(.easeInOut(duration: 0.15), value: isOn)
        }
    }
}

// MARK: - Seek Bar
struct SeekBar: View {
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void
    private var progress: Double { duration > 0 ? currentTime / duration : 0 }
    private func fmt(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(height: 3)
                    Capsule().fill(Color.white.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(progress), height: 3)
                        .animation(.linear(duration: 0.1), value: progress)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    onSeek(max(0, min(1, v.location.x / geo.size.width)) * duration)
                })
            }
            .frame(height: 16)
            HStack {
                Text(fmt(currentTime)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray)
                Spacer()
                Text(fmt(duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.gray)
            }
        }
    }
}

#Preview {
    NavigationStack { HarmoniAIView() }.preferredColorScheme(.dark)
}
