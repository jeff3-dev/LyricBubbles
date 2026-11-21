import AppKit
import SwiftUI

// MARK: - Style: Fogged Glass
//
// A night window, fogged over. Each lyric is written into the condensation with a fingertip,
// word by word in time with the song, so the city lights behind show through the letters.
// Lines of a verse stack up on the pane; when the song moves to a new segment, a breath
// fogs the old writing back over and the next segment starts on fresh glass.
//
// A camera floats in front of the pane: it zooms in on the line being written, pans along
// with the fingertip, rolls with the handwriting and pulls back between segments. The lights
// behind the glass move less than the glass itself (parallax), and fast camera moves smear
// with motion blur.

struct FogGlassView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(GlassSettings.storageKey) private var settings = GlassSettings()
    @State private var art: ArtLayers?
    @State private var textures: GlassTextures?
    @State private var rig = CameraRig()
    @State private var sim = DropletSim()
    @State private var hovering = false
    @State private var showControls = false

    /// The demo reel passes album-art layers it has already made, so switching is instant.
    init(model: PlayerModel, art: ArtLayers? = nil) {
        self.model = model
        _art = State(initialValue: art)
    }

    var body: some View {
        // Every display frame (no minimum interval): a 60 fps cap on a 120 Hz screen lands
        // frames unevenly, which reads as stutter.
        TimelineView(.animation) { ctx in
            let s = settings
            let pos = model.position(at: ctx.date) + leadTime
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let beat = model.audio.sample(at: ctx.date).beat * s[.pulse]
            let scene = currentScene(pos: pos, s: s)

            GeometryReader { geo in
                let size = geo.size
                let over = CGSize(width: size.width * GlassComposite.overscan, height: size.height * GlassComposite.overscan)
                let head = GlassCameraPlanner.writeHead(scene: scene, pos: pos, size: size, s: s)
                let boost = scene.puff.map { max(0, 1 - $0.age / 1.5) } ?? 0
                let _ = sim.step(at: ctx.date, size: size, amount: s[.droplets], boost: boost,
                                 wipe: head.map { ($0.point, $0.radius) })
                let target = GlassCameraPlanner.target(scene: scene, pos: pos, size: size, s: s, t: t, beat: beat)
                let cam = rig.step(to: target, at: ctx.date, response: 0.22 + s[.smooth] * 1.3)
                let blur = MotionTaps(velocity: rig.screenVelocity, zoomVelocity: rig.zoomVelocity,
                                      zoom: cam.zoom, amount: s[.motionBlur])
                let lights = BokehField.lights(t: t, beat: beat, size: over, amount: s[.lights], palette: model.artPalette)
                GlassComposite(scene: scene, pos: pos, size: size, t: t, beat: beat, cam: cam, blur: blur, s: s,
                               art: s.flag(.art) ? art : nil, lights: lights,
                               drops: sim.drops, trail: sim.trail, simTime: sim.time, tex: textures)
            }
        }
        .overlay(alignment: .bottom) { caption }
        .overlay(alignment: .topTrailing) { controlsButton }
        .background(Color.black)
        .ignoresSafeArea()
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hovering = h } }
        .task(id: model.snapshot?.artworkURL) { await loadArt() }
        .task { textures = await GlassTextures.shared.value }
    }

    // MARK: What to write

    private func currentScene(pos: Double, s: GlassSettings) -> GlassScene {
        switch model.status {
        case .notRunning: return .message("Open Spotify ♡")
        case .stopped: return .message("press play…")
        case .error: return .message("can't reach Spotify")
        case .active(let snap):
            if model.loadingLyrics { return .message("…") }
            switch model.lyrics {
            case .synced(let lines):
                return GlassScene.make(lines: lines, title: snap.title, pos: pos,
                                       maxRows: s.lines, fadeOld: s[.fadeOld], speed: s[.speed])
            case .instrumental: return .message("no words, just vibes")
            case .plainOnly: return .message("no timed lyrics")
            case .notFound, .none: return .message("no lyrics found")
            }
        }
    }

    private var caption: some View {
        Group {
            if let s = model.snapshot {
                Text("\(s.title) · \(s.artist)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 20)
            }
        }
        .allowsHitTesting(false)
    }

    private var controlsButton: some View {
        Button { showControls.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showControls, arrowEdge: .bottom) { GlassControls() }
        .help("Glass controls")
        .padding(.top, 10)
        .padding(.trailing, 12)
        .opacity(hovering || showControls ? 1 : 0)
    }

    private func loadArt() async {
        guard let url = model.snapshot?.artworkURL else { art = nil; return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        art = await ArtLayers.make(from: data)
    }
}

// MARK: - Composite

/// Stacks every layer of the window. Glass layers move with the camera; the backdrop moves
/// less (it's further away). Full-bleed layers are drawn oversized so camera moves never
/// reveal an edge. Nothing here blurs per frame except motion blur while the camera moves.
struct GlassComposite: View {
    let scene: GlassScene
    let pos: Double
    let size: CGSize
    let t: Double
    let beat: Double
    let cam: StageCamera
    let blur: MotionTaps
    let s: GlassSettings
    let art: ArtLayers?
    let lights: [BokehLight]                 // in the oversized backdrop's coordinates
    let drops: [DropletSim.Drop]
    let trail: [DropletSim.TrailDot]
    let simTime: Double
    let tex: GlassTextures?

    static let overscan: CGFloat = 1.4

    var body: some View {
        let over = CGSize(width: size.width * Self.overscan, height: size.height * Self.overscan)
        let inset = CGSize(width: (over.width - size.width) / 2, height: (over.height - size.height) / 2)
        let depth = 1 - s[.parallax] * 0.75
        let behind = CamTransform(cam: cam, size: size, depth: depth)
        let glass = CamTransform(cam: cam, size: size)
        let wet = s[.wetness]
        let dropAmount = s[.droplets]

        ZStack {
            // 1. Through the fog: soft, washed out.
            GlassBackdrop(art: art?.soft, lights: lights, fogged: true, fog: s[.fog], extraBlur: blur.backdropBlur)
                .frame(width: over.width, height: over.height)
                .modifier(behind)

            // 2. The condensation itself, drifting very slowly.
            ZStack {
                FogTint(density: s[.fog])
                if let tex {
                    Image(decorative: tex.fog, scale: 1).resizable().interpolation(.high)
                        .scaleEffect(1.08)
                        .offset(x: sin(t * 0.031) * 16, y: cos(t * 0.023) * 12)
                        .blendMode(.screen)
                        .opacity(s[.texture] * (0.3 + 0.45 * s[.fog]))
                }
            }
            .frame(width: over.width, height: over.height)
            .modifier(glass)

            // 3. Through the writing and the trails drops leave: sharp, dark, saturated.
            GlassBackdrop(art: art?.clear, lights: lights, fogged: false, fog: s[.fog], extraBlur: blur.backdropBlur * 0.5)
                .frame(width: over.width, height: over.height)
                .modifier(behind)
                .mask {
                    ZStack {
                        ForEach(blur.taps) { tap in
                            writing(softness: 1.1)
                                .modifier(CamTransform(cam: cam, size: size, tap: tap))
                                .opacity(tap.opacity)
                        }
                        if dropAmount > 0 {
                            TrailMask(trail: trail, now: simTime)
                                .frame(width: size.width, height: size.height)
                                .modifier(glass)
                        }
                    }
                }

            // 4. Fine mist on the fog (wiped away by the finger and by running drops).
            if let tex, dropAmount > 0 {
                Image(decorative: tex.drops, scale: 1).resizable().interpolation(.high)
                    .frame(width: over.width, height: over.height)
                    .reverseMask {
                        ZStack {
                            writing(softness: 2.5)
                            TrailMask(trail: trail, now: simTime).frame(width: size.width, height: size.height)
                        }
                    }
                    .opacity(0.3 + 0.7 * dropAmount)
                    .blur(radius: blur.backdropBlur * 0.35)
                    .modifier(glass)
            }

            // 5. Wet inside the strokes: rivulets and a moving glint.
            if wet > 0 || s[.reflections] > 0 {
                ZStack {
                    if let tex {
                        Image(decorative: tex.streaks, scale: 1).resizable()
                            .opacity(0.55 * wet)
                    }
                    Glint(t: t, amount: 0.25 + s[.reflections] * 0.6)
                }
                .frame(width: over.width, height: over.height)
                .blendMode(.screen)
                .mask { writing(softness: 1.4) }
                .modifier(glass)
            }

            // 6. Beads of water piled up along every stroke edge.
            if wet > 0 {
                ZStack {
                    Color.white.opacity(0.1 + 0.16 * wet)
                    if let tex {
                        Image(decorative: tex.beads, scale: 1).resizable().interpolation(.high)
                            .opacity(0.35 + 0.65 * wet)
                    }
                }
                .frame(width: over.width, height: over.height)
                .mask { RimBand(scene: scene, pos: pos, size: size, s: s, spread: 3 + wet * 4) }
                .blur(radius: blur.backdropBlur * 0.25)
                .modifier(glass)
            }

            // 7. Live droplets: little lenses that grow, merge and run.
            if dropAmount > 0 {
                let paneLights = lights.map {
                    BokehLight(p: CGPoint(x: $0.p.x - inset.width, y: $0.p.y - inset.height),
                               r: $0.r, color: $0.color, alpha: $0.alpha)
                }
                let side = max(over.width, over.height)
                DropsLayer(drops: drops, lights: paneLights, art: art?.clear,
                           artRect: CGRect(x: size.width / 2 - side / 2, y: size.height / 2 - side / 2, width: side, height: side),
                           shine: s[.reflections])
                    .frame(width: size.width, height: size.height)
                    .opacity(min(1, 0.45 + dropAmount))
                    .blur(radius: blur.backdropBlur * 0.35)
                    .modifier(glass)
            }

            // 8. Room light reflecting off the whole pane (moves with you, not the glass).
            if s[.reflections] > 0 {
                Glint(t: t * 0.6 + 40, amount: s[.reflections] * 0.22)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                RadialGradient(colors: [.white.opacity(0.09 * s[.reflections]), .clear],
                               center: UnitPoint(x: 0.12, y: 0.05), startRadius: 0, endRadius: size.height * 0.55)
                    .blendMode(.screen)
            }

            // 9. A breath that fogs the pane over between segments.
            if let puff = scene.puff, s.flag(.breath) {
                BreathPuff(puff: puff, size: size)
                    .frame(width: size.width, height: size.height)
                    .modifier(glass)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func writing(softness: CGFloat) -> some View {
        GlassWriting(scene: scene, pos: pos, size: size, s: s, softness: softness)
    }
}

// MARK: - Camera

/// Decides where the camera wants to be: on the fingertip while a line is written, easing back
/// to frame the page once it's done, and wide while a breath clears the glass.
enum GlassCameraPlanner {
    static func target(scene: GlassScene, pos: Double, size: CGSize, s: GlassSettings, t: Double, beat: Double) -> StageCamera {
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        let sway = sin(t * 0.23) * 1.4 * s[.tilt] + sin(t * 0.11 + 1) * 0.6 * s[.tilt]
        let wide = StageCamera(center: mid, zoom: 1 + beat * 0.03, angle: sway)
        guard size.width > 10, let st = scene.strokes.last(where: { $0.current }) else { return wide }
        if let puff = scene.puff, puff.age < 0.75, s.flag(.breath) { return wide }

        let p = GlassWriting.placement(st, in: size, s: s)
        let head = headPoint(st, p, pos: pos, s: s).point

        // Once the line is written, drift back to the middle of the page.
        let done = smoothstep((pos - st.start - st.writeDuration) / 1.6)
        let follow = CGFloat(s[.pan] * (1 - done))
        let lineCenter = CGPoint(x: p.x, y: p.y)
        var c = mix(lineCenter, head, follow)
        c = mix(c, CGPoint(x: mid.x, y: (c.y + mid.y) / 2), CGFloat(done * 0.6))

        var r = Seeded(st.seed ^ 0x5EED)
        let zin = 1 + s[.zoom] * 1.1 * (0.8 + 0.4 * r.next())
        var z = zin + (1 + (zin - 1) * 0.3 - zin) * done
        z += beat * 0.035

        // Keep the view inside the (oversized) pane.
        let margin = (GlassComposite.overscan - 1) / 2 * 0.6
        let hw = size.width / (2 * z), hh = size.height / (2 * z)
        c.x = min(max(c.x, hw - size.width * margin), size.width - hw + size.width * margin)
        c.y = min(max(c.y, hh - size.height * margin), size.height - hh + size.height * margin)

        let roll = -Double(p.tilt) * 0.75 * s[.tilt] * (1 - done * 0.5) + sway
        return StageCamera(center: c, zoom: z, angle: roll)
    }

    /// Where the fingertip is on the line being written right now (nil when nobody is writing).
    static func writeHead(scene: GlassScene, pos: Double, size: CGSize, s: GlassSettings) -> (point: CGPoint, radius: CGFloat)? {
        guard size.width > 10, let st = scene.strokes.last(where: { $0.current }) else { return nil }
        let q = (pos - st.start) / st.writeDuration
        guard q > 0, q < 1 else { return nil }
        let p = GlassWriting.placement(st, in: size, s: s)
        return (headPoint(st, p, pos: pos, s: s).point, p.fontSize * 0.55)
    }

    private static func headPoint(_ st: GlassStroke, _ p: GlassWriting.Placement, pos: Double, s: GlassSettings) -> (point: CGPoint, q: Double) {
        let lineLen = CGFloat(st.text.count) * p.fontSize * s.font.widthFactor
        let rows = max(1, Int((lineLen / p.maxWidth).rounded(.up)))
        let rowW = min(p.maxWidth, lineLen / CGFloat(rows))
        let rowH = p.fontSize * 0.95
        let q = min(1, max(0, (pos - st.start) / st.writeDuration))
        let rq = q * Double(rows)
        let ri = min(rows - 1, Int(rq))
        let fr = CGFloat(rq - Double(ri))
        return (CGPoint(x: p.x - rowW / 2 + rowW * fr,
                        y: p.y - CGFloat(rows) * rowH / 2 + rowH * (CGFloat(ri) + 0.5)), q)
    }

    private static func mix(_ a: CGPoint, _ b: CGPoint, _ k: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }
}

// MARK: - Scene planning

/// One line of writing on the pane.
struct GlassStroke: Identifiable {
    let id: Int
    let text: String
    let start: Double        // song time the finger touches the glass
    let writeDuration: Double
    let slot: Int            // row on the pane within its segment
    let rows: Int            // how many rows the segment uses (for vertical centering)
    var fog: Double          // 0 = freshly wiped, 1 = fogged over again
    let seed: UInt64
    var current = true       // false while an old segment is fogging away
}

struct GlassPuff {
    let age: Double
    let seed: UInt64
}

struct GlassScene {
    var strokes: [GlassStroke]
    var puff: GlassPuff?

    static func message(_ text: String) -> GlassScene {
        GlassScene(strokes: [GlassStroke(id: -100, text: text, start: -1000, writeDuration: 1, slot: 0, rows: 1,
                                         fog: 0, seed: hash(text))], puff: nil)
    }

    /// Splits the song into segments (verse/chorus blocks, broken on empty lines and capped at
    /// `maxRows` lines) and returns what's on the glass at `pos`.
    static func make(lines: [LyricLine], title: String, pos: Double,
                     maxRows: Int = 4, fadeOld: Double = 0.5, speed: Double = 0.5) -> GlassScene {
        // Song title is written on the glass during the intro.
        let segments = LyricPages.make(lines: lines, intro: title.lowercased(), maxRows: maxRows)
        guard let ci = segments.lastIndex(where: { $0.start <= pos }) else { return GlassScene(strokes: [], puff: nil) }
        let age = pos - segments[ci].start
        let style = (fadeOld: fadeOld, speed: speed)
        var strokes = Self.strokes(of: segments[ci], pos: pos, extraFog: 0, style: style)

        // The previous segment fogs back over while the new one begins.
        var puff: GlassPuff?
        let fogOut = 1.4
        if ci > 0, age < fogOut + 0.6 {
            let k = smoothstep(age / fogOut)
            var old = Self.strokes(of: segments[ci - 1], pos: pos, extraFog: k, style: style)
            for i in old.indices { old[i].current = false }
            strokes = old + strokes
            if !segments[ci - 1].lines.isEmpty {
                puff = GlassPuff(age: age, seed: UInt64(bitPattern: Int64(segments[ci].start * 1000)))
            }
        }
        return GlassScene(strokes: strokes.filter { $0.fog < 0.999 }, puff: puff)
    }

    private static func strokes(of seg: LyricPage, pos: Double, extraFog: Double,
                                style: (fadeOld: Double, speed: Double)) -> [GlassStroke] {
        let written = seg.lines.enumerated().filter { $0.element.line.time <= pos }
        guard let newest = written.last else { return [] }
        // Older lines on the same page dim as new ones arrive.
        let settle = smoothstep((pos - newest.element.line.time) / 0.8)
        let fadeRate = style.fadeOld * 0.26
        func rankFog(_ r: Double) -> Double { r <= 0 ? 0 : min(0.85, r * fadeRate) }
        let pace = 1.7 - 1.3 * style.speed
        return written.map { idx, entry in
            let rank = Double(newest.offset - idx)
            let dim = rankFog(rank - 1) + (rankFog(rank) - rankFog(rank - 1)) * settle
            let gap = max(0.4, entry.next - entry.line.time)
            let chars = Double(entry.line.text.count)
            let dur = min(gap * 0.85, max(0.4, min(4, chars * 0.07 * pace)))
            return GlassStroke(id: entry.line.id, text: entry.line.text, start: entry.line.time,
                               writeDuration: dur, slot: idx, rows: seg.lines.count,
                               fog: max(rank == 0 ? 0 : dim, extraFog),
                               seed: hash("\(entry.line.id)|\(entry.line.text)"))
        }
    }

    static func hash(_ s: String) -> UInt64 { LyricPages.hash(s) }
}

// MARK: - Writing

/// The finger-written strokes in white. Used as the mask that clears the fog.
struct GlassWriting: View {
    let scene: GlassScene
    let pos: Double
    let size: CGSize
    var s = GlassSettings()
    var softness: CGFloat = 1

    var body: some View {
        ZStack {
            ForEach(scene.strokes) { stroke in
                let place = Self.placement(stroke, in: size, s: s)
                StrokeView(stroke: stroke, pos: pos, fontSize: place.fontSize, maxWidth: place.maxWidth,
                           font: s.font, drips: s[.drips])
                    .blur(radius: softness + stroke.fog * 9)
                    .opacity(1 - stroke.fog)
                    .rotationEffect(.degrees(place.tilt))
                    .position(x: place.x, y: place.y)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    struct Placement { let x, y, tilt, fontSize, maxWidth: CGFloat }

    static func placement(_ st: GlassStroke, in size: CGSize, s: GlassSettings) -> Placement {
        var r = Seeded(st.seed)
        let rows = max(1, st.rows)
        let rowH = min(size.height * 0.21, size.height * 0.78 / CGFloat(rows))
        let center = size.height * 0.47
        let y = center + (CGFloat(st.slot) - CGFloat(rows - 1) / 2) * rowH + CGFloat(r.next() - 0.5) * rowH * 0.12
        let x = size.width / 2 + CGFloat(r.next() - 0.5) * size.width * 0.1
        let tilt = CGFloat(r.next() - 0.5) * 7
        let base = min(46, max(24, size.width / 10.5)) * CGFloat(0.7 + s[.size] * 0.6)
        let long = st.text.count > 34
        return Placement(x: x, y: y, tilt: tilt, fontSize: long ? base * 0.8 : base, maxWidth: size.width * 0.84)
    }
}

/// One line, revealed word by word with a left-to-right wipe, plus drips once it's written.
struct StrokeView: View {
    let stroke: GlassStroke
    let pos: Double
    let fontSize: CGFloat
    let maxWidth: CGFloat
    var font: GlassFont = .bradley
    var drips: Double = 0.5

    var body: some View {
        let words = stroke.text.split(separator: " ").map(String.init)
        let weights = words.map { Double(max(1, $0.count)) + 0.6 }   // + a beat for the gap
        let total = weights.reduce(0, +)
        let written = min(1, max(0, (pos - stroke.start) / stroke.writeDuration)) * total
        var cum = 0.0
        let ranges: [(Double, Double)] = weights.map { w in defer { cum += w }; return (cum, w) }

        FlowLayout(spacing: fontSize * 0.3, lineSpacing: -fontSize * 0.12) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let p = min(1, max(0, (written - ranges[i].0) / ranges[i].1))
                let wordEnd = stroke.start + stroke.writeDuration * (ranges[i].0 + ranges[i].1) / total
                Text(word)
                    .font(font.font(fontSize))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .mask { WipeMask(progress: p) }
                    .overlay(alignment: .top) {
                        Drip(seed: stroke.seed &+ UInt64(i) &* 7919, wordLength: word.count,
                             age: pos - wordEnd, fontSize: fontSize, amount: drips)
                    }
            }
        }
        .frame(maxWidth: maxWidth)
    }
}

/// Clears from left to right with a soft leading edge, like a fingertip moving.
struct WipeMask: View {
    let progress: Double

    var body: some View {
        if progress >= 1 {
            Rectangle()
        } else if progress <= 0 {
            Color.clear
        } else {
            let edge = 0.18
            let head = progress * (1 + edge)
            LinearGradient(stops: [
                .init(color: .white, location: max(0, head - edge)),
                .init(color: .clear, location: min(1, max(head - edge + 0.001, head))),
            ], startPoint: .leading, endPoint: .trailing)
        }
    }
}

/// A rivulet that meanders down from some letters after they're written, thinning as it goes,
/// with a fat bead at its head.
struct Drip: View {
    let seed: UInt64
    let wordLength: Int
    let age: Double
    let fontSize: CGFloat
    var amount: Double = 0.5

    var body: some View {
        var r = Seeded(seed)
        let chance = r.next()
        let delay = 0.5 + r.next() * 2.5
        let maxLen = fontSize * CGFloat(0.6 + r.next() * 2.2) * CGFloat(0.5 + amount)
        let xFrac = CGFloat(r.next() - 0.5) * 0.6
        let wob = r.next() * 6.28
        let t = age - delay
        let show = amount > 0 && wordLength >= 3 && chance < 0.45 * amount && t > 0
        let len = maxLen * CGFloat(1 - exp(-max(0, t) / 1.6))
        let w = fontSize * 0.08
        let top = fontSize * 0.62

        if show {
            Canvas { ctx, size in
                let x0 = size.width / 2 + size.width * xFrac
                var path = Path()
                path.move(to: CGPoint(x: x0, y: top))
                var y: CGFloat = 0
                while y < len {
                    y = min(len, y + 3)
                    path.addLine(to: CGPoint(x: x0 + sin(y * 0.09 + wob) * w * 0.9, y: top + y))
                }
                ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: w * 0.75, lineCap: .round))
                let hx = x0 + sin(len * 0.09 + wob) * w * 0.9
                let b = w * 1.9
                ctx.fill(Path(ellipseIn: CGRect(x: hx - b / 2, y: top + len - b * 0.45, width: b, height: b * 1.15)),
                         with: .color(.white))
            }
            .frame(height: top + maxLen + w * 3, alignment: .top)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Glass

/// What's behind the window: album art and drifting city lights. The art arrives pre-blurred
/// and the lights are plain gradients, so this costs no blur filters per frame.
struct GlassBackdrop: View {
    let art: CGImage?
    let lights: [BokehLight]
    let fogged: Bool
    var fog: Double = 0.5
    var extraBlur: CGFloat = 0

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.035, blue: 0.06)
            if let art {
                Image(decorative: art, scale: 1)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .opacity(fogged ? 0.5 : 0.42)
            }
            Canvas { ctx, _ in
                for l in lights {
                    if fogged {
                        BokehField.drawSoft(&ctx, l, spread: CGFloat(1.5 + fog * 1.1))
                    } else {
                        BokehField.drawCrisp(&ctx, l)
                    }
                }
            }
        }
        .drawingGroup()
        .blur(radius: extraBlur)
        .brightness(fogged ? 0.03 + fog * 0.04 : -0.06)
        .contrast(fogged ? 1 - fog * 0.25 : 1.12)
        .clipped()
    }
}

/// The milky layer of condensation, heavier toward the bottom of the pane.
struct FogTint: View {
    var density: Double = 0.5

    var body: some View {
        LinearGradient(colors: [Color.white.opacity(0.05 + density * 0.24), Color.white.opacity(0.1 + density * 0.36)],
                       startPoint: .top, endPoint: .bottom)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}

/// A soft diagonal band of light sliding slowly across.
struct Glint: View {
    let t: Double
    let amount: Double

    var body: some View {
        let c = (t * 0.035).truncatingRemainder(dividingBy: 1.8) - 0.4
        LinearGradient(stops: [
            .init(color: .clear, location: clamp(c - 0.16)),
            .init(color: .white.opacity(amount), location: clamp(c)),
            .init(color: .white.opacity(amount * 0.25), location: clamp(c + 0.05)),
            .init(color: .clear, location: clamp(c + 0.2)),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
        .allowsHitTesting(false)
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}

/// A band hugging the outside of every stroke, where the wiped water piles up.
struct RimBand: View {
    let scene: GlassScene
    let pos: Double
    let size: CGSize
    let s: GlassSettings
    var spread: CGFloat = 3.5

    var body: some View {
        ZStack {
            // Stacked copies firm up the faint outer halo of the blur into a solid band.
            ForEach(0..<2, id: \.self) { _ in
                GlassWriting(scene: scene, pos: pos, size: size, s: s, softness: spread)
            }
            GlassWriting(scene: scene, pos: pos, size: size, s: s, softness: 0.6)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }
}

/// Someone breathes on the glass: a soft cloud blooms and fades, fogging the old writing.
struct BreathPuff: View {
    let puff: GlassPuff
    let size: CGSize

    var body: some View {
        var r = Seeded(puff.seed)
        let cx = size.width * CGFloat(0.35 + r.next() * 0.3)
        let cy = size.height * CGFloat(0.35 + r.next() * 0.3)
        let a = puff.age
        let grow = 1 - exp(-a / 0.5)
        let alpha = min(1, a / 0.25) * max(0, 1 - a / 1.9)
        let d = max(size.width, size.height) * CGFloat(0.5 + 0.9 * grow)
        return RadialGradient(colors: [.white.opacity(0.32 * alpha), .white.opacity(0.14 * alpha), .clear],
                              center: .center, startRadius: 0, endRadius: d / 2)
            .frame(width: d, height: d)
            .position(x: cx, y: cy)
            .allowsHitTesting(false)
    }
}

// MARK: - Dashboard preview

/// Looping card preview: a word written into a fogged pane, then breathed away.
struct GlassPreview: View {
    private let words = ["hello", "la la la", "sing it"]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let cycle = 3.2
            let n = Int(t / cycle)
            let ph = t - Double(n) * cycle
            let word = words[n % words.count]
            let write = min(1, ph / 1.3)
            let fog = smoothstep((ph - 2.4) / 0.7)
            let zoom = 1 + 0.25 * smoothstep(ph / 1.3) * (1 - fog)
            let lights = BokehField.lights(t: t, beat: 0, size: CGSize(width: 260, height: 150), amount: 0.6, palette: [])
            ZStack {
                GlassBackdrop(art: nil, lights: lights, fogged: true)
                    .overlay(FogTint())
                GlassBackdrop(art: nil, lights: lights, fogged: false)
                    .mask {
                        Text(word)
                            .font(GlassFont.bradley.font(34))
                            .mask { WipeMask(progress: write) }
                            .blur(radius: 1 + fog * 8)
                            .opacity(1 - fog)
                            .rotationEffect(.degrees(-4))
                    }
            }
            .scaleEffect(zoom)
        }
    }
}
