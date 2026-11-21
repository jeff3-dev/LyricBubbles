import SwiftUI

// MARK: - Megaverse silhouettes
//
// Generic animated figures, built like `GothamFigures`: each stands with its feet at y = 0 and
// is about 1 tall (up is negative y). They're small paths, rebuilt each frame as they move.

private func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

private func poly(_ pts: [(Double, Double)]) -> Path {
    var p = Path()
    p.addLines(pts.map { P($0.0, $0.1) })
    p.closeSubpath()
    return p
}

private func oval(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
    Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
}

private func limb(_ pts: [(Double, Double)], _ w: Double) -> Path {
    var p = Path()
    p.addLines(pts.map { P($0.0, $0.1) })
    return p.strokedPath(StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
}

private func rotated(_ p: Path, _ a: Double, about c: CGPoint) -> Path {
    p.applying(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a).translatedBy(x: -c.x, y: -c.y))
}

private func rot(_ q: CGPoint, _ a: Double, about c: CGPoint) -> CGPoint {
    q.applying(CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a).translatedBy(x: -c.x, y: -c.y))
}

/// A figure at one moment: its parts, where each head is (for balloon tails), and where its
/// cigarette smoke starts, if it smokes.
struct MegaPose {
    var parts: [Path]
    var heads: [CGPoint]
    var smoke: CGPoint?
}

enum MegaFigureKind: Int, CaseIterable {
    case singer, sax, bassist, couple, pair, detective, commuter, shark, chalker, digger, listener

    func pose(t: Double, beat: Double, seed: Double) -> MegaPose {
        switch self {
        case .singer: Self.singer(t, beat, seed)
        case .sax: Self.sax(t, beat, seed)
        case .bassist: Self.bassist(t, beat, seed)
        case .couple: Self.couple(t, beat, seed)
        case .pair: Self.pair(t, beat, seed)
        case .detective: Self.detective(t, beat, seed)
        case .commuter: Self.commuter(t, beat, seed)
        case .shark: Self.shark(t, beat, seed)
        case .chalker: Self.chalker(t, beat, seed)
        case .digger: Self.digger(t, beat, seed)
        case .listener: Self.listener(t, beat, seed)
        }
    }

    // A man in a suit: legs, jacket, head and hat. Returns parts and the head centre.
    private static func man(x: Double, lean: Double, hat: Bool = true, stride: Double = 0) -> ([Path], CGPoint) {
        let hip = P(x, -0.47)
        var parts: [Path] = []
        parts.append(limb([(x - 0.035, -0.48), (x - 0.04 - stride, -0.24), (x - 0.045 - stride * 1.6, -0.02)], 0.06))
        parts.append(limb([(x + 0.035, -0.48), (x + 0.04 + stride, -0.24), (x + 0.045 + stride * 1.6, -0.02)], 0.06))
        parts.append(poly([(x - 0.075 - stride * 1.6, 0), (x - 0.005 - stride * 1.6, 0), (x - 0.01 - stride * 1.6, -0.035), (x - 0.07 - stride * 1.6, -0.035)]))
        parts.append(poly([(x + 0.005 + stride * 1.6, 0), (x + 0.085 + stride * 1.6, 0), (x + 0.08 + stride * 1.6, -0.035), (x + 0.01 + stride * 1.6, -0.035)]))
        var upper: [Path] = []
        upper.append(poly([(x - 0.1, -0.8), (x + 0.1, -0.8), (x + 0.085, -0.44), (x - 0.085, -0.44)]))
        upper.append(oval(x, -0.88, 0.052, 0.062))
        upper.append(Path(CGRect(x: x - 0.025, y: -0.84, width: 0.05, height: 0.05)))
        if hat {
            upper.append(Path(CGRect(x: x - 0.09, y: -0.925, width: 0.18, height: 0.018)))
            upper.append(poly([(x - 0.055, -0.925), (x + 0.055, -0.925), (x + 0.048, -0.99), (x - 0.048, -0.99)]))
        }
        parts += upper.map { rotated($0, lean, about: hip) }
        return (parts, rot(P(x, -0.88), lean, about: hip))
    }

    /// Singer at the mic: a long gown, swaying, one hand on the mic.
    private static func singer(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let sway = 0.05 * sin(t * 1.4 + seed * 6) + 0.02 * beat
        let feet = P(0, 0)
        var body: [Path] = []
        var gown = Path()
        gown.move(to: P(-0.075, -0.8))
        gown.addLine(to: P(0.075, -0.8))
        gown.addQuadCurve(to: P(0.055, -0.56), control: P(0.09, -0.68))
        gown.addQuadCurve(to: P(0.06, -0.24), control: P(0.03, -0.4))
        gown.addQuadCurve(to: P(0.2, 0), control: P(0.1, -0.08))
        gown.addLine(to: P(-0.17, 0))
        gown.addQuadCurve(to: P(-0.06, -0.24), control: P(-0.09, -0.08))
        gown.addQuadCurve(to: P(-0.055, -0.56), control: P(-0.03, -0.4))
        gown.addQuadCurve(to: P(-0.075, -0.8), control: P(-0.09, -0.68))
        gown.closeSubpath()
        body.append(gown)
        body.append(Path(CGRect(x: -0.02, y: -0.86, width: 0.04, height: 0.07)))
        body.append(oval(0, -0.9, 0.05, 0.06))
        body.append(oval(-0.025, -0.92, 0.06, 0.055))          // hair
        body.append(oval(-0.07, -0.88, 0.035, 0.05))           // curl
        let mic = P(0.11, -0.89)
        let hand = P(0.1, -0.86 + 0.01 * sin(t * 2))
        body.append(limb([(0.07, -0.78), (0.15, -0.7), (hand.x, hand.y)], 0.035))
        let arm = 0.25 * sin(t * 0.9 + seed * 3) + 0.4 * beat
        body.append(limb([(-0.07, -0.78), (-0.11 - 0.05 * arm, -0.62), (-0.1 - 0.12 * arm, -0.5 - 0.1 * arm)], 0.032))
        var parts = body.map { rotated($0, sway, about: feet) }
        // The mic stand stays put.
        parts.append(limb([(0.15, 0), (0.15, -0.8), (mic.x, mic.y)], 0.016))
        parts.append(poly([(0.07, 0), (0.23, 0), (0.15, -0.025)]))
        parts.append(oval(mic.x, mic.y, 0.018, 0.026))
        return MegaPose(parts: parts, heads: [rot(P(0, -0.9), sway, about: feet)], smoke: nil)
    }

    /// Sax player leaning back, the horn bobbing on the beat.
    private static func sax(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let lean = -0.06 - 0.08 * beat + 0.03 * sin(t * 2.1 + seed * 5)
        var (parts, head) = man(x: 0, lean: lean)
        let hip = P(0, -0.47)
        var horn = Path()
        horn.move(to: P(0.03, -0.84))
        horn.addLine(to: P(0.09, -0.78))
        horn.addQuadCurve(to: P(0.06, -0.5), control: P(0.12, -0.62))
        horn.addQuadCurve(to: P(0.17, -0.46), control: P(0.08, -0.4))
        let hornPath = horn.strokedPath(StrokeStyle(lineWidth: 0.035, lineCap: .round))
        let bell = poly([(0.15, -0.5), (0.22, -0.56), (0.24, -0.5), (0.18, -0.44)])
        parts.append(rotated(hornPath, lean, about: hip))
        parts.append(rotated(bell, lean, about: hip))
        parts.append(rotated(limb([(0.08, -0.76), (0.12, -0.66), (0.09, -0.62)], 0.032), lean, about: hip))
        parts.append(rotated(limb([(-0.08, -0.76), (-0.02, -0.6), (0.07, -0.54)], 0.032), lean, about: hip))
        return MegaPose(parts: parts, heads: [head], smoke: nil)
    }

    /// Bassist beside an upright bass, plucking.
    private static func bassist(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let sway = 0.03 * sin(t * 1.6 + seed * 4)
        var (parts, head) = man(x: -0.06, lean: sway)
        let pluck = 0.03 * beat
        var bass = Path()
        bass.addEllipse(in: CGRect(x: 0.02, y: -0.36, width: 0.26, height: 0.34))
        bass.addEllipse(in: CGRect(x: 0.05, y: -0.58, width: 0.2, height: 0.26))
        bass.addRect(CGRect(x: 0.08, y: -0.42, width: 0.14, height: 0.1))
        bass.addRect(CGRect(x: 0.137, y: -1.08, width: 0.026, height: 0.54))
        bass.addEllipse(in: CGRect(x: 0.125, y: -1.12, width: 0.05, height: 0.06))
        bass.addRect(CGRect(x: 0.145, y: -0.02, width: 0.01, height: 0.04))
        parts.append(rotated(bass, -0.12, about: P(0.15, 0)))
        parts.append(limb([(-0.0, -0.76), (0.08, -0.82), (0.12, -0.88)], 0.03))
        parts.append(limb([(-0.0, -0.7), (0.06, -0.56), (0.13 + pluck, -0.47)], 0.03))
        return MegaPose(parts: parts, heads: [head], smoke: nil)
    }

    private static func stool(_ x: Double) -> [Path] {
        [oval(x, -0.42, 0.075, 0.018), Path(CGRect(x: x - 0.01, y: -0.42, width: 0.02, height: 0.42)),
         oval(x, -0.14, 0.05, 0.008), poly([(x - 0.07, 0), (x + 0.07, 0), (x, -0.03)])]
    }

    /// Two people on bar stools, leaning in. He smokes.
    private static func couple(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let lean = 0.04 * sin(t * 0.8 + seed * 7)
        var parts: [Path] = stool(-0.17) + stool(0.17)
        // Her: facing right, updo, dress.
        let hipL = P(-0.17, -0.45)
        var her: [Path] = []
        her.append(poly([(-0.23, -0.44), (-0.08, -0.44), (-0.06, -0.38), (-0.22, -0.38)]))   // lap
        her.append(limb([(-0.08, -0.41), (-0.06, -0.12), (-0.03, -0.02)], 0.04))
        her.append(limb([(-0.1, -0.41), (-0.11, -0.12), (-0.07, -0.02)], 0.04))
        var dressTop = poly([(-0.22, -0.43), (-0.12, -0.43), (-0.135, -0.73), (-0.205, -0.73)])
        dressTop = rotated(dressTop, 0.08 + lean, about: hipL)
        her.append(dressTop)
        let headL = rot(P(-0.16, -0.8), 0.08 + lean, about: hipL)
        her.append(oval(headL.x, headL.y, 0.045, 0.055))
        her.append(oval(headL.x - 0.02, headL.y - 0.055, 0.035, 0.03))
        her.append(rotated(limb([(-0.14, -0.7), (-0.08, -0.6), (-0.02, -0.64)], 0.026), 0.08 + lean, about: hipL))
        parts += her
        // Him: facing left, hat.
        let hipR = P(0.17, -0.45)
        var him: [Path] = []
        him.append(poly([(0.08, -0.44), (0.24, -0.44), (0.23, -0.38), (0.06, -0.38)]))
        him.append(limb([(0.08, -0.41), (0.06, -0.12), (0.04, -0.02)], 0.045))
        him.append(limb([(0.11, -0.41), (0.12, -0.12), (0.1, -0.02)], 0.045))
        let torso = poly([(0.11, -0.43), (0.25, -0.43), (0.23, -0.78), (0.1, -0.78)])
        him.append(rotated(torso, -0.08 - lean * 0.6, about: hipR))
        let headR = rot(P(0.17, -0.85), -0.08 - lean * 0.6, about: hipR)
        him.append(oval(headR.x, headR.y, 0.05, 0.058))
        him.append(Path(CGRect(x: headR.x - 0.085, y: headR.y - 0.045, width: 0.17, height: 0.016)))
        him.append(poly([(headR.x - 0.05, headR.y - 0.045), (headR.x + 0.05, headR.y - 0.045), (headR.x + 0.045, headR.y - 0.1), (headR.x - 0.045, headR.y - 0.1)]))
        let hand = rot(P(0.06, -0.66), -0.08 - lean * 0.6, about: hipR)
        him.append(rotated(limb([(0.12, -0.74), (0.1, -0.6), (0.06, -0.66)], 0.03), -0.08 - lean * 0.6, about: hipR))
        him.append(limb([(hand.x, hand.y), (hand.x - 0.04, hand.y - 0.01)], 0.008))
        parts += him
        return MegaPose(parts: parts, heads: [headL, headR], smoke: P(hand.x - 0.04, hand.y - 0.01))
    }

    /// Two people standing close at the ledge, arm in arm, swaying.
    private static func pair(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let sway = 0.035 * sin(t * 0.9 + seed * 3)
        let feet = P(0, 0)
        var parts: [Path] = []
        // Her: dress and long hair.
        var dress = Path()
        dress.move(to: P(-0.17, -0.8)); dress.addLine(to: P(-0.05, -0.8))
        dress.addLine(to: P(-0.06, -0.55)); dress.addQuadCurve(to: P(0.0, -0.18), control: P(-0.02, -0.3))
        dress.addLine(to: P(-0.22, -0.18)); dress.addQuadCurve(to: P(-0.16, -0.55), control: P(-0.2, -0.3))
        dress.closeSubpath()
        parts.append(dress)
        parts.append(limb([(-0.14, -0.2), (-0.14, 0)], 0.03))
        parts.append(limb([(-0.08, -0.2), (-0.08, 0)], 0.03))
        parts.append(Path(CGRect(x: -0.13, y: -0.86, width: 0.04, height: 0.07)))
        parts.append(oval(-0.11, -0.9, 0.048, 0.058))
        parts.append(poly([(-0.16, -0.93), (-0.06, -0.95), (-0.08, -0.74), (-0.17, -0.76)]))
        // Him.
        let (man, head) = Self.man(x: 0.06, lean: -0.05)
        parts += man
        parts.append(limb([(-0.04, -0.76), (0.02, -0.7), (0.05, -0.74)], 0.03))
        let out = parts.map { rotated($0, sway, about: feet) }
        return MegaPose(parts: out, heads: [rot(P(-0.11, -0.9), sway, about: feet), rot(head, sway, about: feet)], smoke: nil)
    }

    /// A detective in a trench coat and fedora, collar up, cigarette lit.
    private static func detective(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let breathe = 0.006 * sin(t * 1.1 + seed * 2)
        var coat = Path()
        coat.move(to: P(-0.08, -0.82)); coat.addLine(to: P(0.08, -0.82))
        coat.addLine(to: P(0.12, -0.74))
        coat.addLine(to: P(0.14, -0.2)); coat.addLine(to: P(0.16, -0.16))
        coat.addLine(to: P(-0.16, -0.16)); coat.addLine(to: P(-0.13, -0.2))
        coat.addLine(to: P(-0.12, -0.74)); coat.closeSubpath()
        var parts: [Path] = [coat.applying(CGAffineTransform(scaleX: 1 + breathe * 4, y: 1))]
        parts.append(limb([(-0.05, -0.18), (-0.055, -0.02)], 0.05))
        parts.append(limb([(0.05, -0.18), (0.055, -0.02)], 0.05))
        parts.append(poly([(-0.1, 0), (-0.02, 0), (-0.03, -0.035), (-0.09, -0.035)]))
        parts.append(poly([(0.02, 0), (0.11, 0), (0.1, -0.035), (0.03, -0.035)]))
        parts.append(poly([(-0.07, -0.86), (0.07, -0.86), (0.1, -0.76), (-0.1, -0.76)]))   // collar
        parts.append(oval(0, -0.9 - breathe, 0.05, 0.06))
        parts.append(Path(CGRect(x: -0.11, y: -0.94 - breathe, width: 0.22, height: 0.018)))
        parts.append(poly([(-0.06, -0.94), (0.06, -0.94), (0.05, -1.01), (0.0, -0.99), (-0.05, -1.01)]))
        parts.append(limb([(0.04, -0.875), (0.085, -0.87)], 0.008))   // cigarette
        return MegaPose(parts: parts, heads: [P(0, -0.9)], smoke: P(0.09, -0.875))
    }

    /// Someone walking with an umbrella.
    private static func commuter(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let stride = 0.05 * sin(t * 4.2 + seed * 9)
        let bob = 0.008 * abs(cos(t * 4.2 + seed * 9))
        var (parts, head) = man(x: 0, lean: 0.04, hat: false, stride: stride)
        parts = parts.map { $0.applying(CGAffineTransform(translationX: 0, y: -bob)) }
        head.y -= bob
        var dome = Path()
        dome.move(to: P(-0.26, -1.0 - bob))
        dome.addQuadCurve(to: P(0.26, -1.0 - bob), control: P(0, -1.32 - bob))
        for i in 0..<4 {
            let x0 = -0.26 + Double(i) * 0.13
            dome.addQuadCurve(to: P(x0 + 0.13, -1.0 - bob), control: P(x0 + 0.065, -1.05 - bob))
        }
        dome.closeSubpath()
        parts.append(dome)
        parts.append(limb([(0.0, -1.2 - bob), (0.0, -0.74 - bob), (0.03, -0.72 - bob)], 0.012))
        parts.append(limb([(0.08, -0.78 - bob), (0.06, -0.66 - bob), (0.0, -0.76 - bob)], 0.032))
        return MegaPose(parts: parts, heads: [head], smoke: nil)
    }

    /// A pool player bent over the table, facing right, the cue jabbing on the beat.
    private static func shark(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let dx = -0.04 + 0.07 * beat + 0.02 * sin(t * 2.4 + seed * 5)
        let bob = 0.006 * sin(t * 1.3 + seed)
        var parts: [Path] = []
        parts.append(limb([(-0.05, -0.47), (-0.09, -0.24), (-0.13, -0.02)], 0.065))
        parts.append(limb([(0.02, -0.47), (0.13, -0.27), (0.11, -0.02)], 0.065))
        parts.append(poly([(-0.17, 0), (-0.09, 0), (-0.1, -0.035), (-0.16, -0.035)]))
        parts.append(poly([(0.08, 0), (0.18, 0), (0.17, -0.035), (0.09, -0.035)]))
        let sh = P(0.24, -0.63 + bob)
        parts.append(limb([(-0.02, -0.5), (sh.x, sh.y)], 0.17))                 // torso, bent level
        let head = P(0.34, -0.68 + bob)
        parts.append(oval(head.x, head.y, 0.052, 0.06))
        parts.append(oval(head.x - 0.01, head.y - 0.045, 0.06, 0.022))             // flat cap
        parts.append(poly([(head.x + 0.02, head.y - 0.06), (head.x + 0.09, head.y - 0.045), (head.x + 0.03, head.y - 0.03)]))
        // Bridge hand on the felt, the cue sliding over it.
        let bridge = P(0.5, -0.46)
        parts.append(limb([(sh.x, sh.y + 0.02), (0.38, -0.52), (bridge.x, bridge.y)], 0.035))
        parts.append(limb([(-0.24 + dx, -0.5), (0.72 + dx, -0.455)], 0.016))
        parts.append(limb([(-0.26 + dx, -0.5), (-0.1 + dx, -0.494)], 0.026))       // butt
        parts.append(limb([(sh.x - 0.06, sh.y + 0.03), (0.04, -0.66), (-0.06 + dx, -0.5)], 0.035))
        return MegaPose(parts: parts, heads: [head], smoke: nil)
    }

    /// Standing with a cue upright, chalking the tip in time.
    private static func chalker(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let lean = 0.03 * sin(t * 0.8 + seed * 4) - 0.02
        var (parts, head) = man(x: 0, lean: lean)
        let twist = 0.025 * sin(t * 9) * (0.3 + beat)
        parts.append(limb([(0.13, -0.02), (0.1, -1.14)], 0.016))
        parts.append(limb([(0.08, -0.76), (0.15, -0.66), (0.115, -0.6)], 0.032))
        parts.append(limb([(-0.08, -0.76), (-0.02, -0.98), (0.08 + twist, -1.12)], 0.032))
        parts.append(Path(CGRect(x: 0.07 + twist, y: -1.15, width: 0.045, height: 0.04)))
        return MegaPose(parts: parts, heads: [head], smoke: nil)
    }

    /// Someone digging through a record crate, nodding, flicking sleeves forward.
    private static func digger(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let lean = 0.1 + 0.035 * beat + 0.015 * sin(t * 1.7 + seed * 3)
        var (parts, head) = man(x: 0, lean: lean, hat: false)
        let hip = P(0, -0.47)
        parts.append(rotated(oval(0, -0.925, 0.058, 0.035), lean, about: hip))  // hair
        let flick = 0.03 * sin(t * 2.6 + seed * 7)
        parts.append(rotated(limb([(0.08, -0.76), (0.14, -0.6), (0.12 + flick, -0.44)], 0.032), lean, about: hip))
        parts.append(rotated(limb([(-0.08, -0.76), (-0.06, -0.6), (0.02, -0.46)], 0.032), lean, about: hip))
        return MegaPose(parts: parts, heads: [head], smoke: nil)
    }

    /// The clerk in headphones, nodding to the record.
    private static func listener(_ t: Double, _ beat: Double, _ seed: Double) -> MegaPose {
        let lean = 0.05 * beat + 0.02 * sin(t * 2.2 + seed * 5)
        var (parts, head) = man(x: 0, lean: lean, hat: false)
        let hip = P(0, -0.47)
        var band = Path()
        band.addArc(center: head, radius: 0.068, startAngle: .degrees(195 + lean * 57), endAngle: .degrees(345 + lean * 57), clockwise: false)
        parts.append(band.strokedPath(StrokeStyle(lineWidth: 0.016, lineCap: .round)))
        let cup = CGAffineTransform(translationX: head.x, y: head.y).rotated(by: lean)
        parts.append(oval(-0.062, 0.005, 0.022, 0.034).applying(cup))
        parts.append(oval(0.062, 0.005, 0.022, 0.034).applying(cup))
        parts.append(rotated(limb([(0.08, -0.76), (0.15, -0.66), (0.06, -0.86)], 0.032), lean, about: hip))
        parts.append(rotated(limb([(-0.08, -0.76), (-0.1, -0.6), (-0.02, -0.5)], 0.032), lean, about: hip))
        return MegaPose(parts: parts, heads: [head], smoke: nil)
    }
}
