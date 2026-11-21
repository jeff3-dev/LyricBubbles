import SwiftUI

// MARK: - Scene description
//
// A Megaverse scene is a look-free description built from layered parametric parts:
// architecture shapes (with a role, a palette hue and a tone), lights, figures, the cover-art
// spots and a few location features. Each look renderer draws the same description its own way.
// Everything is in a 1600 × 1000 stage space, y down; the camera fills the window with it.

enum MegaStage {
    static let size = CGSize(width: 1600, height: 1000)
}

struct MegaShape {
    enum Role { case sky, wall, panel, trim, floor, ground, mass, furniture, fabric, glass, lit, metal }
    var path: Path
    var role: Role
    var hue: MegaHue
    var tone: Double          // 0 dark … 0.5 the palette colour … 1 light
    var tube = false          // Neon draws its edges as glowing tubes; Deco edges them in gold
}

struct MegaLight {
    enum Kind { case bulb, sconce, spot, pendant, lamp }
    var kind: Kind
    var pos: CGPoint
    var size: CGFloat
    var hue: MegaHue = .warm
    var aim = CGPoint.zero    // spot: where the beam lands
    var phase = 0.0
}

struct MegaCastMember {
    var kind: MegaFigureKind
    var feet: CGPoint
    var height: CGFloat
    var flip = false
    var slots: [Int] = []     // singer slots for the balloon tails (one per head)
    var phase = 0.0
    var walk: (from: CGFloat, to: CGFloat, period: Double)? = nil

    /// Where the feet are now (walkers cross the scene and loop).
    func feetNow(_ t: Double) -> (CGPoint, Bool) {
        guard let w = walk else { return (feet, flip) }
        let k = (t / w.period + phase).truncatingRemainder(dividingBy: 1)
        return (CGPoint(x: w.from + (w.to - w.from) * k, y: feet.y), w.to < w.from)
    }
}

struct MegaArtPlace {
    enum Kind { case painting, poster, billboard }
    var rect: CGRect
    var kind: Kind
}

struct MegaVinyl {
    var center: CGPoint
    var radius: CGFloat
    var squash: CGFloat       // vertical squash for the tabletop angle
    var plinth: CGRect
}

/// A pool table seen from a low angle: the felt is a trapezoid (far edge, near edge).
/// Balls live in table space (x 0…1 along the length, y 0…0.5 across) and are projected on.
struct MegaTable {
    var farY: CGFloat, farX0: CGFloat, farX1: CGFloat
    var nearY: CGFloat, nearX0: CGFloat, nearX1: CGFloat
    var ball: CGFloat                 // ball radius at the near edge, in stage units

    func project(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let v = y / 0.5
        let x0 = farX0 + (nearX0 - farX0) * v, x1 = farX1 + (nearX1 - farX1) * v
        return CGPoint(x: x0 + (x1 - x0) * x, y: farY + (nearY - farY) * v)
    }
    var felt: Path {
        var p = Path()
        p.addLines([CGPoint(x: farX0, y: farY), CGPoint(x: farX1, y: farY), CGPoint(x: nearX1, y: nearY), CGPoint(x: nearX0, y: nearY)])
        p.closeSubpath()
        return p
    }
}

/// A theatre marquee: bulbs in chase order and the blade sign's letters.
struct MegaMarquee {
    var bulbs: [CGPoint]
    var bulbSize: CGFloat = 26
    var blade: CGRect
    var word = "THEATRE"
}

struct MegaScene {
    let location: MegaLocation
    let variant: Int
    var backdrop: [MegaShape] = []   // sky and walls: the look draws its own extras right after these
    var mid: [MegaShape] = []        // architecture and props behind the figures
    var front: [MegaShape] = []      // in front of the figures
    var lights: [MegaLight] = []
    var cast: [MegaCastMember] = []
    var art: MegaArtPlace?
    var vinyl: MegaVinyl?
    var floorY: CGFloat = 760
    var outdoor = false
    var moon: CGPoint?
    /// Lit windows in ten buckets (bucket i lights up when the lit fraction passes i/10), drawn
    /// right after mid shape `after` so nearer buildings cover them.
    var windowLayers: [(after: Int, buckets: [Path])] = []
    var windowBase = 0.3              // lit fraction at silence
    var puddles: [CGRect] = []
    var carLane: CGFloat?
    var sunburst = CGPoint(x: 800, y: 560)
    var signRect = CGRect(x: 420, y: 70, width: 760, height: 170)
    var vents: [CGPoint] = []
    var ashtrays: [CGPoint] = []
    var blinds = false                // Noir throws venetian-blind shadows on the back wall
    var table: MegaTable?             // billiards: the balls break on accent hits
    var marquee: MegaMarquee?         // bulb chase lights step on beats
    var crates: [CGRect] = []         // record crates (front of the box); sleeves flip in them
    var sleeveWall: [CGRect] = []     // sleeves displayed face-out on the wall
}

// MARK: - Shape helpers

private func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

private func poly(_ pts: [(CGFloat, CGFloat)]) -> Path {
    var p = Path()
    p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
    p.closeSubpath()
    return p
}

private func rects(_ rs: [CGRect]) -> Path {
    var p = Path()
    for r in rs { p.addRect(r) }
    return p
}

private func line(_ pts: [(CGFloat, CGFloat)], _ w: CGFloat) -> Path {
    var p = Path()
    p.addLines(pts.map { CGPoint(x: $0.0, y: $0.1) })
    return p.strokedPath(StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
}

/// A stepped (ziggurat) top on a rect: the deco silhouette for towers and pilasters.
private func stepped(_ r: CGRect, steps: Int, stepH: CGFloat, inset: CGFloat) -> Path {
    var left: [CGPoint] = [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY + CGFloat(steps) * stepH)]
    for i in 0..<steps {
        let x = r.minX + inset * CGFloat(i + 1)
        left.append(CGPoint(x: x, y: r.minY + CGFloat(steps - i) * stepH))
        left.append(CGPoint(x: x, y: r.minY + CGFloat(steps - i - 1) * stepH))
    }
    let right = left.reversed().map { CGPoint(x: r.minX + r.maxX - $0.x, y: $0.y) }
    var p = Path()
    p.addLines(left + right)
    p.closeSubpath()
    return p
}

// MARK: - Builders

enum MegaScenes {
    private static var cache: [String: MegaScene] = [:]
    private static let lock = NSLock()

    /// The scene for a location and variant (0…2). Built once and cached.
    static func scene(_ location: MegaLocation, variant: Int) -> MegaScene {
        let key = "\(location.rawValue)|\(variant)"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let s: MegaScene
        switch location {
        case .stage: s = stage(variant)
        case .street: s = street(variant)
        case .rooftop: s = rooftop(variant)
        case .billiards: s = billiards(variant)
        case .marquee: s = marquee(variant)
        case .records: s = records(variant)
        default: s = lounge(variant)
        }
        lock.lock()
        cache[key] = s
        lock.unlock()
        return s
    }

    // 1. Lounge: wall painting and turntable; lamps pulse, smoke curls.
    static func lounge(_ v: Int) -> MegaScene {
        var s = MegaScene(location: .lounge, variant: v)
        var rng = Seeded(UInt64(101 + v * 7))
        s.blinds = true
        s.backdrop.append(MegaShape(path: Path(R(-500, -300, 2600, 1070)), role: .wall, hue: .mid, tone: 0.28))
        // Wainscot, chair rail and pilasters with stepped caps.
        s.mid.append(MegaShape(path: Path(R(-500, 560, 2600, 200)), role: .panel, hue: .base, tone: 0.42))
        s.mid.append(MegaShape(path: Path(R(-500, 552, 2600, 10)), role: .trim, hue: .accent, tone: 0.5, tube: true))
        var pil: [CGRect] = []
        for x in stride(from: CGFloat(-120), through: 1700, by: 300) where abs(x - 460) > 200 { pil.append(R(x, 120, 44, 432)) }
        for r in pil {
            s.mid.append(MegaShape(path: stepped(R(r.minX - 12, r.minY - 60, r.width + 24, r.height + 60), steps: 3, stepH: 18, inset: 8),
                                   role: .panel, hue: .mid, tone: 0.4, tube: true))
        }
        // Crown moulding.
        s.mid.append(MegaShape(path: Path(R(-500, 40, 2600, 14)), role: .trim, hue: .accent, tone: 0.5, tube: true))
        // The painting (cover art) with sconces either side.
        s.art = MegaArtPlace(rect: R(300, 200, 320, 320), kind: .painting)
        for x: CGFloat in [232, 688] {
            s.mid.append(MegaShape(path: poly([(x - 16, 340), (x + 16, 340), (x + 26, 300), (x - 26, 300)]), role: .metal, hue: .accent, tone: 0.55, tube: true))
            s.lights.append(MegaLight(kind: .sconce, pos: CGPoint(x: x, y: 296), size: 120, phase: Double(x)))
        }
        // Back bar: shelves of bottles under a mirror.
        s.mid.append(MegaShape(path: Path(roundedRect: R(1000, 250, 640, 300), cornerRadius: 6), role: .glass, hue: .pop, tone: 0.22, tube: true))
        s.mid.append(MegaShape(path: rects([R(1000, 360, 640, 8), R(1000, 460, 640, 8)]), role: .trim, hue: .accent, tone: 0.45))
        var bottles = Path()
        for shelf: CGFloat in [360, 460] {
            var x: CGFloat = 1020
            while x < 1620 {
                let h = CGFloat(40 + rng.next() * 46), w = CGFloat(14 + rng.next() * 12)
                bottles.addRoundedRect(in: R(x, shelf - h, w, h), cornerSize: CGSize(width: 5, height: 5))
                bottles.addRect(R(x + w * 0.3, shelf - h - 16, w * 0.4, 18))
                x += w + 6 + CGFloat(rng.next() * 18)
            }
        }
        s.mid.append(MegaShape(path: bottles, role: .glass, hue: .accent, tone: 0.35))
        // Pendant lamps over the bar.
        for (i, x) in [1110, 1320, 1530].enumerated() {
            let cx = CGFloat(x)
            s.mid.append(MegaShape(path: line([(cx, -20), (cx, 150)], 3), role: .metal, hue: .base, tone: 0.2))
            s.mid.append(MegaShape(path: poly([(cx - 18, 150), (cx + 18, 150), (cx + 46, 196), (cx - 46, 196)]), role: .metal, hue: .accent, tone: 0.5, tube: true))
            s.lights.append(MegaLight(kind: .pendant, pos: CGPoint(x: cx, y: 200), size: 150, aim: CGPoint(x: cx, y: 600), phase: Double(i) * 1.7))
        }
        // A floor lamp by the small stage.
        s.mid.append(MegaShape(path: line([(820 + 190, 760), (820 + 190, 390)], 6), role: .metal, hue: .base, tone: 0.2))
        s.mid.append(MegaShape(path: poly([(985, 390), (1035, 390), (1052, 330), (968, 330)]), role: .fabric, hue: .warm, tone: 0.5, tube: true))
        s.lights.append(MegaLight(kind: .lamp, pos: CGPoint(x: 1010, y: 370), size: 170, phase: 2.2))
        // The little round stage and the floor.
        s.mid.append(MegaShape(path: Path(R(-500, 760, 2600, 500)), role: .floor, hue: .base, tone: 0.3))
        s.mid.append(MegaShape(path: Path(ellipseIn: R(640, 735, 360, 50)), role: .furniture, hue: .accent, tone: 0.32, tube: true))
        // Singer on the little stage, the couple at the bar.
        s.cast.append(MegaCastMember(kind: .singer, feet: CGPoint(x: 815, y: 762), height: 420, slots: [0], phase: 0.2))
        s.cast.append(MegaCastMember(kind: .couple, feet: CGPoint(x: 1290, y: 790), height: 380, slots: [1, 2], phase: 0.6))
        // Bar counter in front.
        s.front.append(MegaShape(path: Path(R(1060, 600, 640, 420)), role: .furniture, hue: .mid, tone: 0.24, tube: false))
        s.front.append(MegaShape(path: Path(R(1040, 586, 680, 20)), role: .trim, hue: .accent, tone: 0.5, tube: true))
        var fluting = Path()
        for x in stride(from: CGFloat(1090), to: 1700, by: 46) { fluting.addRect(R(x, 630, 10, 360)) }
        s.front.append(MegaShape(path: fluting, role: .trim, hue: .accent, tone: 0.35))
        // Side table with the turntable.
        s.front.append(MegaShape(path: rects([R(150, 780, 18, 260), R(482, 780, 18, 260)]), role: .metal, hue: .base, tone: 0.18))
        s.front.append(MegaShape(path: Path(roundedRect: R(110, 760, 430, 30), cornerRadius: 8), role: .furniture, hue: .mid, tone: 0.3, tube: true))
        s.vinyl = MegaVinyl(center: CGPoint(x: 315, y: 712), radius: 150, squash: 0.32, plinth: R(130, 700, 390, 62))
        s.ashtrays = [CGPoint(x: 1180, y: 580)]
        s.sunburst = CGPoint(x: 815, y: 760)
        s.signRect = R(640, 70, 700, 150)
        return s
    }

    // 2. Jazz stage: poster beside the stage; sax bobs, spotlights sweep on beats.
    static func stage(_ v: Int) -> MegaScene {
        var s = MegaScene(location: .stage, variant: v)
        var rng = Seeded(UInt64(211 + v * 13))
        s.backdrop.append(MegaShape(path: Path(R(-500, -300, 2600, 1100)), role: .wall, hue: .base, tone: 0.35))
        // Back curtain inside the proscenium, with fold lines.
        s.mid.append(MegaShape(path: Path(R(330, 150, 1140, 560)), role: .fabric, hue: .accent, tone: 0.24))
        var folds = Path()
        for x in stride(from: CGFloat(360), to: 1460, by: 52) {
            folds.addRect(R(x, 150, 14, 560))
        }
        s.mid.append(MegaShape(path: folds, role: .fabric, hue: .accent, tone: 0.14))
        // Drum kit and a piano at the back.
        var kit = Path()
        kit.addEllipse(in: R(1170, 560, 130, 130))
        kit.addEllipse(in: R(1130, 560, 60, 36))
        kit.addEllipse(in: R(1280, 548, 70, 40))
        kit.addRect(R(1350, 470, 5, 220))
        kit.addEllipse(in: R(1300, 458, 110, 18))
        s.mid.append(MegaShape(path: kit, role: .furniture, hue: .base, tone: 0.16, tube: true))
        s.mid.append(MegaShape(path: poly([(380, 700), (380, 560), (560, 540), (700, 600), (700, 700)]), role: .furniture, hue: .base, tone: 0.12, tube: true))
        // Proscenium: a stepped deco arch (even-odd: frame with the opening cut out).
        var arch = Path(R(-500, -300, 2600, 1060))
        var opening = Path()
        opening.addLines([CGPoint(x: 330, y: 760), CGPoint(x: 330, y: 230), CGPoint(x: 380, y: 230), CGPoint(x: 380, y: 190),
                          CGPoint(x: 440, y: 190), CGPoint(x: 440, y: 150), CGPoint(x: 1360, y: 150), CGPoint(x: 1360, y: 190),
                          CGPoint(x: 1420, y: 190), CGPoint(x: 1420, y: 230), CGPoint(x: 1470, y: 230), CGPoint(x: 1470, y: 760)])
        opening.closeSubpath()
        arch.addPath(opening)
        s.mid.append(MegaShape(path: Path(arch.cgPath.normalized(using: .evenOdd)), role: .mass, hue: .mid, tone: 0.3))
        s.mid.append(MegaShape(path: opening.strokedPath(StrokeStyle(lineWidth: 12, lineJoin: .miter)), role: .trim, hue: .accent, tone: 0.5, tube: true))
        // Side drapes.
        s.mid.append(MegaShape(path: {
            var p = Path()
            p.move(to: CGPoint(x: 320, y: 140)); p.addLine(to: CGPoint(x: 520, y: 140))
            p.addQuadCurve(to: CGPoint(x: 400, y: 520), control: CGPoint(x: 420, y: 300))
            p.addQuadCurve(to: CGPoint(x: 440, y: 760), control: CGPoint(x: 380, y: 640))
            p.addLine(to: CGPoint(x: 320, y: 760)); p.closeSubpath(); return p
        }(), role: .fabric, hue: .accent, tone: 0.42, tube: true))
        s.mid.append(MegaShape(path: {
            var p = Path()
            p.move(to: CGPoint(x: 1480, y: 140)); p.addLine(to: CGPoint(x: 1280, y: 140))
            p.addQuadCurve(to: CGPoint(x: 1400, y: 520), control: CGPoint(x: 1380, y: 300))
            p.addQuadCurve(to: CGPoint(x: 1360, y: 760), control: CGPoint(x: 1420, y: 640))
            p.addLine(to: CGPoint(x: 1480, y: 760)); p.closeSubpath(); return p
        }(), role: .fabric, hue: .accent, tone: 0.42, tube: true))
        // Valance with scallops.
        var val = Path(R(320, 140, 1160, 50))
        for i in 0..<12 { val.addEllipse(in: R(320 + CGFloat(i) * 96.7, 160, 96.7, 54)) }
        s.mid.append(MegaShape(path: val, role: .fabric, hue: .accent, tone: 0.36, tube: false))
        // Marquee band over the arch for signage.
        s.signRect = R(520, 20, 760, 110)
        // Poster beside the stage.
        s.art = MegaArtPlace(rect: R(110, 270, 190, 250), kind: .poster)
        // Stage platform and the floor.
        s.mid.append(MegaShape(path: Path(R(-500, 780, 2600, 400)), role: .floor, hue: .base, tone: 0.22))
        s.mid.append(MegaShape(path: Path(R(300, 700, 1200, 82)), role: .floor, hue: .mid, tone: 0.42, tube: false))
        s.mid.append(MegaShape(path: Path(R(290, 694, 1220, 12)), role: .trim, hue: .accent, tone: 0.5, tube: true))
        // Footlights.
        for i in 0..<9 {
            s.lights.append(MegaLight(kind: .bulb, pos: CGPoint(x: 380 + CGFloat(i) * 130, y: 706), size: 34, phase: Double(i)))
        }
        // Spotlights from the fly loft.
        s.lights.append(MegaLight(kind: .spot, pos: CGPoint(x: 260, y: -60), size: 120, hue: .warm, aim: CGPoint(x: 820, y: 720), phase: 0))
        s.lights.append(MegaLight(kind: .spot, pos: CGPoint(x: 1340, y: -60), size: 120, hue: .pop, aim: CGPoint(x: 600, y: 720), phase: 2))
        s.floorY = 702
        s.sunburst = CGPoint(x: 900, y: 700)
        // The band.
        let swap = rng.next() < 0.5
        s.cast.append(MegaCastMember(kind: .singer, feet: CGPoint(x: 900, y: 704), height: 440, slots: [0], phase: 0.1))
        s.cast.append(MegaCastMember(kind: .sax, feet: CGPoint(x: swap ? 1120 : 640, y: 704), height: 430, flip: !swap, slots: [1], phase: 0.4))
        s.cast.append(MegaCastMember(kind: .bassist, feet: CGPoint(x: swap ? 640 : 1120, y: 704), height: 420, flip: swap, slots: [2], phase: 0.8))
        // Audience heads in the dark foreground.
        var heads = Path()
        var x: CGFloat = -80
        while x < 1700 {
            let r = CGFloat(34 + rng.next() * 12), y = CGFloat(905 + rng.next() * 30)
            heads.addEllipse(in: R(x - r, y - r * 1.15, r * 2, r * 2.3))
            heads.addRoundedRect(in: R(x - r * 2.3, y + r * 0.9, r * 4.6, 200), cornerSize: CGSize(width: r * 1.6, height: r * 1.6))
            x += CGFloat(110 + rng.next() * 60)
        }
        s.front.append(MegaShape(path: heads, role: .mass, hue: .base, tone: 0.04, tube: false))
        s.ashtrays = [CGPoint(x: 210, y: 880), CGPoint(x: 1380, y: 870)]
        return s
    }

    // 3. Rain-soaked street: poster on the wall; puddles ripple on the beat, a car passes.
    static func street(_ v: Int) -> MegaScene {
        var s = MegaScene(location: .street, variant: v)
        var rng = Seeded(UInt64(307 + v * 17))
        s.outdoor = true
        s.backdrop.append(MegaShape(path: Path(R(-500, -400, 2600, 1160)), role: .sky, hue: .sky, tone: 0.5))
        // Distant buildings up the street.
        var far = Path()
        var farWin: [[CGRect]] = Array(repeating: [], count: 10)
        var x: CGFloat = 470
        while x < 1140 {
            let w = CGFloat(70 + rng.next() * 90), top = CGFloat(160 + rng.next() * 260)
            if rng.next() < 0.4 {
                far.addPath(stepped(R(x, top - 60, w, 820 - top), steps: 3, stepH: 20, inset: w * 0.1))
            } else {
                far.addRect(R(x, top, w, 760 - top))
            }
            for wy in stride(from: top + 24, to: 700, by: 30) {
                for wx in stride(from: x + 10, to: x + w - 14, by: 20) {
                    farWin[Int(rng.next() * 10)].append(R(wx, wy, 8, 12))
                }
            }
            x += w + 4
        }
        s.mid.append(MegaShape(path: far, role: .mass, hue: .mid, tone: 0.22, tube: true))
        // Facades either side, with windows.
        let left = poly([(-500, 760), (-500, -100), (480, 40), (480, 760)])
        let right = poly([(2100, 760), (2100, -100), (1120, 20), (1120, 760)])
        s.mid.append(MegaShape(path: left, role: .wall, hue: .mid, tone: 0.3, tube: false))
        s.mid.append(MegaShape(path: right, role: .wall, hue: .mid, tone: 0.34, tube: false))
        var nearWin: [[CGRect]] = Array(repeating: [], count: 10)
        for row in 0..<6 {
            let y = CGFloat(110 + row * 70)
            for c in 0..<6 {
                let wx = CGFloat(-60 + c * 88)
                if wx > 440 { continue }
                nearWin[Int(rng.next() * 10)].append(R(wx, y + (480 - wx) * 0.06, 40, 48))
            }
            for c in 0..<5 {
                let wx = CGFloat(1170 + c * 92)
                if (1180...1440).contains(wx) && (360...640).contains(y) { continue }
                nearWin[Int(rng.next() * 10)].append(R(wx, y + (wx - 1120) * 0.03, 42, 48))
            }
        }
        s.windowLayers = [(0, farWin.map { rects($0) }), (2, nearWin.map { rects($0) })]
        s.windowBase = 0.35
        // Cornices and a fire escape.
        s.mid.append(MegaShape(path: line([(-500, -70), (480, 50)], 14), role: .trim, hue: .accent, tone: 0.45, tube: true))
        s.mid.append(MegaShape(path: line([(2100, -70), (1120, 30)], 14), role: .trim, hue: .accent, tone: 0.45, tube: true))
        var esc = Path()
        for y: CGFloat in [180, 320, 460] {
            esc.addRect(R(1480, y, 220, 8))
            esc.addPath(line([(1490, y), (1690, y + 140)], 5))
            for rx in stride(from: CGFloat(1480), through: 1700, by: 22) { esc.addRect(R(rx, y - 40, 3, 40)) }
        }
        s.mid.append(MegaShape(path: esc, role: .metal, hue: .base, tone: 0.1, tube: true))
        // Storefront: lit window and a striped awning.
        s.mid.append(MegaShape(path: Path(R(30, 590, 400, 150)), role: .lit, hue: .warm, tone: 0.6, tube: true))
        s.mid.append(MegaShape(path: rects([R(30, 590, 400, 8), R(226, 590, 8, 150)]), role: .mass, hue: .base, tone: 0.1))
        var stripes = Path()
        for i in 0..<8 { if i % 2 == 0 { stripes.addPath(poly([(CGFloat(10 + i * 56), 520), (CGFloat(66 + i * 56), 520), (CGFloat(70 + i * 56), 580), (CGFloat(6 + i * 56), 580)])) } }
        s.mid.append(MegaShape(path: poly([(10, 520), (458, 520), (470, 580), (-2, 580)]), role: .fabric, hue: .pop, tone: 0.5, tube: true))
        s.mid.append(MegaShape(path: stripes, role: .fabric, hue: .pop, tone: 0.8))
        // Poster pasted on the right-hand wall.
        s.art = MegaArtPlace(rect: R(1190, 380, 230, 270), kind: .poster)
        // Street lamp.
        s.mid.append(MegaShape(path: line([(920, 760), (920, 300), (930, 270), (990, 262)], 10), role: .metal, hue: .base, tone: 0.12, tube: true))
        s.mid.append(MegaShape(path: poly([(960, 262), (1020, 262), (1010, 290), (970, 290)]), role: .metal, hue: .base, tone: 0.2, tube: true))
        s.lights.append(MegaLight(kind: .lamp, pos: CGPoint(x: 990, y: 292), size: 200, aim: CGPoint(x: 990, y: 790), phase: 0.5))
        // Wet street, curb and puddles.
        s.mid.append(MegaShape(path: Path(R(-500, 760, 2600, 500)), role: .ground, hue: .base, tone: 0.3))
        s.mid.append(MegaShape(path: Path(R(-500, 790, 2600, 10)), role: .trim, hue: .mid, tone: 0.4))
        s.puddles = [R(140, 860, 300, 46), R(760, 900, 380, 54), R(1300, 850, 260, 40)]
        s.carLane = 840
        s.floorY = 790
        s.cast.append(MegaCastMember(kind: .detective, feet: CGPoint(x: 1010, y: 792), height: 400, flip: true, slots: [0], phase: 0.3))
        s.cast.append(MegaCastMember(kind: .commuter, feet: CGPoint(x: 300, y: 800), height: 360, slots: [1], phase: 0.15,
                                     walk: (from: -150, to: 1750, period: 26)))
        s.vents = [CGPoint(x: 640, y: 800), CGPoint(x: 1360, y: 805)]
        s.signRect = R(560, 120, 480, 150)
        s.sunburst = CGPoint(x: 800, y: 760)
        return s
    }

    // 4. Rooftop skyline: billboard frame; windows flicker on with energy.
    static func rooftop(_ v: Int) -> MegaScene {
        var s = MegaScene(location: .rooftop, variant: v)
        var rng = Seeded(UInt64(401 + v * 19))
        s.outdoor = true
        s.backdrop.append(MegaShape(path: Path(R(-500, -400, 2600, 1300)), role: .sky, hue: .sky, tone: 0.5))
        s.moon = CGPoint(x: v == 1 ? 260 : 1300, y: 150)
        // Two layers of skyline; the near one has a stepped spire.
        for layer in 0..<2 {
            var p = Path()
            var buckets: [[CGRect]] = Array(repeating: [], count: 10)
            var x: CGFloat = -300
            let base: CGFloat = layer == 0 ? 640 : 700
            while x < 1900 {
                let w = CGFloat(60 + rng.next() * (layer == 0 ? 80 : 130))
                let h = CGFloat((layer == 0 ? 160 : 120) + rng.next() * (layer == 0 ? 260 : 300))
                let top = base - h
                if layer == 1, rng.next() < 0.22 {
                    p.addPath(stepped(R(x, top - 90, w, h + 90 + 300), steps: 4, stepH: 22, inset: w * 0.08))
                    p.addRect(R(x + w / 2 - 2, top - 170, 4, 90))
                } else {
                    p.addRect(R(x, top, w, h + 300))
                }
                let step: CGFloat = layer == 0 ? 16 : 22
                for wy in stride(from: top + 14, to: base + 60, by: step) {
                    for wx in stride(from: x + 8, to: x + w - 10, by: step * 0.9) {
                        buckets[Int(rng.next() * 10)].append(R(wx, wy, layer == 0 ? 5 : 8, layer == 0 ? 7 : 11))
                    }
                }
                x += w + CGFloat(rng.next() * 20)
            }
            s.mid.append(MegaShape(path: p, role: .mass, hue: layer == 0 ? .mid : .base, tone: layer == 0 ? 0.28 : 0.3, tube: layer == 1))
            s.windowLayers.append((layer, buckets.map { rects($0) }))
        }
        s.windowBase = 0.22
        // Water tower on the left.
        var tower = Path()
        tower.addRoundedRect(in: R(130, 470, 210, 190), cornerSize: CGSize(width: 10, height: 10))
        tower.addPath(poly([(118, 476), (352, 476), (235, 400)]))
        for lx: CGFloat in [150, 225, 310] { tower.addRect(R(lx, 660, 12, 130)) }
        tower.addPath(line([(150, 790), (322, 680)], 6))
        tower.addPath(line([(322, 790), (150, 680)], 6))
        s.mid.append(MegaShape(path: tower, role: .furniture, hue: .base, tone: 0.16, tube: true))
        var bands = Path()
        for y: CGFloat in [520, 590] { bands.addRect(R(130, y, 210, 6)) }
        s.mid.append(MegaShape(path: bands, role: .trim, hue: .accent, tone: 0.4))
        // Billboard on a scaffold.
        s.mid.append(MegaShape(path: rects([R(1140, 520, 12, 280), R(1400, 520, 12, 280), R(1140, 640, 272, 8)]), role: .metal, hue: .base, tone: 0.14, tube: true))
        s.mid.append(MegaShape(path: Path(R(1040, 196, 470, 330)), role: .furniture, hue: .mid, tone: 0.38, tube: true))
        s.art = MegaArtPlace(rect: R(1060, 216, 430, 290), kind: .billboard)
        for lx: CGFloat in [1130, 1275, 1420] {
            s.mid.append(MegaShape(path: line([(lx, 196), (lx, 168), (lx + 24, 156)], 4), role: .metal, hue: .base, tone: 0.2))
            s.lights.append(MegaLight(kind: .pendant, pos: CGPoint(x: lx + 26, y: 162), size: 90, aim: CGPoint(x: lx + 30, y: 400), phase: Double(lx)))
        }
        // String lights across the roof.
        var cord = Path()
        cord.move(to: CGPoint(x: -100, y: 330))
        cord.addQuadCurve(to: CGPoint(x: 1040, y: 360), control: CGPoint(x: 470, y: 520))
        s.mid.append(MegaShape(path: cord.strokedPath(StrokeStyle(lineWidth: 3)), role: .metal, hue: .base, tone: 0.2))
        for i in 0..<13 {
            let k = CGFloat(i) / 12, a = CGFloat(-100), b = CGFloat(1040), c = CGFloat(470)
            let px = (1 - k) * (1 - k) * a + 2 * (1 - k) * k * c + k * k * b
            let py = (1 - k) * (1 - k) * 330 + 2 * (1 - k) * k * 520 + k * k * 360
            s.lights.append(MegaLight(kind: .bulb, pos: CGPoint(x: px, y: py + 8), size: 30, hue: i % 3 == 0 ? .pop : .warm, phase: Double(i) * 0.9))
        }
        // The roof and its parapet.
        s.mid.append(MegaShape(path: Path(R(-500, 790, 2600, 400)), role: .floor, hue: .base, tone: 0.2))
        s.cast.append(MegaCastMember(kind: .pair, feet: CGPoint(x: 760, y: 820), height: 400, slots: [0, 1], phase: 0.35))
        s.cast.append(MegaCastMember(kind: .sax, feet: CGPoint(x: 420, y: 822), height: 380, slots: [2], phase: 0.7))
        s.front.append(MegaShape(path: Path(R(-500, 830, 2600, 400)), role: .mass, hue: .base, tone: 0.14))
        s.front.append(MegaShape(path: Path(R(-500, 820, 2600, 16)), role: .trim, hue: .accent, tone: 0.45, tube: true))
        var tiles = Path()
        for x in stride(from: CGFloat(-480), to: 2100, by: 120) { tiles.addRect(R(x, 836, 4, 200)) }
        s.front.append(MegaShape(path: tiles, role: .trim, hue: .mid, tone: 0.3))
        s.vents = [CGPoint(x: 1500, y: 800), CGPoint(x: 60, y: 820)]
        s.floorY = 820
        s.signRect = R(260, 30, 760, 150)
        s.sunburst = CGPoint(x: 760, y: 820)
        return s
    }

    // 5. Billiard room: wall painting over the table; the rack breaks on a drop.
    static func billiards(_ v: Int) -> MegaScene {
        var s = MegaScene(location: .billiards, variant: v)
        var rng = Seeded(UInt64(503 + v * 23))
        s.blinds = true
        s.backdrop.append(MegaShape(path: Path(R(-500, -300, 2600, 1070)), role: .wall, hue: .mid, tone: 0.26))
        // Wainscot with raised panels, chair rail and crown.
        s.mid.append(MegaShape(path: Path(R(-500, 520, 2600, 240)), role: .panel, hue: .base, tone: 0.36))
        var raised = Path()
        for x in stride(from: CGFloat(-460), to: 2100, by: 190) { raised.addRect(R(x, 548, 150, 180)) }
        s.mid.append(MegaShape(path: raised, role: .panel, hue: .base, tone: 0.3, tube: true))
        s.mid.append(MegaShape(path: Path(R(-500, 512, 2600, 12)), role: .trim, hue: .accent, tone: 0.5, tube: true))
        s.mid.append(MegaShape(path: Path(R(-500, 30, 2600, 14)), role: .trim, hue: .accent, tone: 0.5, tube: true))
        // The painting (cover art) between two stepped pilasters.
        s.art = MegaArtPlace(rect: R(670, 160, 260, 260), kind: .painting)
        for x: CGFloat in [520, 1036] {
            s.mid.append(MegaShape(path: stepped(R(x, 100, 44, 412), steps: 3, stepH: 16, inset: 7), role: .panel, hue: .mid, tone: 0.4, tube: true))
        }
        // Scoring beads on a wire, left wall.
        s.mid.append(MegaShape(path: rects([R(90, 190, 360, 4), R(90, 230, 360, 4)]), role: .metal, hue: .base, tone: 0.2))
        var beads = Path()
        for (row, y) in [CGFloat(192), 232].enumerated() {
            var x: CGFloat = 100
            for i in 0..<14 {
                beads.addEllipse(in: R(x, y - 11, 22, 22))
                x += 24 + (i == 4 + row * 3 ? 120 : 0)
            }
        }
        s.mid.append(MegaShape(path: beads, role: .furniture, hue: .accent, tone: 0.45, tube: true))
        // Cue rack, right wall.
        s.mid.append(MegaShape(path: Path(roundedRect: R(1220, 150, 260, 340), cornerRadius: 6), role: .furniture, hue: .mid, tone: 0.32, tube: true))
        var cues = Path()
        for i in 0..<7 {
            let x = CGFloat(1248 + i * 34)
            cues.addPath(line([(x, 172), (x + 4, 470)], 7))
        }
        s.mid.append(MegaShape(path: cues, role: .trim, hue: .warm, tone: 0.45))
        s.mid.append(MegaShape(path: rects([R(1232, 170, 236, 10), R(1232, 452, 236, 12)]), role: .trim, hue: .accent, tone: 0.45))
        // Floor.
        s.mid.append(MegaShape(path: Path(R(-500, 760, 2600, 500)), role: .floor, hue: .base, tone: 0.28))
        // The table: rails, apron, legs. Felt and balls are drawn by MegaFX.billiards.
        let t = MegaTable(farY: 572, farX0: 500, farX1: 1100, nearY: 668, nearX0: 430, nearX1: 1170, ball: 13)
        s.table = t
        s.mid.append(MegaShape(path: poly([(470, 554), (1130, 554), (1210, 690), (390, 690)]), role: .furniture, hue: .mid, tone: 0.3, tube: true))
        s.mid.append(MegaShape(path: Path(R(400, 690, 800, 46)), role: .furniture, hue: .mid, tone: 0.22, tube: true))
        s.mid.append(MegaShape(path: rects([R(430, 736, 56, 40), R(1114, 736, 56, 40)]), role: .furniture, hue: .mid, tone: 0.18))
        s.mid.append(MegaShape(path: rects([R(400, 690, 800, 7)]), role: .trim, hue: .accent, tone: 0.45))
        // The long lamp over the table: three shades on a bar.
        s.mid.append(MegaShape(path: rects([R(560, -40, 4, 300), R(1036, -40, 4, 300)]), role: .metal, hue: .base, tone: 0.2))
        s.mid.append(MegaShape(path: Path(roundedRect: R(500, 256, 600, 16), cornerRadius: 4), role: .metal, hue: .accent, tone: 0.45, tube: true))
        for (i, x) in [CGFloat(590), 800, 1010].enumerated() {
            s.mid.append(MegaShape(path: poly([(x - 44, 272), (x + 44, 272), (x + 76, 326), (x - 76, 326)]), role: .glass, hue: .pop, tone: 0.42, tube: true))
            s.lights.append(MegaLight(kind: .pendant, pos: CGPoint(x: x, y: 328), size: 150, hue: .warm, aim: CGPoint(x: x, y: 640), phase: Double(i) * 1.3))
        }
        // The players: one bent over the break, one chalking up.
        let left = rng.next() < 0.5 || v == 0
        s.cast.append(MegaCastMember(kind: .shark, feet: CGPoint(x: left ? 300 : 1300, y: 800), height: 400, flip: !left, slots: [0], phase: 0.25))
        s.cast.append(MegaCastMember(kind: .chalker, feet: CGPoint(x: left ? 1330 : 270, y: 796), height: 400, flip: left, slots: [1], phase: 0.65))
        // A side table with a drink and an ashtray, front corner.
        s.front.append(MegaShape(path: rects([R(1472, 820, 14, 240)]), role: .metal, hue: .base, tone: 0.16))
        s.front.append(MegaShape(path: Path(ellipseIn: R(1380, 800, 200, 36)), role: .furniture, hue: .mid, tone: 0.3, tube: true))
        s.front.append(MegaShape(path: Path(roundedRect: R(1430, 744, 30, 62), cornerRadius: 4), role: .glass, hue: .warm, tone: 0.5, tube: true))
        s.ashtrays = [CGPoint(x: 1520, y: 800)]
        s.floorY = 760
        s.signRect = R(380, 34, 840, 100)
        s.sunburst = CGPoint(x: 800, y: 640)
        return s
    }

    // 6. Theatre marquee: the one-sheet in a lit case; bulbs chase on the beat.
    static func marquee(_ v: Int) -> MegaScene {
        var s = MegaScene(location: .marquee, variant: v)
        var rng = Seeded(UInt64(601 + v * 29))
        s.outdoor = true
        s.backdrop.append(MegaShape(path: Path(R(-500, -400, 2600, 1160)), role: .sky, hue: .sky, tone: 0.5))
        // Neighbouring buildings with windows, then the theatre's stepped facade.
        var side = Path()
        var win: [[CGRect]] = Array(repeating: [], count: 10)
        for (x0, x1, top) in [(CGFloat(-500), CGFloat(120), CGFloat(60)), (1480, 2100, 20)] {
            side.addRect(R(x0, top, x1 - x0, 760 - top))
            for wy in stride(from: top + 40, to: 470, by: 64) {
                for wx in stride(from: x0 + 30, to: x1 - 40, by: 70) { win[Int(rng.next() * 10)].append(R(wx, wy, 34, 40)) }
            }
        }
        s.mid.append(MegaShape(path: side, role: .mass, hue: .base, tone: 0.24, tube: true))
        s.windowLayers = [(0, win.map { rects($0) })]
        s.windowBase = 0.3
        s.mid.append(MegaShape(path: stepped(R(120, -120, 1360, 880), steps: 4, stepH: 40, inset: 70), role: .wall, hue: .mid, tone: 0.32, tube: true))
        // Fluted pilasters and a sunburst grille over the canopy.
        var flutes = Path()
        for x: CGFloat in [1360] { for k in 0..<3 { flutes.addRect(R(x + CGFloat(k) * 22, 40, 10, 720)) } }
        s.mid.append(MegaShape(path: flutes, role: .trim, hue: .accent, tone: 0.4))
        var fan = Path()
        let fc = CGPoint(x: 840, y: 210)
        for k in 0..<11 where k % 2 == 0 {
            let a0 = Double.pi + Double.pi * Double(k) / 11, a1 = Double.pi + Double.pi * Double(k + 1) / 11
            fan.move(to: fc)
            fan.addLine(to: CGPoint(x: fc.x + cos(a0) * 230, y: fc.y + sin(a0) * 230))
            fan.addLine(to: CGPoint(x: fc.x + cos(a1) * 230, y: fc.y + sin(a1) * 230))
            fan.closeSubpath()
        }
        s.mid.append(MegaShape(path: fan, role: .trim, hue: .accent, tone: 0.42, tube: true))
        // Doors and the box office.
        s.mid.append(MegaShape(path: Path(R(540, 520, 520, 240)), role: .lit, hue: .warm, tone: 0.6, tube: true))
        var mullions = Path()
        for x in stride(from: CGFloat(540), through: 1060, by: 104) { mullions.addRect(R(x - 4, 520, 8, 240)) }
        mullions.addRect(R(540, 600, 520, 6))
        s.mid.append(MegaShape(path: mullions, role: .metal, hue: .base, tone: 0.12))
        var booth = Path()
        booth.move(to: CGPoint(x: 730, y: 760)); booth.addLine(to: CGPoint(x: 730, y: 590))
        booth.addQuadCurve(to: CGPoint(x: 870, y: 590), control: CGPoint(x: 800, y: 520))
        booth.addLine(to: CGPoint(x: 870, y: 760)); booth.closeSubpath()
        s.mid.append(MegaShape(path: booth, role: .furniture, hue: .accent, tone: 0.36, tube: true))
        s.mid.append(MegaShape(path: Path(roundedRect: R(752, 610, 96, 70), cornerRadius: 30), role: .lit, hue: .warm, tone: 0.7))
        // The one-sheet case (cover art) and a "coming soon" case.
        s.art = MegaArtPlace(rect: R(330, 480, 160, 230), kind: .poster)
        s.mid.append(MegaShape(path: Path(R(1110, 472, 176, 246)), role: .furniture, hue: .accent, tone: 0.4, tube: true))
        s.mid.append(MegaShape(path: Path(R(1118, 480, 160, 230)), role: .lit, hue: .pop, tone: 0.55))
        // Sidewalk and the street.
        s.mid.append(MegaShape(path: Path(R(-500, 760, 2600, 500)), role: .ground, hue: .base, tone: 0.3))
        s.mid.append(MegaShape(path: Path(R(-500, 800, 2600, 10)), role: .trim, hue: .mid, tone: 0.4))
        // The canopy: a lit soffit, the letterboard face and its stepped crest.
        s.mid.append(MegaShape(path: poly([(330, 430), (1350, 430), (1440, 474), (250, 474)]), role: .lit, hue: .warm, tone: 0.5, tube: true))
        s.mid.append(MegaShape(path: Path(R(330, 236, 1020, 196)), role: .furniture, hue: .mid, tone: 0.2, tube: true))
        s.mid.append(MegaShape(path: Path(R(372, 262, 936, 144)), role: .panel, hue: .base, tone: 0.82))
        s.mid.append(MegaShape(path: stepped(R(600, 176, 480, 62), steps: 2, stepH: 20, inset: 50), role: .trim, hue: .accent, tone: 0.5, tube: true))
        s.signRect = R(388, 270, 904, 128)
        // Bulbs round the letterboard (in chase order), then a row under the soffit.
        var bulbs: [CGPoint] = []
        let fr = R(346, 248, 988, 172)
        for k in 0..<28 { bulbs.append(CGPoint(x: fr.minX + fr.width * CGFloat(k) / 28, y: fr.minY)) }
        for k in 0..<5 { bulbs.append(CGPoint(x: fr.maxX, y: fr.minY + fr.height * CGFloat(k) / 5)) }
        for k in 0..<28 { bulbs.append(CGPoint(x: fr.maxX - fr.width * CGFloat(k) / 28, y: fr.maxY)) }
        for k in 0..<5 { bulbs.append(CGPoint(x: fr.minX, y: fr.maxY - fr.height * CGFloat(k) / 5)) }
        for k in 0..<24 { bulbs.append(CGPoint(x: 290 + CGFloat(k) * 47, y: 466)) }
        // The blade sign, up the left of the facade.
        let blade = R(204, -10, 92, 430)
        s.mid.append(MegaShape(path: rects([R(296, 30, 40, 10), R(296, 300, 40, 10)]), role: .metal, hue: .base, tone: 0.2))
        s.mid.append(MegaShape(path: stepped(blade.insetBy(dx: -8, dy: -8), steps: 2, stepH: 18, inset: 12), role: .furniture, hue: .accent, tone: 0.3, tube: true))
        for k in 0..<10 { bulbs.append(CGPoint(x: blade.minX - 2, y: blade.minY + 20 + CGFloat(k) * 46)) }
        for k in 0..<10 { bulbs.append(CGPoint(x: blade.maxX + 2, y: blade.maxY - 20 - CGFloat(k) * 46)) }
        s.marquee = MegaMarquee(bulbs: bulbs, blade: blade, word: v == 1 ? "CINEMA" : "THEATRE")
        // A couple under the canopy reading the one-sheet; someone walks by.
        s.cast.append(MegaCastMember(kind: .pair, feet: CGPoint(x: 520, y: 800), height: 380, flip: true, slots: [0, 1], phase: 0.4))
        s.cast.append(MegaCastMember(kind: .commuter, feet: CGPoint(x: 1300, y: 812), height: 370, slots: [2], phase: 0.55,
                                     walk: (from: 1750, to: -150, period: 30)))
        s.puddles = [R(200, 880, 280, 40), R(1060, 900, 340, 50)]
        s.carLane = 850
        s.floorY = 800
        s.sunburst = CGPoint(x: 800, y: 470)
        return s
    }

    // 7. Record shop: sleeves in the crates and on the wall, the turntable on the counter.
    static func records(_ v: Int) -> MegaScene {
        var s = MegaScene(location: .records, variant: v)
        s.backdrop.append(MegaShape(path: Path(R(-500, -300, 2600, 1070)), role: .wall, hue: .mid, tone: 0.3))
        // Shop window on the left with the street beyond.
        s.mid.append(MegaShape(path: Path(R(-120, 120, 330, 470)), role: .glass, hue: .sky, tone: 0.2, tube: true))
        s.mid.append(MegaShape(path: rects([R(-120, 350, 330, 8), R(40, 120, 8, 470)]), role: .metal, hue: .base, tone: 0.14))
        // Shelves of sleeves face-out on the back wall.
        for row in 0..<2 {
            let y = CGFloat(140 + row * 190)
            s.mid.append(MegaShape(path: Path(R(260, y + 150, 900, 12)), role: .trim, hue: .accent, tone: 0.45, tube: true))
            for c in 0..<6 { s.sleeveWall.append(R(278 + CGFloat(c) * 148, y, 136, 136)) }
        }
        // Pendant globes.
        for (i, x) in [CGFloat(480), 980].enumerated() {
            s.mid.append(MegaShape(path: line([(x, -40), (x, 70)], 3), role: .metal, hue: .base, tone: 0.2))
            s.mid.append(MegaShape(path: Path(ellipseIn: R(x - 30, 70, 60, 48)), role: .glass, hue: .warm, tone: 0.55, tube: true))
            s.lights.append(MegaLight(kind: .pendant, pos: CGPoint(x: x, y: 118), size: 130, aim: CGPoint(x: x, y: 700), phase: Double(i) * 2))
        }
        // Speaker cabinets by the counter.
        var spk = Path(roundedRect: R(1430, 230, 150, 230), cornerRadius: 8)
        spk.addEllipse(in: R(1460, 250, 90, 90))
        spk.addEllipse(in: R(1470, 360, 70, 70))
        s.mid.append(MegaShape(path: spk, role: .furniture, hue: .base, tone: 0.18, tube: true))
        s.mid.append(MegaShape(path: Path(R(-500, 760, 2600, 500)), role: .floor, hue: .base, tone: 0.3))
        // The browser behind the crates and the clerk behind the counter.
        s.cast.append(MegaCastMember(kind: .digger, feet: CGPoint(x: v == 1 ? 900 : 560, y: 776), height: 400, flip: v == 1, slots: [0], phase: 0.3))
        s.cast.append(MegaCastMember(kind: .listener, feet: CGPoint(x: 1360, y: 800), height: 410, flip: true, slots: [1], phase: 0.7))
        // The counter with the turntable.
        s.front.append(MegaShape(path: Path(R(1180, 560, 520, 460)), role: .furniture, hue: .mid, tone: 0.26, tube: true))
        s.front.append(MegaShape(path: Path(R(1160, 548, 560, 18)), role: .trim, hue: .accent, tone: 0.5, tube: true))
        var grooves = Path()
        for y in stride(from: CGFloat(610), to: 1000, by: 60) { grooves.addRect(R(1200, y, 500, 6)) }
        s.front.append(MegaShape(path: grooves, role: .trim, hue: .accent, tone: 0.32))
        s.vinyl = MegaVinyl(center: CGPoint(x: 1370, y: 514), radius: 120, squash: 0.3, plinth: R(1220, 500, 300, 50))
        // The crates on a low bench.
        s.crates = [R(120, 690, 290, 150), R(440, 690, 290, 150), R(760, 690, 290, 150)]
        s.front.append(MegaShape(path: rects([R(140, 870, 16, 200), R(1010, 870, 16, 200)]), role: .metal, hue: .base, tone: 0.16))
        s.front.append(MegaShape(path: Path(R(100, 840, 970, 32)), role: .furniture, hue: .mid, tone: 0.34, tube: true))
        s.floorY = 760
        s.signRect = R(300, 20, 840, 100)
        s.sunburst = CGPoint(x: 700, y: 760)
        return s
    }
}
