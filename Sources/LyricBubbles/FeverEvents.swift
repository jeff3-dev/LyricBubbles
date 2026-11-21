import SwiftUI

// MARK: - Fever City chaos events
//
// Every scheduled event is worked out from the clock alone: time is cut into slots (shorter when the
// event's slider and the master Chaos slider are higher), and a seeded roll per slot decides whether
// the event runs in it and when. So a preview can render any moment, and nothing is kept between frames.
// Positions are in pixels; sizes follow the window height `H`.

enum FeverEvent: String, CaseIterable {
    case ufo, rocket, parade, donut, train, kaiju, cat, whale, wink, show

    var key: FeverSettings.Key {
        switch self {
        case .ufo: .ufo
        case .rocket: .rocket
        case .parade: .parade
        case .donut: .donut
        case .train: .train
        case .kaiju: .kaiju
        case .cat: .cat
        case .whale: .whale
        case .wink: .moon
        case .show: .fireworks
        }
    }

    var duration: Double {
        switch self {
        case .ufo: 10
        case .rocket: 8
        case .parade: 16
        case .donut: 6
        case .train: 9
        case .kaiju: 18
        case .cat: 9
        case .whale: 20
        case .wink: 0.7
        case .show: 7
        }
    }

    /// Seconds between runs at a rate of 1.
    var period: Double {
        switch self {
        case .ufo: 35
        case .rocket: 40
        case .parade: 50
        case .donut: 30
        case .train: 30
        case .kaiju: 60
        case .cat: 35
        case .whale: 50
        case .wink: 10
        case .show: 45
        }
    }

    /// Big enough for the camera to cut to.
    var isBig: Bool { self == .ufo || self == .kaiju || self == .cat || self == .whale }
}

struct FeverActive {
    let kind: FeverEvent
    let p: Double           // 0...1 through the event
    let age: Double         // seconds since it started
    let start: Double
    let seed: Double        // 0...1, picks where and which variant
}

enum FeverEvents {
    static func active(_ f: FeverFrame) -> [FeverEvent: FeverActive] {
        var out: [FeverEvent: FeverActive] = [:]
        for kind in FeverEvent.allCases {
            if let p = f.force[kind] {
                let age = p * kind.duration
                out[kind] = FeverActive(kind: kind, p: p, age: age, start: f.t - age, seed: 0.37)
                continue
            }
            let q = f.s.rate(kind.key)
            guard q > 0.001 else { continue }
            let d = kind.duration
            let P = max(d * 1.2, kind.period / q)
            let n = floor(f.t / P)
            var r = Seeded(LyricPages.hash("\(kind.rawValue)\(Int(n))"))
            guard r.next() < 0.8 else { continue }
            let start = n * P + r.next() * (P - d)
            let age = f.t - start
            guard age >= 0, age < d else { continue }
            out[kind] = FeverActive(kind: kind, p: age / d, age: age, start: start, seed: r.next())
        }
        return out
    }

    // MARK: Anchors (where the camera looks)

    static func ufoPos(_ e: FeverActive, W: CGFloat, H: CGFloat) -> CGPoint {
        let hover = CGPoint(x: W * (0.35 + 0.3 * e.seed), y: H * 0.3 + H * 0.015 * sin(e.age * 2.1))
        if e.p < 0.2 {
            let k = smoothstep(e.p / 0.2)
            return CGPoint(x: W * 1.15 + (hover.x - W * 1.15) * k, y: -H * 0.05 + (hover.y + H * 0.05) * k)
        }
        if e.p > 0.82 {
            let k = pow((e.p - 0.82) / 0.18, 2)
            return CGPoint(x: hover.x + (-W * 0.3 - hover.x) * k, y: hover.y + (-H * 0.15 - hover.y) * k)
        }
        return hover
    }

    static func rocketPos(_ e: FeverActive, W: CGFloat, H: CGFloat, at p: Double? = nil) -> CGPoint {
        let p = p ?? e.p
        let x0 = W * (0.12 + 0.7 * e.seed)
        let q = max(0, (p - 0.15) / 0.85)
        return CGPoint(x: x0 + W * 0.12 * q * q, y: H * 0.7 - H * 1.3 * q * q)
    }

    static func kaijuX(_ e: FeverActive, W: CGFloat, H: CGFloat) -> CGFloat {
        let right = e.seed < 0.5
        let x = -H * 0.5 + (W + H) * e.p
        return right ? x : W - x
    }

    static func catPos(_ e: FeverActive, W: CGFloat, H: CGFloat) -> CGPoint {
        let rise = smoothstep(e.p / 0.14) * (1 - smoothstep((e.p - 0.86) / 0.14))
        return CGPoint(x: W * (0.22 + 0.56 * e.seed), y: H * 1.2 - H * 0.58 * rise)
    }

    static func whalePos(_ e: FeverActive, W: CGFloat, H: CGFloat) -> CGPoint {
        let L = H * 0.62
        let x = -L + (W + 2 * L) * e.p
        return CGPoint(x: e.seed < 0.5 ? x : W - x, y: H * 0.24 + H * 0.04 * sin(e.age * 0.45))
    }

    static func anchor(_ e: FeverActive, W: CGFloat, H: CGFloat) -> CGPoint {
        switch e.kind {
        case .ufo: ufoPos(e, W: W, H: H)
        case .kaiju: CGPoint(x: kaijuX(e, W: W, H: H), y: H * 0.5)
        case .cat: catPos(e, W: W, H: H)
        case .whale: whalePos(e, W: W, H: H)
        default: CGPoint(x: W / 2, y: H / 2)
        }
    }

    // MARK: Sky

    static func drawUFO(_ g: inout GraphicsContext, _ e: FeverActive, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        let c = ufoPos(e, W: W, H: H)
        let street = H * 0.96
        let beamOn = smoothstep((e.p - 0.28) / 0.05) * (1 - smoothstep((e.p - 0.74) / 0.05))
        let green = NeonRGB(0.55, 1, 0.7)
        if beamOn > 0 {
            var beam = Path()
            beam.move(to: CGPoint(x: c.x - H * 0.03, y: c.y + H * 0.02))
            beam.addLine(to: CGPoint(x: c.x + H * 0.03, y: c.y + H * 0.02))
            beam.addLine(to: CGPoint(x: c.x + H * 0.12, y: street))
            beam.addLine(to: CGPoint(x: c.x - H * 0.12, y: street))
            beam.closeSubpath()
            g.drawLayer { l in
                l.blendMode = .plusLighter
                l.fill(beam, with: .linearGradient(Gradient(colors: [green.color(0.5 * beamOn), green.color(0.15 * beamOn)]),
                                                   startPoint: c, endPoint: CGPoint(x: c.x, y: street)))
                l.fill(Path(ellipseIn: CGRect(x: c.x - H * 0.13, y: street - H * 0.015, width: H * 0.26, height: H * 0.03)),
                       with: .color(green.color(0.4 * beamOn)))
            }
            // A car (or a cow, if you squint) floats up the beam, spinning.
            let k = smoothstep((e.p - 0.34) / 0.36)
            if e.p > 0.3, k < 1 {
                var u = g
                u.translateBy(x: c.x, y: street - H * 0.02 - (street - c.y - H * 0.03) * k)
                u.rotate(by: .radians(k * 5))
                u.scaleBy(x: 1 - 0.5 * k, y: 1 - 0.5 * k)
                FeverRenderer.car(&u, H: H, color: f.pal.bldg[Int(e.seed * 5) % 5].mixed(.white, 0.3), facingRight: true)
            }
        }
        // Saucer.
        let w = H * 0.2, h = H * 0.05
        g.fill(Path(ellipseIn: CGRect(x: c.x - w * 0.25, y: c.y - h * 1.1, width: w * 0.5, height: h * 1.4)),
               with: .linearGradient(Gradient(colors: [rgb(0.7, 1, 0.95, 0.9), rgb(0.2, 0.6, 0.7, 0.9)]),
                                     startPoint: CGPoint(x: c.x, y: c.y - h), endPoint: CGPoint(x: c.x, y: c.y)))
        g.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)),
               with: .linearGradient(Gradient(colors: [rgb(0.85, 0.87, 0.92), rgb(0.42, 0.44, 0.52)]),
                                     startPoint: CGPoint(x: c.x, y: c.y - h / 2), endPoint: CGPoint(x: c.x, y: c.y + h / 2)))
        for i in 0..<7 {
            let a = Double(i) / 6
            let x = c.x - w * 0.42 + w * 0.84 * a
            let on = Int(f.t * 8 + Double(i)) % 3 == 0
            let r = H * 0.007
            g.fill(Path(ellipseIn: CGRect(x: x - r, y: c.y - r + h * 0.05, width: r * 2, height: r * 2)),
                   with: .color(on ? rgb(1, 0.95, 0.4) : rgb(1, 0.3, 0.5)))
        }
    }

    static func drawRocket(_ g: inout GraphicsContext, _ e: FeverActive, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        let c = rocketPos(e, W: W, H: H)
        // Smoke trail behind it, oldest biggest.
        let smoke = f.pal.cloud.mixed(.white, 0.5)
        for k in stride(from: 14, through: 1, by: -1) {
            let pp = e.p - Double(k) * 0.025
            guard pp > 0 else { continue }
            var pt = rocketPos(e, W: W, H: H, at: pp)
            pt.y += H * 0.05
            let r = H * (0.018 + 0.006 * Double(k)) * (pp < 0.15 ? 1.6 : 1)
            pt.x += sin(Double(k) * 1.7 + e.start) * r * 0.4
            g.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                   with: .color(smoke.color(0.5 * (1 - Double(k) / 15))))
        }
        let shake = e.p < 0.15 ? sin(f.t * 80) * H * 0.002 : 0
        var u = g
        u.translateBy(x: c.x + shake, y: c.y)
        let tilt = e.p > 0.15 ? 0.12 * min(1, (e.p - 0.15) * 3) : 0
        u.rotate(by: .radians(tilt))
        let s = H * 0.1
        // Flame.
        if e.p > 0.08 {
            let fl = 1 + 0.25 * sin(f.t * 47) + (e.p > 0.15 ? 0.6 : 0)
            var flame = Path()
            flame.move(to: CGPoint(x: -s * 0.12, y: s * 0.45))
            flame.addQuadCurve(to: CGPoint(x: s * 0.12, y: s * 0.45), control: CGPoint(x: 0, y: s * (0.45 + 0.7 * fl)))
            u.drawLayer { l in
                l.blendMode = .plusLighter
                l.fill(flame, with: .linearGradient(Gradient(colors: [rgb(1, 1, 0.7), rgb(1, 0.5, 0.1, 0.8), rgb(1, 0.2, 0, 0)]),
                                                    startPoint: CGPoint(x: 0, y: s * 0.45), endPoint: CGPoint(x: 0, y: s * (0.45 + 0.7 * fl))))
            }
        }
        var fins = Path()
        fins.addLines([CGPoint(x: -s * 0.14, y: s * 0.1), CGPoint(x: -s * 0.28, y: s * 0.48), CGPoint(x: -s * 0.1, y: s * 0.4)])
        fins.closeSubpath()
        fins.addLines([CGPoint(x: s * 0.14, y: s * 0.1), CGPoint(x: s * 0.28, y: s * 0.48), CGPoint(x: s * 0.1, y: s * 0.4)])
        fins.closeSubpath()
        u.fill(fins, with: .color(rgb(0.95, 0.25, 0.3)))
        u.fill(Path(roundedRect: CGRect(x: -s * 0.15, y: -s * 0.3, width: s * 0.3, height: s * 0.75), cornerRadius: s * 0.12),
               with: .color(rgb(0.96, 0.96, 1)))
        var nose = Path()
        nose.move(to: CGPoint(x: -s * 0.15, y: -s * 0.22))
        nose.addQuadCurve(to: CGPoint(x: s * 0.15, y: -s * 0.22), control: CGPoint(x: 0, y: -s * 0.75))
        nose.closeSubpath()
        u.fill(nose, with: .color(rgb(0.95, 0.25, 0.3)))
        u.fill(Path(ellipseIn: CGRect(x: -s * 0.07, y: -s * 0.08, width: s * 0.14, height: s * 0.14)), with: .color(rgb(0.4, 0.8, 1)))
    }

    static func drawBalloons(_ g: inout GraphicsContext, _ f: FeverFrame) {
        let v = f.s.rate(.balloons)
        guard v > 0 else { return }
        let W = f.size.width, H = f.size.height
        let n = min(9, Int(ceil(v * 4)))
        let colors = f.pal.bldg.map { $0.mixed(.white, 0.25) } + [f.pal.accent]
        for i in 0..<n {
            var r = Seeded(UInt64(i + 1) &* 0x9E37_79B9_7F4A_7C15)
            let size = H * (0.045 + 0.04 * r.next())
            let speed = 0.01 + 0.02 * r.next()
            let span = W + size * 4
            var x = (r.next() * span + f.t * speed * H - f.camX * H * 0.25 * (size / H * 8))
                .truncatingRemainder(dividingBy: span)
            if x < 0 { x += span }
            x -= size * 2
            let y = H * (0.12 + 0.35 * r.next()) + sin(f.t * 0.6 + Double(i)) * H * 0.01
            let a = colors[i % colors.count], b = colors[(i + 2) % colors.count]
            var env = Path()
            env.addArc(center: CGPoint(x: x, y: y), radius: size, startAngle: .degrees(150), endAngle: .degrees(30), clockwise: false)
            env.addLine(to: CGPoint(x: x + size * 0.3, y: y + size * 1.25))
            env.addLine(to: CGPoint(x: x - size * 0.3, y: y + size * 1.25))
            env.closeSubpath()
            g.fill(env, with: .color(a.color))
            var stripes = g
            stripes.clip(to: env)
            for k in [-0.55, 0.0, 0.55] {
                stripes.fill(Path(ellipseIn: CGRect(x: x + size * k - size * 0.14, y: y - size * 1.1, width: size * 0.28, height: size * 2.6)),
                             with: .color(b.color))
            }
            var ropes = Path()
            ropes.move(to: CGPoint(x: x - size * 0.3, y: y + size * 1.25)); ropes.addLine(to: CGPoint(x: x - size * 0.2, y: y + size * 1.5))
            ropes.move(to: CGPoint(x: x + size * 0.3, y: y + size * 1.25)); ropes.addLine(to: CGPoint(x: x + size * 0.2, y: y + size * 1.5))
            g.stroke(ropes, with: .color(rgb(0.2, 0.15, 0.1, 0.8)), lineWidth: max(0.5, size * 0.03))
            g.fill(Path(CGRect(x: x - size * 0.22, y: y + size * 1.5, width: size * 0.44, height: size * 0.32)), with: .color(rgb(0.55, 0.35, 0.2)))
        }
    }

    /// Bursts: one on some big beats, and a show every so often.
    static func drawFireworks(_ g: inout GraphicsContext, _ f: FeverFrame, show: FeverActive?) {
        let v = f.s[.fireworks]
        guard v > 0 else { return }
        var bursts: [(Double, UInt64)] = []
        for b in f.beats where f.t - b < 1.8 {
            let h = LyricPages.hash("fw\(Int(b * 100))")
            if Double(h % 1000) / 1000 < v * 0.6 { bursts.append((f.t - b, h)) }
        }
        if let show {
            var k = 0.0
            while k <= show.age && k < show.kind.duration - 1 {
                if show.age - k < 1.8 { bursts.append((show.age - k, LyricPages.hash("show\(Int(show.start))\(Int(k * 10))"))) }
                k += 0.42
            }
        }
        guard !bursts.isEmpty else { return }
        let W = f.size.width, H = f.size.height
        let colors = [f.pal.accent, f.pal.window, f.pal.windowAlt, NeonRGB(1, 1, 1), f.pal.bldg[1].mixed(.white, 0.4)]
        g.drawLayer { l in
            l.blendMode = .plusLighter
            for (age, h) in bursts {
                var r = Seeded(h)
                let c = CGPoint(x: W * (0.08 + 0.84 * r.next()), y: H * (0.08 + 0.32 * r.next()))
                let col = colors[Int(r.next() * 5) % 5]
                let R = H * (0.08 + 0.08 * r.next())
                let rad = R * (1 - exp(-age * 4.5))
                let fade = max(0, 1 - age / 1.8)
                let drop = H * 0.05 * age * age
                if age < 0.15 {
                    l.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.4, y: c.y - R * 0.4, width: R * 0.8, height: R * 0.8)),
                           with: .radialGradient(Gradient(colors: [col.mixed(.white, 0.6).color(0.8), .clear]),
                                                 center: c, startRadius: 0, endRadius: R * 0.4))
                }
                var streaks = Path()
                var dots = Path()
                let n = 22
                for i in 0..<n {
                    let a = Double(i) / Double(n) * 2 * .pi + r.next() * 0.2
                    let p1 = CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad + drop)
                    let p0 = CGPoint(x: c.x + cos(a) * rad * 0.72, y: c.y + sin(a) * rad * 0.72 + drop * 0.7)
                    streaks.move(to: p0); streaks.addLine(to: p1)
                    let d = H * 0.005
                    dots.addEllipse(in: CGRect(x: p1.x - d, y: p1.y - d, width: d * 2, height: d * 2))
                }
                l.stroke(streaks, with: .color(col.color(0.6 * fade)), style: StrokeStyle(lineWidth: H * 0.004, lineCap: .round))
                l.fill(dots, with: .color(col.mixed(.white, 0.5).color(fade)))
            }
        }
    }

    // MARK: Giants

    static func drawWhale(_ g: inout GraphicsContext, _ e: FeverActive, _ f: FeverFrame) {
        let H = f.size.height
        let c = whalePos(e, W: f.size.width, H: H)
        let L = H * 0.62
        let body = f.pal.skyMid.mixed(NeonRGB(0.1, 0.2, 0.45), 0.55)
        let belly = body.mixed(.white, 0.45)
        var u = g
        u.translateBy(x: c.x, y: c.y)
        u.scaleBy(x: e.seed < 0.5 ? L : -L, y: L)
        u.rotate(by: .radians(0.05 * sin(e.age * 0.45 + 1)))
        let flap = sin(e.age * 1.6) * 0.06
        var p = Path()
        p.move(to: CGPoint(x: 0.32, y: 0.02))
        p.addCurve(to: CGPoint(x: -0.42, y: -0.01 + flap * 0.3), control1: CGPoint(x: 0.3, y: -0.2), control2: CGPoint(x: -0.15, y: -0.12))
        p.addCurve(to: CGPoint(x: 0.32, y: 0.02), control1: CGPoint(x: -0.15, y: 0.08), control2: CGPoint(x: 0.25, y: 0.16))
        p.closeSubpath()
        // Tail flukes.
        var fluke = Path()
        let tx = -0.42, ty = -0.01 + flap * 0.3
        fluke.move(to: CGPoint(x: tx + 0.04, y: ty))
        fluke.addQuadCurve(to: CGPoint(x: tx - 0.12, y: ty - 0.1 + flap), control: CGPoint(x: tx - 0.03, y: ty - 0.08 + flap))
        fluke.addQuadCurve(to: CGPoint(x: tx - 0.04, y: ty), control: CGPoint(x: tx - 0.06, y: ty - 0.02))
        fluke.addQuadCurve(to: CGPoint(x: tx - 0.12, y: ty + 0.1 + flap), control: CGPoint(x: tx - 0.06, y: ty + 0.02))
        fluke.addQuadCurve(to: CGPoint(x: tx + 0.04, y: ty), control: CGPoint(x: tx - 0.03, y: ty + 0.08 + flap))
        u.fill(fluke, with: .color(body.color))
        u.fill(p, with: .color(body.color))
        var bellyP = Path()
        bellyP.move(to: CGPoint(x: 0.31, y: 0.04))
        bellyP.addCurve(to: CGPoint(x: -0.2, y: 0.05), control1: CGPoint(x: 0.22, y: 0.15), control2: CGPoint(x: -0.05, y: 0.1))
        bellyP.addCurve(to: CGPoint(x: 0.31, y: 0.04), control1: CGPoint(x: 0, y: 0.06), control2: CGPoint(x: 0.2, y: 0.07))
        u.fill(bellyP, with: .color(belly.color))
        var grooves = Path()
        for k in 0..<4 {
            let y = 0.065 + Double(k) * 0.012
            grooves.move(to: CGPoint(x: 0.25, y: y)); grooves.addLine(to: CGPoint(x: 0.0, y: y - 0.01))
        }
        u.stroke(grooves, with: .color(body.color(0.4)), lineWidth: 0.004)
        // Fin, eye, smile.
        var fin = Path()
        fin.move(to: CGPoint(x: 0.08, y: 0.07))
        fin.addQuadCurve(to: CGPoint(x: -0.04, y: 0.17 + flap * 0.5), control: CGPoint(x: 0.08, y: 0.15))
        fin.addQuadCurve(to: CGPoint(x: 0.0, y: 0.06), control: CGPoint(x: -0.01, y: 0.1))
        u.fill(fin, with: .color(body.mixed(.white, 0.1).color))
        u.fill(Path(ellipseIn: CGRect(x: 0.18, y: -0.015, width: 0.022, height: 0.022)), with: .color(rgb(0.05, 0.05, 0.1)))
        u.fill(Path(ellipseIn: CGRect(x: 0.186, y: -0.012, width: 0.007, height: 0.007)), with: .color(.white))
        var smile = Path()
        smile.move(to: CGPoint(x: 0.3, y: 0.035))
        smile.addQuadCurve(to: CGPoint(x: 0.17, y: 0.03), control: CGPoint(x: 0.24, y: 0.06))
        u.stroke(smile, with: .color(rgb(0.05, 0.05, 0.1, 0.7)), lineWidth: 0.005)
        // Spout now and then.
        let spout = e.age.truncatingRemainder(dividingBy: 7)
        if spout < 1.6 {
            let k = spout / 1.6
            var drops = Path()
            for i in 0..<10 {
                let a = -.pi / 2 + (Double(i) / 9 - 0.5) * 1.6
                let r = 0.04 + 0.12 * k
                let x = 0.12 + cos(a) * r * 0.6, y = -0.13 + sin(a) * r * 0.9 + 0.2 * k * k
                drops.addEllipse(in: CGRect(x: x - 0.006, y: y - 0.006, width: 0.012, height: 0.012))
            }
            u.fill(drops, with: .color(rgb(0.85, 0.95, 1, 0.85 * (1 - k))))
        }
    }

    /// The kaiju strolls behind the middle buildings, glowing on the beat.
    static func drawKaiju(_ g: inout GraphicsContext, _ e: FeverActive, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        let x = kaijuX(e, W: W, H: H)
        let facing: CGFloat = e.seed < 0.5 ? 1 : -1
        let step = e.age * 1.4
        let bob = abs(sin(step * .pi)) * 0.015
        let S = H * 0.62
        let dark = f.pal.skyTop.mixed(NeonRGB(0.02, 0.02, 0.05), 0.55).mixed(f.pal.haze, 0.2)
        let glow = f.pal.accent.mixed(NeonRGB(0.4, 1, 0.9), 0.5)
        var u = g
        u.translateBy(x: x, y: H * 0.86)
        u.scaleBy(x: S * facing, y: S)
        u.translateBy(x: 0, y: -bob)
        var body = Path()
        // Tail.
        let sway = sin(e.age * 1.1) * 0.04
        body.move(to: CGPoint(x: -0.1, y: -0.3))
        body.addQuadCurve(to: CGPoint(x: -0.6, y: -0.02 + sway), control: CGPoint(x: -0.35, y: -0.3))
        body.addQuadCurve(to: CGPoint(x: -0.05, y: -0.15), control: CGPoint(x: -0.3, y: -0.08))
        body.closeSubpath()
        // Torso, neck, head.
        body.addEllipse(in: CGRect(x: -0.2, y: -0.55, width: 0.36, height: 0.45))
        body.addEllipse(in: CGRect(x: -0.02, y: -0.72, width: 0.18, height: 0.3))
        body.addEllipse(in: CGRect(x: 0.04, y: -0.82, width: 0.24, height: 0.14))
        // Legs, alternating.
        let l1 = sin(step * .pi) * 0.05
        body.addRoundedRect(in: CGRect(x: -0.12 + l1, y: -0.2, width: 0.11, height: 0.25), cornerSize: CGSize(width: 0.04, height: 0.04))
        body.addRoundedRect(in: CGRect(x: 0.02 - l1, y: -0.2, width: 0.11, height: 0.25), cornerSize: CGSize(width: 0.04, height: 0.04))
        // Little arms.
        body.addRoundedRect(in: CGRect(x: 0.1, y: -0.48 + l1 * 0.3, width: 0.12, height: 0.04), cornerSize: CGSize(width: 0.02, height: 0.02))
        u.fill(body, with: .color(dark.color))
        // Back spikes glow with the beat.
        let pulse = 0.35 + 0.65 * max(f.beat, 0.3 + 0.2 * sin(e.age * 3))
        var spikes = Path()
        for i in 0..<6 {
            let a = Double(i) / 5
            let bx = -0.2 + 0.24 * a, by = -0.5 - 0.22 * a + (a > 0.6 ? 0.05 : 0)
            let sz = 0.05 + 0.03 * sin(a * .pi)
            spikes.addLines([CGPoint(x: bx - sz * 0.5, y: by + 0.02), CGPoint(x: bx - sz * 0.6, y: by - sz), CGPoint(x: bx + sz * 0.5, y: by + 0.02)])
            spikes.closeSubpath()
        }
        u.fill(spikes, with: .color(dark.mixed(glow, 0.25).color))
        u.drawLayer { l in
            l.blendMode = .plusLighter
            l.fill(spikes, with: .color(glow.color(0.55 * pulse)))
            l.fill(Path(ellipseIn: CGRect(x: 0.17, y: -0.79, width: 0.035, height: 0.025)), with: .color(rgb(1, 0.9, 0.3)))
            // A beam of breath in the middle of its walk.
            let breath = smoothstep((e.p - 0.45) / 0.04) * (1 - smoothstep((e.p - 0.6) / 0.04))
            if breath > 0 {
                var cone = Path()
                cone.move(to: CGPoint(x: 0.27, y: -0.74))
                cone.addLine(to: CGPoint(x: 1.3, y: -1.05))
                cone.addLine(to: CGPoint(x: 1.3, y: -0.8))
                cone.closeSubpath()
                l.fill(cone, with: .linearGradient(Gradient(colors: [glow.mixed(.white, 0.5).color(0.9 * breath), glow.color(0)]),
                                                   startPoint: CGPoint(x: 0.27, y: -0.74), endPoint: CGPoint(x: 1.3, y: -0.9)))
            }
        }
    }

    static func drawCat(_ g: inout GraphicsContext, _ e: FeverActive, _ f: FeverFrame) {
        let H = f.size.height
        let c = catPos(e, W: f.size.width, H: H)
        let R = H * 0.22
        let coats: [(NeonRGB, NeonRGB)] = [(NeonRGB(1, 0.6, 0.25), NeonRGB(1, 0.85, 0.65)), (NeonRGB(0.55, 0.55, 0.6), NeonRGB(0.85, 0.85, 0.9)),
                                          (NeonRGB(0.12, 0.12, 0.15), NeonRGB(0.95, 0.95, 0.95)), (NeonRGB(0.95, 0.95, 0.95), NeonRGB(1, 0.75, 0.8))]
        let (fur, light) = coats[Int(e.seed * 4) % 4]
        var u = g
        u.translateBy(x: c.x, y: c.y)
        u.scaleBy(x: R, y: R)
        u.rotate(by: .radians(0.12 * sin(e.age * 0.9)))
        var ears = Path()
        ears.addLines([CGPoint(x: -0.85, y: -0.35), CGPoint(x: -0.7, y: -1.25), CGPoint(x: -0.2, y: -0.8)]); ears.closeSubpath()
        ears.addLines([CGPoint(x: 0.85, y: -0.35), CGPoint(x: 0.7, y: -1.25), CGPoint(x: 0.2, y: -0.8)]); ears.closeSubpath()
        u.fill(ears, with: .color(fur.color))
        var inner = Path()
        inner.addLines([CGPoint(x: -0.72, y: -0.5), CGPoint(x: -0.66, y: -1.05), CGPoint(x: -0.35, y: -0.78)]); inner.closeSubpath()
        inner.addLines([CGPoint(x: 0.72, y: -0.5), CGPoint(x: 0.66, y: -1.05), CGPoint(x: 0.35, y: -0.78)]); inner.closeSubpath()
        u.fill(inner, with: .color(rgb(1, 0.6, 0.7)))
        u.fill(Path(ellipseIn: CGRect(x: -1, y: -0.95, width: 2, height: 1.9)), with: .color(fur.color))
        u.fill(Path(ellipseIn: CGRect(x: -0.45, y: 0.05, width: 0.9, height: 0.6)), with: .color(light.color))
        // Eyes look around and blink.
        let blink = e.age.truncatingRemainder(dividingBy: 3.1) < 0.14 ? 0.1 : 1.0
        let look = sin(e.age * 0.8) * 0.12
        for sx in [-1.0, 1.0] {
            let ec = CGPoint(x: sx * 0.38, y: -0.2)
            u.fill(Path(ellipseIn: CGRect(x: ec.x - 0.2, y: ec.y - 0.24 * blink, width: 0.4, height: 0.48 * blink)),
                   with: .color(rgb(0.6, 0.95, 0.4)))
            if blink > 0.5 {
                u.fill(Path(ellipseIn: CGRect(x: ec.x - 0.06 + look, y: ec.y - 0.2, width: 0.12, height: 0.4)), with: .color(rgb(0.05, 0.05, 0.05)))
                u.fill(Path(ellipseIn: CGRect(x: ec.x - 0.1 + look, y: ec.y - 0.16, width: 0.07, height: 0.07)), with: .color(.white))
            }
        }
        var nose = Path()
        nose.addLines([CGPoint(x: -0.09, y: 0.12), CGPoint(x: 0.09, y: 0.12), CGPoint(x: 0, y: 0.22)]); nose.closeSubpath()
        u.fill(nose, with: .color(rgb(1, 0.5, 0.6)))
        var mouth = Path()
        mouth.move(to: CGPoint(x: -0.16, y: 0.3)); mouth.addQuadCurve(to: CGPoint(x: 0, y: 0.24), control: CGPoint(x: -0.06, y: 0.36))
        mouth.addQuadCurve(to: CGPoint(x: 0.16, y: 0.3), control: CGPoint(x: 0.06, y: 0.36))
        var whiskers = Path()
        for sx in [-1.0, 1.0] {
            for k in 0..<3 {
                let y = 0.18 + Double(k) * 0.07
                whiskers.move(to: CGPoint(x: sx * 0.3, y: y)); whiskers.addLine(to: CGPoint(x: sx * 0.95, y: y - 0.08 + Double(k) * 0.08))
            }
        }
        u.stroke(mouth, with: .color(rgb(0.1, 0.05, 0.05, 0.8)), lineWidth: 0.025)
        u.stroke(whiskers, with: .color(light.mixed(.white, 0.5).color(0.9)), lineWidth: 0.015)
        // Paws on the roofs while it's up.
        let paws = smoothstep((e.p - 0.18) / 0.08) * (1 - smoothstep((e.p - 0.76) / 0.08))
        if paws > 0 {
            for sx in [-1.0, 1.0] {
                let py = 0.85 + (1 - paws) * 0.6
                u.fill(Path(ellipseIn: CGRect(x: sx * 0.9 - 0.25, y: py, width: 0.5, height: 0.32)), with: .color(fur.color))
                var toes = Path()
                for k in 0..<3 { toes.move(to: CGPoint(x: sx * 0.9 - 0.1 + Double(k) * 0.1, y: py + 0.18)); toes.addLine(to: CGPoint(x: sx * 0.9 - 0.1 + Double(k) * 0.1, y: py + 0.3)) }
                u.stroke(toes, with: .color(rgb(0, 0, 0, 0.35)), lineWidth: 0.02)
            }
        }
    }

    // MARK: Street

    static func drawDonut(_ g: inout GraphicsContext, _ e: FeverActive, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        let R = H * 0.17
        let x = W + R - (W + 2 * R) * e.p
        let y = H * 0.985 - R - abs(sin(e.age * 4)) * H * 0.03
        let angle = -(W + 2 * R) * e.p / R
        // Motion lines.
        var lines = Path()
        for k in 0..<3 {
            let ly = y - R * 0.5 + Double(k) * R * 0.5
            lines.move(to: CGPoint(x: x + R * 1.15, y: ly)); lines.addLine(to: CGPoint(x: x + R * (1.5 + 0.2 * Double(k)), y: ly))
        }
        g.stroke(lines, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: H * 0.006, lineCap: .round))
        var u = g
        u.translateBy(x: x, y: y)
        u.rotate(by: .radians(angle))
        var dough = Path(ellipseIn: CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R))
        dough.addEllipse(in: CGRect(x: -R * 0.32, y: -R * 0.32, width: R * 0.64, height: R * 0.64))
        u.fill(dough, with: .color(rgb(0.86, 0.6, 0.32)), style: FillStyle(eoFill: true))
        var icing = Path()
        let n = 14
        for i in 0...n * 2 {
            let a = Double(i) / Double(n * 2) * 2 * .pi
            let rr = R * (i % 2 == 0 ? 0.88 : 0.8)
            let p = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if i == 0 { icing.move(to: p) } else { icing.addLine(to: p) }
        }
        icing.closeSubpath()
        icing.addEllipse(in: CGRect(x: -R * 0.4, y: -R * 0.4, width: R * 0.8, height: R * 0.8))
        u.fill(icing, with: .color(f.pal.accent.mixed(NeonRGB(1, 0.5, 0.75), 0.5).color), style: FillStyle(eoFill: true))
        let sprinkles = [NeonRGB(1, 1, 1), NeonRGB(1, 0.9, 0.2), NeonRGB(0.3, 0.8, 1), NeonRGB(0.4, 1, 0.5)]
        var r = Seeded(99)
        for i in 0..<18 {
            let a = r.next() * 2 * .pi, d = R * (0.5 + 0.3 * r.next())
            var s = u
            s.translateBy(x: cos(a) * d, y: sin(a) * d)
            s.rotate(by: .radians(r.next() * 3))
            s.fill(Path(roundedRect: CGRect(x: -R * 0.06, y: -R * 0.018, width: R * 0.12, height: R * 0.036), cornerRadius: R * 0.018),
                   with: .color(sprinkles[i % 4].color))
        }
    }

    static func drawParade(_ g: inout GraphicsContext, _ e: FeverActive, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        let gap = H * 0.055
        let count = 22
        let length = gap * Double(count)
        let head = -H * 0.1 + (W + length + H * 0.2) * e.p
        let y = H * 0.915
        let colors = f.pal.bldg.map { $0.mixed(.white, 0.35) } + [f.pal.accent]
        let bounce = f.beat > 0.2 ? f.beat : abs(sin(e.age * 6)) * 0.6
        for i in 0..<count {
            let x = head - Double(i) * gap
            guard x > -H * 0.3, x < W + H * 0.3 else { continue }
            let hop = bounce * H * 0.008 * (i % 2 == 0 ? 1 : 0.6)
            if i % 7 == 3 {
                // A balloon character floating over the marchers, tied to one of them.
                let by = H * 0.6 + sin(e.age * 1.3 + Double(i)) * H * 0.02
                let bx = x + sin(e.age * 0.9 + Double(i)) * H * 0.02
                var string = Path()
                string.move(to: CGPoint(x: x, y: y - H * 0.03)); string.addLine(to: CGPoint(x: bx, y: by + H * 0.07))
                g.stroke(string, with: .color(.white.opacity(0.7)), lineWidth: 1)
                balloonBuddy(&g, CGPoint(x: bx, y: by), H * 0.075, colors[(i / 7) % colors.count], kind: i / 7)
            }
            if i % 9 == 5 {
                // A float with a disco ball.
                let fw = gap * 2.4
                g.fill(Path(roundedRect: CGRect(x: x - fw / 2, y: y - H * 0.06 - hop, width: fw, height: H * 0.06), cornerRadius: H * 0.012),
                       with: .color(colors[(i + 2) % colors.count].color))
                g.fill(Path(CGRect(x: x - fw / 2, y: y - H * 0.03 - hop, width: fw, height: H * 0.008)), with: .color(.white.opacity(0.8)))
                let bc = CGPoint(x: x, y: y - H * 0.1 - hop)
                g.fill(Path(ellipseIn: CGRect(x: bc.x - H * 0.03, y: bc.y - H * 0.03, width: H * 0.06, height: H * 0.06)),
                       with: .color(rgb(0.85, 0.87, 0.95)))
                g.drawLayer { l in
                    l.blendMode = .plusLighter
                    for k in 0..<5 {
                        let a = e.age * 2 + Double(k) * 1.256
                        let sp = CGPoint(x: bc.x + cos(a) * H * 0.02, y: bc.y + sin(a) * H * 0.015)
                        l.fill(Path(ellipseIn: CGRect(x: sp.x - H * 0.005, y: sp.y - H * 0.005, width: H * 0.01, height: H * 0.01)),
                               with: .color(colors[k % colors.count].mixed(.white, 0.5).color))
                    }
                }
                continue
            }
            // A marcher: body, head, tall hat.
            let c = colors[i % colors.count]
            let bh = H * 0.032
            g.fill(Path(roundedRect: CGRect(x: x - H * 0.009, y: y - bh - hop, width: H * 0.018, height: bh), cornerRadius: H * 0.006),
                   with: .color(c.color))
            g.fill(Path(ellipseIn: CGRect(x: x - H * 0.007, y: y - bh - H * 0.015 - hop, width: H * 0.014, height: H * 0.014)),
                   with: .color(rgb(1, 0.85, 0.7)))
            g.fill(Path(CGRect(x: x - H * 0.006, y: y - bh - H * 0.03 - hop, width: H * 0.012, height: H * 0.016)),
                   with: .color(c.mixed(NeonRGB(0, 0, 0), 0.5).color))
            if i % 3 == 0 {
                var baton = Path()
                let a = e.age * 8 + Double(i)
                baton.move(to: CGPoint(x: x + H * 0.012 - cos(a) * H * 0.012, y: y - bh - hop - sin(a) * H * 0.012))
                baton.addLine(to: CGPoint(x: x + H * 0.012 + cos(a) * H * 0.012, y: y - bh - hop + sin(a) * H * 0.012))
                g.stroke(baton, with: .color(.white), lineWidth: max(1, H * 0.003))
            }
        }
    }

    private static func balloonBuddy(_ g: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ color: NeonRGB, kind: Int) {
        if kind % 2 == 0 {
            // A star.
            var star = Path()
            for i in 0..<10 {
                let a = -Double.pi / 2 + Double(i) * .pi / 5
                let rr = i % 2 == 0 ? r : r * 0.5
                let p = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                if i == 0 { star.move(to: p) } else { star.addLine(to: p) }
            }
            star.closeSubpath()
            g.fill(star, with: .color(NeonRGB(1, 0.86, 0.25).color))
        } else {
            // A bear: head and ears.
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.95, y: c.y - r * 0.95, width: r * 0.6, height: r * 0.6)), with: .color(color.color))
            g.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.35, y: c.y - r * 0.95, width: r * 0.6, height: r * 0.6)), with: .color(color.color))
            g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.8, y: c.y - r * 0.75, width: r * 1.6, height: r * 1.55)), with: .color(color.color))
        }
        for sx in [-1.0, 1.0] {
            g.fill(Path(ellipseIn: CGRect(x: c.x + sx * r * 0.25 - r * 0.07, y: c.y - r * 0.15, width: r * 0.14, height: r * 0.18)),
                   with: .color(rgb(0.1, 0.05, 0.1)))
        }
        var smile = Path()
        smile.move(to: CGPoint(x: c.x - r * 0.2, y: c.y + r * 0.18))
        smile.addQuadCurve(to: CGPoint(x: c.x + r * 0.2, y: c.y + r * 0.18), control: CGPoint(x: c.x, y: c.y + r * 0.38))
        g.stroke(smile, with: .color(rgb(0.1, 0.05, 0.1)), lineWidth: max(1, r * 0.06))
    }

    /// The roller-coaster track over the near roofs: a straight run with a loop in the middle.
    static func coasterTrack(W: CGFloat, H: CGFloat) -> [CGPoint] {
        let yb = H * 0.6, cx = W * 0.5, R = H * 0.13
        var pts: [CGPoint] = []
        let steps = 40
        for i in 0...steps {
            let x = -H * 0.3 + (cx + H * 0.3) * Double(i) / Double(steps)
            pts.append(CGPoint(x: x, y: yb + sin(x / H * 9) * H * 0.02 * (1 - Double(i) / Double(steps))))
        }
        for i in 1...60 {
            let th = Double(i) / 60 * 2 * .pi
            pts.append(CGPoint(x: cx + R * sin(th) + H * 0.05 * Double(i) / 60, y: yb - R + R * cos(th)))
        }
        let x1 = cx + H * 0.05
        for i in 1...steps {
            let x = x1 + (W + H * 0.3 - x1) * Double(i) / Double(steps)
            pts.append(CGPoint(x: x, y: yb + sin((x - x1) / H * 9) * H * 0.02 * Double(i) / Double(steps)))
        }
        return pts
    }

    static func drawTrain(_ g: inout GraphicsContext, _ e: FeverActive, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        let pts = coasterTrack(W: W, H: H)
        var lens = [0.0]
        for i in 1..<pts.count { lens.append(lens[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        let total = lens.last!
        let fade = smoothstep(e.p / 0.08) * (1 - smoothstep((e.p - 0.92) / 0.08))
        var track = Path()
        track.addLines(pts)
        // Supports down to the roofs, then rails and ties.
        var posts = Path()
        var i = 0
        while i < pts.count {
            let p = pts[i]
            if p.y > H * 0.52 || i % 20 == 0 { posts.move(to: p); posts.addLine(to: CGPoint(x: p.x, y: H * 0.92)) }
            i += 8
        }
        let steel = f.pal.accent.mixed(.white, 0.3)
        g.stroke(posts, with: .color(f.pal.sign.mixed(.white, 0.2).color(0.8 * fade)), lineWidth: H * 0.006)
        g.stroke(track, with: .color(steel.color(fade)), style: StrokeStyle(lineWidth: H * 0.008, lineCap: .round, lineJoin: .round))
        g.stroke(track, with: .color(steel.mixed(.white, 0.5).color(0.8 * fade)),
                 style: StrokeStyle(lineWidth: H * 0.016, lineCap: .butt, dash: [H * 0.004, H * 0.014]))

        func at(_ s: Double) -> (CGPoint, Double)? {
            guard s >= 0, s <= total else { return nil }
            var k = 1
            while k < lens.count - 1 && lens[k] < s { k += 1 }
            let a = pts[k - 1], b = pts[k]
            let seg = max(0.001, lens[k] - lens[k - 1])
            let u = (s - lens[k - 1]) / seg
            return (CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u), atan2(b.y - a.y, b.x - a.x))
        }
        let carLen = H * 0.075
        let run = max(0, min(1, (e.p - 0.06) / 0.9))
        let headS = (total + carLen * 5) * run
        for k in 0..<4 {
            guard let (p, ang) = at(headS - Double(k) * carLen * 1.1) else { continue }
            var u = g
            u.translateBy(x: p.x, y: p.y)
            u.rotate(by: .radians(ang))
            let c = f.pal.bldg[(k + 1) % 5].mixed(.white, 0.35)
            // Riders with their arms up.
            for r in 0..<2 {
                let rx = -carLen * 0.25 + Double(r) * carLen * 0.35
                u.fill(Path(ellipseIn: CGRect(x: rx - H * 0.008, y: -H * 0.04, width: H * 0.016, height: H * 0.016)), with: .color(rgb(1, 0.85, 0.7)))
                var arms = Path()
                arms.move(to: CGPoint(x: rx - H * 0.006, y: -H * 0.025)); arms.addLine(to: CGPoint(x: rx - H * 0.014, y: -H * 0.055))
                arms.move(to: CGPoint(x: rx + H * 0.006, y: -H * 0.025)); arms.addLine(to: CGPoint(x: rx + H * 0.014, y: -H * 0.055))
                u.stroke(arms, with: .color(rgb(1, 0.85, 0.7)), lineWidth: H * 0.004)
            }
            u.fill(Path(roundedRect: CGRect(x: -carLen / 2, y: -H * 0.03, width: carLen, height: H * 0.028), cornerRadius: H * 0.008),
                   with: .color(c.color))
            u.fill(Path(CGRect(x: -carLen / 2, y: -H * 0.02, width: carLen, height: H * 0.005)), with: .color(.white.opacity(0.7)))
        }
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
    Color(.sRGB, red: r, green: g, blue: b, opacity: max(0, min(1, a)))
}
