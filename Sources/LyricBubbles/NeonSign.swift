import AVFoundation
import SwiftUI

// MARK: - Style: Neon Sign
//
// A dark wall at night. Each part of the song is a neon sign made of glass tubing, hung side
// by side along the wall. As the singer reaches each word its tubes sputter on, hum, and light
// up the bricks around them. When the song moves on, the sign powers down letter by letter and
// the camera pulls back and travels to the next sign along the wall.
//
// Everything is drawn in one Canvas: wall, hardware, the light the tubes throw on the wall,
// the tubes themselves (glow is the same outline stroked wider and fainter, no blur filters),
// sparks, rain and the wet pavement.

struct NeonSignView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(NeonSettings.storageKey) private var settings = NeonSettings()
    @State private var textures: NeonTextures?
    @State private var rig = CameraRig()
    @State private var programs: NeonProgramCache
    @State private var hovering = false
    @State private var showControls = false

    /// The demo reel passes a cache it has already filled, so switching to this style is instant.
    init(model: PlayerModel, programs: NeonProgramCache? = nil) {
        self.model = model
        _programs = State(initialValue: programs ?? NeonProgramCache())
    }

    var body: some View {
        // Every display frame (no minimum interval): a 60 fps cap stutters on 120 Hz screens.
        TimelineView(.animation) { ctx in
            let s = settings
            let pos = model.position(at: ctx.date) + leadTime
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let audio = model.audio.sample(at: ctx.date)
            let plans = currentPlans(s)

            GeometryReader { geo in
                let frame = NeonStage.frame(plans: plans, pos: pos, t: t, beat: audio.beat * s[.pulse], level: audio.level,
                                            size: geo.size, s: s, palette: model.artPalette, rig: rig, date: ctx.date,
                                            tex: textures)
                let _ = NeonHum.shared.update(enabled: s.flag(.hum), volume: s[.humVolume] * frame.litAmount)
                NeonCanvas(frame: frame)
            }
        }
        .overlay(alignment: .bottom) { caption }
        .overlay(alignment: .topTrailing) { controlsButton }
        .background(Color.black)
        .ignoresSafeArea()
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hovering = h } }
        .task { textures = await NeonTextures.shared.value }
        .onDisappear { NeonHum.shared.update(enabled: false, volume: 0) }
    }

    private func currentPlans(_ s: NeonSettings) -> [NeonSignPlan] {
        switch model.status {
        case .notRunning: return NeonProgram.message("Open Spotify")
        case .stopped: return NeonProgram.message("press play")
        case .error: return NeonProgram.message("no signal")
        case .active(let snap):
            if model.loadingLyrics { return NeonProgram.message("…") }
            switch model.lyrics {
            case .synced(let lines): return programs.plans(lines: lines, title: snap.title, maxRows: s.lines)
            case .instrumental: return NeonProgram.message("no words, just vibes")
            case .plainOnly: return NeonProgram.message("no timed lyrics")
            case .notFound, .none: return NeonProgram.message("no lyrics found")
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
        .popover(isPresented: $showControls, arrowEdge: .bottom) { NeonControls() }
        .help("Neon controls")
        .padding(.top, 10)
        .padding(.trailing, 12)
        .opacity(hovering || showControls ? 1 : 0)
    }
}

/// The whole scene in one GPU-backed canvas.
struct NeonCanvas: View {
    let frame: NeonFrame

    var body: some View {
        Canvas { ctx, _ in NeonRenderer.draw(&ctx, frame) }
            .drawingGroup()
    }
}

// MARK: - Program: the signs and when they light

/// One sign: a page of the song.
struct NeonSignPlan {
    struct Line {
        let id: Int
        let text: String
        let start: Double
        let duration: Double     // time over which its words light up
        let singer: Int
    }

    let index: Int
    let lines: [Line]
    let start: Double
    let offStart: Double         // when it starts powering down (infinity: never)
    let seed: UInt64

    var texts: [String] { lines.map(\.text) }
}

enum NeonProgram {
    static func make(lines: [LyricLine], title: String, maxRows: Int) -> [NeonSignPlan] {
        let pages = LyricPages.make(lines: lines, intro: title, maxRows: maxRows)
        var out: [NeonSignPlan] = []
        for (pi, page) in pages.enumerated() where !page.lines.isEmpty {
            let nextStart = pi + 1 < pages.count ? pages[pi + 1].start : Double.infinity
            let ls = page.lines.map { e -> NeonSignPlan.Line in
                let text = e.line.text.trimmingCharacters(in: .whitespaces)
                let gap = max(0.4, e.next - e.line.time)
                let dur = min(gap * 0.85, max(0.4, min(5, Double(text.count) * 0.068)))
                return .init(id: e.line.id, text: text, start: e.line.time, duration: dur, singer: e.line.singer)
            }
            let lastEnd = ls.last.map { $0.start + $0.duration } ?? page.start
            // Power down in the gap before the next part, or right as it starts if there's no gap.
            let off = nextStart.isFinite ? min(nextStart, max(lastEnd + 0.2, nextStart - 0.95)) : .infinity
            out.append(NeonSignPlan(index: out.count, lines: ls, start: page.start, offStart: off,
                                    seed: LyricPages.hash(ls.map(\.text).joined(separator: "|") + "\(page.start)")))
        }
        return out
    }

    /// A status sign, fully lit.
    static func message(_ text: String) -> [NeonSignPlan] {
        [NeonSignPlan(index: 0, lines: [.init(id: -100, text: text, start: -1000, duration: 0.01, singer: 0)],
                      start: -1000, offStart: .infinity, seed: LyricPages.hash(text))]
    }
}

/// Keeps the song's signs between frames (rebuilt only when the lyrics or layout change).
final class NeonProgramCache {
    private var key = ""
    private var plans: [NeonSignPlan] = []

    func plans(lines: [LyricLine], title: String, maxRows: Int) -> [NeonSignPlan] {
        let k = "\(title)|\(maxRows)|\(lines.count)|\(lines.first?.id ?? 0)|\(lines.last?.time ?? 0)|\(lines.map(\.singer).reduce(0, &+))"
        if k != key {
            key = k
            plans = NeonProgram.make(lines: lines, title: title, maxRows: maxRows)
        }
        return plans
    }
}

// MARK: - Light: how bright every letter is right now

enum NeonLight {
    /// When each of the sign's words starts lighting, and over how long (letter-weighted,
    /// with a beat for the gap, like Fogged Glass's handwriting).
    static func wordTimes(_ plan: NeonSignPlan, _ geo: NeonSignGeometry) -> [(start: Double, dur: Double)] {
        var out = Array(repeating: (start: Double.infinity, dur: 0.1), count: geo.words.count)
        for (li, line) in plan.lines.enumerated() where li < geo.lineWords.count {
            let range = geo.lineWords[li]
            let weights = range.map { Double(max(1, geo.words[$0].letters.count)) + 0.6 }
            let total = max(0.001, weights.reduce(0, +))
            var cum = 0.0
            for (k, w) in range.enumerated() {
                out[w] = (line.start + line.duration * cum / total, max(0.05, line.duration * weights[k] / total))
                cum += weights[k]
            }
        }
        return out
    }

    /// The power-on: two or three quick flickers, then full brightness with a small overshoot.
    static func ignite(_ age: Double, seed: UInt64, speed: Double) -> Double {
        guard age >= 0 else { return 0 }
        let dur = 0.08 + 0.22 * (1 - speed)
        if age < dur {
            var r = Seeded(seed)
            let n = 2 + Int(r.next() * 2)
            let ph = age / dur * Double(n)
            let k = Int(ph)
            var rk = Seeded(seed &+ UInt64(k + 1) &* 0x9E37_79B9)
            let level = 0.3 + 0.55 * rk.next() * Double(k + 1) / Double(n)
            return ph - Double(k) < 0.5 ? level : 0.04
        }
        let a = age - dur
        return 1 + 0.35 * exp(-a / 0.09)
    }

    /// Power-down multiplier for one letter: holds, sputters, then goes dark. The last letter
    /// out pops brightly before it dies.
    static func die(_ age: Double, order: Double, seed: UInt64, last: Bool) -> Double {
        let d = order * 0.55
        guard age >= d else { return 1 }
        let x = age - d
        if x < 0.16 {
            var r = Seeded(seed &+ UInt64(Int(x * 55)) &* 7919)
            return r.next() < 0.5 ? 0.06 : 0.75
        }
        if last, x < 0.23 { return 2.2 }
        return 0
    }

    static func deathTime(order: Double, last: Bool) -> Double { order * 0.55 + (last ? 0.23 : 0.16) }

    static func order(_ i: Int, seed: UInt64, lastIndex: Int) -> Double {
        if i == lastIndex { return 1 }
        var r = Seeded(seed ^ (UInt64(i + 1) &* 0x2545_F491_4F6C_DD1D))
        return r.next() * 0.95
    }

    private static func noise(_ seed: UInt64, _ bucket: Int) -> Seeded {
        Seeded(seed ^ (UInt64(bitPattern: Int64(bucket)) &* 0x9E37_79B9_7F4A_7C15))
    }

    /// A seeded letter that drops out now and then.
    static func weak(_ t: Double, seed: UInt64, flicker: Double) -> Double {
        var r = noise(seed, Int(t * 9))
        return r.next() < 0.03 * flicker ? 0.12 + 0.3 * r.next() : 1
    }

    /// A letter with a bad transformer: long bursts of sputtering, then a while of working.
    static func broken(_ t: Double, seed: UInt64) -> Double {
        var r0 = Seeded(seed)
        let cycle = (t + r0.next() * 10).truncatingRemainder(dividingBy: 6.5)
        var r = noise(seed, Int(t * (cycle < 1.6 ? 16 : 5)))
        if cycle < 1.6 { return r.next() < 0.55 ? 0.04 : 0.5 + 0.5 * r.next() }
        return r.next() < 0.1 ? 0.15 : 1
    }

    struct Result {
        var bright: [Double]
        var fill: [Double]?
        var sparks: [NeonSpark]
        var wordStarts: [(start: Double, dur: Double)]
    }

    static func letters(_ plan: NeonSignPlan, _ geo: NeonSignGeometry, pos: Double, t: Double, s: NeonSettings) -> Result {
        let n = geo.letters.count
        let times = wordTimes(plan, geo)
        var bright = [Double](repeating: 0, count: n)
        let gas = s.flag(.gasFill)
        var fill: [Double]? = gas ? [Double](repeating: 1, count: n) : nil
        var sparks: [NeonSpark] = []
        guard n > 0 else { return Result(bright: bright, fill: fill, sparks: sparks, wordStarts: times) }

        var r = Seeded(plan.seed ^ 0xBADC0DE)
        let weakIdx = Int(r.next() * Double(n))
        let brokenIdx = (weakIdx + 1 + Int(r.next() * Double(max(1, n - 1)))) % n
        let lastIdx = Int(r.next() * Double(n))
        let flicker = s[.flicker]
        let speed = s[.ignition]
        let sparkAmount = s[.sparks]
        let spark = geo.fontSize / 44
        let shimmer = 1 + 0.045 * flicker * sin(t * 41 + Double(plan.seed % 97)) * sin(t * 7.7 + Double(plan.seed % 13))
        let dying = pos >= plan.offStart
        let dieAge = pos - plan.offStart
        let ignDur = 0.08 + 0.22 * (1 - speed)

        for (wi, w) in geo.words.enumerated() {
            let (ws, wd) = times[wi]
            guard pos >= ws - 0.01 else { continue }
            var rw = Seeded(plan.seed &+ UInt64(wi + 1) &* 104_729)
            let wordSeed = UInt64(rw.next() * 1e9)
            // Ignition sparks.
            if sparkAmount > 0, rw.next() < sparkAmount * 0.5, let first = w.letters.first {
                let age = pos - ws - (gas ? 0 : ignDur)
                if age >= 0, age < 1 { sparks.append(NeonSpark(p: geo.letters[first].center, age: age, seed: wordSeed, scale: spark)) }
            }
            let count = Double(max(1, w.letters.count))
            for li in w.letters {
                let k = Double(geo.letters[li].indexInWord)
                var b: Double
                if gas {
                    let ls = ws + wd * 0.9 * k / count
                    let ld = max(0.04, wd * 0.9 / count)
                    let f = min(1, max(0, (pos - ls) / ld))
                    fill?[li] = f
                    b = f > 0 ? 1 + 0.3 * exp(-max(0, pos - ls - ld) / 0.12) : 0
                } else {
                    b = ignite(pos - ws, seed: wordSeed, speed: speed)
                }
                if b <= 0 { continue }
                b *= shimmer
                if li == weakIdx, flicker > 0 { b *= weak(t, seed: plan.seed, flicker: flicker) }
                if li == brokenIdx, s.flag(.broken) { b *= broken(t, seed: plan.seed ^ 0xB0B) }
                if dying {
                    let last = li == lastIdx
                    let o = order(li, seed: plan.seed, lastIndex: lastIdx)
                    b *= die(dieAge, order: o, seed: plan.seed &+ UInt64(li), last: last)
                    let deathAge = dieAge - deathTime(order: o, last: last)
                    if sparkAmount > 0, deathAge >= 0, deathAge < 1 {
                        var rs = Seeded(plan.seed ^ UInt64(li &* 31 + 5))
                        if last || rs.next() < sparkAmount * 0.35 {
                            sparks.append(NeonSpark(p: geo.letters[li].center, age: deathAge,
                                                    seed: plan.seed &+ UInt64(li), scale: spark * (last ? 1.5 : 1)))
                        }
                    }
                }
                bright[li] = b
            }
        }
        return Result(bright: bright, fill: fill, sparks: sparks, wordStarts: times)
    }
}

struct NeonSpark {
    let p: CGPoint           // in the sign's own coordinates
    let age: Double
    let seed: UInt64
    let scale: CGFloat
}

// MARK: - Stage: placing signs and building a frame

struct PlacedSign {
    let plan: NeonSignPlan
    let geo: NeonSignGeometry
    let origin: CGPoint      // sign centre on the wall
    let tilt: Double         // degrees

    func toWall(_ p: CGPoint) -> CGPoint {
        let a = tilt * .pi / 180
        return CGPoint(x: origin.x + p.x * cos(a) - p.y * sin(a), y: origin.y + p.x * sin(a) + p.y * cos(a))
    }
}

struct NeonSignState {
    let placed: PlacedSign
    let bright: [Double]
    let fill: [Double]?
    let colors: [NeonRGB]        // per lyric line
    let alt: [NeonRGB?]          // second colour for "everyone" lines (alternating letters)
    let presence: Double         // the glass fading in as the sign is hung
    let sparks: [NeonSpark]
}

struct NeonFrame {
    var size: CGSize
    var cam: StageCamera
    var taps: [MotionTaps.Tap]
    var signs: [NeonSignState]
    var t: Double
    var beat: Double
    var level: Double
    var s: NeonSettings
    var tex: NeonTextures?
    var pavementY: CGFloat
    var litAmount: Double        // 0…1, how much of the current sign is glowing (drives the hum)
}

enum NeonStage {
    static func spacing(_ size: CGSize) -> CGFloat { size.width * 1.25 }
    static func pavementY(_ size: CGSize) -> CGFloat { size.height * 0.88 }

    static func place(_ plan: NeonSignPlan, size: CGSize, s: NeonSettings) -> PlacedSign {
        let base = min(66, max(26, size.width / 8.5)) * CGFloat(0.7 + s[.size] * 0.6)
        let box = CGSize(width: max(60, size.width * 0.84), height: max(40, size.height * 0.6))
        let geo = NeonGlyphs.sign(plan.texts, font: s.font, fontSize: base, box: box)
        var r = Seeded(plan.seed)
        let origin = CGPoint(x: CGFloat(plan.index) * spacing(size),
                             y: size.height * 0.44 + CGFloat(r.next() - 0.5) * size.height * 0.05)
        return PlacedSign(plan: plan, geo: geo, origin: origin, tilt: (r.next() - 0.5) * 2.2)
    }

    static func palette(_ s: NeonSettings, art: [Color]) -> [NeonRGB] {
        switch s.colorMode {
        case .album: art.isEmpty ? NeonRGB.classic : art.map(NeonRGB.init)
        case .classic: NeonRGB.classic
        case .single: [s.singleColor]
        case .singer: NeonRGB.classic + NeonRGB.extra
        }
    }

    static func colors(_ plan: NeonSignPlan, s: NeonSettings, pal: [NeonRGB]) -> ([NeonRGB], [NeonRGB?]) {
        let n = pal.count
        var main: [NeonRGB] = [], alt: [NeonRGB?] = []
        for (li, line) in plan.lines.enumerated() {
            let c: NeonRGB
            if s.colorMode == .singer, line.singer >= 0 {
                c = pal[line.singer % n]
            } else if s.colorMode == .singer {
                c = pal[0]
            } else {
                c = pal[(plan.index * 2 + li) % n]
            }
            main.append(c)
            if line.singer == Cast.everyone {
                let i = pal.firstIndex(of: c) ?? 0
                alt.append(n > 1 ? pal[(i + 1) % n] : c.mixed(.white, 0.45))
            } else {
                alt.append(nil)
            }
        }
        return (main, alt)
    }

    /// Everything one frame needs: which signs are up, how bright each letter is, and where
    /// the camera is.
    static func frame(plans: [NeonSignPlan], pos: Double, t: Double, beat: Double, level: Double, size: CGSize,
                      s: NeonSettings, palette art: [Color], rig: CameraRig?, date: Date, tex: NeonTextures?) -> NeonFrame {
        let pal = palette(s, art: art)
        // The camera moves to a sign shortly before its first line; its glass is hung a little earlier.
        let ci = plans.lastIndex { $0.start - 0.35 <= pos }
        var states: [NeonSignState] = []
        var current: (PlacedSign, NeonLight.Result)?
        var lit = 0.0
        let upcoming = (ci.map { $0 + 1 } ?? 0)
        let hung = upcoming < plans.count && plans[upcoming].start - 0.7 <= pos ? upcoming : (ci ?? -1)
        if size.width > 10, hung >= 0 {
            for i in max(0, (ci ?? 0) - 1)...hung {
                let placed = place(plans[i], size: size, s: s)
                let res = NeonLight.letters(plans[i], placed.geo, pos: pos, t: t, s: s)
                let (main, alt) = colors(plans[i], s: s, pal: pal)
                let presence = smoothstep((pos - (plans[i].start - 0.7)) / 0.5)
                states.append(NeonSignState(placed: placed, bright: res.bright, fill: res.fill, colors: main, alt: alt,
                                            presence: presence, sparks: res.sparks))
                if i == ci {
                    current = (placed, res)
                    let total = res.bright.reduce(0) { $0 + min(1, $1) }
                    lit = res.bright.isEmpty ? 0 : min(1, total / Double(res.bright.count) * 1.5)
                }
            }
        }
        let target = NeonCameraPlanner.target(current: current, first: plans.first.map { place($0, size: size, s: s) },
                                              pos: pos, size: size, s: s, t: t, beat: beat)
        let cam = rig?.step(to: target, at: date, response: 0.22 + s[.smooth] * 1.3) ?? target
        let blur = MotionTaps(velocity: rig?.screenVelocity ?? .zero, zoomVelocity: rig?.zoomVelocity ?? 0,
                              zoom: cam.zoom, amount: s[.motionBlur])
        return NeonFrame(size: size, cam: cam, taps: blur.taps, signs: states, t: t, beat: beat, level: level, s: s,
                         tex: tex, pavementY: pavementY(size), litAmount: lit)
    }
}

// MARK: - Camera

/// Frames the word that's lighting up, pans along the line, eases back to the whole sign once
/// the line is lit, and pulls back while travelling to the next sign.
enum NeonCameraPlanner {
    static func target(current: (PlacedSign, NeonLight.Result)?, first: PlacedSign?, pos: Double, size: CGSize,
                       s: NeonSettings, t: Double, beat: Double) -> StageCamera {
        let sway = (sin(t * 0.23) * 1.2 + sin(t * 0.11 + 1) * 0.5) * s[.tilt]
        guard let (sign, res) = current else {
            let c = first?.origin ?? CGPoint(x: size.width / 2, y: size.height / 2)
            return StageCamera(center: c, zoom: 1, angle: sway)
        }
        let plan = sign.plan
        let wide = StageCamera(center: sign.origin, zoom: 1 + beat * 0.025, angle: sway)

        // Travelling between signs: pull back.
        if plan.index > 0, pos < plan.start + 0.5 {
            return StageCamera(center: sign.origin, zoom: 1 - 0.12 - 0.18 * s[.zoom], angle: sway * 0.5)
        }
        // Powering down: ease out a little.
        if pos >= plan.offStart {
            return StageCamera(center: sign.origin, zoom: 0.94, angle: sway)
        }
        guard let wi = res.wordStarts.indices.last(where: { res.wordStarts[$0].start <= pos }) else { return wide }
        let word = sign.geo.words[wi]
        let line = plan.lines[min(plan.lines.count - 1, word.line)]
        let done = smoothstep((pos - line.start - line.duration) / 1.6)
        let wc = sign.toWall(CGPoint(x: word.bounds.midX, y: word.bounds.midY))
        let follow = CGFloat(s[.pan] * (1 - done) * 0.85)
        let c = CGPoint(x: sign.origin.x + (wc.x - sign.origin.x) * follow,
                        y: sign.origin.y + (wc.y - sign.origin.y) * follow)
        var r = Seeded(plan.seed ^ UInt64(line.id &+ 1000))
        let zin = 1 + s[.zoom] * 0.9 * (0.85 + 0.3 * r.next())
        let z = zin + (1 + (zin - 1) * 0.3 - zin) * done + beat * 0.03
        return StageCamera(center: c, zoom: z, angle: sway - sign.tilt * 0.6 * s[.tilt])
    }
}

// MARK: - Drawing

enum NeonRenderer {
    static func camTransform(_ cam: StageCamera, _ size: CGSize, depth: Double = 1,
                             tap: MotionTaps.Tap = .identity) -> CGAffineTransform {
        let z = CGFloat(1 + (cam.zoom - 1) * depth) * tap.scale
        return CGAffineTransform(translationX: size.width / 2 + tap.offset.width, y: size.height / 2 + tap.offset.height)
            .rotated(by: cam.angle * (0.4 + 0.6 * depth) * .pi / 180)
            .scaledBy(x: z, y: z)
            .translatedBy(x: -cam.center.x * depth, y: -cam.center.y * depth)
    }

    /// The part of the wall the camera can see through `t`.
    static func visible(_ t: CGAffineTransform, _ size: CGSize) -> CGRect {
        let inv = t.inverted()
        let pts = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height),
                   CGPoint(x: size.width, y: size.height)].map { $0.applying(inv) }
        let xs = pts.map(\.x), ys = pts.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    static func signTransform(_ base: CGAffineTransform, _ p: PlacedSign) -> CGAffineTransform {
        CGAffineTransform(translationX: p.origin.x, y: p.origin.y).rotated(by: p.tilt * .pi / 180).concatenating(base)
    }

    static func draw(_ ctx: inout GraphicsContext, _ f: NeonFrame) {
        let size = f.size
        let s = f.s
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.02, green: 0.02, blue: 0.03)))
        guard size.width > 10 else { return }
        let world = camTransform(f.cam, size)
        let view = visible(world, size).insetBy(dx: -20, dy: -20)
        let swell = 1 + 0.6 * f.beat
        let gain = (0.45 + 0.75 * s[.brightness]) * (0.92 + 0.16 * f.level)

        // 1. The wall (slides a little slower than the signs: depth), and the pavement.
        if let tex = f.tex {
            let depth = 1 - s[.parallax] * 0.2
            let wt = camTransform(f.cam, size, depth: depth)
            tile(&ctx, image: tex.wall(s.wall), scale: NeonTextures.scale(s.wall), transform: wt,
                 rect: visible(wt, size).insetBy(dx: -4, dy: -4))
            var g = ctx
            g.concatenate(world)
            let pave = CGRect(x: view.minX, y: f.pavementY, width: view.width, height: max(0, view.maxY - f.pavementY))
            if pave.height > 0 {
                g.clip(to: Path(pave))
                tile(&g, image: tex.asphalt, scale: 1, transform: .identity, rect: pave)
                g.fill(Path(CGRect(x: view.minX, y: f.pavementY - 3, width: view.width, height: 7)),
                       with: .color(Color(white: 0.42)))
            }
        } else {
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.2, green: 0.1, blue: 0.08)))
        }

        // 2. Hardware: standoffs, cable and transformer (lit by the sign like the wall is).
        if s.flag(.hardware) {
            for st in f.signs {
                var g = ctx
                g.concatenate(signTransform(world, st.placed))
                g.opacity = st.presence
                drawHardware(&g, st.placed, pavementY: f.pavementY - st.placed.origin.y, tube: st.placed.geo.tube(s[.thickness]))
            }
        }

        // 3. Light on the wall: ambient darkness plus a pool of colour around each lit word,
        //    multiplied into the bricks.
        ctx.blendMode = .multiply
        ctx.drawLayer { l in
            let ambient = 0.13 + 0.05 * (1 - s[.wallLight])
            l.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: ambient * 0.9, green: ambient * 0.95, blue: ambient * 1.15)))
            l.blendMode = .plusLighter
            for st in f.signs {
                var g = l
                g.concatenate(signTransform(world, st.placed))
                for w in st.placed.geo.words {
                    let b = wordLevel(st, w) * gain
                    guard b > 0.02 else { continue }
                    let k = b * s[.wallLight] * swell
                    let r = max(w.bounds.width * 0.75, st.placed.geo.fontSize * 1.5) * CGFloat(1.1 + s[.wallLight] + 0.4 * s[.glow])
                    let c = st.colors[min(st.colors.count - 1, w.line)]
                    var e = g
                    e.translateBy(x: w.bounds.midX, y: w.bounds.midY)
                    e.scaleBy(x: 1, y: 0.8)
                    e.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)),
                           with: .radialGradient(Gradient(colors: [c.color(0.75 * k), c.color(0.28 * k), c.color(0)]),
                                                 center: .zero, startRadius: 0, endRadius: r))
                }
            }
        }
        ctx.blendMode = .normal

        // 4. Reflections of the lit words in the wet pavement, rippling.
        if s[.wet] > 0 {
            var g = ctx
            g.concatenate(world)
            g.blendMode = .plusLighter
            g.clip(to: Path(CGRect(x: view.minX, y: f.pavementY + 2, width: view.width, height: max(0, view.maxY - f.pavementY))))
            for st in f.signs {
                for w in st.placed.geo.words {
                    let b = wordLevel(st, w) * gain
                    guard b > 0.02 else { continue }
                    let c = st.colors[min(st.colors.count - 1, w.line)]
                    let mid = st.placed.toWall(CGPoint(x: w.bounds.midX, y: w.bounds.midY))
                    let fs = st.placed.geo.fontSize
                    let top = f.pavementY + 3
                    let depth = fs * 3.4
                    let bands = 16
                    let bh = depth / CGFloat(bands)
                    for k in 0..<bands {
                        let y = top + CGFloat(k) * bh
                        let ripple = sin(f.t * 2.3 + Double(k) * 1.7 + Double(mid.x) * 0.031) * Double(fs) * 0.05 * (1 + Double(k) * 0.12)
                        let fall = 1 - Double(k) / Double(bands)
                        let a = 0.42 * s[.wet] * min(1, b) * fall * fall
                        let width = w.bounds.width * CGFloat(0.8 + 0.25 * sin(Double(k) * 2.1 + f.t * 1.3))
                        let x = mid.x - width / 2 + CGFloat(ripple)
                        g.fill(Path(CGRect(x: x, y: y, width: width, height: bh * 0.55)),
                               with: .linearGradient(Gradient(stops: [.init(color: c.color(0), location: 0),
                                                                     .init(color: c.color(a), location: 0.3),
                                                                     .init(color: c.color(a), location: 0.7),
                                                                     .init(color: c.color(0), location: 1)]),
                                                     startPoint: CGPoint(x: x, y: y), endPoint: CGPoint(x: x + width, y: y)))
                    }
                }
            }
        }

        // 5. Glass tubes, unlit.
        for st in f.signs {
            var g = ctx
            g.concatenate(signTransform(world, st.placed))
            g.opacity = st.presence
            drawUnlit(&g, st.placed.geo, tube: st.placed.geo.tube(s[.thickness]), solid: s.solidTubes)
        }

        // 6. Lit tubes: glow once, then the tube and its white-hot core (repeated along the
        //    camera's motion for motion blur).
        for st in f.signs where st.bright.contains(where: { $0 > 0.02 }) {
            var g = ctx
            g.concatenate(signTransform(world, st.placed))
            drawLit(&g, st, s: s, gain: gain, swell: swell, layer: .glow)
            for tap in f.taps {
                var b = ctx
                b.concatenate(signTransform(camTransform(f.cam, size, tap: tap), st.placed))
                b.opacity = f.taps.count > 1 ? tap.opacity : 1
                drawLit(&b, st, s: s, gain: gain, swell: swell, layer: .body)
            }
        }

        // 7. Sparks.
        for st in f.signs where !st.sparks.isEmpty {
            var g = ctx
            g.concatenate(signTransform(world, st.placed))
            g.blendMode = .plusLighter
            for sp in st.sparks { drawSpark(&g, sp, tube: st.placed.geo.tube(s[.thickness])) }
        }

        // 8. Rain, in front of everything.
        if s[.rain] > 0 {
            var g = ctx
            g.blendMode = .plusLighter
            let n = Int(150 * s[.rain])
            let H = Double(size.height) + 80
            for i in 0..<n {
                var r = Seeded(UInt64(i) &* 7919 &+ 17)
                let x0 = r.next() * Double(size.width) * 1.2 - Double(size.width) * 0.1
                let speed = 650 + 500 * r.next()
                let len = 10 + 22 * r.next()
                let y = (f.t * speed + r.next() * 5000).truncatingRemainder(dividingBy: H) - 40
                let x = x0 + y * 0.1
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x - len * 0.1, y: y - len))
                g.stroke(p, with: .color(Color(red: 0.8, green: 0.85, blue: 1, opacity: 0.07 + 0.12 * r.next())), lineWidth: 1)
            }
        }

        // 9. Vignette.
        let d = max(size.width, size.height)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [.clear, .clear, .black.opacity(0.55)]),
                                       center: CGPoint(x: size.width / 2, y: size.height * 0.45),
                                       startRadius: 0, endRadius: d * 0.75))
    }

    /// Average brightness of a word (0 when dark).
    private static func wordLevel(_ st: NeonSignState, _ w: NeonWordGeo) -> Double {
        guard !w.letters.isEmpty else { return 0 }
        var sum = 0.0
        for i in w.letters { sum += min(1.3, st.bright[i]) }
        return sum / Double(w.letters.count)
    }

    private static func tile(_ ctx: inout GraphicsContext, image: CGImage, scale: CGFloat,
                             transform: CGAffineTransform, rect: CGRect) {
        var g = ctx
        g.concatenate(transform)
        let img = g.resolve(Image(decorative: image, scale: scale))
        let tw = CGFloat(image.width) / scale, th = CGFloat(image.height) / scale
        let x0 = Int(floor(rect.minX / tw)), x1 = Int(floor(rect.maxX / tw))
        let y0 = Int(floor(rect.minY / th)), y1 = Int(floor(rect.maxY / th))
        guard (x1 - x0 + 1) * (y1 - y0 + 1) < 400 else { return }
        for ix in x0...x1 {
            for iy in y0...y1 {
                // A hair of overlap hides seams between tiles.
                g.draw(img, in: CGRect(x: CGFloat(ix) * tw - 0.25, y: CGFloat(iy) * th - 0.25, width: tw + 0.5, height: th + 0.5))
            }
        }
    }

    // MARK: Tubes

    static func drawUnlit(_ g: inout GraphicsContext, _ geo: NeonSignGeometry, tube: CGFloat, solid: Bool) {
        let round = { (w: CGFloat) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
        if solid {
            g.fill(geo.outline, with: .color(Color(white: 0.6, opacity: 0.14)))
            g.stroke(geo.outline, with: .color(Color(white: 0.62, opacity: 0.26)), style: round(tube * 0.7))
        } else {
            g.stroke(geo.outline, with: .color(Color(white: 0.6, opacity: 0.3)), style: round(tube * 1.3))
        }
        var h = g
        h.translateBy(x: -tube * 0.22, y: -tube * 0.28)
        h.stroke(geo.outline, with: .color(.white.opacity(0.16)), style: round(max(0.5, tube * 0.3)))
    }

    enum Layer { case glow, body }

    /// Draws the lit letters. The body is drawn word by word (whole words when every letter
    /// shares a brightness); the glow is gathered into one path per colour and brightness so
    /// overlapping halos of neighbouring words don't stack into visible seams.
    static func drawLit(_ g: inout GraphicsContext, _ st: NeonSignState, s: NeonSettings, gain: Double,
                        swell: Double, layer: Layer) {
        let geo = st.placed.geo
        let tube = geo.tube(s[.thickness])
        let solid = s.solidTubes
        var groups: [String: (path: Path, color: NeonRGB, b: Double)] = [:]
        func emit(_ path: Path, _ c: NeonRGB, _ b: Double, solid: Bool) {
            if layer == .body {
                strokeTube(&g, path, c, b, tube, s, swell, layer, solid)
            } else {
                let q = (b * 20).rounded() / 20
                let key = "\(c.r),\(c.g),\(c.b)|\(q)"
                if groups[key] == nil { groups[key] = (Path(), c, q) }
                groups[key]!.path.addPath(path)
            }
        }
        for w in geo.words {
            guard let first = w.letters.first else { continue }
            let c = st.colors[min(st.colors.count - 1, w.line)]
            let alt = st.alt[min(st.alt.count - 1, w.line)]
            let b0 = st.bright[first]
            let uniform = w.letters.allSatisfy { abs(st.bright[$0] - b0) < 0.01 && (st.fill?[$0] ?? 1) >= 1 }
            if uniform {
                guard b0 > 0.02 else { continue }
                if let alt {
                    emit(w.even, c, b0 * gain, solid: solid)
                    emit(w.odd, alt, b0 * gain, solid: solid)
                } else {
                    emit(w.path, c, b0 * gain, solid: solid)
                }
            } else {
                for li in w.letters {
                    let b = st.bright[li]
                    guard b > 0.02 else { continue }
                    let color = alt != nil && geo.letters[li].indexInWord % 2 == 1 ? alt! : c
                    let f = st.fill?[li] ?? 1
                    if f < 1 {
                        guard f > 0 else { continue }
                        emit(geo.letters[li].path.trimmedPath(from: 0, to: f), color, b * gain, solid: false)
                    } else {
                        emit(geo.letters[li].path, color, b * gain, solid: solid)
                    }
                }
            }
        }
        for (_, grp) in groups {
            strokeTube(&g, grp.path, grp.color, grp.b, tube, s, swell, .glow, solid)
        }
    }

    private static func strokeTube(_ g: inout GraphicsContext, _ path: Path, _ c: NeonRGB, _ b: Double, _ w: CGFloat,
                             _ s: NeonSettings, _ swell: Double, _ layer: Layer, _ solid: Bool) {
        let round = { (lw: CGFloat) in StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round) }
        switch layer {
        case .glow:
            let glow = s[.glow]
            let k = b * swell
            var x = g
            x.blendMode = .plusLighter
            // Many thin steps, each fainter and wider, so the halo fades out without a hard edge.
            let spread = CGFloat(0.55 + glow)
            let steps: [(CGFloat, Double)] = [(2.3, 0.2), (3.6, 0.1), (5.6, 0.065), (8.5, 0.042), (12.5, 0.028),
                                              (18, 0.018), (26, 0.011), (36, 0.007)]
            for (i, (width, alpha)) in steps.enumerated() {
                let lw = i == 0 ? w * width : w * (2.3 + (width - 2.3) * spread)
                x.stroke(path, with: .color(c.color(alpha * k * (0.45 + 0.9 * glow))), style: round(lw))
            }
        case .body:
            let a = min(1, b)
            let hot = c.mixed(.white, min(0.92, 0.6 + 0.25 * max(0, b - 0.8)))
            if solid {
                g.fill(path, with: .color(c.color(a)))
                g.stroke(path, with: .color(c.color(a)), style: round(w * 0.9))
                g.fill(path, with: .color(hot.color(a * 0.92)))
                g.stroke(path, with: .color(c.color(a)), style: round(w * 0.55))
            } else {
                g.stroke(path, with: .color(c.color(a)), style: round(w * 1.35))
                g.stroke(path, with: .color(hot.color(a)), style: round(w * 0.5))
            }
        }
    }

    // MARK: Hardware

    static func drawHardware(_ g: inout GraphicsContext, _ p: PlacedSign, pavementY: CGFloat, tube: CGFloat) {
        let geo = p.geo
        let fs = geo.fontSize
        // Standoffs that hold the tubes off the wall.
        for row in geo.rows where row.width > fs {
            for x in [row.minX + row.width * 0.14, row.maxX - row.width * 0.14] {
                let c = CGPoint(x: x, y: row.midY + fs * 0.08)
                let r = max(2, tube * 2.3)
                g.fill(Path(ellipseIn: CGRect(x: c.x - r + 2, y: c.y - r + 3, width: r * 2, height: r * 2)),
                       with: .color(.black.opacity(0.5)))
                g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(Color(white: 0.55)))
                g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.7, width: r * 0.8, height: r * 0.6)),
                       with: .color(Color(white: 0.9)))
            }
        }
        // Transformer box below the sign's right end, cable to it, conduit down to the street.
        let b = geo.bounds
        let box = CGRect(x: b.maxX - fs * 0.2, y: b.maxY + fs * 0.35, width: fs * 1.0, height: fs * 0.62)
        var cable = Path()
        let start = CGPoint(x: b.maxX - fs * 0.1, y: (geo.rows.last?.midY ?? b.maxY) + fs * 0.15)
        cable.move(to: start)
        cable.addCurve(to: CGPoint(x: box.midX, y: box.minY),
                       control1: CGPoint(x: start.x + fs * 0.7, y: start.y + fs * 0.05),
                       control2: CGPoint(x: box.midX, y: box.minY - fs * 0.4))
        g.stroke(cable, with: .color(.black.opacity(0.85)), style: StrokeStyle(lineWidth: max(1.5, tube * 1.1), lineCap: .round))
        g.stroke(cable, with: .color(Color(white: 0.45)), style: StrokeStyle(lineWidth: max(0.5, tube * 0.35), lineCap: .round))
        if pavementY > box.maxY {
            let conduit = Path(CGRect(x: box.midX - tube * 0.9, y: box.maxY, width: tube * 1.8, height: pavementY - box.maxY))
            g.fill(conduit, with: .color(Color(white: 0.4)))
            g.fill(Path(CGRect(x: box.midX - tube * 0.9, y: box.maxY, width: tube * 0.5, height: pavementY - box.maxY)),
                   with: .color(Color(white: 0.65)))
        }
        g.fill(Path(roundedRect: box.offsetBy(dx: 3, dy: 4), cornerRadius: 3), with: .color(.black.opacity(0.5)))
        g.fill(Path(roundedRect: box, cornerRadius: 3), with: .color(Color(white: 0.42)))
        g.stroke(Path(roundedRect: box, cornerRadius: 3), with: .color(Color(white: 0.2)), lineWidth: 1)
        g.fill(Path(CGRect(x: box.minX + box.width * 0.15, y: box.minY + box.height * 0.25,
                           width: box.width * 0.4, height: box.height * 0.22)), with: .color(Color(white: 0.75)))
        for k in 0..<3 {
            g.fill(Path(CGRect(x: box.minX + box.width * (0.62 + CGFloat(k) * 0.1), y: box.minY + box.height * 0.2,
                               width: box.width * 0.05, height: box.height * 0.6)), with: .color(Color(white: 0.25)))
        }
    }

    // MARK: Sparks

    static func drawSpark(_ g: inout GraphicsContext, _ sp: NeonSpark, tube: CGFloat) {
        if sp.age < 0.08 {
            let r = tube * 4 * sp.scale
            g.fill(Path(ellipseIn: CGRect(x: sp.p.x - r, y: sp.p.y - r, width: r * 2, height: r * 2)),
                   with: .radialGradient(Gradient(colors: [.white.opacity(1 - sp.age / 0.08), .clear]),
                                         center: sp.p, startRadius: 0, endRadius: r))
        }
        for i in 0..<8 {
            var r = Seeded(sp.seed &+ UInt64(i) &* 2_654_435_761)
            let life = 0.3 + 0.5 * r.next()
            guard sp.age < life else { continue }
            let ang = -Double.pi / 2 + (r.next() - 0.5) * 2.8
            let v = (70 + 170 * r.next()) * Double(sp.scale)
            let gravity = 650 * Double(sp.scale)
            func at(_ a: Double) -> CGPoint {
                CGPoint(x: sp.p.x + CGFloat(cos(ang) * v * a), y: sp.p.y + CGFloat(sin(ang) * v * a + 0.5 * gravity * a * a))
            }
            var path = Path()
            path.move(to: at(max(0, sp.age - 0.03)))
            path.addLine(to: at(sp.age))
            let fade = 1 - sp.age / life
            g.stroke(path, with: .color(Color(red: 1, green: 0.85 * fade + 0.4 * (1 - fade), blue: 0.5 * fade, opacity: fade)),
                     style: StrokeStyle(lineWidth: 1.4 * sp.scale, lineCap: .round))
        }
    }
}

// MARK: - Hum

/// A quiet mains buzz while the sign is lit. Off unless turned on in the controls.
final class NeonHum {
    static let shared = NeonHum()

    private var engine: AVAudioEngine?
    private let target = UnsafeMutablePointer<Float>.allocate(capacity: 1)

    private init() { target.pointee = 0 }

    @discardableResult
    func update(enabled: Bool, volume: Double) -> Bool {
        target.pointee = enabled ? Float(max(0, min(1, volume))) : 0
        if enabled, engine == nil { start() }
        if !enabled, engine != nil { stop() }
        return engine != nil
    }

    private func start() {
        let engine = AVAudioEngine()
        let format = engine.outputNode.outputFormat(forBus: 0)
        let rate = format.sampleRate > 0 ? format.sampleRate : 48_000
        let target = self.target
        var phase = 0.0, gain: Float = 0
        let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let node = AVAudioSourceNode(format: mono) { _, _, frames, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            let step = 60.0 / rate
            for i in 0..<Int(frames) {
                gain += (target.pointee - gain) * 0.0004
                let x = 2 * Double.pi * phase
                // 60 Hz mains with strong 120 Hz and a little rasp on top.
                var v = 0.45 * sin(x) + 0.5 * sin(2 * x) + 0.18 * sin(3 * x) + 0.1 * sin(4 * x)
                v += 0.04 * (sin(2 * x) > 0 ? 1 : -1)
                let sample = Float(v) * gain * 0.05
                phase += step
                if phase > 1 { phase -= 1 }
                for b in buffers {
                    b.mData?.assumingMemoryBound(to: Float.self)[i] = sample
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: mono)
        do {
            try engine.start()
            self.engine = engine
        } catch {
            self.engine = nil
        }
    }

    private func stop() {
        engine?.stop()
        engine = nil
    }
}

// MARK: - Dashboard preview

/// Looping card preview: a little sign sputters on, glows, then powers down.
struct NeonPreview: View {
    private let words = ["open late", "la la la", "sing it"]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let cycle = 3.6
            let n = Int(t / cycle)
            let ph = t - Double(n) * cycle
            let text = words[n % words.count]
            Canvas { g, size in
                var s = NeonSettings()
                s[.sparks] = 0.6
                s[.thickness] = 0.6
                let plan = NeonSignPlan(index: 0, lines: [.init(id: 0, text: text, start: 0.25, duration: 0.8, singer: 0)],
                                        start: 0.25, offStart: 2.7, seed: LyricPages.hash(text))
                let geo = NeonGlyphs.sign(plan.texts, font: .script, fontSize: 40,
                                          box: CGSize(width: size.width * 0.8, height: size.height * 0.6))
                let res = NeonLight.letters(plan, geo, pos: ph, t: t, s: s)
                let c = NeonRGB.classic[n % NeonRGB.classic.count]
                let placed = PlacedSign(plan: plan, geo: geo, origin: CGPoint(x: size.width / 2, y: size.height * 0.47), tilt: -2)
                let st = NeonSignState(placed: placed, bright: res.bright, fill: nil, colors: [c], alt: [nil],
                                       presence: 1, sparks: res.sparks)
                // Bricks, faintly.
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.07, green: 0.04, blue: 0.04)))
                var bricks = Path()
                for row in 0..<Int(size.height / 14) + 1 {
                    let y = CGFloat(row) * 14
                    bricks.addRect(CGRect(x: 0, y: y, width: size.width, height: 1.5))
                    var x: CGFloat = row % 2 == 0 ? 0 : 18
                    while x < size.width { bricks.addRect(CGRect(x: x, y: y, width: 1.5, height: 14)); x += 36 }
                }
                g.fill(bricks, with: .color(.black.opacity(0.5)))
                let lit = res.bright.isEmpty ? 0 : res.bright.reduce(0) { $0 + min(1, $1) } / Double(res.bright.count)
                g.fill(Path(CGRect(origin: .zero, size: size)),
                       with: .radialGradient(Gradient(colors: [c.color(0.4 * lit), c.color(0.12 * lit), .clear]),
                                             center: placed.origin, startRadius: 0, endRadius: size.width * 0.55))
                var sg = g
                sg.concatenate(NeonRenderer.signTransform(.identity, placed))
                NeonRenderer.drawUnlit(&sg, geo, tube: geo.tube(s[.thickness]), solid: s.solidTubes)
                NeonRenderer.drawLit(&sg, st, s: s, gain: 1.05, swell: 1, layer: .glow)
                NeonRenderer.drawLit(&sg, st, s: s, gain: 1.05, swell: 1, layer: .body)
                sg.blendMode = .plusLighter
                for sp in res.sparks { NeonRenderer.drawSpark(&sg, sp, tube: geo.tube(s[.thickness])) }
            }
        }
        .drawingGroup()
    }
}
