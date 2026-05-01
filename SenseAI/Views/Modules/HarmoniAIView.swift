import SwiftUI
import UIKit

// MARK: - Visual Entities

struct BassRing {
    var radius: CGFloat
    var maxRadius: CGFloat
    var life: Double
    var thickness: CGFloat
    var hue: Double
    var x: CGFloat
    var y: CGFloat
    var speed: CGFloat
}

struct DrumBurst {
    var x: CGFloat
    var y: CGFloat
    var rings: [DrumRing]
    var strongHit: Bool
}

struct DrumRing {
    var radius: CGFloat
    var maxRadius: CGFloat
    var life: Double
    var hue: Double
    var thickness: CGFloat
}

struct VocalParticle {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: Double
    var maxLife: Double
    var size: CGFloat
    var hue: Double
    var trail: [CGPoint]
    var trailLen: Int
}

struct StarNode {
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: Double
    var maxLife: Double
    var radius: CGFloat
    var hue: Double
}

// MARK: - Render State
// All mutable visual data in one struct — mutated once per tick, Canvas reads it passively.
struct RenderState {
    var phase: Double = 0
    var moodHue: Double = 0.55
    var beatScale: CGFloat = 1.0
    var beatFlashLife: Double = 0
    var beatFlashIntensity: Double = 0

    var sDrums: Double = 0
    var sBass: Double = 0
    var sVocals: Double = 0
    var sOther: Double = 0

    var bassRings: [BassRing] = []
    var drumBursts: [DrumBurst] = []
    var vocalParts: [VocalParticle] = []
    var starNodes: [StarNode] = []

    // 24-band EQ with peak hold
    var eqBands: [Float] = Array(repeating: 0, count: 24)
    var eqPeaks: [Float] = Array(repeating: 0, count: 24)
}

// MARK: - HarmoniAI View
struct HarmoniAIView: View {
    @StateObject private var engine = HarmoniAIEngine()
    @State private var state = RenderState()

    @State private var lastBassRing   = -10
    @State private var lastDrumBurst  = -10
    @State private var lastVocalSpawn = -5
    @State private var lastStarSpawn  = -20
    @State private var frameCount     = 0

    @State private var peakDrums:  Double = 0.1
    @State private var peakBass:   Double = 0.1
    @State private var peakVocals: Double = 0.1

    private let heavyGen  = UIImpactFeedbackGenerator(style: .heavy)
    private let mediumGen = UIImpactFeedbackGenerator(style: .heavy)   // was .medium
    private let softGen   = UIImpactFeedbackGenerator(style: .medium)  // was .soft

    @State private var showImporter  = false
    @State private var importSession = HarmoniImportSession()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // Canvas — TimelineView drives rendering, Canvas draws the current state value.
                // No SwiftUI view diffing overhead inside the canvas — purely imperative draw calls.
                GeometryReader { _ in
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !engine.isPlaying)) { timeline in

                        Canvas { ctx, size in
                            drawScene(ctx: ctx, size: size)
                        }
                        .onChange(of: timeline.date) { _, _ in
                            tick()
                        }
                    }
                    .scaleEffect(state.beatScale)
                    .ignoresSafeArea(edges: .top)
                }

                // EQ visualizer
                eqVisualizer
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                // Stem bars
                spectrumBars
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                // Controls
                controlsSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                BackButton(accentColor: hueColor(state.moodHue, s: 0.8, b: 1.0))
            }
        }
        .sheet(isPresented: $showImporter) { importerSheet }
        .onDisappear { engine.cleanup() }
        .onAppear { heavyGen.prepare(); mediumGen.prepare(); softGen.prepare() }
        .onChange(of: engine.hapticEvent) { event in
            switch event {
            case .heavy:
                heavyGen.impactOccurred(intensity: 1.0)
                // Double-punch for strong hits — second buzz ~12ms later
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
                    heavyGen.impactOccurred(intensity: 0.85)
                }
            case .medium: mediumGen.impactOccurred(intensity: 1.0)
            case .soft:   softGen.impactOccurred(intensity: 1.0)
            case .none:   break
            }
        }
//        .onReceive(Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()) { _ in
//            guard engine.isPlaying else { return }
//            tick()
//        }
    }

    // MARK: - Color helper
    private func hueColor(_ h: Double, s: Double = 0.9, b: Double = 1.0, a: Double = 1.0) -> Color {
        Color(hue: h.truncatingRemainder(dividingBy: 1.0), saturation: s, brightness: b).opacity(a)
    }

    // MARK: - EQ Visualizer
    private var eqVisualizer: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(state.eqBands.enumerated()), id: \.offset) { i, val in

                let hue = (state.moodHue + Double(i) / 24.0 * 0.24)
                    .truncatingRemainder(dividingBy: 1.0)

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            Color(
                                hue: hue,
                                saturation: 0.9,
                                brightness: 1.0
                            )
                        )
                        .frame(height: max(6, CGFloat(val) * 210))
                        .animation(.linear(duration: 0.045), value: val)
                }
            }
        }
        .frame(height: 220)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    // MARK: - Draw (pure reads of state — no mutation)

    private func drawScene(ctx: GraphicsContext, size: CGSize) {
        drawBassPulse(ctx: ctx, size: size)
        drawBeatFlash(ctx: ctx, size: size)
        drawStarField(ctx: ctx, size: size)
        drawBassRings(ctx: ctx, size: size)
        drawVocalParticles(ctx: ctx, size: size)
        drawDrumBursts(ctx: ctx, size: size)
    }

    private func drawBassPulse(ctx: GraphicsContext, size: CGSize) {
        let b = state.sBass
        guard b > 0.02 else { return }
        let cx = size.width / 2
        let cy = size.height * 0.62

        for i in 0..<3 {
            let breathe = CGFloat(sin(state.phase * 0.9 + Double(i) * 1.1) * 0.08 + 1.0)
            let radius = size.width * CGFloat(0.28 + Double(i) * 0.2) * CGFloat(b * 0.55 + 0.45) * breathe
            let hue = (state.moodHue + Double(i) * 0.045).truncatingRemainder(dividingBy: 1.0)
            let alpha = b * (0.20 - Double(i) * 0.05)
            guard alpha > 0.005 else { continue }
            ctx.fill(
                Path(ellipseIn: CGRect(x: cx - radius, y: cy - radius * 0.65, width: radius * 2, height: radius * 1.3)),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(hue: hue, saturation: 0.95, brightness: 0.8).opacity(alpha),
                        Color(hue: hue, saturation: 0.7,  brightness: 0.4).opacity(0)
                    ]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: radius
                )
            )
        }

        // Interference sine waves
        let waveY = size.height * 0.74
        let amp = CGFloat(b * 38)
        let segs = 60
        var w1 = Path(), w2 = Path()
        for s in 0...segs {
            let t = Double(s) / Double(segs)
            let wx = size.width * CGFloat(t)
            let wy1 = waveY + amp * CGFloat(sin(t * .pi * 5.5 + state.phase * 2.8))
            let wy2 = waveY + amp * CGFloat(sin(t * .pi * 5.5 + state.phase * 2.8 + .pi))
            if s == 0 { w1.move(to: .init(x: wx, y: wy1)); w2.move(to: .init(x: wx, y: wy2)) }
            else       { w1.addLine(to: .init(x: wx, y: wy1)); w2.addLine(to: .init(x: wx, y: wy2)) }
        }
        ctx.stroke(w1, with: .color(Color(hue: state.moodHue, saturation: 0.8, brightness: 1.0).opacity(b * 0.30)),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        ctx.stroke(w2, with: .color(Color(hue: (state.moodHue + 0.05).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.9).opacity(b * 0.15)),
                   style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
    }

    private func drawBeatFlash(ctx: GraphicsContext, size: CGSize) {
        guard state.beatFlashLife > 0 else { return }
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(hue: state.moodHue, saturation: 0.25, brightness: 1.0)
                    .opacity(state.beatFlashLife * state.beatFlashIntensity * 0.15)))
    }

    private func drawStarField(ctx: GraphicsContext, size: CGSize) {
        for (i, star) in state.starNodes.enumerated() {
            let alpha = star.life / star.maxLife
            for j in (i+1)..<state.starNodes.count {
                let other = state.starNodes[j]
                let dist = hypot(star.x - other.x, star.y - other.y)
                guard dist < 110 else { continue }
                let la = alpha * Double(1 - dist / 110) * 0.33
                var ln = Path(); ln.move(to: .init(x: star.x, y: star.y)); ln.addLine(to: .init(x: other.x, y: other.y))
                ctx.stroke(ln, with: .color(Color(hue: star.hue, saturation: 0.6, brightness: 0.9).opacity(la)),
                           style: StrokeStyle(lineWidth: 0.5))
            }
        }
        for star in state.starNodes {
            let t = star.life / star.maxLife
            let alpha = t < 0.15 ? t / 0.15 : (t > 0.75 ? (1.0 - t) / 0.25 : 1.0)
            let r = star.radius * CGFloat(alpha)
            ctx.fill(Path(ellipseIn: CGRect(x: star.x - r * 2.2, y: star.y - r * 2.2, width: r * 4.4, height: r * 4.4)),
                     with: .radialGradient(
                        Gradient(colors: [Color(hue: star.hue, saturation: 0.7, brightness: 1.0).opacity(alpha * 0.36), .clear]),
                        center: .init(x: star.x, y: star.y), startRadius: 0, endRadius: r * 2.2))
            ctx.fill(Path(ellipseIn: CGRect(x: star.x - r * 0.55, y: star.y - r * 0.55, width: r * 1.1, height: r * 1.1)),
                     with: .color(Color.white.opacity(alpha * 0.88)))
        }
    }

    private func drawBassRings(ctx: GraphicsContext, size: CGSize) {
        for ring in state.bassRings {
            let alpha = ring.life * ring.life * 0.62
            guard alpha > 0.01 else { continue }
            var p = Path()
            p.addEllipse(in: CGRect(x: ring.x - ring.radius, y: ring.y - ring.radius * 0.62, width: ring.radius * 2, height: ring.radius * 1.24))
            ctx.stroke(p, with: .color(Color(hue: ring.hue, saturation: 0.85, brightness: 1.0).opacity(alpha * 0.26)),
                       style: StrokeStyle(lineWidth: ring.thickness * 2.6))
            ctx.stroke(p, with: .color(Color(hue: ring.hue, saturation: 0.90, brightness: 1.0).opacity(alpha)),
                       style: StrokeStyle(lineWidth: ring.thickness))
        }
    }

    private func drawVocalParticles(ctx: GraphicsContext, size: CGSize) {
        for p in state.vocalParts {
            guard p.trail.count > 1 else { continue }
            let alpha = p.life / p.maxLife
            for i in 1..<p.trail.count {
                let prog = Double(i) / Double(p.trail.count)
                var seg = Path(); seg.move(to: p.trail[i-1]); seg.addLine(to: p.trail[i])
                ctx.stroke(seg,
                           with: .color(Color(hue: p.hue, saturation: 0.7, brightness: 1.0).opacity(alpha * prog * 0.78)),
                           style: StrokeStyle(lineWidth: p.size * CGFloat(prog * 0.82 + 0.18), lineCap: .round))
            }
            if let head = p.trail.last {
                let hr = p.size * 2.0
                ctx.fill(Path(ellipseIn: CGRect(x: head.x - hr, y: head.y - hr, width: hr * 2, height: hr * 2)),
                         with: .radialGradient(
                            Gradient(colors: [Color.white.opacity(alpha * 0.72), Color(hue: p.hue, saturation: 0.6, brightness: 1.0).opacity(alpha * 0.28), .clear]),
                            center: head, startRadius: 0, endRadius: hr))
            }
        }
    }

    private func drawDrumBursts(ctx: GraphicsContext, size: CGSize) {
        for burst in state.drumBursts {
            for ring in burst.rings {
                guard ring.life > 0, ring.radius > 0 else { continue }
                let alpha = ring.life * ring.life
                var p = Path()
                p.addEllipse(in: CGRect(x: burst.x - ring.radius, y: burst.y - ring.radius, width: ring.radius * 2, height: ring.radius * 2))
                ctx.stroke(p, with: .color(Color(hue: ring.hue, saturation: 0.5, brightness: 1.0).opacity(alpha * 0.62)),
                           style: StrokeStyle(lineWidth: ring.thickness))
                if burst.strongHit && ring.life > 0.55 {
                    for s in 0..<10 {
                        let angle = Double(s) / 10.0 * .pi * 2
                        let ir = ring.radius * 0.82, or_ = ring.radius * 1.22
                        var sp = Path()
                        sp.move(to: .init(x: burst.x + ir * CGFloat(cos(angle)), y: burst.y + ir * CGFloat(sin(angle))))
                        sp.addLine(to: .init(x: burst.x + or_ * CGFloat(cos(angle)), y: burst.y + or_ * CGFloat(sin(angle))))
                        ctx.stroke(sp, with: .color(Color(hue: ring.hue, saturation: 0.3, brightness: 1.0).opacity(alpha * 0.42)),
                                   style: StrokeStyle(lineWidth: 1.0, lineCap: .round))
                    }
                }
            }
            if burst.strongHit, let first = burst.rings.first, first.life > 0.68 {
                let dr = 11 * CGFloat((first.life - 0.68) / 0.32)
                ctx.fill(Path(ellipseIn: CGRect(x: burst.x - dr, y: burst.y - dr, width: dr * 2, height: dr * 2)),
                         with: .color(Color.white.opacity(first.life * 0.86)))
            }
        }
    }

    // MARK: - Tick (all mutation, runs once per frame)
    private func tick() {
        frameCount += 1
        state.phase += 0.018

        let d = Double(engine.drumsEnergy)
        let b = Double(engine.bassEnergy)
        let v = Double(engine.vocalsEnergy)
        let o = Double(engine.otherEnergy)

        peakDrums  = max(peakDrums  * 0.994, d)
        peakBass   = max(peakBass   * 0.996, b)
        peakVocals = max(peakVocals * 0.995, v)

        state.sDrums  += (d - state.sDrums)  * (d > state.sDrums  ? 0.55 : 0.10)
        state.sBass   += (b - state.sBass)   * (b > state.sBass   ? 0.25 : 0.06)
        state.sVocals += (v - state.sVocals) * (v > state.sVocals ? 0.35 : 0.08)
        state.sOther  += (o - state.sOther)  * (o > state.sOther  ? 0.20 : 0.07)

        state.moodHue = (state.moodHue + 0.0008 + state.sBass * 0.0014 + (engine.isBeat ? 0.007 : 0))
            .truncatingRemainder(dividingBy: 1.0)

        if engine.isBeat {
            state.beatScale = 1.0 + CGFloat(min(state.sDrums + state.sBass * 0.4, 1.0) * 0.016)
        } else {
            state.beatScale += (1.0 - state.beatScale) * 0.14
        }

        if engine.strongHit {
            state.beatFlashLife = 1.0
            state.beatFlashIntensity = min(state.sDrums, 1.0)
        }
        if state.beatFlashLife > 0 { state.beatFlashLife -= 1.0/60.0 * 5.5 }

        // EQ bands — synthesize 24 bands from 4 stems with frequency-realistic weighting
        for i in 0..<24 {
            let t = Float(i) / 23.0
            let bassW  = max(0, 1.0 - t * 3.4)
            let drumW  = t < 0.35 ? t * 2.9 : max(0, 1.0 - (t - 0.35) * 2.4)
            let vocalW = t > 0.4 && t < 0.85 ? sin((t - 0.4) / 0.45 * Float.pi) : 0
            let otherW = max(0, (t - 0.55) * 2.1)
            let noise  = Float.random(in: 0...0.035)
            let target = min(1.0, Float(b) * bassW + Float(d) * drumW * 0.88 + Float(v) * vocalW * 0.82 + Float(o) * otherW * 0.72 + noise)
            let atk: Float = target > state.eqBands[i] ? 0.48 : 0.11
            state.eqBands[i] += (target - state.eqBands[i]) * atk
            if state.eqBands[i] > state.eqPeaks[i] {
                state.eqPeaks[i] = state.eqBands[i]
            } else {
                state.eqPeaks[i] = max(0, state.eqPeaks[i] - Float(1.0/60.0) * 0.26)
            }
        }

        // Spawn
        let size = CGSize(width: 390, height: 600)

        if state.sBass > 0.14 && frameCount - lastBassRing > max(6, Int(28 - state.sBass * 20)) {
            lastBassRing = frameCount; spawnBassRings(size: size)
        }
        if engine.strongHit && frameCount - lastDrumBurst > 5 {
            lastDrumBurst = frameCount; spawnDrumBurst(size: size, strong: true)
        } else if engine.isBeat && frameCount - lastDrumBurst > 14 {
            lastDrumBurst = frameCount; spawnDrumBurst(size: size, strong: false)
        }
        if state.sVocals > 0.16 && frameCount - lastVocalSpawn > max(3, Int(18 - state.sVocals * 13)) {
            lastVocalSpawn = frameCount; spawnVocalParticle(size: size)
        }
        if state.sOther > 0.11 && frameCount - lastStarSpawn > max(10, Int(38 - state.sOther * 26)) {
            lastStarSpawn = frameCount; spawnStarNode(size: size)
        }

        tickBassRings(); tickDrumBursts(); tickVocalParticles(); tickStarNodes()
    }

    // MARK: - Spawn helpers
    private func spawnBassRings(size: CGSize) {
        let cx = size.width / 2 + CGFloat.random(in: -25...25)
        let cy = size.height * 0.77 + CGFloat.random(in: -15...15)
        let count = state.sBass > 0.55 ? 3 : (state.sBass > 0.3 ? 2 : 1)
        for i in 0..<count {
            let hue = (state.moodHue + Double(i) * 0.03).truncatingRemainder(dividingBy: 1.0)
            let maxR = size.width * CGFloat(0.22 + state.sBass * 0.42 + Double(i) * 0.07)
            state.bassRings.append(BassRing(radius: 6, maxRadius: maxR, life: 1.0,
                                            thickness: CGFloat(state.sBass * 2.8 + 0.9), hue: hue, x: cx, y: cy,
                                            speed: CGFloat(state.sBass * 4.5 + 2.2) * CGFloat.random(in: 0.88...1.12)))
        }
        if state.bassRings.count > 8 { state.bassRings.removeFirst(state.bassRings.count - 8) }
    }

    private func spawnDrumBurst(size: CGSize, strong: Bool) {
        let x = CGFloat.random(in: size.width * (strong ? 0.28 : 0.12)...size.width * (strong ? 0.72 : 0.88))
        let y = CGFloat.random(in: size.height * (strong ? 0.28 : 0.18)...size.height * (strong ? 0.62 : 0.72))
        let baseHue = (state.moodHue + (strong ? 0.0 : 0.07)).truncatingRemainder(dividingBy: 1.0)
        var rings: [DrumRing] = []
        for i in 0..<(strong ? 4 : 2) {
            let maxR = size.width * CGFloat(strong ? (0.18 + Double(i) * 0.11) : (0.10 + Double(i) * 0.07))
            rings.append(DrumRing(radius: 4, maxRadius: maxR, life: 1.0 - Double(i) * 0.06,
                                  hue: (baseHue + Double(i) * 0.02).truncatingRemainder(dividingBy: 1.0),
                                  thickness: strong ? CGFloat(2.4 - Double(i) * 0.38) : 1.4))
        }
        state.drumBursts.append(DrumBurst(x: x, y: y, rings: rings, strongHit: strong))
        if state.drumBursts.count > 5 { state.drumBursts.removeFirst() }
    }

    private func spawnVocalParticle(size: CGSize) {
        let fromLeft = Bool.random()
        let x: CGFloat = fromLeft ? -8 : size.width + 8
        let y = CGFloat.random(in: size.height * 0.08...size.height * 0.68)
        let tx = size.width / 2 + CGFloat.random(in: -70...70)
        let ty = CGFloat.random(in: size.height * 0.18...size.height * 0.58)
        let dist = hypot(tx - x, ty - y)
        let speed = CGFloat(state.sVocals * 4.5 + 2.2)
        let maxLife = Double.random(in: 1.1...2.6)
        let hue = (state.moodHue + 0.14 + Double.random(in: -0.05...0.05)).truncatingRemainder(dividingBy: 1.0)
        state.vocalParts.append(VocalParticle(
            x: x, y: y, vx: ((tx - x) / dist) * speed, vy: ((ty - y) / dist) * speed,
            life: maxLife, maxLife: maxLife, size: CGFloat(state.sVocals * 3.2 + 1.4), hue: hue,
            trail: [CGPoint(x: x, y: y)], trailLen: Int(state.sVocals * 22 + 10)))
        if state.vocalParts.count > 8 { state.vocalParts.removeFirst() }
    }

    private func spawnStarNode(size: CGSize) {
        let hue = (state.moodHue + 0.30 + Double.random(in: -0.07...0.07)).truncatingRemainder(dividingBy: 1.0)
        let maxLife = Double.random(in: 2.4...5.0 + state.sOther * 1.8)
        state.starNodes.append(StarNode(
            x: CGFloat.random(in: 35...size.width - 35), y: CGFloat.random(in: 55...size.height * 0.62),
            vx: CGFloat.random(in: -0.28...0.28), vy: CGFloat.random(in: -0.45 ... -0.08),
            life: maxLife, maxLife: maxLife, radius: CGFloat(state.sOther * 4.8 + 2.2), hue: hue))
        if state.starNodes.count > 10 { state.starNodes.removeFirst() }
    }

    // MARK: - Entity ticks
    private func tickBassRings() {
        state.bassRings = state.bassRings.compactMap {
            var r = $0; r.radius += r.speed; r.life = Double(1.0 - r.radius / r.maxRadius)
            return r.life > 0.02 ? r : nil
        }
    }
    private func tickDrumBursts() {
        let decay = 1.4 / 60.0
        state.drumBursts = state.drumBursts.compactMap { b in
            var burst = b
            burst.rings = burst.rings.compactMap { r in
                var ring = r; ring.life -= decay; guard ring.life > 0 else { return nil }
                ring.radius = 4 + ring.maxRadius * CGFloat(1.0 - ring.life); return ring
            }
            return burst.rings.isEmpty ? nil : burst
        }
    }
    private func tickVocalParticles() {
        state.vocalParts = state.vocalParts.compactMap {
            var p = $0; p.life -= 1.0/60.0; guard p.life > 0 else { return nil }
            p.vx += CGFloat.random(in: -0.07...0.07); p.vy += CGFloat.random(in: -0.05...0.05) - 0.012
            p.x += p.vx; p.y += p.vy
            p.trail.append(CGPoint(x: p.x, y: p.y))
            if p.trail.count > p.trailLen { p.trail.removeFirst() }
            return p
        }
    }
    private func tickStarNodes() {
        state.starNodes = state.starNodes.compactMap {
            var s = $0; s.life -= 1.0/60.0; guard s.life > 0 else { return nil }
            s.x += s.vx; s.y += s.vy; return s
        }
    }

    // MARK: - Spectrum Bars
    private var spectrumBars: some View {
        HStack(alignment: .bottom, spacing: 6) {
            SpectrumBar(label: "DRUMS",  energy: engine.drumsEnergy,  color: Color.white.opacity(0.9))
            SpectrumBar(label: "BASS",   energy: engine.bassEnergy,   color: hueColor(state.moodHue, s: 0.9, b: 1.0))
            SpectrumBar(label: "VOCALS", energy: engine.vocalsEnergy, color: hueColor((state.moodHue + 0.15).truncatingRemainder(dividingBy: 1), s: 0.85, b: 1.0))
            SpectrumBar(label: "OTHER",  energy: engine.otherEnergy,  color: hueColor((state.moodHue + 0.32).truncatingRemainder(dividingBy: 1), s: 0.75, b: 0.95))
        }
        .frame(height: 60)
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Controls
    private var controlsSection: some View {
        VStack(spacing: 12) {
            if engine.isLoaded {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.songTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        if engine.tempoBpm > 0 {
                            Text("\(Int(engine.tempoBpm)) BPM").font(.system(size: 12)).foregroundStyle(hueColor(state.moodHue, s: 0.8, b: 1.0))
                        }
                    }
                    Spacer()
                    if engine.playbackMode == .stems {
                        HStack(spacing: 6) {
                            CompactStemDot(label: "D", isOn: $engine.drumsEnabled,  color: Color.white.opacity(0.85))
                            CompactStemDot(label: "B", isOn: $engine.bassEnabled,   color: hueColor(state.moodHue, s: 0.8, b: 1.0))
                            CompactStemDot(label: "V", isOn: $engine.vocalsEnabled, color: hueColor((state.moodHue + 0.15).truncatingRemainder(dividingBy: 1), s: 0.8, b: 1.0))
                            CompactStemDot(label: "O", isOn: $engine.otherEnabled,  color: hueColor((state.moodHue + 0.32).truncatingRemainder(dividingBy: 1), s: 0.7, b: 0.9))
                        }
                        .onChange(of: engine.drumsEnabled)  { _, _ in engine.updateStemVolumes() }
                        .onChange(of: engine.bassEnabled)   { _, _ in engine.updateStemVolumes() }
                        .onChange(of: engine.vocalsEnabled) { _, _ in engine.updateStemVolumes() }
                        .onChange(of: engine.otherEnabled)  { _, _ in engine.updateStemVolumes() }
                    }
                }
                SeekBar(currentTime: engine.currentTime, duration: engine.duration) { engine.seek(to: $0) }
                HStack(spacing: 10) {
                    Button(action: { engine.playbackMode = engine.playbackMode == .fullMix ? .stems : .fullMix }) {
                        Text(engine.playbackMode == .fullMix ? "Mix" : "Stems").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(hueColor(state.moodHue)).padding(.horizontal, 14).padding(.vertical, 10)
                            .background(hueColor(state.moodHue).opacity(0.12)).clipShape(Capsule())
                    }
                    Button(action: { engine.togglePlayback() }) {
                        HStack(spacing: 8) {
                            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .semibold))
                            Text(engine.isPlaying ? "Pause" : "Play").font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(hueColor(state.moodHue)).clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button(action: { showImporter = true }) {
                        Image(systemName: "folder").font(.system(size: 15))
                            .foregroundStyle(hueColor(state.moodHue)).frame(width: 46, height: 46)
                            .background(hueColor(state.moodHue).opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            } else {
                Button(action: { showImporter = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 15, weight: .semibold))
                        Text("Import Song + Stem Data").font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.black).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color(red: 0.20, green: 0.83, blue: 0.60)).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text("Process a song in the HarmoniAI Colab notebook first")
                    .font(.system(size: 12)).foregroundStyle(Color.gray.opacity(0.4)).multilineTextAlignment(.center)
            }
            if let error = engine.errorMessage {
                Text(error).font(.system(size: 12)).foregroundStyle(Color(red: 0.98, green: 0.42, blue: 0.51)).multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Importer sheet
    private var importerSheet: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.07).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text("Load a Song").font(.system(size: 22, weight: .bold)).foregroundStyle(.white).padding(.top, 32)
                    HarmoniImportView(session: $importSession) {
                        guard let json = importSession.jsonURL, let audio = importSession.audioURL else { return }
                        engine.loadSongData(jsonURL: json, audioURL: audio,
                                            drumsURL: importSession.drumsURL, bassURL: importSession.bassURL,
                                            vocalsURL: importSession.vocalsURL, otherURL: importSession.otherURL)
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
                        .fill(LinearGradient(colors: [color, color.opacity(0.4)], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(3, geo.size.height * CGFloat(energy)))
                        .animation(.easeOut(duration: 0.05), value: energy)
                }
            }
            Text(label).font(.system(size: 7, weight: .semibold)).tracking(0.5).foregroundStyle(color.opacity(0.8))
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
            Text(label).font(.system(size: 10, weight: .bold))
                .foregroundStyle(isOn ? .black : color.opacity(0.4))
                .frame(width: 28, height: 28)
                .background(isOn ? color : color.opacity(0.1))
                .clipShape(Circle()).animation(.easeInOut(duration: 0.15), value: isOn)
        }
    }
}

// MARK: - Seek Bar
struct SeekBar: View {
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void
    private var progress: Double { duration > 0 ? currentTime / duration : 0 }
    private func fmt(_ t: Double) -> String { String(format: "%d:%02d", Int(t) / 60, Int(t) % 60) }
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
