import SwiftUI

// MARK: - Style: Fever City
//
// A chunky toy-box city at dusk sliding past in parallax layers, like a TV screensaver city, on crack.
// Lyrics land all over it: billboards pop up from behind the roofs, a blimp, a plane's tow banner,
// skywriting, a tower that spells the line in its windows. Meanwhile UFOs abduct cars, rockets launch,
// a kaiju strolls behind the skyline, a giant cat peeks over the roofs, a whale swims through the
// clouds, a coaster loops over the rooftops, cars hop on the beat and the city flips day and night.
//
// Built on Gotham Night: the line timing (GothamScript), the cloud texture (GothamTextures) and the
// parallax-layer city all come from there. Everything is drawn in one Canvas (FeverRenderer), events
// are scheduled from the clock (FeverEvents), so any moment can be rendered without history.

struct FeverView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(FeverSettings.storageKey) private var settings = FeverSettings()
    @State private var textures: GothamTextures?
    @State private var fx = FeverFX()
    @State private var script = GothamScriptCache()
    @State private var hovering = false
    @State private var showControls = false

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
                FeverCanvas(frame: frame)
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
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .lineLimit(1)
                    .padding(.bottom, 10)
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
        .popover(isPresented: $showControls, arrowEdge: .bottom) { FeverControls() }
        .help("Fever City controls")
        .padding(.top, 10)
        .padding(.trailing, 12)
        .opacity(hovering || showControls ? 1 : 0)
    }
}

struct FeverCanvas: View {
    let frame: FeverFrame

    var body: some View {
        Canvas { ctx, _ in FeverRenderer.draw(&ctx, frame) }
            .drawingGroup()
    }
}

// MARK: - Palettes

struct FeverPalette {
    var skyTop, skyMid, skyLow: NeonRGB
    var orb, cloud, haze: NeonRGB
    var bldg: [NeonRGB]          // five building colours
    var window, windowAlt, accent, road, sign: NeonRGB
    var night: Double            // 0 broad daylight ... 1 deep night (stars, lit windows)

    static let names = ["Dusk", "Daybreak", "Midnight", "Candy", "Acid", "Album art"]
    static let count = names.count
    /// The palettes a swap cycles through (not album art).
    static let fixed = 5

    static func preset(_ i: Int, art: [Color]) -> FeverPalette {
        func c(_ r: Double, _ g: Double, _ b: Double) -> NeonRGB { NeonRGB(r, g, b) }
        switch i {
        case 1:
            return FeverPalette(skyTop: c(0.32, 0.55, 0.95), skyMid: c(0.68, 0.78, 1), skyLow: c(1, 0.82, 0.62),
                                orb: c(1, 0.93, 0.6), cloud: c(1, 1, 1), haze: c(0.8, 0.85, 1),
                                bldg: [c(0.95, 0.58, 0.5), c(0.48, 0.74, 0.86), c(0.96, 0.82, 0.5), c(0.62, 0.56, 0.86), c(0.42, 0.6, 0.72)],
                                window: c(1, 0.98, 0.85), windowAlt: c(0.75, 0.93, 1), accent: c(1, 0.45, 0.4),
                                road: c(0.42, 0.42, 0.5), sign: c(0.2, 0.25, 0.4), night: 0)
        case 2:
            return FeverPalette(skyTop: c(0.02, 0.03, 0.12), skyMid: c(0.06, 0.08, 0.26), skyLow: c(0.24, 0.12, 0.38),
                                orb: c(0.9, 0.95, 1), cloud: c(0.3, 0.32, 0.55), haze: c(0.15, 0.12, 0.35),
                                bldg: [c(0.12, 0.14, 0.32), c(0.18, 0.12, 0.36), c(0.08, 0.18, 0.3), c(0.22, 0.16, 0.42), c(0.1, 0.1, 0.24)],
                                window: c(0.35, 1, 0.92), windowAlt: c(1, 0.35, 0.8), accent: c(1, 0.3, 0.75),
                                road: c(0.06, 0.06, 0.14), sign: c(0.05, 0.04, 0.12), night: 1)
        case 3:
            return FeverPalette(skyTop: c(1, 0.55, 0.78), skyMid: c(1, 0.78, 0.86), skyLow: c(0.7, 0.96, 0.9),
                                orb: c(1, 1, 0.85), cloud: c(1, 1, 1), haze: c(1, 0.85, 0.95),
                                bldg: [c(1, 0.45, 0.65), c(0.42, 0.84, 0.74), c(1, 0.84, 0.4), c(0.66, 0.55, 1), c(1, 0.64, 0.44)],
                                window: c(1, 1, 0.9), windowAlt: c(0.85, 1, 1), accent: c(0.4, 0.3, 0.9),
                                road: c(0.55, 0.42, 0.6), sign: c(0.35, 0.15, 0.4), night: 0.15)
        case 4:
            return FeverPalette(skyTop: c(0.08, 0, 0.14), skyMid: c(0, 0.42, 0.36), skyLow: c(0.85, 1, 0.2),
                                orb: c(1, 0.3, 0.8), cloud: c(0.5, 1, 0.6), haze: c(0.2, 0.6, 0.4),
                                bldg: [c(1, 0.1, 0.6), c(0.1, 0.85, 1), c(0.65, 1, 0.1), c(1, 0.5, 0), c(0.5, 0.1, 1)],
                                window: c(1, 1, 0.3), windowAlt: c(0.2, 1, 1), accent: c(1, 1, 0.2),
                                road: c(0.1, 0.05, 0.15), sign: c(0.05, 0, 0.1), night: 0.75)
        case 5 where !art.isEmpty:
            let a = art.map { NeonRGB($0) }
            let p = a[0], q = a[min(1, a.count - 1)], r = a[min(2, a.count - 1)]
            let navy = c(0.04, 0.03, 0.1)
            return FeverPalette(skyTop: p.mixed(navy, 0.75), skyMid: p.mixed(navy, 0.35), skyLow: q.mixed(.white, 0.35),
                                orb: r.mixed(.white, 0.7), cloud: q.mixed(.white, 0.6), haze: p.mixed(.white, 0.2),
                                bldg: [p.mixed(navy, 0.3), q.mixed(navy, 0.35), r.mixed(navy, 0.3), p.mixed(q, 0.5), q.mixed(r, 0.5)],
                                window: r.mixed(.white, 0.6), windowAlt: q.mixed(.white, 0.7), accent: r,
                                road: p.mixed(navy, 0.7), sign: p.mixed(navy, 0.85), night: 0.6)
        default:
            return FeverPalette(skyTop: c(0.16, 0.09, 0.36), skyMid: c(0.52, 0.24, 0.6), skyLow: c(1, 0.56, 0.55),
                                orb: c(1, 0.95, 0.82), cloud: c(0.96, 0.72, 0.86), haze: c(0.62, 0.36, 0.66),
                                bldg: [c(0.36, 0.23, 0.6), c(0.55, 0.3, 0.7), c(0.28, 0.34, 0.68), c(0.62, 0.3, 0.55), c(0.24, 0.2, 0.48)],
                                window: c(1, 0.86, 0.45), windowAlt: c(0.6, 0.95, 1), accent: c(1, 0.4, 0.62),
                                road: c(0.2, 0.13, 0.3), sign: c(0.14, 0.07, 0.24), night: 0.6)
        }
    }

    func mixed(_ o: FeverPalette, _ k: Double) -> FeverPalette {
        guard k > 0 else { return self }
        guard k < 1 else { return o }
        return FeverPalette(skyTop: skyTop.mixed(o.skyTop, k), skyMid: skyMid.mixed(o.skyMid, k), skyLow: skyLow.mixed(o.skyLow, k),
                            orb: orb.mixed(o.orb, k), cloud: cloud.mixed(o.cloud, k), haze: haze.mixed(o.haze, k),
                            bldg: zip(bldg, o.bldg).map { $0.mixed($1, k) },
                            window: window.mixed(o.window, k), windowAlt: windowAlt.mixed(o.windowAlt, k),
                            accent: accent.mixed(o.accent, k), road: road.mixed(o.road, k), sign: sign.mixed(o.sign, k),
                            night: night + (o.night - night) * k)
    }

    /// The same colours lit for a time of day. Auto keeps the palette's own light.
    func lit(_ time: FeverTime, t: Double) -> FeverPalette {
        func c(_ r: Double, _ g: Double, _ b: Double) -> NeonRGB { NeonRGB(r, g, b) }
        func sky(_ top: NeonRGB, _ mid: NeonRGB, _ low: NeonRGB, orb: NeonRGB, cloud: NeonRGB, haze: NeonRGB,
                 shade: NeonRGB, _ k: Double, night n: Double) -> FeverPalette {
            var p = self
            p.skyTop = top; p.skyMid = mid; p.skyLow = low; p.orb = orb; p.cloud = cloud; p.haze = haze
            p.bldg = bldg.map { $0.mixed(shade, k) }
            p.road = road.mixed(shade, k * 0.8)
            p.night = n
            if n > 0.8 { p.window = window.mixed(c(1, 0.85, 0.4), 0.3) }
            return p
        }
        switch time {
        case .auto: return self
        case .dawn:
            return sky(c(0.28, 0.36, 0.7), c(0.92, 0.66, 0.74), c(1, 0.84, 0.6), orb: c(1, 0.92, 0.72), cloud: c(1, 0.86, 0.88),
                       haze: c(0.9, 0.72, 0.8), shade: c(1, 0.85, 0.82), 0.18, night: 0.3)
        case .day:
            return sky(c(0.32, 0.55, 0.95), c(0.68, 0.78, 1), c(0.92, 0.93, 1), orb: c(1, 0.93, 0.6), cloud: c(1, 1, 1),
                       haze: c(0.8, 0.85, 1), shade: c(1, 1, 1), 0.3, night: 0)
        case .sunset:
            return sky(c(0.22, 0.1, 0.4), c(0.86, 0.34, 0.46), c(1, 0.66, 0.32), orb: c(1, 0.78, 0.45), cloud: c(1, 0.62, 0.6),
                       haze: c(0.8, 0.4, 0.5), shade: c(0.4, 0.15, 0.35), 0.3, night: 0.5)
        case .night:
            return sky(c(0.02, 0.03, 0.12), c(0.05, 0.06, 0.22), c(0.18, 0.1, 0.32), orb: c(0.92, 0.95, 1), cloud: c(0.22, 0.24, 0.42),
                       haze: c(0.12, 0.1, 0.3), shade: c(0.03, 0.03, 0.12), 0.55, night: 1)
        case .cycle:
            // Each stop holds, then eases into the next; one lap every 7.5 minutes (the clock wraps at an hour).
            let stops: [FeverTime] = [.dawn, .day, .sunset, .night]
            let u = (t / 450).truncatingRemainder(dividingBy: 1) * 4
            let i = Int(u) % 4
            let k = smoothstep((u - Double(i) - 0.65) / 0.35)
            return lit(stops[i], t: t).mixed(lit(stops[(i + 1) % 4], t: t), k)
        }
    }

    /// The sky and light under some weather.
    func weathered(_ w: FeverWeather, _ a: Double) -> FeverPalette {
        func c(_ r: Double, _ g: Double, _ b: Double) -> NeonRGB { NeonRGB(r, g, b) }
        var p = self
        func overcast(_ grey: NeonRGB, _ k: Double, cloud: NeonRGB, _ ck: Double) {
            let g = grey.mixed(skyTop, night * 0.7)
            p.skyTop = skyTop.mixed(g, k); p.skyMid = skyMid.mixed(g, k); p.skyLow = skyLow.mixed(g, k)
            p.cloud = self.cloud.mixed(cloud.mixed(skyTop, night * 0.6), ck)
            p.haze = haze.mixed(g, k)
        }
        switch w {
        case .clear: break
        case .rain:
            overcast(c(0.42, 0.45, 0.55), 0.5 * a, cloud: c(0.55, 0.57, 0.65), 0.6 * a)
            p.night = min(1, night + 0.15 * a)
        case .storm:
            overcast(c(0.12, 0.13, 0.2), 0.7 * a, cloud: c(0.25, 0.26, 0.34), 0.75 * a)
            p.bldg = bldg.map { $0.mixed(c(0.1, 0.1, 0.16), 0.25 * a) }
            p.night = min(1, night + 0.4 * a)
        case .snow:
            overcast(c(0.82, 0.84, 0.9), 0.4 * a, cloud: c(1, 1, 1), 0.6 * a)
            p.road = road.mixed(c(0.85, 0.87, 0.92), 0.35 * a)
        case .fog:
            overcast(c(0.7, 0.72, 0.78), 0.5 * a, cloud: c(0.85, 0.86, 0.9), 0.5 * a)
            p.bldg = bldg.map { $0.mixed(p.haze, 0.2 * a) }
        }
        return p
    }

    /// The same city at the other end of the day.
    var flipped: FeverPalette {
        var p = self
        if night > 0.45 {
            let day = FeverPalette.preset(1, art: [])
            p.skyTop = day.skyTop; p.skyMid = day.skyMid; p.skyLow = day.skyLow
            p.cloud = .white; p.haze = day.haze; p.orb = NeonRGB(1, 0.92, 0.55)
            p.bldg = bldg.map { $0.mixed(.white, 0.3) }
            p.road = road.mixed(NeonRGB(0.5, 0.5, 0.55), 0.6)
            p.night = 0
        } else {
            let navy = NeonRGB(0.03, 0.03, 0.12)
            p.skyTop = navy; p.skyMid = skyTop.mixed(navy, 0.7); p.skyLow = skyLow.mixed(navy, 0.6)
            p.cloud = cloud.mixed(navy, 0.6); p.haze = haze.mixed(navy, 0.6); p.orb = NeonRGB(0.95, 0.97, 1)
            p.bldg = bldg.map { $0.mixed(navy, 0.55) }
            p.road = road.mixed(navy, 0.6)
            p.window = NeonRGB(1, 0.85, 0.4)
            p.night = 1
        }
        return p
    }
}

// MARK: - Frame

struct FeverFrame {
    var size: CGSize
    var t: Double
    var pos: Double
    var camX: Double            // how far the city has slid, in screen heights (nearest layer)
    var s: FeverSettings
    var beat: Double
    var level: Double
    var moment: GothamMoment
    var pal: FeverPalette
    var beats: [Double]         // recent beat times (in t), newest last
    var beatCount: Int
    var swapFlash: Double       // 0...1 just after a palette swap
    var tex: GothamTextures?
    var city: FeverCityMap
    var stages: [FeverStage]
    var force: [FeverEvent: Double] = [:]   // previews: pin an event at a progress

    static func panSpeed(_ s: FeverSettings) -> Double { 0.02 + 0.16 * s[.speed] }

    /// The palette for this moment: the chosen one (shifted by any swaps), maybe flipped day/night
    /// for this section of the song.
    static func palette(_ s: FeverSettings, art: [Color], moment: GothamMoment, pos: Double, shift: Int, t: Double) -> FeverPalette {
        let chosen = Int(s[.palette])
        let base = (shift == 0 || chosen >= FeverPalette.fixed
            ? FeverPalette.preset(chosen, art: art)
            : FeverPalette.preset((chosen + shift) % FeverPalette.fixed, art: art))
            .lit(s.time, t: t).weathered(s.weather, s[.intensity])
        guard s[.flip] > 0, moment.sectionAge.isFinite else { return base }
        let start = pos - moment.sectionAge
        let roll = Double(LyricPages.hash("flip\(Int(start * 10))") % 1000) / 1000
        guard roll < s[.flip] * 0.7 else { return base }
        return base.mixed(base.flipped.weathered(s.weather, s[.intensity]), smoothstep(moment.sectionAge / 1.2))
    }

    /// A frame without state, for the dashboard card and the preview renders.
    static func still(script: [GothamLine], pos: Double, t: Double, size: CGSize, s: FeverSettings,
                      tex: GothamTextures?, city: FeverCityMap, level: Double = 0.5) -> FeverFrame {
        let m = GothamScript.moment(script, pos: pos)
        return FeverFrame(size: size, t: t, pos: pos, camX: t * panSpeed(s), s: s, beat: 0.3, level: level, moment: m,
                          pal: palette(s, art: [], moment: m, pos: pos, shift: 0, t: t),
                          beats: [t - 1.4, t - 0.8, t - 0.25], beatCount: Int(t * 2), swapFlash: 0, tex: tex, city: city,
                          stages: FeverLyrics.stages(script, moment: m, pos: pos, place: s.place))
    }
}

// MARK: - Lyric stages

/// One song section's lyrics: the carrier it stays on and how far it has arrived or left.
/// Neighbouring sections on the same carrier merge, so a carrier only changes hands at a real change.
struct FeverStage {
    var carrier: FeverRenderer.Carrier
    var index: Int          // which section, for variety
    var age: Double         // seconds since the carrier started arriving
    var leave: Double       // 0 there ... 1 gone
    var lines: [(line: GothamLine, out: Double)]
}

enum FeverLyrics {
    /// How long a carrier takes to arrive or leave; the old one leaves while the new one arrives.
    static let handoff = 1.6
    /// Carriers start arriving this long before their section's first line.
    static let lead = 0.9

    static func carrier(section: Int, seed: Int, _ place: FeverPlace) -> FeverRenderer.Carrier {
        let kinds: [FeverRenderer.Carrier] = switch place {
        case .everywhere: [.billboard, .blimp, .tower, .skywriting, .banner]
        case .sky: [.blimp, .skywriting, .banner]
        case .billboards: [.billboard]
        case .caption: [.caption]
        case .blimp: [.blimp]
        case .tower: [.tower]
        case .banner: [.banner]
        case .skywriting: [.skywriting]
        }
        return kinds[(section + seed) % kinds.count]
    }

    static func stages(_ script: [GothamLine], moment m: GothamMoment, pos: Double, place: FeverPlace) -> [FeverStage] {
        guard let first = script.first else { return [] }
        if first.id == -100 {
            return [FeverStage(carrier: place == .caption ? .caption : (place == .everywhere || place == .billboards ? .billboard
                                                                       : carrier(section: 0, seed: 0, place)),
                               index: 0, age: 100, leave: 0, lines: m.shown)]
        }
        let seed = Int(LyricPages.hash(script.map(\.text).prefix(3).joined()) % 97)
        struct Group { var carrier: FeverRenderer.Carrier; var index: Int; var start: Double; var lastEnd: Double; var ids: [Int] }
        var groups: [Group] = []
        var section = -1
        for (i, l) in script.enumerated() {
            if i == 0 || l.newSection {
                section += 1
                let c = carrier(section: section, seed: seed, place)
                if groups.last?.carrier != c {
                    groups.append(Group(carrier: c, index: section, start: l.start, lastEnd: l.end, ids: []))
                }
            }
            groups[groups.count - 1].lastEnd = l.end
            groups[groups.count - 1].ids.append(l.id)
        }
        var out: [FeverStage] = []
        for (gi, g) in groups.enumerated() {
            let begin = g.start - lead
            let end = gi + 1 < groups.count ? groups[gi + 1].start - lead : g.lastEnd + GothamScript.exit
            guard pos >= begin, pos < end + handoff else { continue }
            let lines = m.shown.filter { g.ids.contains($0.line.id) }
            out.append(FeverStage(carrier: g.carrier, index: g.index, age: pos - begin,
                                  leave: max(0, min(1, (pos - end) / handoff)), lines: lines))
        }
        return out
    }
}

/// What carries over between frames: the pan, recent beats and palette swaps.
final class FeverFX {
    private var last: Date?
    private var camX = 0.0
    private var lastBeat = 0.0
    private var beats: [Double] = []
    private var beatCount = 0
    private var shift = 0
    private var swapAt = -100.0
    private var swappedSection = -1.0
    private var prevPal: FeverPalette?
    let city = FeverCityMap()

    func frame(script: [GothamLine], pos: Double, t: Double, date: Date, beat: Double, level: Double,
               size: CGSize, s: FeverSettings, art: [Color], tex: GothamTextures?) -> FeverFrame {
        let dt = last.map { min(0.1, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        let m = GothamScript.moment(script, pos: pos)
        let pulse = s[.pulse]

        // The city slides on; a new section gives it a shove, the wild camera floors it on loud parts.
        let a = m.sectionAge
        var boost = a >= 0 && a < 2.5 ? 5 * pow(sin(.pi * a / 2.5), 2) : 0
        if s.camera == .wild { boost += 2.5 * max(0, level - 0.45) * pulse }
        camX += dt * FeverFrame.panSpeed(s) * (1 + boost)

        // Beat onsets drive the fireworks, hops and dancing lights.
        if pulse > 0, beat > 0.7, lastBeat <= 0.7, (beats.last.map { t - $0 > 0.2 } ?? true) {
            beats.append(t)
            beatCount += 1
            if beats.count > 10 { beats.removeFirst() }
        }
        if let b = beats.last, b > t { beats.removeAll() }    // the clock wrapped
        lastBeat = beat

        // Palette swap at the start of some sections.
        if s[.swap] > 0, a < 0.4, a.isFinite {
            let start = ((pos - a) * 10).rounded()
            if start != swappedSection {
                swappedSection = start
                let roll = Double(LyricPages.hash("swap\(Int(start))") % 1000) / 1000
                if roll < s[.swap] * 0.7 {
                    prevPal = FeverFrame.palette(s, art: art, moment: m, pos: pos, shift: shift, t: t)
                    shift += 1
                    swapAt = t
                }
            }
        }
        var pal = FeverFrame.palette(s, art: art, moment: m, pos: pos, shift: shift, t: t)
        let k = (t - swapAt) / 0.5
        if let prev = prevPal, k >= 0, k < 1 { pal = prev.mixed(pal, smoothstep(k)) }
        let flash = k >= 0 && k < 1.5 ? max(0, 1 - k / 1.5) : 0

        return FeverFrame(size: size, t: t, pos: pos, camX: camX, s: s, beat: beat * pulse, level: level, moment: m,
                          pal: pal, beats: pulse > 0 ? beats : [], beatCount: beatCount, swapFlash: flash,
                          tex: tex, city: city, stages: FeverLyrics.stages(script, moment: m, pos: pos, place: s.place))
    }
}

// MARK: - City: endless procedural toy-box skyline in three layers

struct FeverLayerSpec {
    let depth: Double
    let slot: Double
    let baseY: Double
    let minH: Double
    let maxH: Double
    let pitch: Double
    let empty: Double
    let fade: Double        // how far the colours sink into the haze
}

struct FeverBuilding {
    var body = Path()           // in screen heights, x from the slot's left edge
    var trim = Path()           // roofs, domes, awnings: a lighter shade of the body
    var lit = Path()
    var alt = Path()
    var dark = Path()
    var color = 0
    var top = 0.0
    var phase = 0.0
    var empty: Bool { body.isEmpty }
}

final class FeverCityMap {
    static let layers: [FeverLayerSpec] = [
        FeverLayerSpec(depth: 0.2, slot: 0.09, baseY: 0.74, minH: 0.14, maxH: 0.42, pitch: 0.014, empty: 0, fade: 0.5),
        FeverLayerSpec(depth: 0.45, slot: 0.15, baseY: 0.84, minH: 0.16, maxH: 0.46, pitch: 0.022, empty: 0.05, fade: 0.22),
        FeverLayerSpec(depth: 1.0, slot: 0.25, baseY: 0.905, minH: 0.12, maxH: 0.3, pitch: 0.034, empty: 0.12, fade: 0),
    ]

    private var cache: [Int: FeverBuilding] = [:]

    func building(_ layer: Int, _ i: Int) -> FeverBuilding {
        let key = i &* 4 &+ layer
        if let b = cache[key] { return b }
        if cache.count > 600 { cache.removeAll(keepingCapacity: true) }
        let b = Self.make(layer, i)
        cache[key] = b
        return b
    }

    static func make(_ layer: Int, _ i: Int) -> FeverBuilding {
        let spec = layers[layer]
        var r = Seeded(UInt64(bitPattern: Int64(i)) &* 0x9E37_79B9_7F4A_7C15 ^ (UInt64(layer + 7) &* 0xD1B5_4A32_D192_ED03))
        var b = FeverBuilding()
        if r.next() < spec.empty { return b }
        let w = spec.slot * (0.5 + 0.45 * r.next())
        let x0 = (spec.slot - w) / 2 + (r.next() - 0.5) * spec.slot * 0.2
        let h = spec.minH + (spec.maxH - spec.minH) * pow(r.next(), 1.3)
        let base = spec.baseY + 0.12
        let top = spec.baseY - h
        b.color = Int(r.next() * 5) % 5
        b.top = top
        b.phase = r.next() * 6.28
        var tiers: [CGRect] = []

        let style = Int(r.next() * (layer == 2 ? 5 : 6))
        switch style {
        case 0:     // capsule top
            let rc = CGRect(x: x0, y: top + w / 2, width: w, height: base - top - w / 2)
            b.body.addRect(rc)
            b.body.addEllipse(in: CGRect(x: x0, y: top, width: w, height: w))
            tiers = [rc.insetBy(dx: 0, dy: w * 0.15)]
        case 1:     // wedding-cake steps
            let t1 = top + h * 0.35, t2 = top + h * 0.15
            tiers = [CGRect(x: x0, y: t1, width: w, height: base - t1),
                     CGRect(x: x0 + w * 0.15, y: t2, width: w * 0.7, height: t1 - t2),
                     CGRect(x: x0 + w * 0.3, y: top, width: w * 0.4, height: t2 - top)]
            tiers.forEach { b.body.addRect($0) }
            for tr in tiers { b.trim.addRect(CGRect(x: tr.minX - 0.003, y: tr.minY, width: tr.width + 0.006, height: 0.008)) }
        case 2:     // witch-hat cone roof
            let roofH = w * (0.6 + 0.6 * r.next())
            let wall = top + roofH
            tiers = [CGRect(x: x0, y: wall, width: w, height: base - wall)]
            b.body.addRect(tiers[0])
            b.trim.addLines([CGPoint(x: x0 - w * 0.08, y: wall), CGPoint(x: x0 + w / 2, y: top), CGPoint(x: x0 + w * 1.08, y: wall)])
            b.trim.closeSubpath()
        case 3:     // onion dome with a spike
            let domeH = w * 0.7
            let wall = top + domeH
            tiers = [CGRect(x: x0, y: wall, width: w, height: base - wall)]
            b.body.addRect(tiers[0])
            b.trim.move(to: CGPoint(x: x0 + w * 0.05, y: wall))
            b.trim.addCurve(to: CGPoint(x: x0 + w / 2, y: top + domeH * 0.1),
                            control1: CGPoint(x: x0 - w * 0.15, y: wall - domeH * 0.7),
                            control2: CGPoint(x: x0 + w * 0.4, y: wall - domeH * 0.8))
            b.trim.addCurve(to: CGPoint(x: x0 + w * 0.95, y: wall),
                            control1: CGPoint(x: x0 + w * 0.6, y: wall - domeH * 0.8),
                            control2: CGPoint(x: x0 + w * 1.15, y: wall - domeH * 0.7))
            b.trim.closeSubpath()
            b.trim.addRect(CGRect(x: x0 + w / 2 - 0.0015, y: top - h * 0.08, width: 0.003, height: h * 0.1))
        case 4:     // arched roof with a sign band
            let wall = top + w * 0.25
            tiers = [CGRect(x: x0, y: wall, width: w, height: base - wall)]
            b.body.addRect(tiers[0])
            b.body.move(to: CGPoint(x: x0, y: wall))
            b.body.addQuadCurve(to: CGPoint(x: x0 + w, y: wall), control: CGPoint(x: x0 + w / 2, y: top - w * 0.25))
            b.body.closeSubpath()
            b.trim.addRect(CGRect(x: x0, y: wall + h * 0.08, width: w, height: 0.012))
        default:    // needle tower with a saucer and a ball on top
            let stemW = w * 0.22
            b.body.addRect(CGRect(x: x0 + (w - stemW) / 2, y: top + h * 0.25, width: stemW, height: base - top - h * 0.25))
            b.trim.addEllipse(in: CGRect(x: x0 - w * 0.1, y: top + h * 0.18, width: w * 1.2, height: h * 0.09))
            b.trim.addEllipse(in: CGRect(x: x0 + w * 0.32, y: top, width: w * 0.36, height: w * 0.36))
            b.trim.addRect(CGRect(x: x0 + w / 2 - 0.0015, y: top - h * 0.1, width: 0.003, height: h * 0.12))
            b.body.addRect(CGRect(x: x0 + w * 0.15, y: top + h * 0.12, width: w * 0.7, height: h * 0.08))
        }
        if layer == 2 {     // shopfront awning on the street
            let ay = spec.baseY - 0.05
            b.trim.addRect(CGRect(x: x0 - 0.006, y: ay, width: w + 0.012, height: 0.018))
        }

        let light = 0.5 + 0.7 * r.next()
        let floor = spec.baseY - (layer == 2 ? 0.055 : 0.01)
        for tier in tiers { addWindows(tier, pitch: spec.pitch, light: light, floor: floor, r: &r, into: &b) }
        return b
    }

    private static func addWindows(_ rc: CGRect, pitch: Double, light: Double, floor: Double,
                                   r: inout Seeded, into b: inout FeverBuilding) {
        let ww = pitch * 0.5, wh = pitch * 0.62, py = pitch * 1.25
        let cols = Int((rc.width - pitch * 0.4) / pitch)
        guard cols >= 1 else { return }
        let mx = rc.minX + (rc.width - Double(cols) * pitch) / 2 + (pitch - ww) / 2
        var y = rc.minY + pitch * 0.55
        var rows = 0
        let round = ww * 0.3
        while y + wh < min(rc.maxY, floor), rows < 60 {
            let storey = r.next()
            for c in 0..<cols {
                let v = (r.next() * 0.6 + storey * 0.4) / light
                let cell = CGRect(x: mx + Double(c) * pitch, y: y, width: ww, height: wh)
                if v < 0.3 { b.lit.addRoundedRect(in: cell, cornerSize: CGSize(width: round, height: round)) }
                else if v < 0.4 { b.alt.addRoundedRect(in: cell, cornerSize: CGSize(width: round, height: round)) }
                else { b.dark.addRect(cell) }
            }
            y += py
            rows += 1
        }
    }
}

// MARK: - Dashboard preview

struct FeverPreview: View {
    @State private var tex: GothamTextures?
    private static let city = FeverCityMap()
    private static let script = GothamScript.make(lines: [
        LyricLine(id: 0, time: 0.3, text: "turn the city up"),
        LyricLine(id: 1, time: 3.5, text: "all night long"),
        LyricLine(id: 2, time: 6.8, text: "lose your mind"),
        LyricLine(id: 3, time: 10.0, text: ""),
    ], title: "")

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let pos = t.truncatingRemainder(dividingBy: 12)
            Canvas { g, size in
                var s = FeverSettings()
                s[.camera] = 0
                s[.chaos] = 1
                s[.flip] = 0
                var f = FeverFrame.still(script: Self.script, pos: pos, t: t, size: size, s: s, tex: tex, city: Self.city)
                // The card always has something silly going on.
                let loop = t.truncatingRemainder(dividingBy: 24)
                if loop < 12 { f.force[.whale] = loop / 12 } else { f.force[.ufo] = (loop - 12) / 12 }
                FeverRenderer.draw(&g, f)
            }
        }
        .drawingGroup()
        .task { tex = await GothamTextures.shared.value }
    }
}
