import SwiftUI

// MARK: - Style: Night Sky
//
// A deep night sky. Each part of the song is a constellation: its words are spelled in stars
// joined by faint lines, and each star blooms on as its word is sung. The constellations hang
// one behind another along an endless forward flight: the camera never stops, each constellation
// is hung where the camera will be when it's sung, and the speed swells into warp over the
// seconds before a part that repeats an earlier one (the chorus).
//
// Everything is drawn in one Canvas: sky gradient, Milky Way texture (built once, off the main
// thread), a 3D field of stars that streak with the camera's speed, then the constellations.
// Glow comes from radial gradients and wide faint strokes, never blur filters.

struct NightSkyView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(SkySettings.storageKey) private var settings = SkySettings()
    @State private var textures: SkyTextures?
    @State private var programs: SkyProgramCache
    @State private var hovering = false
    @State private var showControls = false

    /// The demo reel passes a cache it has already filled, so switching to this style is instant.
    init(model: PlayerModel, programs: SkyProgramCache? = nil) {
        self.model = model
        _programs = State(initialValue: programs ?? SkyProgramCache())
    }

    var body: some View {
        // Every display frame (no minimum interval): a 60 fps cap stutters on 120 Hz screens.
        TimelineView(.animation) { ctx in
            let s = settings
            let pos = model.position(at: ctx.date) + leadTime
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let audio = model.audio.sample(at: ctx.date)
            let flight = currentFlight(s)

            GeometryReader { geo in
                SkyCanvas(frame: SkyStage.frame(flight: flight, pos: pos, t: t, beat: audio.beat * s[.pulse], level: audio.level,
                                                size: geo.size, s: s, art: model.artPalette, tex: textures))
            }
        }
        .overlay(alignment: .bottom) { caption }
        .overlay(alignment: .topTrailing) { controlsButton }
        .background(Color.black)
        .ignoresSafeArea()
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hovering = h } }
        .task { textures = await SkyTextures.shared.value }
    }

    private func currentFlight(_ s: SkySettings) -> SkyFlight {
        switch model.status {
        case .notRunning: return programs.message("Open Spotify")
        case .stopped: return programs.message("press play")
        case .error: return programs.message("no signal")
        case .active(let snap):
            if model.loadingLyrics { return programs.message("…") }
            switch model.lyrics {
            case .synced(let lines): return programs.flight(lines: lines, title: snap.title, s: s)
            case .instrumental: return programs.message("no words, just stars")
            case .plainOnly: return programs.message("no timed lyrics")
            case .notFound, .none: return programs.message("no lyrics found")
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
        .popover(isPresented: $showControls, arrowEdge: .bottom) { SkyControls() }
        .help("Night Sky controls")
        .padding(.top, 10)
        .padding(.trailing, 12)
        .opacity(hovering || showControls ? 1 : 0)
    }
}

/// The whole scene in one GPU-backed canvas.
struct SkyCanvas: View {
    let frame: SkyFrame

    var body: some View {
        Canvas { ctx, _ in SkyRenderer.draw(&ctx, frame) }
            .drawingGroup()
    }
}

// MARK: - Program: where each constellation hangs

/// One constellation: a page of the song, placed in the sky.
struct SkyPage {
    let plan: NeonSignPlan
    var x = 0.0, y = 0.0, z = 0.0   // world position of its centre (placed by SkyFlight)
    let tilt: Double                // degrees
    let chorus: Bool                // repeats an earlier part: the flight warps into it
}

enum SkyProgram {
    static func make(lines: [LyricLine], title: String, maxRows: Int) -> [SkyPage] {
        let plans = NeonProgram.make(lines: lines, title: title, maxRows: maxRows)
        var seen = Set<String>()
        var out: [SkyPage] = []
        for (i, p) in plans.enumerated() {
            let keys = p.texts.map(normalized).filter { !$0.isEmpty }
            let repeats = keys.filter { seen.contains($0) }.count
            let chorus = i > 0 && !keys.isEmpty && Double(repeats) >= Double(keys.count) * 0.5
            seen.formUnion(keys)
            var r = Seeded(p.seed)
            out.append(SkyPage(plan: p, tilt: (r.next() - 0.5) * 10, chorus: chorus))
        }
        return out
    }

    static func normalized(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " })
            .trimmingCharacters(in: .whitespaces)
    }

    /// A status constellation, fully lit, that hangs ahead while the sky drifts past.
    static func message(_ text: String) -> SkyFlight {
        SkyFlight(pages: [SkyPage(plan: NeonProgram.message(text)[0], tilt: 0, chorus: false)], speed: 0, warp: 0, curve: 0.5)
    }
}

/// Keeps the song's flight between frames (rebuilt only when the lyrics, layout or flight settings change).
final class SkyProgramCache {
    private var key = ""
    private var cached: SkyFlight?

    func flight(lines: [LyricLine], title: String, s: SkySettings) -> SkyFlight {
        let k = "\(title)|\(s.rows)|\(s[.speed])|\(s[.warp])|\(s[.curve])|\(lines.count)|\(lines.first?.id ?? 0)|\(lines.last?.time ?? 0)|\(lines.map(\.singer).reduce(0, &+))"
        return cachedFlight(k) { SkyFlight(pages: SkyProgram.make(lines: lines, title: title, maxRows: s.rows),
                                           speed: s[.speed], warp: s[.warp], curve: s[.curve]) }
    }

    func message(_ text: String) -> SkyFlight { cachedFlight("msg|\(text)") { SkyProgram.message(text) } }

    private func cachedFlight(_ k: String, _ make: () -> SkyFlight) -> SkyFlight {
        if k != key || cached == nil { key = k; cached = make() }
        return cached!
    }
}

// MARK: - Camera: an endless forward cruise
//
// The camera never stops or lunges. Its forward speed is a smooth curve over the whole song: each
// part sets a cruising speed (fast enough to carry the camera from deep in the sky up to its
// constellation while it's sung), blended into the next with smootherstep, and a warp bell swells
// over the seconds before a repeated part (the chorus) and eases off as it begins. The speed is
// integrated once into a table, and each constellation is then hung at the depth the camera will
// be at when it's sung, so the words always come to the camera, never the other way round.
// Sideways, the camera follows a slow wandering path through the sky.

struct SkyCamState {
    var x = 0.0, y = 0.0, z = 0.0
    var vz = 0.0          // forward speed, world units per second
    var warp = 0.0        // 0…1 warp swell into a chorus
}

final class SkyFlight {
    /// How far ahead of the camera a constellation is when its last word has been sung.
    static let endDepth = 520.0
    /// Depth a message constellation hangs at.
    static let messageDepth = 1150.0

    let pages: [SkyPage]
    let pinned: Bool        // a single status message that stays ahead while the camera drifts
    private let curve: Double
    private let t0: Double
    private let dt = 1.0 / 60
    private let zs: [Double], vs: [Double], ws: [Double]

    init(pages raw: [SkyPage], speed: Double, warp: Double, curve: Double) {
        self.curve = curve
        pinned = raw.count == 1 && raw[0].plan.start < -500
        let cruise = 120 + 260 * speed          // calm speed between parts
        let pass = 700 + 500 * speed            // distance flown while a part is sung

        // When each part is sung.
        var wins: [(s: Double, e: Double)] = []
        for (i, p) in raw.enumerated() where !pinned {
            let sung = p.plan.lines.map { $0.start + $0.duration }.max() ?? p.plan.start
            var e = min(p.plan.offStart, sung + 1.2)
            if i + 1 < raw.count { e = min(e, raw[i + 1].plan.start) }
            wins.append((p.plan.start, max(p.plan.start + 0.8, e)))
        }

        // Speed keys: one per part, plus a calm cruise in the middle of long gaps.
        var keys: [(t: Double, v: Double)] = []
        func key(_ t: Double, _ v: Double) { if t > (keys.last?.t ?? -.infinity) + 0.05 { keys.append((t, v)) } }
        for (i, w) in wins.enumerated() {
            key((w.s + w.e) / 2, max(0.5 * cruise, min(2.2 * cruise, pass / (w.e - w.s))))
            if i + 1 < wins.count, wins[i + 1].s - w.e > 5 { key((w.e + wins[i + 1].s) / 2, cruise) }
        }
        if keys.isEmpty { keys = [(0, pinned ? 90 : cruise)] }

        // Warp bells: rise over the seconds before a chorus, peak just before it, ease off as it starts.
        var bells: [(a: Double, p: Double, e: Double)] = []
        if warp > 0 {
            for i in raw.indices.dropFirst() where raw[i].chorus && i < wins.count {
                let s = wins[i].s
                let a = min(s - 2.0, max(wins[i - 1].e - 0.8, s - 4.0))
                bells.append((a, s - 0.4, s + 1.8))
            }
        }
        let amp = 6.0 * warp

        let start = min(-5, (wins.first?.s ?? 0) - 15)
        let end = max(start + 1, (wins.last?.e ?? 0) + 20)
        t0 = start
        let n = Int((end - start) / dt) + 2
        var zs = [Double](repeating: 0, count: n), vs = zs, ws = zs
        var ki = 0
        for k in 0..<n {
            let t = start + Double(k) * dt
            while ki + 1 < keys.count && keys[ki + 1].t <= t { ki += 1 }
            var v: Double
            if t <= keys[0].t { v = keys[0].v }
            else if ki + 1 >= keys.count { v = keys[ki].v }
            else {
                let a = keys[ki], b = keys[ki + 1]
                v = a.v + (b.v - a.v) * SkyFlight.smoother((t - a.t) / (b.t - a.t))
            }
            var w = 0.0
            for b in bells where t > b.a && t < b.e {
                w = max(w, t < b.p ? SkyFlight.smoother((t - b.a) / (b.p - b.a)) : 1 - SkyFlight.smoother((t - b.p) / (b.e - b.p)))
            }
            v *= 1 + amp * w
            vs[k] = v; ws[k] = w
            if k > 0 { zs[k] = zs[k - 1] + (vs[k - 1] + v) / 2 * dt }
        }
        self.zs = zs; self.vs = vs; self.ws = ws

        // Hang each constellation where the camera will be when it's sung, near the wandering path.
        var placed = raw
        if pinned {
            placed[0].z = Self.messageDepth
        } else {
            for i in placed.indices {
                var r = Seeded(placed[i].plan.seed &+ 0x51F7)
                let z = Self.sample(zs, vs, ws, t0: start, dt: dt, at: wins[i].e).z + Self.endDepth
                placed[i].z = z
                placed[i].x = Self.pathX(z, curve) + (r.next() - 0.5) * 360
                placed[i].y = Self.pathY(z, curve) + (r.next() - 0.5) * 200
            }
        }
        pages = placed
    }

    /// The camera at a song position.
    func at(_ pos: Double) -> SkyCamState {
        let s = Self.sample(zs, vs, ws, t0: t0, dt: dt, at: pos)
        return SkyCamState(x: Self.pathX(s.z, curve), y: Self.pathY(s.z, curve), z: s.z, vz: s.v, warp: s.w)
    }

    /// Depth of a page in front of the camera.
    func depth(_ p: SkyPage, cam: SkyCamState) -> Double { pinned ? Self.messageDepth : p.z - cam.z }

    /// 0 → 1 with zero speed and acceleration at both ends.
    static func smoother(_ u: Double) -> Double {
        let u = max(0, min(1, u))
        return u * u * u * (u * (u * 6 - 15) + 10)
    }

    static func pathX(_ z: Double, _ curve: Double) -> Double {
        curve * (620 * sin(z * 0.00029 + 0.7) + 260 * sin(z * 0.00083 + 2.1))
    }

    static func pathY(_ z: Double, _ curve: Double) -> Double {
        curve * (240 * sin(z * 0.00023 + 1.3) + 120 * sin(z * 0.00061))
    }

    /// Cubic Hermite through the integrated table, so speed is continuous between samples too.
    private static func sample(_ zs: [Double], _ vs: [Double], _ ws: [Double], t0: Double, dt: Double,
                               at t: Double) -> (z: Double, v: Double, w: Double) {
        let u = (t - t0) / dt
        let last = zs.count - 1
        if u <= 0 { return (zs[0] + vs[0] * (t - t0), vs[0], 0) }
        if u >= Double(last) { return (zs[last] + vs[last] * (u - Double(last)) * dt, vs[last], 0) }
        let k = Int(u), f = u - Double(k)
        let f2 = f * f, f3 = f2 * f
        let z = (2 * f3 - 3 * f2 + 1) * zs[k] + (f3 - 2 * f2 + f) * dt * vs[k]
              + (-2 * f3 + 3 * f2) * zs[k + 1] + (f3 - f2) * dt * vs[k + 1]
        return (z, vs[k] + (vs[k + 1] - vs[k]) * f, ws[k] + (ws[k + 1] - ws[k]) * f)
    }
}

// MARK: - Constellations: letters walked into stars

struct SkyStar {
    var p: CGPoint
    var letter: Int        // index into geo.letters
    var order: Double      // 0…1 along the letter, for lighting order
    var mag: Double        // 0.5…1 brightness and size
    var hash: Double       // 0…1, for twinkle phase
}

final class SkyConstellation {
    let geo: NeonSignGeometry
    let stars: [SkyStar]
    let links: [(a: Int, b: Int)]

    init(geo: NeonSignGeometry, stars: [SkyStar], links: [(a: Int, b: Int)]) {
        self.geo = geo; self.stars = stars; self.links = links
    }

    var unit: CGFloat { geo.fontSize }
}

enum SkyStars {
    private static var cache: [String: SkyConstellation] = [:]
    private static let lock = NSLock()

    /// The constellation for these lines, fitted inside `box` (world units). Cached.
    static func constellation(_ texts: [String], font: SkyFont, box: CGSize, density: Double) -> SkyConstellation {
        let key = "\(font.rawValue)|\(Int(density * 20))|\(Int(box.width))x\(Int(box.height))|" + texts.joined(separator: "\n")
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        let geo = NeonGlyphs.sign(texts, face: font.face, fontSize: 150, box: box)
        let con = build(geo, font: font, density: density)

        lock.lock()
        if cache.count > 60 { cache = [:] }
        cache[key] = con
        lock.unlock()
        return con
    }

    static func build(_ geo: NeonSignGeometry, font: SkyFont, density: Double) -> SkyConstellation {
        let fs = geo.fontSize
        let spacing = fs * CGFloat(0.2 - 0.1 * density)
        // Points closer than this (the two sides of a thin stroke) become one star on the centre line.
        let merge = fs * (font == .hand ? 0.09 : 0.085)
        var stars: [SkyStar] = []
        var links: [(a: Int, b: Int)] = []

        for (li, letter) in geo.letters.enumerated() {
            var samples: [[CGPoint]] = []
            for poly in polylines(letter.path.cgPath) {
                let pts = resample(poly.pts, closed: poly.closed, spacing: spacing)
                if !pts.isEmpty { samples.append(pts) }
            }
            let total = max(1, samples.reduce(0) { $0 + $1.count })

            // Greedy clustering on a grid, in walking order.
            var sums: [CGPoint] = [], counts: [Int] = [], firsts: [Int] = []
            var grid: [Int64: [Int]] = [:]
            func cell(_ p: CGPoint) -> (Int, Int) { (Int((p.x / merge).rounded(.down)), Int((p.y / merge).rounded(.down))) }
            func gkey(_ x: Int, _ y: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(y))) }
            var seq = 0
            var edgeSet = Set<Int64>()
            var localLinks: [(Int, Int)] = []
            for chain in samples {
                var prev: Int?
                var firstC: Int?
                for p in chain {
                    let (cx, cy) = cell(p)
                    var best: Int?
                    var bestD = merge * merge
                    for dx in -1...1 {
                        for dy in -1...1 {
                            for c in grid[gkey(cx + dx, cy + dy)] ?? [] {
                                let m = CGPoint(x: sums[c].x / CGFloat(counts[c]), y: sums[c].y / CGFloat(counts[c]))
                                let d = (m.x - p.x) * (m.x - p.x) + (m.y - p.y) * (m.y - p.y)
                                if d < bestD { bestD = d; best = c }
                            }
                        }
                    }
                    let c: Int
                    if let best {
                        c = best
                        sums[c].x += p.x; sums[c].y += p.y; counts[c] += 1
                    } else {
                        c = sums.count
                        sums.append(p); counts.append(1); firsts.append(seq)
                        grid[gkey(cx, cy), default: []].append(c)
                    }
                    if let pr = prev, pr != c {
                        let k = Int64(min(pr, c)) << 32 | Int64(max(pr, c))
                        if edgeSet.insert(k).inserted { localLinks.append((pr, c)) }
                    }
                    if firstC == nil { firstC = c }
                    prev = c
                    seq += 1
                }
                if let pr = prev, let f = firstC, pr != f, chain.count > 2 {
                    let k = Int64(min(pr, f)) << 32 | Int64(max(pr, f))
                    if edgeSet.insert(k).inserted { localLinks.append((pr, f)) }
                }
            }

            var degree = Array(repeating: 0, count: sums.count)
            for (a, b) in localLinks { degree[a] += 1; degree[b] += 1 }
            let base = stars.count
            var r = Seeded(UInt64(li &* 7919 &+ 17) &+ UInt64(geo.letters.count))
            for c in sums.indices {
                let p = CGPoint(x: sums[c].x / CGFloat(counts[c]), y: sums[c].y / CGFloat(counts[c]))
                // Ends, corners and junctions are the bright stars of the figure.
                let mag = degree[c] == 2 ? 0.5 + 0.35 * r.next() : 0.85 + 0.15 * r.next()
                stars.append(SkyStar(p: p, letter: li, order: Double(firsts[c]) / Double(total), mag: mag, hash: r.next()))
            }
            for (a, b) in localLinks { links.append((base + a, base + b)) }
        }
        return SkyConstellation(geo: geo, stars: stars, links: links)
    }

    /// The path as polylines (curves flattened).
    static func polylines(_ path: CGPath) -> [(pts: [CGPoint], closed: Bool)] {
        var out: [(pts: [CGPoint], closed: Bool)] = []
        var cur: [CGPoint] = []
        var last = CGPoint.zero
        path.applyWithBlock { el in
            let e = el.pointee
            let p = e.points
            switch e.type {
            case .moveToPoint:
                if cur.count > 1 { out.append((cur, false)) }
                cur = [p[0]]; last = p[0]
            case .addLineToPoint:
                cur.append(p[0]); last = p[0]
            case .addQuadCurveToPoint:
                let a = last, c = p[0], b = p[1]
                for k in 1...6 {
                    let t = CGFloat(k) / 6, m = 1 - t
                    cur.append(CGPoint(x: m * m * a.x + 2 * m * t * c.x + t * t * b.x,
                                       y: m * m * a.y + 2 * m * t * c.y + t * t * b.y))
                }
                last = b
            case .addCurveToPoint:
                let a = last, c1 = p[0], c2 = p[1], b = p[2]
                for k in 1...8 {
                    let t = CGFloat(k) / 8, m = 1 - t
                    let w0 = m * m * m, w1 = 3 * m * m * t, w2 = 3 * m * t * t, w3 = t * t * t
                    cur.append(CGPoint(x: w0 * a.x + w1 * c1.x + w2 * c2.x + w3 * b.x,
                                       y: w0 * a.y + w1 * c1.y + w2 * c2.y + w3 * b.y))
                }
                last = b
            case .closeSubpath:
                if cur.count > 1 { out.append((cur, true)) }
                if let f = cur.first { last = f }
                cur = []
            @unknown default:
                break
            }
        }
        if cur.count > 1 { out.append((cur, false)) }
        return out
    }

    /// Evenly spaced points along a polyline.
    static func resample(_ pts: [CGPoint], closed: Bool, spacing: CGFloat) -> [CGPoint] {
        var seg = pts
        if closed, let f = pts.first { seg.append(f) }
        var length: CGFloat = 0
        for i in 1..<seg.count { length += hypot(seg[i].x - seg[i - 1].x, seg[i].y - seg[i - 1].y) }
        guard length > 0.5 else { return [] }
        let n = max(closed ? 3 : 2, Int((length / spacing).rounded()))
        let step = length / CGFloat(closed ? n : n - 1)
        var out: [CGPoint] = []
        var target: CGFloat = 0
        var acc: CGFloat = 0
        for i in 1..<seg.count {
            let a = seg[i - 1], b = seg[i]
            let l = hypot(b.x - a.x, b.y - a.y)
            while target <= acc + l + 0.001, out.count < (closed ? n : n) {
                let k = l > 0 ? (target - acc) / l : 0
                out.append(CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k))
                target += step
            }
            acc += l
        }
        return out
    }
}

// MARK: - Background star field

struct FieldStar {
    let x, y, z: Double
    let mag: Double
    let hash: Double
}

enum SkyField {
    static let depth = 7000.0
    static let stars: [FieldStar] = {
        var r = Seeded(0x5EED_57A2)
        return (0..<2200).map { _ in
            let mag = pow(r.next(), 2.2) * 0.85 + 0.15
            return FieldStar(x: (r.next() - 0.5) * 5200, y: (r.next() - 0.5) * 3400, z: r.next() * depth,
                             mag: mag, hash: r.next())
        }
    }()

    /// Draws the field into a context whose origin is the screen centre.
    static func draw(_ g: inout GraphicsContext, size: CGSize, camX: Double, camY: Double, camZ: Double,
                     vz: Double, focal: Double, count: Int, shutter: Double, twinkle: Double, boost: Double, t: Double) {
        var dots = [Path(), Path(), Path()]
        var streaks = [Path(), Path(), Path()]
        let reach = max(size.width, size.height) * 0.62
        for i in 0..<min(count, stars.count) {
            let st = stars[i]
            var zr = (st.z - camZ).truncatingRemainder(dividingBy: depth)
            if zr < 0 { zr += depth }
            zr += 25
            let k = focal / zr
            let sx = (st.x - camX) * k, sy = (st.y - camY) * k
            guard abs(sx) < reach, abs(sy) < reach else { continue }
            let tw = 1 + twinkle * 0.5 * sin(t * (1.3 + 3 * st.hash) + st.hash * 40)
            let b = st.mag * tw * boost * (1 - smoothstep((zr - depth * 0.6) / (depth * 0.4))) * smoothstep(zr / 140)
            guard b > 0.05 else { continue }
            let bi = min(2, Int(b * 3))
            let tz = zr + vz * shutter
            if tz > 25 {
                let k2 = focal / tz
                let tx = (st.x - camX) * k2, ty = (st.y - camY) * k2
                if (sx - tx) * (sx - tx) + (sy - ty) * (sy - ty) > 2.5 {
                    streaks[bi].move(to: CGPoint(x: sx, y: sy))
                    streaks[bi].addLine(to: CGPoint(x: tx, y: ty))
                    continue
                }
            }
            let r = min(2.4, max(0.45, st.mag * 1500 / zr))
            dots[bi].addEllipse(in: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2))
        }
        let alphas = [0.3, 0.6, 1.0]
        for b in 0..<3 {
            let c = Color(red: 0.86, green: 0.9, blue: 1, opacity: alphas[b])
            g.fill(dots[b], with: .color(c))
            g.stroke(streaks[b], with: .color(c), style: StrokeStyle(lineWidth: 0.6 + 0.5 * CGFloat(b), lineCap: .round))
        }
    }
}

// MARK: - Stage: everything for one frame

struct SkyPageState {
    let con: SkyConstellation
    let transform: CGAffineTransform   // page (world units) → screen, origin at screen centre
    let alpha: Double
    let lights: [Double]               // per star: 0 unlit … 1 lit (twinkle and beat applied)
    let blooms: [Double]               // per star: size multiplier for the bloom as it lights
    let colors: [NeonRGB]
    let grow: [Double]                 // per link: 0…1 how far it has been drawn
    var pts: [CGPoint] = []            // per star: where it is now (scattered or gathering)
    var chart = 0.07                   // brightness of the unlit stars
    var linkFade = 1.0                 // lines fade as the constellation breaks apart
}

struct SkyFrame {
    var size: CGSize
    var t: Double
    var roll: Double                   // degrees
    var cam: SkyCamState
    var vz: Double
    var focal: Double
    var warp: Double
    var pages: [SkyPageState]
    var s: SkySettings
    var beat: Double
    var level = 0.0
    var tex: SkyTextures?
    var props: [(depth: Double, prop: SkyProp)] = []
    var pal: [NeonRGB] = []
}

enum SkyStage {
    static let singerPalette = [NeonRGB(0.93, 0.96, 1), NeonRGB(1, 0.82, 0.45), NeonRGB(0.5, 0.78, 1),
                                NeonRGB(1, 0.56, 0.72), NeonRGB(0.55, 1, 0.82)]

    static func palette(_ s: SkySettings, art: [Color]) -> [NeonRGB] {
        switch s.colorMode {
        case .white: [singerPalette[0]]
        case .singer: singerPalette
        case .album: art.isEmpty ? singerPalette : art.map { NeonRGB($0).mixed(.white, 0.35) }
        }
    }

    /// World box a constellation is fitted into, from the window's shape.
    static func box(_ size: CGSize) -> CGSize {
        let h = 1000 * size.height / max(1, size.width) * 0.62
        return CGSize(width: 1000, height: max(250, min(900, (h / 25).rounded() * 25)))
    }

    static func frame(flight: SkyFlight, pos: Double, t: Double, beat: Double, level: Double = 0, size: CGSize,
                      s: SkySettings, art: [Color], tex: SkyTextures?) -> SkyFrame {
        let pages = flight.pages
        var cam = flight.at(pos)
        let ahead = flight.at(pos + 0.02)
        let vz = cam.vz
        let lateral = (ahead.x - cam.x) / 0.02
        let sway = s[.sway]
        let swayX = sin(t * 0.21) * 40 * sway, swayY = cos(t * 0.17) * 26 * sway
        cam.x += swayX
        cam.y += swayY
        let roll = sin(t * 0.09) * 2.4 * sway - max(-10, min(10, lateral * 0.0045))
        let warp = cam.warp * s[.warp]
        let focal = Double(size.width) * (1 - 0.25 * warp)
        let pal = palette(s, art: art)
        let box = box(size)

        var states: [(Double, SkyPageState)] = []
        for p in pages {
            let depth = flight.depth(p, cam: cam)
            guard depth > 40, depth < 5600 else { continue }
            let alpha = smoothstep((depth - 40) / 460) * (1 - smoothstep((depth - 1400) / 2800))
            guard alpha > 0.01 else { continue }
            let con = SkyStars.constellation(p.plan.texts, font: s.font, box: box, density: s[.density])
            let k = focal / depth
            let tr = CGAffineTransform(scaleX: k, y: k)
                .translatedBy(x: flight.pinned ? -swayX : p.x - cam.x, y: flight.pinned ? -swayY : p.y - cam.y)
                .rotated(by: p.tilt * .pi / 180)
            states.append((depth, pageState(p.plan, con, transform: tr, alpha: alpha, pos: pos, t: t, beat: beat, s: s, pal: pal)))
        }
        states.sort { $0.0 > $1.0 }
        var props: [(depth: Double, prop: SkyProp)] = []
        if s.layer(.nebula) > 0 || s.layer(.landmarks) > 0 {
            for p in SkyScenery.props(for: pages) {
                let depth = p.z - cam.z
                guard depth > 30, depth < SkyScenery.farthest else { continue }
                if case .nebula = p.kind { if s.layer(.nebula) == 0 { continue } } else if s.layer(.landmarks) == 0 { continue }
                props.append((depth, p))
            }
            props.sort { $0.depth > $1.depth }
        }
        return SkyFrame(size: size, t: t, roll: roll, cam: cam, vz: vz, focal: focal, warp: warp,
                        pages: states.map(\.1), s: s, beat: beat, level: level, tex: tex, props: props, pal: pal)
    }

    static func pageState(_ plan: NeonSignPlan, _ con: SkyConstellation, transform: CGAffineTransform, alpha: Double,
                          pos: Double, t: Double, beat: Double, s: SkySettings, pal: [NeonRGB]) -> SkyPageState {
        let geo = con.geo
        let times = NeonLight.wordTimes(plan, geo)
        let n = con.stars.count
        var starT = [Double](repeating: 0, count: n)
        var lights = [Double](repeating: 0, count: n)
        var blooms = [Double](repeating: 1, count: n)
        var colors = [NeonRGB](repeating: pal[0], count: n)
        let dim = 1 - 0.35 * smoothstep((pos - plan.offStart) / 0.8)
        let tw = s[.twinkle]
        for (i, st) in con.stars.enumerated() {
            let letter = geo.letters[st.letter]
            let word = geo.words[letter.word]
            let wt = times[letter.word]
            let count = Double(max(1, word.letters.count))
            let start = wt.start + wt.dur * (Double(letter.indexInWord) + st.order) / count
            starT[i] = start
            let age = pos - start
            let on = smoothstep(age / 0.08)
            if on > 0 {
                blooms[i] = 1 + 1.4 * exp(-max(0, age) * 5)
                let twinkle = 1 + tw * 0.32 * sin(t * (2 + 2.5 * st.hash) + st.hash * 50)
                lights[i] = on * twinkle * (1 + 0.6 * beat) * dim
            }
            if pal.count > 1, word.line < plan.lines.count {
                let singer = plan.lines[word.line].singer
                colors[i] = singer >= 0 ? pal[singer % pal.count] : pal[st.letter % pal.count]
            }
        }
        let grow = con.links.map { l in smoothstep((pos - max(starT[l.a], starT[l.b])) / 0.18) }

        // Before it's sung the constellation gathers out of loose stars; once it's done it breaks
        // apart and the stars drift outward as the camera flies through them.
        let gather = pow(1 - smoothstep((pos - (plan.start - 2.6)) / 2.4), 1.6)
        let scatter = pow(smoothstep((pos - plan.offStart + 0.15) / 2.0), 1.3)
        var pts = con.stars.map(\.p)
        if gather > 0.001 || scatter > 0.001 {
            let mid = CGPoint(x: geo.bounds.midX, y: geo.bounds.midY)
            for (i, st) in con.stars.enumerated() {
                let h1 = (st.hash * 53.17).truncatingRemainder(dividingBy: 1)
                let h2 = (st.hash * 17.31).truncatingRemainder(dividingBy: 1)
                var dx = st.p.x - mid.x, dy = st.p.y - mid.y
                let len = max(1, hypot(dx, dy))
                dx /= len; dy /= len
                if scatter > 0.001 {
                    let ang = h1 * 2 * .pi
                    let d = CGFloat(scatter * (260 + 760 * h2))
                    // Outward, with a little swirl.
                    let sw = CGFloat(scatter * (h1 - 0.5) * 0.9)
                    let rx = dx * cos(sw) - dy * sin(sw), ry = dx * sin(sw) + dy * cos(sw)
                    pts[i].x += (rx * 0.75 + CGFloat(cos(ang)) * 0.45) * d
                    pts[i].y += (ry * 0.75 + CGFloat(sin(ang)) * 0.45) * d
                }
                if gather > 0.001 {
                    let ang = h2 * 2 * .pi + 1.3
                    let d = CGFloat(gather * (420 + 900 * h1))
                    pts[i].x += (CGFloat(cos(ang)) * 0.8 + dx * 0.4) * d
                    pts[i].y += (CGFloat(sin(ang)) * 0.8 + dy * 0.4) * d
                }
                if scatter > 0 { lights[i] *= 1 - 0.45 * scatter }
            }
        }
        var out = SkyPageState(con: con, transform: transform, alpha: alpha, lights: lights, blooms: blooms,
                               colors: colors, grow: grow)
        out.pts = pts
        // Converging stars shine a little brighter while they travel.
        out.chart = 0.07 + 0.16 * sin(.pi * min(1, gather)) + 0.05 * scatter
        out.linkFade = (1 - scatter) * (1 - gather)
        return out
    }
}

// MARK: - Renderer

enum SkyRenderer {
    static func draw(_ ctx: inout GraphicsContext, _ f: SkyFrame) {
        let size = f.size
        let full = Path(CGRect(origin: .zero, size: size))
        ctx.fill(full, with: .linearGradient(
            Gradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.14), Color(red: 0.01, green: 0.015, blue: 0.05),
                              Color(red: 0.005, green: 0.005, blue: 0.02)]),
            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.3, y: size.height)))

        var g = ctx
        g.translateBy(x: size.width / 2, y: size.height / 2)
        g.rotate(by: .degrees(f.roll))

        // Milky Way, barely moving (it's very far away).
        if let tex = f.tex, f.s[.milkyWay] > 0 {
            var m = g
            m.opacity = f.s[.milkyWay] * 0.9
            m.translateBy(x: -f.cam.x * 0.04, y: -f.cam.y * 0.04)
            m.rotate(by: .degrees(-24 + f.t * 0.12))
            let w = hypot(size.width, size.height) * 1.35
            m.draw(Image(decorative: tex.milkyWay, scale: 1), in: CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2))
        }

        let s = f.s
        let shutter = (0.012 + 0.06 * s[.streaks]) * (1 + 3 * f.warp)

        SkyLayers.drawAurora(&g, f)
        SkyLayers.drawProps(&g, f, nebulae: true)

        var field = g
        field.blendMode = .plusLighter
        SkyField.draw(&field, size: size, camX: f.cam.x, camY: f.cam.y, camZ: f.cam.z, vz: f.vz, focal: f.focal,
                      count: Int(250 + 1950 * s[.field]), shutter: shutter, twinkle: s[.twinkle],
                      boost: 1 + 0.35 * f.beat, t: f.t)

        // Planets cover the far field stars; constellations always read on top.
        SkyLayers.drawProps(&g, f, nebulae: false)

        for page in f.pages {
            var pg = g
            pg.concatenate(page.transform)
            drawPage(&pg, page, s: s)
        }

        SkyLayers.drawDust(&g, f, shutter: shutter)

        // A soft glow that swells and fades with the warp (no flash, no cut).
        if f.warp > 0.01 {
            var fl = ctx
            fl.blendMode = .plusLighter
            fl.fill(full, with: .radialGradient(
                Gradient(colors: [Color(red: 0.7, green: 0.8, blue: 1, opacity: 0.22 * f.warp), .clear]),
                center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0, endRadius: max(size.width, size.height) * 0.7))
        }

        // Vignette.
        ctx.fill(full, with: .radialGradient(
            Gradient(colors: [.clear, .clear, .black.opacity(0.55)]),
            center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0,
            endRadius: hypot(size.width, size.height) * 0.6))
    }

    /// One constellation, in its own world units (the context already holds its transform).
    static func drawPage(_ g: inout GraphicsContext, _ p: SkyPageState, s: SkySettings) {
        let con = p.con
        let u = con.unit
        let a = p.alpha
        let size = s[.starSize]
        let core = u * CGFloat(0.02 + 0.022 * size)
        let haloK = CGFloat(3 + 5 * s[.glow])

        // Faint star chart: every star, unlit.
        let pts = p.pts.count == con.stars.count ? p.pts : con.stars.map(\.p)
        var chart = Path()
        for (i, st) in con.stars.enumerated() where p.lights[i] < 0.5 {
            let r = core * 0.55 * CGFloat(st.mag)
            chart.addEllipse(in: CGRect(x: pts[i].x - r, y: pts[i].y - r, width: r * 2, height: r * 2))
        }
        g.fill(chart, with: .color(.white.opacity(p.chart * a)))

        g.blendMode = .plusLighter

        // Lines, grouped by colour.
        if s[.links] > 0, p.linkFade > 0.01 {
            var byColor: [Int: (NeonRGB, Path)] = [:]
            for (i, l) in con.links.enumerated() where p.grow[i] > 0.001 {
                let c = p.colors[l.a]
                let key = Int(c.r * 255) << 16 | Int(c.g * 255) << 8 | Int(c.b * 255)
                let pa = pts[l.a], pb = pts[l.b]
                let k = CGFloat(p.grow[i])
                var path = byColor[key]?.1 ?? Path()
                path.move(to: pa)
                path.addLine(to: CGPoint(x: pa.x + (pb.x - pa.x) * k, y: pa.y + (pb.y - pa.y) * k))
                byColor[key] = (c, path)
            }
            let lw = u * CGFloat(0.004 + 0.008 * s[.links])
            for (_, (c, path)) in byColor {
                let la = a * p.linkFade
                g.stroke(path, with: .color(c.color(0.12 * s[.links] * la)), style: StrokeStyle(lineWidth: lw * 4, lineCap: .round))
                g.stroke(path, with: .color(c.mixed(.white, 0.4).color(0.5 * s[.links] * la)),
                         style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }
        }

        // Stars: halo, spikes on the bright ones, hot core.
        var spikes: [Int: (NeonRGB, Path)] = [:]
        for (i, st) in con.stars.enumerated() {
            let l = p.lights[i]
            guard l > 0.01 else { continue }
            let c = p.colors[i]
            let sp = pts[i]
            let r = core * CGFloat(st.mag) * CGFloat(p.blooms[i])
            let hr = r * haloK
            g.fill(Path(ellipseIn: CGRect(x: sp.x - hr, y: sp.y - hr, width: hr * 2, height: hr * 2)),
                   with: .radialGradient(Gradient(colors: [c.color(0.55 * l * a), c.color(0.12 * l * a), c.color(0)]),
                                         center: sp, startRadius: 0, endRadius: hr))
            g.fill(Path(ellipseIn: CGRect(x: sp.x - r, y: sp.y - r, width: r * 2, height: r * 2)),
                   with: .color(c.mixed(.white, 0.7).color(min(1, l) * a)))
            if st.mag > 0.92 {
                let key = Int(c.r * 255) << 16 | Int(c.g * 255) << 8 | Int(c.b * 255)
                var path = spikes[key]?.1 ?? Path()
                let sl = r * CGFloat(3.5 + 2 * l)
                path.move(to: CGPoint(x: sp.x - sl, y: sp.y)); path.addLine(to: CGPoint(x: sp.x + sl, y: sp.y))
                path.move(to: CGPoint(x: sp.x, y: sp.y - sl)); path.addLine(to: CGPoint(x: sp.x, y: sp.y + sl))
                spikes[key] = (c, path)
            }
        }
        for (_, (c, path)) in spikes {
            g.stroke(path, with: .color(c.mixed(.white, 0.5).color(0.45 * a)), lineWidth: core * 0.35)
        }
    }
}

// MARK: - Textures

/// The Milky Way band, built once off the main thread.
final class SkyTextures: @unchecked Sendable {
    let milkyWay: CGImage
    let nebulae: [CGImage]
    let galaxy: CGImage?

    init(milkyWay: CGImage, nebulae: [CGImage] = [], galaxy: CGImage? = nil) {
        self.milkyWay = milkyWay; self.nebulae = nebulae; self.galaxy = galaxy
    }

    static let shared: Task<SkyTextures?, Never> = Task.detached(priority: .userInitiated) { make() }

    static func make() -> SkyTextures? {
        let w = 1400, h = 700
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var r = Seeded(0x00C0_FFEE)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        func gauss() -> Double { (r.next() + r.next() + r.next() + r.next() - 2) / 2 }
        func centre(_ x: Double) -> Double { Double(h) / 2 + sin(x / Double(w) * 5.2) * 40 }
        func blob(_ x: Double, _ y: Double, _ rad: Double, _ c: (Double, Double, Double), _ a: Double) {
            let colors = [CGColor(colorSpace: cs, components: [c.0, c.1, c.2, a])!,
                          CGColor(colorSpace: cs, components: [c.0, c.1, c.2, 0])!] as CFArray
            guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) else { return }
            ctx.drawRadialGradient(grad, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                   endCenter: CGPoint(x: x, y: y), endRadius: rad, options: [])
        }
        // Soft glow of the band.
        for _ in 0..<700 {
            let x = r.next() * Double(w)
            let y = centre(x) + gauss() * 130
            let warm = max(0, 1 - abs(x - Double(w) * 0.58) / (Double(w) * 0.22))
            let c = (0.55 + 0.4 * warm, 0.6 + 0.2 * warm, 0.9 - 0.2 * warm)
            blob(x, y, 30 + r.next() * 90, c, 0.035 + 0.04 * warm)
        }
        // Dark dust lanes.
        ctx.setBlendMode(.destinationOut)
        for _ in 0..<160 {
            let x = r.next() * Double(w)
            blob(x, centre(x) + gauss() * 22 + 8, 14 + r.next() * 40, (0, 0, 0), 0.22)
        }
        ctx.setBlendMode(.normal)
        // Dust of faint stars, crowded toward the band.
        for _ in 0..<9000 {
            let x = r.next() * Double(w)
            let y = r.next() < 0.7 ? centre(x) + gauss() * 150 : r.next() * Double(h)
            let rad = 0.35 + pow(r.next(), 3) * 1.1
            ctx.setFillColor(CGColor(colorSpace: cs, components: [0.9, 0.92, 1, 0.15 + 0.6 * r.next()])!)
            ctx.fillEllipse(in: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2))
        }
        guard let img = ctx.makeImage() else { return nil }
        return SkyTextures(milkyWay: img, nebulae: (0..<4).compactMap { SkyLayers.nebula($0) }, galaxy: SkyLayers.galaxy())
    }
}

// MARK: - Dashboard preview

/// Looping card preview: flying through stars while a little constellation lights up.
struct NightSkyPreview: View {
    private let words = ["shine on", "la la la", "stay"]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let cycle = 4.0
            let n = Int(t / cycle)
            let ph = t - Double(n) * cycle
            let text = words[n % words.count]
            Canvas { g, size in
                var s = SkySettings()
                s[.density] = 0.35
                g.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.16), Color(red: 0.01, green: 0.01, blue: 0.04)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                var c = g
                c.translateBy(x: size.width / 2, y: size.height / 2)
                var field = c
                field.blendMode = .plusLighter
                SkyField.draw(&field, size: size, camX: 0, camY: 0, camZ: t * 260, vz: 260, focal: Double(size.width),
                              count: 500, shutter: 0.05, twinkle: 0.5, boost: 1, t: t)
                let plan = NeonSignPlan(index: 0, lines: [.init(id: 0, text: text, start: 0.3, duration: 1.3, singer: 0)],
                                        start: 0.3, offStart: 3.2, seed: LyricPages.hash(text))
                let con = SkyStars.constellation(plan.texts, font: .clean, box: CGSize(width: 1000, height: 450), density: 0.35)
                let k = size.width * 0.78 / 1000 * (1 + ph * 0.03)
                let fade = 1 - smoothstep((ph - 3.3) / 0.6)
                let st = SkyStage.pageState(plan, con, transform: .identity, alpha: fade, pos: ph, t: t, beat: 0,
                                            s: s, pal: [SkyStage.singerPalette[n % SkyStage.singerPalette.count]])
                c.scaleBy(x: k, y: k)
                SkyRenderer.drawPage(&c, st, s: s)
            }
        }
        .drawingGroup()
    }
}
