import SwiftUI

// MARK: - Style: Postcards (scene generator)
//
// Each song is one retro travel poster: a flat, grainy illustration of a coast, a beach, a
// desert road, a city rooftop, a harbour, a mountain lake, a forest or a mountain range, at
// sunset, dusk, night or golden hour. The poster is built from a seed (the song's title) and
// a kind (the vibe: picked by the user or decoded from the song). A scene is an ordered list of layers in a 1600×1000 space;
// PostcardRenderer animates and draws it.

let pcW = 1600.0, pcH = 1000.0

@inline(__always) func pp(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

/// Seeded random numbers with a scrambled seed (small seeds would start out correlated).
struct PCRand {
    private var g: Seeded
    init(_ seed: UInt64) { g = Seeded(PCRand.mix(seed)) }

    static func mix(_ x: UInt64) -> UInt64 {
        var z = x &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func d(_ a: Double = 0, _ b: Double = 1) -> Double { a + (b - a) * g.next() }
    mutating func i(_ n: Int) -> Int { min(n - 1, Int(g.next() * Double(n))) }
    mutating func chance(_ p: Double) -> Bool { g.next() < p }
}

enum PCKind: Int, CaseIterable {
    case coast, beach, desert, city, harbor, lake, forest, mountains

    var label: String {
        switch self {
        case .coast: "Coast"
        case .beach: "Beach"
        case .desert: "Desert"
        case .city: "City"
        case .harbor: "Harbour"
        case .lake: "Lake"
        case .forest: "Forest"
        case .mountains: "Mountains"
        }
    }

    var symbol: String {
        switch self {
        case .coast: "water.waves"
        case .beach: "beach.umbrella"
        case .desert: "sun.dust"
        case .city: "building.2"
        case .harbor: "sailboat"
        case .lake: "drop"
        case .forest: "tree"
        case .mountains: "mountain.2"
        }
    }
}
enum PCTime: Int, CaseIterable { case sunset, dusk, night, golden }

// MARK: Palette

enum PCRole { case far, mid, near, foliage, accent, sea, skyLow, skyMid, glow, warm, plum, sun, sand, ground }

struct PCPalette {
    var chips: [NeonRGB]
    var skyTop, skyMid, skyLow, sun, far, mid, near, glow, accent, sea, foliage, warm, plum, sand, ground, neon: NeonRGB
    var night: Bool

    /// Poster palettes: warm, blue, darkest, light, plum.
    static let bases: [[NeonRGB]] = [
        [NeonRGB(0.93, 0.42, 0.27), NeonRGB(0.17, 0.24, 0.50), NeonRGB(0.10, 0.08, 0.13), NeonRGB(0.98, 0.78, 0.42), NeonRGB(0.43, 0.20, 0.30)],
        [NeonRGB(1.00, 0.45, 0.55), NeonRGB(0.10, 0.50, 0.58), NeonRGB(0.08, 0.10, 0.20), NeonRGB(1.00, 0.80, 0.60), NeonRGB(0.45, 0.25, 0.60)],
        [NeonRGB(0.95, 0.50, 0.20), NeonRGB(0.30, 0.40, 0.60), NeonRGB(0.14, 0.08, 0.07), NeonRGB(0.98, 0.85, 0.55), NeonRGB(0.60, 0.22, 0.15)],
        [NeonRGB(0.95, 0.60, 0.30), NeonRGB(0.10, 0.20, 0.45), NeonRGB(0.04, 0.05, 0.10), NeonRGB(1.00, 0.88, 0.60), NeonRGB(0.25, 0.20, 0.45)],
        [NeonRGB(0.95, 0.55, 0.60), NeonRGB(0.40, 0.35, 0.70), NeonRGB(0.12, 0.10, 0.20), NeonRGB(1.00, 0.85, 0.70), NeonRGB(0.60, 0.35, 0.55)],
        [NeonRGB(1.00, 0.60, 0.45), NeonRGB(0.25, 0.55, 0.62), NeonRGB(0.10, 0.15, 0.17), NeonRGB(0.98, 0.90, 0.70), NeonRGB(0.40, 0.48, 0.45)],
        [NeonRGB(0.90, 0.30, 0.25), NeonRGB(0.20, 0.15, 0.35), NeonRGB(0.07, 0.05, 0.08), NeonRGB(1.00, 0.70, 0.35), NeonRGB(0.50, 0.15, 0.25)],
        [NeonRGB(0.95, 0.55, 0.35), NeonRGB(0.12, 0.42, 0.55), NeonRGB(0.05, 0.10, 0.14), NeonRGB(0.95, 0.85, 0.60), NeonRGB(0.20, 0.30, 0.45)],
    ]

    static func make(_ b: [NeonRGB], time: PCTime) -> PCPalette {
        let warm = b[0], blue = b[1], dark = b[2], light = b[3], plum = b[4]
        let white = NeonRGB.white
        let leaf = NeonRGB(0.22, 0.36, 0.28)
        var p = PCPalette(
            chips: b,
            skyTop: blue.mixed(plum, 0.3).mixed(dark, 0.2),
            skyMid: plum.mixed(warm, 0.55),
            skyLow: warm.mixed(light, 0.3),
            sun: light.mixed(white, 0.35),
            far: blue.mixed(warm, 0.22),
            mid: blue.mixed(dark, 0.35),
            near: dark.mixed(plum, 0.12),
            glow: light,
            accent: blue.mixed(white, 0.1),
            sea: blue.mixed(plum, 0.15),
            foliage: dark.mixed(leaf, 0.45),
            warm: warm,
            plum: plum,
            sand: light.mixed(warm, 0.35),
            ground: warm.mixed(dark, 0.45).mixed(plum, 0.2),
            neon: warm.mixed(white, 0.25),
            night: false)
        switch time {
        case .sunset:
            break
        case .dusk:
            p.skyTop = blue.mixed(dark, 0.35)
            p.skyMid = plum.mixed(blue, 0.3)
            p.skyLow = warm.mixed(plum, 0.25)
            p.far = blue.mixed(plum, 0.3).mixed(dark, 0.1)
            p.ground = p.ground.mixed(blue, 0.2)
        case .night:
            p.skyTop = dark.mixed(blue, 0.3)
            p.skyMid = blue.mixed(dark, 0.3)
            p.skyLow = plum.mixed(warm, 0.3)
            p.sun = light.mixed(white, 0.7)
            p.far = blue.mixed(dark, 0.45)
            p.mid = blue.mixed(dark, 0.62)
            p.sea = blue.mixed(dark, 0.4)
            p.accent = blue.mixed(white, 0.05)
            p.sand = p.sand.mixed(blue, 0.45).mixed(dark, 0.2)
            p.ground = p.ground.mixed(dark, 0.4)
            p.night = true
        case .golden:
            p.skyTop = blue.mixed(white, 0.3)
            p.skyMid = light.mixed(warm, 0.35)
            p.skyLow = light.mixed(white, 0.35)
            p.far = blue.mixed(light, 0.45)
            p.mid = blue.mixed(dark, 0.15)
            p.sea = blue.mixed(white, 0.1)
            p.foliage = dark.mixed(leaf, 0.65)
            p.ground = warm.mixed(light, 0.2).mixed(dark, 0.25)
        }
        return p
    }

    /// Five poster colours from the album art's vivid colours, or nil if there aren't enough.
    static func album(_ colors: [Color]) -> [NeonRGB]? {
        let c = colors.map { NeonRGB($0) }
        guard c.count >= 2 else { return nil }
        func lum(_ x: NeonRGB) -> Double { 0.3 * x.r + 0.59 * x.g + 0.11 * x.b }
        func sat(_ x: NeonRGB) -> Double { max(x.r, x.g, x.b) - min(x.r, x.g, x.b) }
        let byLum = c.sorted { lum($0) < lum($1) }
        let bySat = c.sorted { sat($0) > sat($1) }
        let black = NeonRGB(0.02, 0.02, 0.05)
        let warm = bySat[0]
        let blue = (bySat.count > 1 ? bySat[1] : byLum[0]).mixed(black, 0.25)
        return [warm, blue, byLum[0].mixed(black, 0.78), byLum[byLum.count - 1].mixed(.white, 0.45),
                warm.mixed(blue, 0.5).mixed(black, 0.3)]
    }

    func color(_ r: PCRole) -> NeonRGB {
        switch r {
        case .far: far
        case .mid: mid
        case .near: near
        case .foliage: foliage
        case .accent: accent
        case .sea: sea
        case .skyLow: skyLow
        case .skyMid: skyMid
        case .glow: glow
        case .warm: warm
        case .plum: plum
        case .sun: sun
        case .sand: sand
        case .ground: ground
        }
    }
}

// MARK: Layers

struct PCShape {
    var path: Path
    var role: PCRole
    var tint = 0.0          // haze: mix toward the horizon colour
    var depth = 0.5
    var gradient = false    // lit from above
    var alpha = 1.0
    var bob = 0.0           // bobbing on the water / washing waves (points)
    var phase = 0.0
}

struct PCPalm {
    var trunk: Path
    var crown: CGPoint
    var fronds: [Path]      // around the crown at (0, 0)
    var core: Path
    var phase: Double
    var depth: Double
    var tint: Double
}

/// Many small lights in three groups that twinkle out of step.
struct PCLights {
    var buckets: [Path]
    var depth: Double
    var warm = true
}

struct PCWindows {
    var rects: [CGRect]
    var on: [Double]        // each window switches on once the lit fraction passes this
    var depth: Double
}

struct PCCar {
    var body: Path
    var glass: Path
    var trim: Path
    var wheels: [CGPoint]
    var r: Double
    var lamp: CGPoint
    var depth: Double
}

struct PCSea {
    var top: Double
    var bottom: Double
    var glints: [Path]
    var mirror: [PCShape]   // shapes reflected in the water
}

struct PCCloud {
    var path: Path
    var x: Double
    var speed: Double
    var tone: Double
}

struct PCBeam { var origin: CGPoint; var length: Double; var depth: Double }
struct PCBirds { var seed: UInt64; var y: Double }

enum PCSurfaceKind { case neon, board, sky, banner }

/// Where the lyrics live in the scene.
struct PCSurface {
    var kind: PCSurfaceKind
    var box: CGRect
    var depth: Double
}

enum PCItem {
    case shape(PCShape)
    case palm(PCPalm)
    case lights(PCLights)
    case windows(PCWindows)
    case car(PCCar)
    case sea(PCSea)
    case clouds([PCCloud])
    case beam(PCBeam)
    case birds(PCBirds)
    case lyric
}

struct PCScene {
    let seed: UInt64
    let kind: PCKind
    let time: PCTime
    let paletteIndex: Int
    let place: String
    let mirror: Bool
    var horizon: Double
    var sun: CGPoint
    var sunR: Double
    var retroSun: Bool
    var stars: PCLights?
    var items: [PCItem]
    var surface: PCSurface

    static func make(seed: UInt64, kind forced: PCKind? = nil) -> PCScene {
        var r = PCRand(seed)
        let kind = forced ?? PCKind.allCases[Int(PCRand.mix(seed ^ 0x5BD1_E995) % UInt64(PCKind.allCases.count))]
        let times: [PCTime] = [.sunset, .sunset, .dusk, .dusk, .night, .golden]
        let time = times[r.i(times.count)]
        let pal = r.i(PCPalette.bases.count)
        let mirror = r.chance(0.5)
        let names = places(kind)
        let place = names[r.i(names.count)]

        var b = PCBuilder(r: PCRand(seed &+ 77), time: time)
        switch kind {
        case .coast: b.coast()
        case .beach: b.beach()
        case .desert: b.desert()
        case .city: b.city()
        case .harbor: b.harbor()
        case .lake: b.lake()
        case .forest: b.forest()
        case .mountains: b.mountains()
        }
        if time == .night {
            b.sun = pp(Double(b.sun.x), r.d(110, 260))
            b.sunR = min(b.sunR, 60) * 0.6
            b.retroSun = false
        }
        let stars = time == .night || time == .dusk ? b.stars() : nil
        return PCScene(seed: seed, kind: kind, time: time, paletteIndex: pal, place: place, mirror: mirror,
                       horizon: b.horizon, sun: b.sun, sunR: b.sunR, retroSun: b.retroSun, stars: stars,
                       items: b.items, surface: b.surface)
    }

    static func places(_ k: PCKind) -> [String] {
        switch k {
        case .coast: ["Monaco", "Positano", "Cannes", "Big Sur", "Capri", "Amalfi", "Saint-Tropez", "Malibu"]
        case .beach: ["Tulum", "Waikiki", "Ipanema", "Bondi", "Miami Beach", "Zanzibar", "Goa", "Cabo"]
        case .desert: ["Joshua Tree", "Palm Springs", "Marfa", "Route 66", "Sedona", "Death Valley", "Moab", "Barstow"]
        case .city: ["Los Angeles", "Tokyo", "Hong Kong", "Miami", "Chicago", "Shanghai", "New York", "Seoul"]
        case .harbor: ["Portofino", "Santorini", "Sausalito", "Nice", "Hydra", "Valletta", "Lisbon", "Mykonos"]
        case .lake: ["Lake Tahoe", "Banff", "Lake Como", "Hallstatt", "Lucerne", "Queenstown", "Bled", "Annecy"]
        case .forest: ["Redwoods", "Black Forest", "Muir Woods", "Great Smoky", "Olympic", "Yosemite", "Bavaria", "Tongass"]
        case .mountains: ["Zermatt", "Aspen", "Chamonix", "Patagonia", "Dolomites", "Jackson Hole", "Whistler", "Kathmandu"]
        }
    }
}

// MARK: Geometry

enum PCGeo {
    static let step = 20.0

    /// A filled strip that tapers to a point along a quadratic curve.
    static func blade(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, width w0: Double, steps: Int = 8) -> Path {
        let ax = Double(p0.x), ay = Double(p0.y), cx = Double(c.x), cy = Double(c.y), bx = Double(p1.x), by = Double(p1.y)
        var left: [CGPoint] = [], right: [CGPoint] = []
        for k in 0...steps {
            let t = Double(k) / Double(steps), mt = 1 - t
            let x = mt * mt * ax + 2 * mt * t * cx + t * t * bx
            let y = mt * mt * ay + 2 * mt * t * cy + t * t * by
            let dx = 2 * mt * (cx - ax) + 2 * t * (bx - cx)
            let dy = 2 * mt * (cy - ay) + 2 * t * (by - cy)
            let len = max(0.001, (dx * dx + dy * dy).squareRoot())
            let w = w0 * (1 - t) * 0.5
            left.append(pp(x - dy / len * w, y + dx / len * w))
            right.append(pp(x + dy / len * w, y - dx / len * w))
        }
        var p = Path()
        p.addLines(left + right.reversed())
        p.closeSubpath()
        return p
    }

    /// A hill line across the scene, closed down to `bottom`, with its height every `step`.
    static func ridge(_ r: inout PCRand, base: Double, amp: Double, freq: Double, bottom: Double,
                      profile: (Double) -> Double = { _ in 0 }) -> (Path, [Double]) {
        let p1 = r.d(0, 6.28), p2 = r.d(0, 6.28), p3 = r.d(0, 6.28)
        var hs: [Double] = []
        var path = Path()
        path.move(to: pp(-300, bottom))
        var x = -300.0
        while x <= 1900 {
            let n = sin(x * freq + p1) * 0.6 + sin(x * freq * 2.7 + p2) * 0.28 + sin(x * freq * 7.3 + p3) * 0.12
            let y = base + profile(x) - amp * n + r.d(-1, 1) * amp * 0.04
            hs.append(y)
            path.addLine(to: pp(x, y))
            x += step
        }
        path.addLine(to: pp(1900, bottom))
        path.closeSubpath()
        return (path, hs)
    }

    static func height(_ hs: [Double], _ x: Double) -> Double {
        let i = Int(((x + 300) / step).rounded())
        return hs[max(0, min(hs.count - 1, i))]
    }

    /// Town lights scattered down a slope, denser toward the bottom.
    static func lights(_ r: inout PCRand, on hs: [Double], x0: Double, x1: Double, floor: Double,
                       count: Int, size: Double, depth: Double) -> PCLights {
        var b = [Path(), Path(), Path()]
        for i in 0..<count {
            let x = r.d(x0, x1)
            let top = height(hs, x) + 6
            guard floor > top else { continue }
            let y = top + (floor - top) * pow(r.d(), 0.6)
            let s = size * r.d(0.6, 1.3)
            b[i % 3].addEllipse(in: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2))
        }
        return PCLights(buckets: b, depth: depth)
    }

    /// A fan palm: curved trunk, a skirt of old fronds and spiky fronds round the crown.
    static func palm(_ r: inout PCRand, base: CGPoint, height h: Double, lean: Double, depth: Double, tint: Double) -> PCPalm {
        let bx = Double(base.x), by = Double(base.y)
        let cx = bx + lean * h, cy = by - h
        let kx = bx + lean * h * 0.2 + r.d(-0.04, 0.04) * h, ky = by - h * 0.5
        let w0 = h * 0.03, w1 = h * 0.017
        var left: [CGPoint] = [], right: [CGPoint] = []
        for k in 0...14 {
            let t = Double(k) / 14, mt = 1 - t
            let x = mt * mt * bx + 2 * mt * t * kx + t * t * cx
            let y = mt * mt * by + 2 * mt * t * ky + t * t * cy
            let w = (w0 + (w1 - w0) * t) / 2
            left.append(pp(x - w, y))
            right.append(pp(x + w, y))
        }
        var trunk = Path()
        trunk.addLines(left + right.reversed())
        trunk.closeSubpath()

        let L = h * r.d(0.2, 0.25)
        var fronds: [Path] = []
        let n = 18 + r.i(6)
        for k in 0..<n {
            let a = Double(k) / Double(n) * 2 * .pi + r.d(-0.15, 0.15)
            let dx = cos(a), dy = sin(a) * 0.55
            var len = L * r.d(0.8, 1.15)
            if dy < 0 { len *= 0.85 }
            let droop = len * (0.25 + 0.35 * abs(dx))
            let tip = pp(dx * len, dy * len + droop)
            let ctrl = pp(dx * len * 0.55, dy * len * 0.55 - len * 0.12)
            var f = blade(pp(0, 0), ctrl, tip, width: len * 0.09)
            // a fan of needles near the tip
            let mx = dx * len * 0.5, my = dy * len * 0.5 + droop * 0.15
            let tx = Double(tip.x) - mx, ty = Double(tip.y) - my
            let tl = max(0.001, (tx * tx + ty * ty).squareRoot())
            let nx = -ty / tl, ny = tx / tl
            for s in 0..<5 {
                let spread = (Double(s) - 2) * len * 0.1 + r.d(-0.03, 0.03) * len
                let ex = Double(tip.x) + nx * spread + tx / tl * len * 0.08
                let ey = Double(tip.y) + ny * spread + len * 0.1 * r.d(0.2, 1)
                f.addPath(blade(pp(mx, my), pp((mx + ex) / 2, (my + ey) / 2 - len * 0.04), pp(ex, ey), width: len * 0.035, steps: 5))
            }
            fronds.append(f)
        }
        var core = Path()
        core.addEllipse(in: CGRect(x: -L * 0.13, y: -L * 0.12, width: L * 0.26, height: L * 0.24))
        // the skirt of dry fronds hanging below the crown
        core.addEllipse(in: CGRect(x: -L * 0.1, y: -L * 0.02, width: L * 0.2, height: L * 0.5))
        return PCPalm(trunk: trunk, crown: pp(cx, cy), fronds: fronds, core: core, phase: r.d(0, 6.28), depth: depth, tint: tint)
    }

    static func mesa(_ p: inout Path, x: Double, w: Double, h: Double, base: Double, slope: Double) {
        p.move(to: pp(x - slope, base))
        p.addLine(to: pp(x + slope * 0.15, base - h * 0.7))
        p.addLine(to: pp(x + slope * 0.3, base - h))
        p.addLine(to: pp(x + w - slope * 0.3, base - h))
        p.addLine(to: pp(x + w - slope * 0.1, base - h * 0.75))
        p.addLine(to: pp(x + w + slope, base))
        p.closeSubpath()
    }

    static func cactus(_ p: inout Path, _ r: inout PCRand, x: Double, base: Double, h: Double) {
        let w = h * 0.13
        p.addRoundedRect(in: CGRect(x: x - w / 2, y: base - h, width: w, height: h + 5), cornerSize: CGSize(width: w / 2, height: w / 2))
        for side in [-1.0, 1.0] where r.chance(0.8) {
            let ay = base - h * r.d(0.3, 0.55), ah = h * r.d(0.22, 0.38), aw = w * 0.75
            let ax = x + side * (w / 2 + aw * 0.9)
            p.addRoundedRect(in: CGRect(x: ax - aw / 2, y: ay - ah, width: aw, height: ah + aw / 2),
                             cornerSize: CGSize(width: aw / 2, height: aw / 2))
            p.addRoundedRect(in: CGRect(x: min(x, ax) - aw / 4, y: ay - aw / 2, width: abs(ax - x) + aw / 2, height: aw),
                             cornerSize: CGSize(width: aw / 2, height: aw / 2))
        }
    }

    static func pine(_ p: inout Path, x: Double, base: Double, h: Double) {
        let w = h * 0.36
        p.addRect(CGRect(x: x - w * 0.05, y: base - h * 0.15, width: w * 0.1, height: h * 0.15 + 4))
        for k in 0..<4 {
            let t = Double(k) / 4
            let y0 = base - h * 0.12 - t * h * 0.78
            let ww = w * (1 - t * 0.7)
            p.move(to: pp(x - ww / 2, y0))
            p.addLine(to: pp(x, y0 - h * 0.34))
            p.addLine(to: pp(x + ww / 2, y0))
            p.closeSubpath()
        }
    }

    /// A jagged range of peaks closed down to `bottom`, and snow caps on its peaks.
    static func peaks(_ r: inout PCRand, top: ClosedRange<Double>, valley: ClosedRange<Double>,
                      gap: ClosedRange<Double>, bottom: Double, snow f: Double) -> (Path, Path) {
        var pts: [CGPoint] = [pp(-300, r.d(valley.lowerBound, valley.upperBound))]
        var x = -300.0
        while x < 1900 {
            x += r.d(gap.lowerBound, gap.upperBound)
            pts.append(pp(x, r.d(top.lowerBound, top.upperBound)))
            x += r.d(gap.lowerBound, gap.upperBound)
            pts.append(pp(x, r.d(valley.lowerBound, valley.upperBound)))
        }
        var mtn = Path(), snow = Path()
        mtn.move(to: pp(-300, bottom))
        for q in pts { mtn.addLine(to: q) }
        mtn.addLine(to: pp(Double(pts.last!.x), bottom))
        mtn.closeSubpath()
        guard f > 0 else { return (mtn, snow) }
        for i in stride(from: 1, to: pts.count - 1, by: 2) {
            let pk = pts[i], l = pts[i - 1], rr = pts[i + 1]
            let lp = pp(Double(pk.x + (l.x - pk.x) * f), Double(pk.y + (l.y - pk.y) * f))
            let rp = pp(Double(pk.x + (rr.x - pk.x) * f), Double(pk.y + (rr.y - pk.y) * f))
            snow.move(to: pk)
            snow.addLine(to: rp)
            snow.addLine(to: pp(Double(lp.x + (rp.x - lp.x) * 0.66), Double(max(lp.y, rp.y)) - 4))
            snow.addLine(to: pp(Double(lp.x + (rp.x - lp.x) * 0.4), Double(max(lp.y, rp.y)) + 10))
            snow.addLine(to: lp)
            snow.closeSubpath()
        }
        return (mtn, snow)
    }
}

// MARK: - Scene builders

struct PCBuilder {
    var r: PCRand
    let time: PCTime
    var items: [PCItem] = []
    var surface = PCSurface(kind: .sky, box: CGRect(x: 300, y: 120, width: 1000, height: 220), depth: 0.1)
    var horizon = 600.0
    var sun = pp(800, 520)
    var sunR = 60.0
    var retroSun = false

    mutating func add(_ path: Path, _ role: PCRole, depth: Double, tint: Double = 0, gradient: Bool = false,
                      alpha: Double = 1, bob: Double = 0, phase: Double? = nil) {
        let ph = phase ?? r.d(0, 6.28)
        items.append(.shape(PCShape(path: path, role: role, tint: tint, depth: depth, gradient: gradient,
                                    alpha: alpha, bob: bob, phase: ph)))
    }

    mutating func clouds(_ n: Int, y0: Double, y1: Double) {
        var cs: [PCCloud] = []
        for _ in 0..<n {
            let w = r.d(220, 520), h = r.d(12, 26), y = r.d(y0, y1)
            var p = Path()
            p.addRoundedRect(in: CGRect(x: 0, y: y, width: w, height: h), cornerSize: CGSize(width: h / 2, height: h / 2))
            p.addRoundedRect(in: CGRect(x: w * r.d(0.1, 0.4), y: y - h * 0.8, width: w * r.d(0.35, 0.6), height: h),
                             cornerSize: CGSize(width: h / 2, height: h / 2))
            cs.append(PCCloud(path: p, x: r.d(-300, 1700), speed: r.d(2, 6), tone: r.d(0.1, 0.5)))
        }
        items.append(.clouds(cs))
    }

    mutating func sea(top: Double, bottom: Double, mirror: [PCShape] = []) {
        var b = [Path(), Path(), Path()]
        for i in 0..<240 {
            let k = pow(r.d(), 1.5)
            let y = top + 3 + k * (bottom - top)
            let spread = 30 + k * 260
            let x = r.chance(0.4) ? Double(sun.x) + r.d(-1, 1) * spread : r.d(-300, 1900)
            let len = r.d(10, 40) * (0.4 + k * 1.6)
            let h = 1.5 + k * 2.5
            b[i % 3].addRoundedRect(in: CGRect(x: x - len / 2, y: y, width: len, height: h),
                                    cornerSize: CGSize(width: h / 2, height: h / 2))
        }
        items.append(.sea(PCSea(top: top, bottom: bottom, glints: b, mirror: mirror)))
    }

    mutating func stars() -> PCLights {
        var b = [Path(), Path(), Path()]
        for i in 0..<150 {
            let x = r.d(-300, 1900), y = pow(r.d(), 1.4) * max(100, horizon - 140)
            let s = r.d(0.8, 2.1)
            b[i % 3].addEllipse(in: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2))
        }
        return PCLights(buckets: b, depth: 0, warm: false)
    }

    mutating func bushes(x0: Double, x1: Double, base: Double, height: Double, role: PCRole = .foliage,
                         depth: Double, tint: Double = 0) {
        var p = Path()
        var x = x0
        while x < x1 {
            let rad = height * r.d(0.45, 1.0)
            p.addEllipse(in: CGRect(x: x - rad, y: base - rad * 1.5, width: rad * 2.1, height: rad * 1.9))
            for _ in 0..<3 {
                let br = rad * r.d(0.25, 0.45), a = r.d(-2.6, -0.5)
                let cx = x + cos(a) * rad, cy = base - rad * 0.55 + sin(a) * rad * 0.9
                p.addEllipse(in: CGRect(x: cx - br, y: cy - br, width: br * 2, height: br * 2))
            }
            x += rad * r.d(0.9, 1.5)
        }
        p.addRect(CGRect(x: x0 - height, y: base - height * 0.3, width: x1 - x0 + 2 * height, height: 1150 - base))
        add(p, role, depth: depth, tint: tint, gradient: true)
    }

    mutating func palm(x: Double, base: Double, h: Double, lean: Double, depth: Double, tint: Double = 0) {
        items.append(.palm(PCGeo.palm(&r, base: pp(x, base), height: h, lean: lean, depth: depth, tint: tint)))
    }

    mutating func birds() {
        guard time != .night else { return }
        items.append(.birds(PCBirds(seed: UInt64(r.d() * 1_000_000), y: r.d(150, 360))))
    }

    mutating func car(x: Double, ground: Double, length L: Double, dir: Double, depth: Double) {
        func q(_ u: Double, _ v: Double) -> CGPoint { pp(x + (u - 0.5) * L * dir, ground + v * L) }
        var body = Path()
        body.move(to: q(0.03, -0.06))
        body.addLine(to: q(0.0, -0.16))
        body.addQuadCurve(to: q(0.07, -0.245), control: q(0.0, -0.235))
        body.addLine(to: q(0.2, -0.265))
        body.addQuadCurve(to: q(0.63, -0.265), control: q(0.41, -0.47))
        body.addQuadCurve(to: q(0.96, -0.19), control: q(0.85, -0.25))
        body.addQuadCurve(to: q(1.0, -0.1), control: q(1.01, -0.17))
        body.addLine(to: q(0.97, -0.06))
        body.closeSubpath()
        var glass = Path()
        glass.move(to: q(0.27, -0.28))
        glass.addQuadCurve(to: q(0.585, -0.275), control: q(0.42, -0.43))
        glass.closeSubpath()
        let a = q(0.44, -0.4), b = q(0.455, -0.27)
        var trim = Path()
        trim.addRect(CGRect(x: min(a.x, b.x), y: a.y, width: abs(b.x - a.x), height: b.y - a.y))
        items.append(.car(PCCar(body: body, glass: glass, trim: trim, wheels: [q(0.2, -0.075), q(0.8, -0.075)],
                                r: 0.075 * L, lamp: q(0.975, -0.165), depth: depth)))
    }

    /// A billboard on two posts; the frame, face and bulbs are drawn with the lyric.
    mutating func board(_ box: CGRect, postsTo ground: Double, depth: Double) {
        var posts = Path()
        let pw = Double(box.width) * 0.025
        for u in [0.22, 0.78] {
            posts.addRect(CGRect(x: Double(box.minX) + Double(box.width) * u - pw / 2, y: Double(box.maxY),
                                 width: pw, height: ground - Double(box.maxY)))
        }
        posts.addRect(CGRect(x: Double(box.minX) + Double(box.width) * 0.2, y: Double(box.maxY) + (ground - Double(box.maxY)) * 0.45,
                             width: Double(box.width) * 0.6, height: pw * 0.6))
        add(posts, .near, depth: depth)
        surface = PCSurface(kind: .board, box: box, depth: depth)
        items.append(.lyric)
    }

    mutating func villa(x: Double, ground: Double, w: Double, h: Double, depth: Double) {
        let roofY = ground - h, roofH = h * 0.09
        let midY = ground - h * 0.5, midH = h * 0.08
        let upTop = roofY + roofH, lowTop = midY + midH
        let wallW = w * 0.64
        add(Path(CGRect(x: x, y: roofY, width: w, height: h)), .plum, depth: depth, gradient: true)
        var rects: [CGRect] = []
        let pane = w * 0.075
        var gx = x + wallW + w * 0.04
        while gx + pane < x + w - w * 0.02 {
            rects.append(CGRect(x: gx, y: upTop + h * 0.03, width: pane - w * 0.012, height: midY - upTop - h * 0.03))
            gx += pane
        }
        gx = x + w * 0.06
        while gx + pane < x + w - w * 0.02 {
            rects.append(CGRect(x: gx, y: lowTop + h * 0.04, width: pane - w * 0.012, height: ground - lowTop - h * 0.04))
            gx += pane
        }
        items.append(.windows(PCWindows(rects: rects, on: rects.map { _ in r.d() }, depth: depth)))
        let wall = CGRect(x: x + w * 0.02, y: upTop, width: wallW, height: midY - upTop)
        add(Path(wall), .near, depth: depth, tint: 0.1, gradient: true)
        add(Path(CGRect(x: x - w * 0.07, y: roofY, width: w * 1.12, height: roofH)), .accent, depth: depth, gradient: true)
        add(Path(CGRect(x: x - w * 0.05, y: midY, width: w * 1.1, height: midH)), .accent, depth: depth, gradient: true)
        add(Path(CGRect(x: x + wallW, y: lowTop, width: w * 0.025, height: ground - lowTop)), .near, depth: depth)
        surface = PCSurface(kind: .neon, box: wall.insetBy(dx: wall.width * 0.05, dy: wall.height * 0.1), depth: depth)
        items.append(.lyric)
    }

    // MARK: Kinds

    /// A hillside villa over the sea at dusk, town lights on the headland, palms and a parked car.
    mutating func coast() {
        horizon = 600
        sun = pp(r.d(220, 620), r.d(480, 570))
        sunR = r.d(38, 62)
        clouds(r.i(4) + 2, y0: 90, y1: 430)
        let rise = r.d(180, 260)
        let (far, hs) = PCGeo.ridge(&r, base: 650, amp: 22, freq: 0.004, bottom: 1100) { x in -smoothstep((x - 420) / 1000) * rise }
        let farS = PCShape(path: far, role: .far, tint: 0.15, depth: 0.2, gradient: true)
        sea(top: horizon, bottom: 1100, mirror: [farS])
        items.append(.shape(farS))
        items.append(.lights(PCGeo.lights(&r, on: hs, x0: 420, x1: 1800, floor: 880, count: 520, size: 2.3, depth: 0.2)))
        let (mid, _) = PCGeo.ridge(&r, base: 850, amp: 26, freq: 0.006, bottom: 1100) { x in -smoothstep((x + 100) / 900) * 60 }
        add(mid, .mid, depth: 0.4, gradient: true)
        bushes(x0: -200, x1: 1000, base: 905, height: 48, depth: 0.45, tint: 0.12)
        palm(x: r.d(760, 860), base: 905, h: r.d(380, 460), lean: r.d(-0.05, 0.05), depth: 0.45, tint: 0.2)
        let vx = r.d(880, 960), vw = 760.0
        villa(x: vx, ground: 935, w: vw, h: r.d(540, 590), depth: 0.6)
        add(Path(CGRect(x: -300, y: 930, width: 2200, height: 200)), .warm, depth: 0.8, tint: 0.1, gradient: true)
        car(x: r.d(560, 700), ground: 978, length: r.d(400, 450), dir: 1, depth: 0.8)
        palm(x: r.d(220, 380), base: 1005, h: r.d(820, 900), lean: r.d(-0.04, 0.06), depth: 0.85)
        palm(x: vx + vw * r.d(0.7, 0.76), base: 1005, h: r.d(760, 840), lean: r.d(-0.03, 0.04), depth: 0.85)
        bushes(x0: 1350, x1: 1800, base: 1005, height: 110, depth: 0.95)
        bushes(x0: -250, x1: 120, base: 1005, height: 90, depth: 0.95)
    }

    /// A striped retro sun on the sea, a banner plane, palms leaning in and a lifeguard hut.
    mutating func beach() {
        horizon = 560
        retroSun = true
        sun = pp(r.d(560, 1040), 545)
        sunR = r.d(130, 170)
        clouds(3, y0: 300, y1: 520)
        surface = PCSurface(kind: .banner, box: CGRect(x: 260, y: 120, width: 1080, height: 170), depth: 0.1)
        items.append(.lyric)
        sea(top: horizon, bottom: 1100)
        let sy = r.d(770, 810), ph = r.d(0, 6)
        func shore(_ x: Double) -> Double { sy + sin(x * 0.004 + ph) * 22 }
        var sand = Path(), foam = Path()
        sand.move(to: pp(-300, 1150))
        var x = -300.0
        var top: [CGPoint] = [], bot: [CGPoint] = []
        while x <= 1900 {
            sand.addLine(to: pp(x, shore(x)))
            top.append(pp(x, shore(x) - 9))
            bot.append(pp(x, shore(x) + 2))
            x += 40
        }
        sand.addLine(to: pp(1900, 1150))
        sand.closeSubpath()
        foam.addLines(top + bot.reversed())
        foam.closeSubpath()
        add(sand, .sand, depth: 0.6, gradient: true)
        add(foam, .sun, depth: 0.6, alpha: 0.75, bob: 5)
        // lifeguard hut on stilts
        let hx = r.d(1080, 1320), hb = sy + 90
        var hut = Path()
        for u in [-46.0, -18.0, 18.0, 46.0] { hut.addRect(CGRect(x: hx + u - 3, y: hb - 120, width: 6, height: 120)) }
        hut.addRect(CGRect(x: hx - 60, y: hb - 128, width: 120, height: 8))
        add(hut, .near, depth: 0.65)
        add(Path(CGRect(x: hx - 50, y: hb - 200, width: 100, height: 72)), .warm, depth: 0.65, gradient: true)
        var roof = Path()
        roof.move(to: pp(hx - 66, hb - 198))
        roof.addLine(to: pp(hx, hb - 236))
        roof.addLine(to: pp(hx + 66, hb - 198))
        roof.closeSubpath()
        add(roof, .accent, depth: 0.65, gradient: true)
        items.append(.windows(PCWindows(rects: [CGRect(x: hx - 32, y: hb - 186, width: 64, height: 26)], on: [0], depth: 0.65)))
        palm(x: r.d(60, 220), base: 1005, h: r.d(820, 900), lean: r.d(0.12, 0.22), depth: 0.9)
        palm(x: r.d(1380, 1540), base: 1005, h: r.d(700, 800), lean: r.d(-0.22, -0.12), depth: 0.9)
        if r.chance(0.6) { palm(x: r.d(280, 400), base: 990, h: r.d(500, 600), lean: r.d(0, 0.08), depth: 0.8, tint: 0.08) }
        bushes(x0: -250, x1: 200, base: 1005, height: 80, depth: 0.95)
        bushes(x0: 1450, x1: 1850, base: 1005, height: 80, depth: 0.95)
        birds()
    }

    /// Mesas, a long straight road to the horizon, telegraph poles, cacti and a roadside sign.
    mutating func desert() {
        horizon = 640
        sun = pp(r.d(250, 1350), r.d(540, 625))
        sunR = r.d(60, 90)
        clouds(r.i(3) + 2, y0: 100, y1: 470)
        var far = Path()
        for _ in 0..<4 { PCGeo.mesa(&far, x: r.d(-200, 1600), w: r.d(160, 420), h: r.d(60, 150), base: 646, slope: r.d(30, 70)) }
        add(far, .far, depth: 0.15, tint: 0.2, gradient: true)
        var mid = Path()
        for _ in 0..<2 { PCGeo.mesa(&mid, x: r.d(-300, 1500), w: r.d(300, 600), h: r.d(140, 250), base: 650, slope: 80) }
        add(mid, .mid, depth: 0.3, tint: 0.05, gradient: true)
        add(Path(CGRect(x: -300, y: 640, width: 2200, height: 520)), .ground, depth: 0.5, gradient: true)
        let vx = r.d(700, 950)
        var road = Path()
        road.move(to: pp(vx - 6, 640))
        road.addLine(to: pp(vx + 6, 640))
        road.addLine(to: pp(1350, 1100))
        road.addLine(to: pp(250, 1100))
        road.closeSubpath()
        add(road, .near, depth: 0.5, tint: 0.12, gradient: true)
        var dash = Path()
        for k in 0..<12 {
            let u0 = pow(Double(k) / 12, 2), u1 = pow((Double(k) + 0.5) / 12, 2)
            let y0 = 640 + 460 * u0, y1 = 640 + 460 * u1
            let x0 = vx + (800 - vx) * u0, x1 = vx + (800 - vx) * u1
            let w0 = 1 + 14 * u0, w1 = 1 + 14 * u1
            dash.move(to: pp(x0 - w0 / 2, y0))
            dash.addLine(to: pp(x0 + w0 / 2, y0))
            dash.addLine(to: pp(x1 + w1 / 2, y1))
            dash.addLine(to: pp(x1 - w1 / 2, y1))
            dash.closeSubpath()
        }
        add(dash, .sun, depth: 0.5, alpha: 0.8)
        var poles = Path()
        var tops: [CGPoint] = []
        for k in 0..<7 {
            let u = pow(Double(k + 1) / 7, 1.8)
            let y = 640 + 460 * u, x = vx + 30 + (1500 - vx) * u
            let ph = 18 + 420 * u, pw = 2 + 9 * u
            poles.addRect(CGRect(x: x - pw / 2, y: y - ph, width: pw, height: ph))
            poles.addRect(CGRect(x: x - pw * 4, y: y - ph + pw, width: pw * 8, height: pw * 0.7))
            tops.append(pp(x, y - ph + pw * 1.3))
        }
        poles.addLines(tops + tops.reversed().map { pp(Double($0.x), Double($0.y) + 2.5) })
        poles.closeSubpath()
        add(poles, .near, depth: 0.6)
        var cac = Path()
        for _ in 0..<(r.i(3) + 2) {
            let cx = r.chance(0.5) ? r.d(-120, 120) : r.d(1380, 1720)
            let b = r.d(760, 1010)
            PCGeo.cactus(&cac, &r, x: cx, base: b, h: (b - 640) * r.d(0.9, 1.3))
        }
        add(cac, .foliage, depth: 0.8, gradient: true)
        let box = CGRect(x: r.d(60, 150), y: r.d(240, 290), width: r.d(540, 600), height: r.d(230, 255))
        board(box, postsTo: 870, depth: 0.7)
        if r.chance(0.7) { car(x: Double(box.midX) + r.d(-60, 80), ground: 905, length: 360, dir: 1, depth: 0.75) }
    }

    /// A skyline behind a rooftop with a water tower and a lit billboard.
    mutating func city() {
        horizon = 760
        sun = pp(r.d(300, 1300), r.d(560, 680))
        sunR = r.d(70, 110)
        clouds(3, y0: 100, y1: 450)
        skyline(base: 790, hMin: 120, hMax: 330, wMin: 50, wMax: 120, role: .far, tint: 0.25, depth: 0.15, size: 3, density: 0.35)
        skyline(base: 870, hMin: 220, hMax: 520, wMin: 80, wMax: 170, role: .mid, tint: 0.04, depth: 0.35, size: 5, density: 0.4)
        var roof = Path()
        roof.addRect(CGRect(x: -300, y: 850, width: 2200, height: 300))
        for _ in 0..<5 { roof.addRect(CGRect(x: r.d(-100, 1700), y: 850 - r.d(14, 40), width: r.d(40, 110), height: 50)) }
        let tx = r.chance(0.5) ? r.d(80, 300) : r.d(1250, 1450)
        for u in [-50.0, -16.0, 16.0, 50.0] { roof.addRect(CGRect(x: tx + u - 3, y: 700, width: 6, height: 160)) }
        roof.addRoundedRect(in: CGRect(x: tx - 66, y: 560, width: 132, height: 150), cornerSize: CGSize(width: 10, height: 10))
        roof.move(to: pp(tx - 74, 566))
        roof.addLine(to: pp(tx, 510))
        roof.addLine(to: pp(tx + 74, 566))
        roof.closeSubpath()
        add(roof, .near, depth: 0.8, gradient: true)
        let box = CGRect(x: r.d(430, 560), y: r.d(320, 390), width: r.d(620, 680), height: r.d(240, 270))
        board(box, postsTo: 860, depth: 0.7)
        if r.chance(0.5) {
            palm(x: r.d(-40, 60), base: 1005, h: r.d(760, 860), lean: r.d(0.04, 0.12), depth: 0.9)
            palm(x: r.d(1540, 1640), base: 1005, h: r.d(700, 820), lean: r.d(-0.12, -0.04), depth: 0.9)
        }
        birds()
    }

    mutating func skyline(base: Double, hMin: Double, hMax: Double, wMin: Double, wMax: Double, role: PCRole,
                          tint: Double, depth: Double, size: Double, density: Double) {
        var p = Path()
        var b = [Path(), Path(), Path()]
        var x = -300.0
        while x < 1900 {
            let w = r.d(wMin, wMax), h = r.d(hMin, hMax)
            let top = base - h
            p.addRect(CGRect(x: x, y: top, width: w, height: h + 400))
            if r.chance(0.3) { p.addRect(CGRect(x: x + w * 0.2, y: top - h * 0.12, width: w * 0.6, height: h * 0.12 + 1)) }
            if r.chance(0.2) { p.addRect(CGRect(x: x + w * 0.5 - 1.5, y: top - h * 0.3, width: 3, height: h * 0.3)) }
            var wy = top + size * 3
            while wy < base - size * 2 {
                var wx = x + size * 2
                while wx < x + w - size * 2 {
                    if r.chance(density) { b[r.i(3)].addRect(CGRect(x: wx, y: wy, width: size * 1.4, height: size * 1.8)) }
                    wx += size * 3.2
                }
                wy += size * 4
            }
            x += w + r.d(-wMin * 0.3, wMin * 0.3)
        }
        add(p, role, depth: depth, tint: tint, gradient: true)
        items.append(.lights(PCLights(buckets: b, depth: depth)))
    }

    /// A hillside town over a bay with boats, a lighthouse, and a quayside building with neon.
    mutating func harbor() {
        horizon = 560
        sun = pp(r.d(800, 1300), r.d(470, 540))
        sunR = r.d(40, 60)
        clouds(4, y0: 80, y1: 420)
        let (far, _) = PCGeo.ridge(&r, base: 575, amp: 22, freq: 0.005, bottom: 600) { x in -smoothstep((600 - x) / 700) * 90 }
        let farS = PCShape(path: far, role: .far, tint: 0.2, depth: 0.15, gradient: true)
        let climb = r.d(260, 340)
        let (hill, hs) = PCGeo.ridge(&r, base: 580, amp: 18, freq: 0.006, bottom: 640) { x in -smoothstep((x - 700) / 900) * climb }
        let hillS = PCShape(path: hill, role: .mid, tint: 0.05, depth: 0.3, gradient: true)
        sea(top: horizon, bottom: 1100, mirror: [farS, hillS])
        items.append(.shape(farS))
        items.append(.shape(hillS))
        var houses = Path()
        for _ in 0..<70 {
            let x = r.d(800, 1900)
            let top = PCGeo.height(hs, x)
            guard top < 560 else { continue }
            let y = top + r.d(16, max(18, 590 - top))
            houses.addRect(CGRect(x: x, y: y, width: r.d(10, 22), height: r.d(8, 14)))
        }
        add(houses, .sun, depth: 0.3, tint: 0.3, alpha: 0.4)
        items.append(.lights(PCGeo.lights(&r, on: hs, x0: 760, x1: 1900, floor: 590, count: 280, size: 2.2, depth: 0.3)))
        lighthouse(x: r.d(840, 1000), base: 600, h: r.d(170, 210), depth: 0.35)
        var boats: [(Double, Double)] = []
        for _ in 0..<(r.i(3) + 3) { boats.append((r.d(820, 1650), r.d(640, 920))) }
        for (bx, water) in boats.sorted(by: { $0.1 < $1.1 }) {
            let s = (water - 560) / 360 * 0.9 + 0.3
            boat(x: bx, water: water, s: s, depth: 0.4 + s * 0.3, sail: r.chance(0.6))
        }
        let qw = r.d(720, 780), roofY = r.d(420, 460), base = 860.0
        add(Path(CGRect(x: -300, y: base, width: qw + 360, height: 300)), .near, depth: 0.8, gradient: true)
        add(Path(CGRect(x: -80, y: roofY, width: qw, height: base - roofY)), .plum, depth: 0.8, tint: 0.05, gradient: true)
        add(Path(CGRect(x: -100, y: roofY - 18, width: qw + 40, height: 22)), .accent, depth: 0.8, gradient: true)
        var rects: [CGRect] = []
        var wx = -40.0
        while wx < qw - 160 { rects.append(CGRect(x: wx, y: base - 112, width: 52, height: 92)); wx += 78 }
        items.append(.windows(PCWindows(rects: rects, on: rects.map { _ in r.d() }, depth: 0.8)))
        let sign = CGRect(x: -20, y: roofY + 22, width: qw - 120, height: base - roofY - 160)
        surface = PCSurface(kind: .neon, box: sign, depth: 0.8)
        items.append(.lyric)
        birds()
    }

    mutating func boat(x: Double, water: Double, s: Double, depth: Double, sail: Bool) {
        let ph = r.d(0, 6.28)
        var hull = Path()
        hull.move(to: pp(x - 60 * s, water - 18 * s))
        hull.addLine(to: pp(x + 70 * s, water - 18 * s))
        hull.addLine(to: pp(x + 50 * s, water + 6 * s))
        hull.addLine(to: pp(x - 50 * s, water + 6 * s))
        hull.closeSubpath()
        hull.addRect(CGRect(x: x - 25 * s, y: water - 34 * s, width: 40 * s, height: 17 * s))
        hull.addRect(CGRect(x: x - 2 * s, y: water - 150 * s, width: 3.5 * s, height: 132 * s))
        add(hull, .near, depth: depth, tint: (1 - depth) * 0.3, bob: 3 * s, phase: ph)
        if sail {
            var sp = Path()
            sp.move(to: pp(x + 4 * s, water - 145 * s))
            sp.addLine(to: pp(x + 60 * s, water - 24 * s))
            sp.addLine(to: pp(x + 4 * s, water - 24 * s))
            sp.closeSubpath()
            add(sp, .sun, depth: depth, tint: 0.1, bob: 3 * s, phase: ph)
        }
    }

    mutating func lighthouse(x: Double, base: Double, h: Double, depth: Double) {
        add(Path(CGRect(x: x - 160, y: base, width: 420, height: 14)), .near, depth: depth)
        var tower = Path()
        tower.move(to: pp(x - 22, base))
        tower.addLine(to: pp(x - 14, base - h))
        tower.addLine(to: pp(x + 14, base - h))
        tower.addLine(to: pp(x + 22, base))
        tower.closeSubpath()
        add(tower, .sun, depth: depth, tint: 0.2, gradient: true)
        var bands = Path()
        for f in [0.25, 0.6] { bands.addRect(CGRect(x: x - 21 + 8 * f, y: base - h * f - h * 0.08, width: 42 - 16 * f, height: h * 0.12)) }
        add(bands, .warm, depth: depth)
        add(Path(CGRect(x: x - 15, y: base - h - 26, width: 30, height: 26)), .glow, depth: depth)
        var cap = Path()
        cap.move(to: pp(x - 20, base - h - 26))
        cap.addLine(to: pp(x, base - h - 44))
        cap.addLine(to: pp(x + 20, base - h - 26))
        cap.closeSubpath()
        add(cap, .near, depth: depth)
        items.append(.beam(PCBeam(origin: pp(x, base - h - 13), length: 950, depth: depth)))
    }

    /// Snowy peaks over a still lake, pines in front, the words written across the sky.
    mutating func lake() {
        horizon = 610
        sun = pp(r.d(300, 1300), r.d(380, 450))
        sunR = r.d(45, 70)
        clouds(3, y0: 60, y1: 280)
        surface = PCSurface(kind: .sky, box: CGRect(x: 230, y: 70, width: 1140, height: 190), depth: 0.05)
        items.append(.lyric)
        var mtn = Path(), snow = Path()
        var pts: [CGPoint] = [pp(-300, 520)]
        var x = -300.0
        while x < 1900 {
            x += r.d(90, 170)
            pts.append(pp(x, r.d(285, 420)))
            x += r.d(90, 170)
            pts.append(pp(x, r.d(470, 540)))
        }
        mtn.move(to: pp(-300, 650))
        for q in pts { mtn.addLine(to: q) }
        mtn.addLine(to: pp(Double(pts.last!.x), 650))
        mtn.closeSubpath()
        for i in stride(from: 1, to: pts.count - 1, by: 2) {
            let pk = pts[i], l = pts[i - 1], rr = pts[i + 1]
            let f = 0.28
            let lp = pp(Double(pk.x + (l.x - pk.x) * f), Double(pk.y + (l.y - pk.y) * f))
            let rp = pp(Double(pk.x + (rr.x - pk.x) * f), Double(pk.y + (rr.y - pk.y) * f))
            snow.move(to: pk)
            snow.addLine(to: rp)
            snow.addLine(to: pp(Double(lp.x + (rp.x - lp.x) * 0.66), Double(max(lp.y, rp.y)) - 4))
            snow.addLine(to: pp(Double(lp.x + (rp.x - lp.x) * 0.4), Double(max(lp.y, rp.y)) + 10))
            snow.addLine(to: lp)
            snow.closeSubpath()
        }
        let mtnS = PCShape(path: mtn, role: .far, tint: 0.1, depth: 0.12, gradient: true)
        var (ridgeP, hs) = PCGeo.ridge(&r, base: 600, amp: 22, freq: 0.006, bottom: 640)
        var tx = -300.0
        while tx < 1900 {
            PCGeo.pine(&ridgeP, x: tx, base: PCGeo.height(hs, tx) + 12, h: r.d(30, 64))
            tx += r.d(12, 26)
        }
        let ridgeS = PCShape(path: ridgeP, role: .mid, tint: 0.04, depth: 0.3, gradient: true)
        sea(top: horizon, bottom: 1100, mirror: [mtnS, ridgeS])
        items.append(.shape(mtnS))
        add(snow, .sun, depth: 0.12, tint: 0.15, alpha: 0.85)
        items.append(.shape(ridgeS))
        let cx = r.d(520, 1080)
        add(Path(CGRect(x: cx - 34, y: 584, width: 68, height: 30)), .plum, depth: 0.32, gradient: true)
        var cabinRoof = Path()
        cabinRoof.move(to: pp(cx - 42, 586))
        cabinRoof.addLine(to: pp(cx, 560))
        cabinRoof.addLine(to: pp(cx + 42, 586))
        cabinRoof.closeSubpath()
        cabinRoof.addRect(CGRect(x: cx + 20, y: 612, width: 90, height: 4))
        add(cabinRoof, .near, depth: 0.32)
        items.append(.windows(PCWindows(rects: [CGRect(x: cx - 22, y: 592, width: 14, height: 12),
                                                CGRect(x: cx + 6, y: 592, width: 14, height: 12)], on: [0.1, 0.4], depth: 0.32)))
        var fg = Path()
        for _ in 0..<(r.i(3) + 3) { PCGeo.pine(&fg, x: r.d(-150, 230), base: 1010, h: r.d(380, 700)) }
        for _ in 0..<(r.i(3) + 2) { PCGeo.pine(&fg, x: r.d(1380, 1750), base: 1010, h: r.d(380, 680)) }
        add(fg, .near, depth: 0.9, gradient: true)
        bushes(x0: -250, x1: 320, base: 1010, height: 70, role: .near, depth: 0.95)
        bushes(x0: 1300, x1: 1850, base: 1010, height: 70, role: .near, depth: 0.95)
        birds()
    }
    /// A ridge of pines sitting on a hill line.
    mutating func pineRidge(base: Double, amp: Double, hMin: Double, hMax: Double, role: PCRole,
                            tint: Double, depth: Double) {
        var (p, hs) = PCGeo.ridge(&r, base: base, amp: amp, freq: 0.004, bottom: 1150)
        var x = -300.0
        while x < 1900 {
            PCGeo.pine(&p, x: x, base: PCGeo.height(hs, x) + hMin * 0.25, h: r.d(hMin, hMax))
            x += r.d(hMin * 0.28, hMin * 0.55)
        }
        add(p, role, depth: depth, tint: tint, gradient: true)
    }

    /// A low band of mist between layers.
    mutating func mist(y: Double, h: Double, depth: Double, alpha: Double) {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: -300, y: y, width: 2200, height: h), cornerSize: CGSize(width: h / 2, height: h / 2))
        add(p, .skyLow, depth: depth, alpha: alpha)
    }

    /// Pine ridges fading into mist, a winding river through a meadow and a park sign.
    mutating func forest() {
        horizon = 660
        sun = pp(r.d(500, 1300), r.d(430, 520))
        sunR = r.d(55, 85)
        clouds(r.i(2) + 2, y0: 80, y1: 320)
        birds()
        pineRidge(base: 560, amp: 46, hMin: 24, hMax: 46, role: .far, tint: 0.28, depth: 0.12)
        mist(y: 545, h: 46, depth: 0.15, alpha: 0.35)
        pineRidge(base: 620, amp: 32, hMin: 40, hMax: 78, role: .far, tint: 0.08, depth: 0.22)
        mist(y: 615, h: 40, depth: 0.25, alpha: 0.3)
        pineRidge(base: 690, amp: 22, hMin: 70, hMax: 130, role: .mid, tint: 0, depth: 0.38)
        add(Path(CGRect(x: -300, y: 735, width: 2200, height: 420)), .ground, depth: 0.5, gradient: true)
        // the river winds from the trees to the bottom of the poster
        let vx = r.d(980, 1180), ph = r.d(0, 6.28), sway = r.d(60, 120)
        var left: [CGPoint] = [], right: [CGPoint] = []
        var y = 740.0
        while y <= 1110 {
            let u = (y - 740) / 370
            let cx = vx + sin(u * 3.4 + ph) * sway * u + (1000 - vx) * u * 0.4
            let w = 14 + 760 * pow(u, 1.5)
            left.append(pp(cx - w / 2, y))
            right.append(pp(cx + w / 2, y))
            y += 10
        }
        var river = Path()
        river.addLines(left + right.reversed())
        river.closeSubpath()
        add(river, .sea, depth: 0.55, gradient: true)
        var shine = Path()
        for k in stride(from: 3, to: left.count - 1, by: 4) {
            let a = left[k], b = right[k], w = Double(b.x - a.x)
            let x = Double(a.x) + w * r.d(0.2, 0.6), len = w * r.d(0.12, 0.3)
            let h = 1.5 + Double(k) / Double(left.count) * 3
            shine.addRoundedRect(in: CGRect(x: x, y: Double(a.y), width: len, height: h), cornerSize: CGSize(width: h / 2, height: h / 2))
        }
        add(shine, .sun, depth: 0.55, alpha: 0.55, bob: 3)
        let box = CGRect(x: r.d(70, 150), y: r.d(250, 300), width: r.d(520, 580), height: r.d(220, 245))
        board(box, postsTo: 860, depth: 0.7)
        var fg = Path()
        for _ in 0..<(r.i(2) + 2) { PCGeo.pine(&fg, x: r.d(-160, 40), base: 1010, h: r.d(560, 760)) }
        for _ in 0..<(r.i(3) + 2) { PCGeo.pine(&fg, x: r.d(1360, 1760), base: 1010, h: r.d(420, 720)) }
        add(fg, .near, depth: 0.9, gradient: true)
        bushes(x0: -250, x1: 380, base: 1010, height: 74, role: .near, depth: 0.95)
        bushes(x0: 1280, x1: 1850, base: 1010, height: 74, role: .near, depth: 0.95)
    }

    /// Snowy peaks in layers above the clouds, a pine valley, a chalet and a banner plane.
    mutating func mountains() {
        horizon = 720
        sun = pp(r.d(250, 1350), r.d(300, 400))
        sunR = r.d(48, 72)
        surface = PCSurface(kind: .banner, box: CGRect(x: 260, y: 70, width: 1080, height: 150), depth: 0.08)
        items.append(.lyric)
        let (far, farSnow) = PCGeo.peaks(&r, top: 250...360, valley: 450...540, gap: 130...240, bottom: 800, snow: 0.34)
        add(far, .far, depth: 0.1, tint: 0.22, gradient: true)
        add(farSnow, .sun, depth: 0.1, tint: 0.25, alpha: 0.85)
        clouds(4, y0: 470, y1: 580)
        let (mid, midSnow) = PCGeo.peaks(&r, top: 400...480, valley: 560...620, gap: 110...200, bottom: 820,
                                         snow: r.chance(0.6) ? 0.22 : 0)
        add(mid, .mid, depth: 0.24, tint: 0.08, gradient: true)
        add(midSnow, .sun, depth: 0.24, tint: 0.3, alpha: 0.7)
        mist(y: 600, h: 44, depth: 0.28, alpha: 0.3)
        pineRidge(base: 700, amp: 26, hMin: 44, hMax: 90, role: .mid, tint: 0, depth: 0.4)
        add(Path(CGRect(x: -300, y: 740, width: 2200, height: 420)), .ground, depth: 0.5, gradient: true)
        // chalet on the meadow
        let cx = r.d(640, 1000), cb = 800.0
        add(Path(CGRect(x: cx - 70, y: cb - 66, width: 140, height: 66)), .plum, depth: 0.55, gradient: true)
        var roof = Path()
        roof.move(to: pp(cx - 96, cb - 60))
        roof.addLine(to: pp(cx, cb - 124))
        roof.addLine(to: pp(cx + 96, cb - 60))
        roof.closeSubpath()
        add(roof, .accent, depth: 0.55, gradient: true)
        add(Path(CGRect(x: cx + 34, y: cb - 132, width: 14, height: 40)), .near, depth: 0.55)
        items.append(.windows(PCWindows(rects: [CGRect(x: cx - 50, y: cb - 50, width: 24, height: 22),
                                                CGRect(x: cx + 26, y: cb - 50, width: 24, height: 22),
                                                CGRect(x: cx - 12, y: cb - 96, width: 24, height: 20)],
                                        on: [0.1, 0.35, 0.6], depth: 0.55)))
        // a rocky ledge in front and tall pines on the other side
        let ledgeLeft = r.chance(0.5)
        var ledge = Path()
        let lx: (Double) -> Double = { ledgeLeft ? $0 : 1600 - $0 }
        ledge.move(to: pp(lx(-300), 1150))
        ledge.addLine(to: pp(lx(-300), 860))
        ledge.addLine(to: pp(lx(120), 840))
        ledge.addLine(to: pp(lx(260), 880))
        ledge.addLine(to: pp(lx(420), 900))
        ledge.addLine(to: pp(lx(560), 960))
        ledge.addLine(to: pp(lx(640), 1150))
        ledge.closeSubpath()
        add(ledge, .near, depth: 0.9, gradient: true)
        var fg = Path()
        for _ in 0..<(r.i(3) + 2) { PCGeo.pine(&fg, x: lx(r.d(1380, 1760)), base: 1010, h: r.d(420, 700)) }
        add(fg, .near, depth: 0.9, gradient: true)
        birds()
    }
}
