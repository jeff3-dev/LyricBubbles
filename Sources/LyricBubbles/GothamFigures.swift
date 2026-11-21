import SwiftUI

// MARK: - Gotham Night silhouettes
//
// Every shape is built in its own unit space: figures stand with their feet at y = 0 and are
// about 1 tall (up is negative y); vehicles are 1 long; the bat shapes are 2 wide, centred.
// They're all small paths, cheap enough to rebuild each frame when they animate.

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

/// A left/right symmetric outline: give the right half from the top centre (x = 0) to the
/// bottom centre (x = 0); each segment is a line, or a quad curve when it has a control point.
private func mirrored(_ start: CGPoint, _ segs: [(CGPoint, CGPoint?)]) -> Path {
    func m(_ p: CGPoint) -> CGPoint { CGPoint(x: -p.x, y: p.y) }
    var p = Path()
    p.move(to: start)
    for (to, c) in segs {
        if let c { p.addQuadCurve(to: to, control: c) } else { p.addLine(to: to) }
    }
    let pts = [start] + segs.map(\.0)
    for k in stride(from: segs.count, through: 1, by: -1) {
        let to = m(pts[k - 1])
        if let c = segs[k - 1].1 { p.addQuadCurve(to: to, control: m(c)) } else { p.addLine(to: to) }
    }
    p.closeSubpath()
    return p
}

enum GothamShapes {
    /// The emblem cut out of the signal's light. 2 wide, centred on 0.
    static let emblem: Path = mirrored(P(0, -0.10), [
        (P(0.06, -0.10), nil),
        (P(0.085, -0.30), nil),                 // ear tip
        (P(0.13, -0.08), nil),
        (P(0.34, -0.06), P(0.22, 0.02)),        // shoulder dip
        (P(0.98, -0.36), P(0.62, -0.06)),       // wing top sweeping up to the tip
        (P(0.86, 0.02), P(0.98, -0.12)),
        (P(0.62, 0.10), P(0.70, -0.02)),        // three scallops along the bottom
        (P(0.40, 0.20), P(0.46, 0.06)),
        (P(0.17, 0.26), P(0.24, 0.13)),
        (P(0, 0.40), P(0.04, 0.22)),            // tail
    ])

    /// A caped figure gliding, seen from below. `flap` -1...1 lifts and drops the cape's edges.
    static func glider(flap: Double) -> Path {
        let f = flap * 0.16
        return mirrored(P(0, -0.30), [
            (P(0.045, -0.30), nil),
            (P(0.07, -0.44), nil),               // ear
            (P(0.10, -0.26), nil),
            (P(0.12, -0.17), nil),
            (P(0.20, -0.14), nil),               // shoulder
            (P(1.0, -0.30 + f), P(0.55, -0.30 + f * 0.5)),   // arm holding the cape out
            (P(0.94, -0.04 + f), nil),
            (P(0.70, 0.08 + f * 0.6), P(0.80, -0.03 + f * 0.8)),
            (P(0.46, 0.20 + f * 0.3), P(0.55, 0.07 + f * 0.5)),
            (P(0.24, 0.34), P(0.32, 0.20)),
            (P(0.12, 0.31), nil),
            (P(0.10, 0.62), nil),                // leg
            (P(0.04, 0.65), nil),
            (P(0.03, 0.37), nil),
            (P(0, 0.35), nil),
        ])
    }

    /// A small bat: two wings, flapping.
    static func bat(flap: Double) -> Path {
        let up = -0.5 * flap
        var p = Path()
        p.move(to: P(-1, up))
        p.addQuadCurve(to: P(0, 0), control: P(-0.5, up - 0.35))
        p.addQuadCurve(to: P(1, up), control: P(0.5, up - 0.35))
        p.addQuadCurve(to: P(0, 0.25), control: P(0.45, up + 0.25))
        p.addQuadCurve(to: P(-1, up), control: P(-0.45, up + 0.25))
        p.closeSubpath()
        return p
    }

    // MARK: Vehicles (1 long, wheels on y = 0, facing right)

    static let batmobile: [Path] = {
        var body = Path()
        body.move(to: P(-0.50, -0.05))
        body.addLine(to: P(-0.50, -0.13))
        body.addLine(to: P(-0.47, -0.30))       // tail fin
        body.addLine(to: P(-0.40, -0.15))
        body.addLine(to: P(-0.18, -0.14))
        body.addQuadCurve(to: P(0.06, -0.15), control: P(-0.06, -0.27))   // canopy
        body.addLine(to: P(0.18, -0.12))
        body.addQuadCurve(to: P(0.50, -0.06), control: P(0.38, -0.11))   // long nose
        body.addLine(to: P(0.50, -0.03))
        body.addLine(to: P(0.44, -0.015))
        body.addLine(to: P(-0.46, -0.02))
        body.closeSubpath()
        return [body, oval(-0.30, -0.06, 0.07, 0.065), oval(0.28, -0.06, 0.06, 0.06)]
    }()

    static let policeCar: [Path] = [
        poly([(-0.5, -0.05), (-0.5, -0.20), (-0.25, -0.23), (-0.14, -0.38), (0.16, -0.38), (0.27, -0.23),
              (0.5, -0.19), (0.5, -0.05)]),
        oval(-0.30, -0.07, 0.08, 0.075), oval(0.30, -0.07, 0.08, 0.075),
        poly([(-0.09, -0.38), (-0.09, -0.43), (0.09, -0.43), (0.09, -0.38)]),   // light bar
    ]

    static let blimp: [Path] = [
        oval(0, 0, 0.5, 0.15),
        poly([(-0.36, -0.04), (-0.52, -0.20), (-0.44, -0.02)]),
        poly([(-0.36, 0.04), (-0.52, 0.20), (-0.44, 0.02)]),
        poly([(-0.08, 0.13), (0.08, 0.13), (0.06, 0.20), (-0.06, 0.20)]),       // gondola
    ]
}

// MARK: - Rooftop figures

enum GothamFigure: Int, CaseIterable {
    case perched, joker, catwoman, penguin, robin

    /// Standing height, in screen heights.
    var height: Double {
        switch self {
        case .perched: 0.11
        case .joker: 0.14
        case .catwoman: 0.125
        case .penguin: 0.11
        case .robin: 0.11
        }
    }

    /// A faint rim of colour along the outline, the only hint of who it is besides the shape.
    var rim: NeonRGB {
        switch self {
        case .perched: NeonRGB(0.55, 0.62, 0.8)
        case .joker: NeonRGB(0.45, 0.85, 0.35)
        case .catwoman: NeonRGB(0.62, 0.5, 0.85)
        case .penguin: NeonRGB(0.75, 0.68, 0.55)
        case .robin: NeonRGB(0.9, 0.35, 0.25)
        }
    }

    /// The figure's parts (filled with the same colour), animated by `t`.
    func parts(t: Double, seed: Double) -> [Path] {
        switch self {
        case .perched: Self.perched(t, seed)
        case .joker: Self.joker(t, seed)
        case .catwoman: Self.catwoman(t, seed)
        case .penguin: Self.penguin(t, seed)
        case .robin: Self.robin(t, seed)
        }
    }

    /// Crouched on a gargoyle, cape wrapped round, ears up. Front on.
    private static func perched(_ t: Double, _ seed: Double) -> [Path] {
        let w = 0.02 * sin(t * 1.7 + seed * 6)
        let cape = mirrored(P(0, -0.86), [
            (P(0.05, -0.87), nil),
            (P(0.075, -1.0), nil),               // ear
            (P(0.105, -0.84), nil),
            (P(0.11, -0.74), nil),
            (P(0.25, -0.66), P(0.16, -0.70)),    // shoulder
            (P(0.34, -0.40), P(0.33, -0.62)),
            (P(0.44 + w, -0.04), P(0.36, -0.20)),
            (P(0.40 + w, 0.0), nil),
            (P(0.30, -0.06), P(0.36, -0.08)),
            (P(0.18 + w * 0.5, 0.0), nil),
            (P(0.10, -0.05), P(0.14, -0.06)),
            (P(0, 0.0), nil),
        ])
        // The gargoyle: a hunched stone beast jutting out over the street.
        var garg = Path()
        garg.move(to: P(-0.34, 0.36))
        garg.addLine(to: P(-0.34, 0.08))
        garg.addQuadCurve(to: P(0.22, -0.01), control: P(-0.12, -0.06))
        garg.addLine(to: P(0.34, -0.05))         // horn
        garg.addLine(to: P(0.36, 0.03))
        garg.addQuadCurve(to: P(0.58, 0.09), control: P(0.48, 0.02))   // snout
        garg.addLine(to: P(0.48, 0.15))
        garg.addLine(to: P(0.40, 0.13))
        garg.addQuadCurve(to: P(0.30, 0.30), control: P(0.30, 0.18))
        garg.addLine(to: P(0.24, 0.36))
        garg.closeSubpath()
        return [garg, cape]
    }

    /// Tall and thin: wild curls, flared coat, a cane. Faces left.
    private static func joker(_ t: Double, _ seed: Double) -> [Path] {
        let sway = 0.025 * sin(t * 1.3 + seed * 6)
        var parts: [Path] = [oval(-0.005, -0.89, 0.05, 0.06)]
        for (x, y, r) in [(-0.04, -0.96, 0.03), (0.0, -0.985, 0.035), (0.045, -0.965, 0.032),
                          (0.065, -0.92, 0.03), (0.06, -0.875, 0.024), (-0.05, -0.935, 0.022)] {
            parts.append(oval(x, y, r, r))
        }
        parts.append(poly([(-0.045, -0.905), (-0.08, -0.875), (-0.04, -0.855)]))   // chin and grin
        parts.append(poly([(-0.025, -0.85), (0.03, -0.85), (0.10, -0.79), (0.11, -0.56), (0.13, -0.38),
                           (0.16 + sway, -0.23), (0.05, -0.27), (-0.07, -0.27), (-0.14 + sway * 0.5, -0.24),
                           (-0.12, -0.38), (-0.10, -0.56), (-0.09, -0.79)]))
        parts.append(poly([(-0.07, -0.28), (-0.02, -0.28), (-0.05, -0.03), (-0.06, 0), (-0.14, 0),
                           (-0.12, -0.02), (-0.085, -0.03)]))
        parts.append(poly([(0.0, -0.28), (0.06, -0.28), (0.065, -0.03), (0.11, -0.01), (0.11, 0),
                           (0.035, 0), (0.03, -0.03)]))
        parts.append(limb([(-0.07, -0.76), (-0.16, -0.62), (-0.22, -0.52)], 0.035))   // arm to the cane
        parts.append(limb([(0.08, -0.77), (0.17, -0.64), (0.10, -0.52)], 0.03))      // hand on hip
        var cane = Path()
        cane.move(to: P(-0.27, 0))
        cane.addLine(to: P(-0.225, -0.53))
        cane.addQuadCurve(to: P(-0.17, -0.53), control: P(-0.20, -0.60))
        parts.append(cane.strokedPath(StrokeStyle(lineWidth: 0.016, lineCap: .round)))
        return parts
    }

    /// Slim, cat ears, hip cocked, a whip trailing off the ledge. Faces right.
    private static func catwoman(_ t: Double, _ seed: Double) -> [Path] {
        let sw = 0.05 * sin(t * 1.1 + seed * 6)
        var parts: [Path] = [
            oval(0, -0.885, 0.0425, 0.05),
            poly([(-0.04, -0.91), (-0.035, -0.995), (-0.008, -0.93)]),
            poly([(0.008, -0.93), (0.035, -0.995), (0.04, -0.91)]),
            poly([(-0.015, -0.84), (0.02, -0.84), (0.075, -0.80), (0.06, -0.70), (0.045, -0.60), (0.085, -0.50),
                  (0.07, -0.44), (-0.08, -0.44), (-0.075, -0.50), (-0.04, -0.60), (-0.055, -0.70), (-0.075, -0.80)]),
            poly([(-0.075, -0.46), (-0.01, -0.46), (-0.03, -0.22), (-0.045, -0.02), (-0.075, 0), (-0.075, -0.02),
                  (-0.07, -0.22)]),
            poly([(0.0, -0.46), (0.07, -0.46), (0.10, -0.22), (0.13, -0.02), (0.16, 0), (0.105, 0), (0.075, -0.22)]),
            limb([(-0.07, -0.78), (-0.13, -0.64), (-0.075, -0.52)], 0.028),
            limb([(0.07, -0.78), (0.12, -0.66), (0.17, -0.56)], 0.026),
        ]
        var whip = Path()
        whip.move(to: P(0.17, -0.56))
        whip.addQuadCurve(to: P(0.30 + sw * 0.5, -0.25), control: P(0.30 + sw, -0.55))
        whip.addQuadCurve(to: P(0.22 + sw, 0.0), control: P(0.34, -0.05))
        whip.addQuadCurve(to: P(0.32 + sw, -0.02), control: P(0.27, 0.03))
        parts.append(whip.strokedPath(StrokeStyle(lineWidth: 0.009, lineCap: .round)))
        return parts
    }

    /// Short and round: top hat, long nose, coat tails, an open umbrella. Faces right.
    private static func penguin(_ t: Double, _ seed: Double) -> [Path] {
        let bob = 0.008 * sin(t * 1.1 + seed * 6)
        var canopy = Path()
        canopy.move(to: P(-0.05, -0.80 + bob))
        canopy.addQuadCurve(to: P(0.35, -0.80 + bob), control: P(0.15, -1.06 + bob))
        for k in 1...4 {
            let x = 0.35 - Double(k) * 0.1
            canopy.addQuadCurve(to: P(x, -0.80 + bob), control: P(x + 0.05, -0.84 + bob))
        }
        canopy.closeSubpath()
        return [
            oval(0, -0.26, 0.13, 0.21),
            poly([(-0.10, -0.18), (-0.21, -0.02), (-0.06, -0.08)]),          // coat tails
            Path(CGRect(x: -0.06, y: -0.08, width: 0.035, height: 0.08)),
            Path(CGRect(x: 0.025, y: -0.08, width: 0.035, height: 0.08)),
            Path(CGRect(x: 0.02, y: -0.02, width: 0.07, height: 0.02)),
            oval(0, -0.52, 0.065, 0.065),
            poly([(0.045, -0.54), (0.15, -0.51), (0.05, -0.495)]),            // the nose
            Path(CGRect(x: -0.055, y: -0.70, width: 0.105, height: 0.11)),    // top hat
            Path(CGRect(x: -0.09, y: -0.605, width: 0.17, height: 0.018)),
            limb([(0.08, -0.40), (0.15, -0.33)], 0.045),
            limb([(0.15, -0.30), (0.15, -0.82 + bob)], 0.012),
            limb([(0.15, -0.93 + bob), (0.15, -0.99 + bob)], 0.01),
            canopy,
        ]
    }

    /// Small and wiry, fists on hips, a short cape snapping in the wind. Faces right.
    private static func robin(_ t: Double, _ seed: Double) -> [Path] {
        func f(_ k: Double) -> Double { 0.03 * sin(t * 5 + seed * 6 + k) }
        return [
            oval(0, -0.815, 0.04, 0.045),
            poly([(-0.04, -0.84), (-0.07, -0.87), (-0.03, -0.86)]),
            poly([(-0.02, -0.78), (0.02, -0.78), (0.07, -0.74), (0.06, -0.50), (0.06, -0.46), (-0.06, -0.46),
                  (-0.06, -0.50), (-0.07, -0.74)]),
            poly([(-0.06, -0.47), (-0.005, -0.47), (-0.06, -0.02), (-0.10, 0), (-0.13, 0), (-0.10, -0.02)]),
            poly([(0.0, -0.47), (0.06, -0.47), (0.11, -0.02), (0.15, 0), (0.10, 0), (0.07, -0.02)]),
            limb([(-0.06, -0.73), (-0.12, -0.62), (-0.06, -0.52)], 0.028),
            limb([(0.06, -0.73), (0.12, -0.62), (0.06, -0.52)], 0.028),
            poly([(-0.06, -0.77), (-0.20 + f(0), -0.66), (-0.31 + f(1), -0.52), (-0.25 + f(2), -0.50),
                  (-0.27 + f(3), -0.42), (-0.18 + f(4), -0.46), (-0.15 + f(5), -0.38), (-0.06, -0.50)]),
        ]
    }
}
