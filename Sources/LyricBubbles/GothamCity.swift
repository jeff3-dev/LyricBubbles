import SwiftUI

// MARK: - Style: Gotham Night
//
// A rain-soaked city at night, sliding past in layers like a slow camera pan. A searchlight
// throws each lyric onto the low clouds, word by word; when the line is done it drifts up and
// dissolves into the fog. The bat-signal burns in a corner of the sky and takes over the clouds
// in instrumental breaks. A caped figure glides by now and then, familiar shadows wait on the
// rooftops, and black cars and police lights race along the elevated highway.
//
// Everything is drawn in one Canvas (GothamRenderer): gradients, cached building paths, one
// cloud texture made once, and small silhouette paths. No blur filters.

struct GothamView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(GothamSettings.storageKey) private var settings = GothamSettings()
    @State private var textures: GothamTextures?
    @State private var fx: GothamFX
    @State private var script: GothamScriptCache
    @State private var hovering = false
    @State private var showControls = false

    /// The demo reel passes a city and script it has already built, so switching is instant.
    init(model: PlayerModel, fx: GothamFX? = nil, script: GothamScriptCache? = nil) {
        self.model = model
        _fx = State(initialValue: fx ?? GothamFX())
        _script = State(initialValue: script ?? GothamScriptCache())
    }

    var body: some View {
        // Every display frame (no minimum interval): a 60 fps cap stutters on 120 Hz screens.
        TimelineView(.animation) { ctx in
            let s = settings
            let pos = model.position(at: ctx.date) + leadTime
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let audio = model.audio.sample(at: ctx.date)
            let lines = currentLines()

            GeometryReader { geo in
                let frame = fx.frame(script: lines, pos: pos, t: t, date: ctx.date, beat: audio.beat, level: audio.level,
                                     size: geo.size, s: s, art: model.artPalette, tex: textures)
                GothamCanvas(frame: frame)
            }
        }
        .overlay(alignment: .bottom) { caption }
        .overlay(alignment: .topTrailing) { controlsButton }
        .background(Color.black)
        .ignoresSafeArea()
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hovering = h } }
        .task { textures = await GothamTextures.shared.value }
    }

    private func currentLines() -> [GothamLine] {
        switch model.status {
        case .notRunning: return GothamScript.message("Open Spotify")
        case .stopped: return GothamScript.message("press play")
        case .error: return GothamScript.message("no signal")
        case .active(let snap):
            if model.loadingLyrics { return GothamScript.message("…") }
            switch model.lyrics {
            case .synced(let lines): return script.lines(lines, title: snap.title)
            case .instrumental: return []
            case .plainOnly: return GothamScript.message("no timed lyrics")
            case .notFound, .none: return GothamScript.message("no lyrics found")
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
        .popover(isPresented: $showControls, arrowEdge: .bottom) { GothamControls() }
        .help("Gotham controls")
        .padding(.top, 10)
        .padding(.trailing, 12)
        .opacity(hovering || showControls ? 1 : 0)
    }
}

/// The whole scene in one GPU-backed canvas.
struct GothamCanvas: View {
    let frame: GothamFrame

    var body: some View {
        Canvas { ctx, _ in GothamRenderer.draw(&ctx, frame) }
            .drawingGroup()
    }
}

// MARK: - Script: when each line is thrown on the clouds

struct GothamLine: Equatable {
    let id: Int
    let text: String
    let start: Double
    let reveal: Double      // seconds over which its words appear
    let end: Double         // when it starts drifting off
    let newSection: Bool    // the searchlight sputters on, and the city pans on further
}

/// What's on the clouds at one moment.
struct GothamMoment {
    var shown: [(line: GothamLine, out: Double)] = []   // out: 0 fully there ... 1 gone
    var next: GothamLine?
    var hero: Double = 1            // 0...1: the bat-signal has the sky to itself
    var sectionAge: Double = .infinity
}

enum GothamScript {
    /// How long a finished line takes to dissolve.
    static let exit = 1.3

    static func make(lines: [LyricLine], title: String) -> [GothamLine] {
        var out: [GothamLine] = []
        if let first = lines.first(where: { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }),
           first.time > 2.5, !title.isEmpty {
            let s = min(0.4, first.time / 4)
            out.append(GothamLine(id: -1, text: title, start: s, reveal: 0.8,
                                  end: max(s + 1.2, min(s + 6, first.time - 0.8)), newSection: true))
        }
        var lastSection = Int.min
        for (i, l) in lines.enumerated() {
            let text = l.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            // An empty line in the lyrics marks a break, so it ends the line before it.
            let next = i + 1 < lines.count ? lines[i + 1].time : l.time + 6
            let gap = max(0.3, next - l.time)
            let reveal = min(gap * 0.8, max(0.35, min(4, Double(text.count) * 0.06)))
            let end = min(next, l.time + reveal + 4.5)
            let prev = out.last
            let fresh = prev == nil || prev!.id == -1 || l.section != lastSection || l.time - prev!.end > 2
            lastSection = l.section
            out.append(GothamLine(id: l.id, text: text, start: l.time, reveal: reveal, end: end, newSection: fresh))
        }
        return out
    }

    /// A status line, always shown.
    static func message(_ text: String) -> [GothamLine] {
        [GothamLine(id: -100, text: text, start: -1000, reveal: 0.01, end: .infinity, newSection: false)]
    }

    static func moment(_ lines: [GothamLine], pos: Double) -> GothamMoment {
        var m = GothamMoment()
        var k = -1
        for (i, l) in lines.enumerated() where l.start <= pos { k = i }
        if k >= 0 {
            for j in max(0, k - 1)...k {
                let out = (pos - lines[j].end) / exit
                if out < 1 { m.shown.append((lines[j], max(0, out))) }
            }
            var j = k
            while j > 0 && !lines[j].newSection { j -= 1 }
            m.sectionAge = pos - lines[j].start
        }
        m.next = k + 1 < lines.count ? lines[k + 1] : nil
        let afterEnd = k >= 0 ? pos - lines[k].end : .infinity
        let untilNext = m.next.map { $0.start - pos } ?? .infinity
        m.hero = smoothstep((afterEnd - 0.3) / 1.5) * smoothstep((untilNext - 0.6) / 1.2)
        return m
    }
}

/// Keeps the song's lines between frames (rebuilt only when the lyrics change).
final class GothamScriptCache {
    private var key = ""
    private var cached: [GothamLine] = []

    func lines(_ lines: [LyricLine], title: String) -> [GothamLine] {
        let k = "\(title)|\(lines.count)|\(lines.first?.id ?? 0)|\(lines.last?.time ?? 0)|\(lines.map(\.section).reduce(0, &+))"
        if k != key {
            key = k
            cached = GothamScript.make(lines: lines, title: title)
        }
        return cached
    }
}

// MARK: - Frame

struct GothamFrame {
    var size: CGSize
    var t: Double
    var pos: Double
    var camX: Double            // how far the city has slid, in screen heights (nearest layer)
    var s: GothamSettings
    var beat: Double
    var level: Double
    var moment: GothamMoment
    var flashAt: Double         // when the last beat-driven lightning struck (in t)
    var flashSeed: UInt64
    var ink: NeonRGB
    var tex: GothamTextures?
    var city: GothamCity

    static func panSpeed(_ s: GothamSettings) -> Double { 0.05 * s[.speed] }

    static func ink(_ s: GothamSettings, art: [Color]) -> NeonRGB {
        switch s.colorMode {
        case .projector: NeonRGB(1, 0.93, 0.78)
        case .cold: NeonRGB(0.86, 0.92, 1)
        case .signal: NeonRGB(1, 0.86, 0.42)
        case .album: art.first.map { NeonRGB($0).mixed(.white, 0.45) } ?? NeonRGB(1, 0.93, 0.78)
        }
    }

    /// A frame without state: the city slides at a steady rate and lightning only comes from
    /// the weather. Used by the dashboard card and the preview renders.
    static func still(script: [GothamLine], pos: Double, t: Double, size: CGSize, s: GothamSettings,
                      tex: GothamTextures?, city: GothamCity, level: Double = 0.5) -> GothamFrame {
        GothamFrame(size: size, t: t, pos: pos, camX: t * panSpeed(s), s: s, beat: 0, level: level,
                    moment: GothamScript.moment(script, pos: pos), flashAt: -100, flashSeed: 0,
                    ink: ink(s, art: []), tex: tex, city: city)
    }
}

/// What carries over between frames: how far the city has panned and the last beat lightning.
final class GothamFX {
    private var last: Date?
    private var camX = 0.0
    private var flashAt = -100.0
    private var flashSeed: UInt64 = 1
    let city = GothamCity()

    func frame(script: [GothamLine], pos: Double, t: Double, date: Date, beat: Double, level: Double,
               size: CGSize, s: GothamSettings, art: [Color], tex: GothamTextures?) -> GothamFrame {
        let dt = last.map { min(0.1, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        let m = GothamScript.moment(script, pos: pos)
        // A new part of the song moves the camera on to a fresh stretch of city.
        let a = m.sectionAge
        let boost = a >= 0 && a < 3 ? 8 * pow(sin(.pi * a / 3), 2) : 0
        camX += dt * GothamFrame.panSpeed(s) * (1 + boost)
        // Big beats can call down lightning (subtle: not often).
        let cooldown = 16 - 11 * s[.lightning] * s[.pulse]
        if beat > 0.8, s[.lightning] > 0, s[.pulse] > 0, t - flashAt > cooldown || t < flashAt {
            flashAt = t
            flashSeed = UInt64(max(1, t * 1000))
        }
        return GothamFrame(size: size, t: t, pos: pos, camX: camX, s: s, beat: beat, level: level, moment: m,
                           flashAt: flashAt, flashSeed: flashSeed, ink: GothamFrame.ink(s, art: art),
                           tex: tex, city: city)
    }
}

// MARK: - City: endless procedural skyline in three layers

struct GothamLayerSpec {
    let depth: Double       // how fast it slides relative to the nearest layer
    let slot: Double        // one building per slot, in screen heights
    let baseY: Double
    let minH: Double
    let maxH: Double
    let pitch: Double       // window spacing
    let empty: Double       // chance a slot is a gap
    let windowGain: Double
    let color: NeonRGB
}

struct GothamBuilding {
    var body = Path()           // in screen heights, x from the slot's left edge
    var warm = Path()
    var dim = Path()
    var cold = Path()
    var beacons: [CGPoint] = []
    var figure: GothamFigure?
    var figureRoll = 1.0
    var figureX = 0.0
    var roofY = 0.0
    var flip = false
}

final class GothamCity {
    static let layers: [GothamLayerSpec] = [
        GothamLayerSpec(depth: 0.15, slot: 0.075, baseY: 0.80, minH: 0.16, maxH: 0.42, pitch: 0.010, empty: 0,
                        windowGain: 0.55, color: NeonRGB(0.07, 0.075, 0.095)),
        GothamLayerSpec(depth: 0.4, slot: 0.13, baseY: 0.95, minH: 0.18, maxH: 0.45, pitch: 0.016, empty: 0,
                        windowGain: 0.85, color: NeonRGB(0.032, 0.035, 0.048)),
        GothamLayerSpec(depth: 1.0, slot: 0.30, baseY: 1.05, minH: 0.2, maxH: 0.32, pitch: 0.028, empty: 0.3,
                        windowGain: 0.5, color: NeonRGB(0.010, 0.010, 0.014)),
    ]

    private var cache: [Int: GothamBuilding] = [:]

    func building(_ layer: Int, _ i: Int) -> GothamBuilding {
        let key = i &* 4 &+ layer
        if let b = cache[key] { return b }
        if cache.count > 600 { cache.removeAll(keepingCapacity: true) }
        let b = Self.make(layer, i)
        cache[key] = b
        return b
    }

    static func make(_ layer: Int, _ i: Int) -> GothamBuilding {
        let spec = layers[layer]
        var r = Seeded(UInt64(bitPattern: Int64(i)) &* 0x9E37_79B9_7F4A_7C15 ^ (UInt64(layer + 1) &* 0xD1B5_4A32_D192_ED03))
        var b = GothamBuilding()
        if r.next() < spec.empty { return b }
        let k = spec.pitch / 0.016
        let w = spec.slot * (0.55 + 0.55 * r.next())
        let x0 = (spec.slot - w) / 2 + (r.next() - 0.5) * spec.slot * 0.25
        let h = spec.minH + (spec.maxH - spec.minH) * pow(r.next(), 1.5)
        let base = spec.baseY + 0.15
        let top = spec.baseY - h
        let light = 0.45 + 0.85 * r.next()
        var tiers: [CGRect] = []
        var body = Path()

        // Every piece is wound the same way so overlapping pieces never punch holes.
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
            body.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        func tri(_ xl: Double, _ y: Double, _ xr: Double, _ apex: Double) {
            body.addLines([CGPoint(x: xl, y: y), CGPoint(x: (xl + xr) / 2, y: apex), CGPoint(x: xr, y: y)])
            body.closeSubpath()
        }
        func mast(_ x: Double, _ y: Double, _ len: Double) {
            rect(x - 0.001 * k, y - len, 0.002 * k, len)
            b.beacons.append(CGPoint(x: x, y: y - len))
        }
        func waterTower(_ x: Double, _ roof: Double, _ s: Double) {
            rect(x + 0.1 * s, roof - 0.55 * s, 0.8 * s, 0.55 * s)     // legs, as one dark block
            rect(x, roof - 1.5 * s, s, 0.95 * s)                     // tank
            tri(x - 0.05 * s, roof - 1.5 * s, x + 1.05 * s, roof - 1.95 * s)
        }

        let style = layer == 2 ? 5 : Int(r.next() * 5)
        switch style {
        case 1:     // art deco setbacks, maybe a spire
            let t1 = top + h * 0.32, t2 = top + h * 0.13
            tiers = [CGRect(x: x0, y: t1, width: w, height: base - t1),
                     CGRect(x: x0 + w * 0.14, y: t2, width: w * 0.72, height: t1 - t2),
                     CGRect(x: x0 + w * 0.3, y: top, width: w * 0.4, height: t2 - top)]
            tiers.forEach { body.addRect($0) }
            if r.next() < 0.6 {
                tri(x0 + w * 0.4, top, x0 + w * 0.6, top - h * 0.16)
                b.beacons.append(CGPoint(x: x0 + w * 0.5, y: top - h * 0.16))
            }
        case 2:     // gothic: steep roof and corner pinnacles
            let roofH = w * (0.45 + 0.5 * r.next())
            let wall = top + roofH
            tiers = [CGRect(x: x0, y: wall, width: w, height: base - wall)]
            body.addRect(tiers[0])
            tri(x0, wall, x0 + w, top)
            let pw = w * 0.09
            tri(x0 - pw * 0.2, wall, x0 + pw, wall - roofH * 0.55)
            tri(x0 + w - pw, wall, x0 + w + pw * 0.2, wall - roofH * 0.55)
        case 3:     // slab with a radio mast
            tiers = [CGRect(x: x0, y: top, width: w, height: base - top)]
            body.addRect(tiers[0])
            mast(x0 + w * (0.25 + 0.5 * r.next()), top, h * (0.12 + 0.15 * r.next()) * (layer == 0 ? 1 : 0.7))
        case 4 where layer == 1:    // domed civic building
            let domeH = w * 0.28
            let wall = top + domeH
            tiers = [CGRect(x: x0, y: wall, width: w, height: base - wall)]
            body.addRect(tiers[0])
            body.move(to: CGPoint(x: x0 + w * 0.12, y: wall))
            body.addQuadCurve(to: CGPoint(x: x0 + w * 0.88, y: wall), control: CGPoint(x: x0 + w * 0.5, y: wall - domeH * 2))
            body.closeSubpath()
            rect(x0 + w * 0.46, wall - domeH * 1.3, w * 0.08, domeH * 0.4)
        case 5:     // near rooftops: parapet, water towers, chimneys, someone on the ledge
            tiers = [CGRect(x: x0, y: top, width: w, height: base - top)]
            body.addRect(tiers[0])
            let roof = top - 0.006
            rect(x0 - 0.004, roof, w + 0.008, 0.006)
            if r.next() < 0.45 { waterTower(x0 + w * (0.1 + 0.5 * r.next()), roof, 0.035) }
            if r.next() < 0.5 { rect(x0 + w * (0.6 + 0.3 * r.next()), roof - 0.025, 0.012, 0.025) }
            b.roofY = roof
            b.figureRoll = r.next()
            b.figure = GothamFigure(rawValue: Int(r.next() * Double(GothamFigure.allCases.count))) ?? .joker
            b.flip = r.next() < 0.5
            if b.figure == .perched {
                b.figureX = b.flip ? x0 + 0.012 : x0 + w - 0.012
            } else {
                b.figureX = x0 + w * (0.2 + 0.6 * r.next())
            }
        default:    // plain box, roof clutter
            tiers = [CGRect(x: x0, y: top, width: w, height: base - top)]
            body.addRect(tiers[0])
            if layer == 1 && r.next() < 0.5 { waterTower(x0 + w * (0.15 + 0.5 * r.next()), top, 0.022) }
            if r.next() < 0.3 { mast(x0 + w * 0.7, top, 0.05 * k) }
        }

        b.body = body
        let floor = min(spec.baseY + 0.03, 1.02)
        for tier in tiers { addWindows(tier, pitch: spec.pitch, light: light, floor: floor, r: &r, into: &b) }
        return b
    }

    private static func addWindows(_ rc: CGRect, pitch: Double, light: Double, floor: Double,
                                   r: inout Seeded, into b: inout GothamBuilding) {
        let ww = pitch * 0.42, wh = pitch * 0.6, py = pitch * 1.3
        let cols = Int((rc.width - pitch * 0.5) / pitch)
        guard cols >= 1 else { return }
        let mx = rc.minX + (rc.width - Double(cols) * pitch) / 2 + (pitch - ww) / 2
        var y = rc.minY + pitch * 0.6
        var rows = 0
        while y + wh < min(rc.maxY, floor), rows < 70 {
            let storey = r.next()      // whole floors tend to be lit or dark together
            for c in 0..<cols {
                let v = (r.next() * 0.65 + storey * 0.35) / light
                let cell = CGRect(x: mx + Double(c) * pitch, y: y, width: ww, height: wh)
                if v < 0.16 { b.warm.addRect(cell) } else if v < 0.3 { b.dim.addRect(cell) } else if v < 0.4 { b.cold.addRect(cell) }
            }
            y += py
            rows += 1
        }
    }
}

// MARK: - Textures

/// A soft, horizontally tiling cloud texture (white, the alpha is the cloud), made once.
struct GothamTextures {
    let clouds: CGImage

    static let shared: Task<GothamTextures?, Never> = Task.detached(priority: .userInitiated) { make() }

    static func make() -> GothamTextures? {
        guard let c = cloudImage(width: 384, height: 160) else { return nil }
        return GothamTextures(clouds: c)
    }

    private static func lattice(_ x: Int, _ y: Int, _ seed: UInt64) -> Double {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F ^ seed
        h ^= h >> 31
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 29
        return Double(h & 0xFFFFFF) / Double(0xFFFFFF)
    }

    /// Value noise that wraps every `period` cells along x.
    private static func noise(_ x: Double, _ y: Double, period: Int, seed: UInt64) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = x - Double(ix), fy = y - Double(iy)
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        func at(_ i: Int, _ j: Int) -> Double { lattice(((i % period) + period) % period, j, seed) }
        let a = at(ix, iy), b = at(ix + 1, iy), c = at(ix, iy + 1), d = at(ix + 1, iy + 1)
        return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy
    }

    static func cloudImage(width w: Int, height h: Int) -> CGImage? {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            let v = Double(y) / Double(h)
            let env = pow(sin(.pi * v), 0.7)
            for x in 0..<w {
                let u = Double(x) / Double(w)
                var sum = 0.0, amp = 0.5
                for o in 0..<5 {
                    let f = 1 << o
                    sum += amp * noise(u * Double(5 * f), v * 2.4 * Double(f), period: 5 * f, seed: UInt64(o + 3))
                    amp *= 0.5
                }
                let a = smoothstep((sum / 0.97 - 0.36) / 0.38) * env
                let byte = UInt8(max(0, min(255, a * 255)))
                let i = (y * w + x) * 4
                px[i] = byte; px[i + 1] = byte; px[i + 2] = byte; px[i + 3] = byte
            }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - Dashboard preview

/// Looping card preview: the city drifts by while short lines land on the clouds.
struct GothamPreview: View {
    @State private var tex: GothamTextures?
    private static let city = GothamCity()
    private static let script = GothamScript.make(lines: [
        LyricLine(id: 0, time: 0.3, text: "the city never sleeps"),
        LyricLine(id: 1, time: 3.3, text: "look up"),
        LyricLine(id: 2, time: 6.3, text: "into the night"),
        LyricLine(id: 3, time: 9.0, text: ""),
    ], title: "")

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let pos = t.truncatingRemainder(dividingBy: 12)
            Canvas { g, size in
                var s = GothamSettings()
                s[.size] = 0.2
                s[.nextLine] = 0
                s[.speed] = 0.9
                s[.characters] = 1
                s[.batman] = 1
                let f = GothamFrame.still(script: Self.script, pos: pos, t: t, size: size, s: s, tex: tex, city: Self.city)
                GothamRenderer.draw(&g, f)
            }
        }
        .drawingGroup()
        .task { tex = await GothamTextures.shared.value }
    }
}
