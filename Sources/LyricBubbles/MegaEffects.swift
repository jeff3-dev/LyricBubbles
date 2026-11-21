import SwiftUI

// MARK: - Weather, smoke, accent hits and the finishing pass

enum MegaFX {
    /// How much weather now: the mood's own amount, swelling with energy when the reaction is on.
    static func amount(_ kit: MegaKit, base: Double) -> Double {
        base * (0.45 + kit.weather * (0.3 + 0.9 * kit.f.level))
    }

    /// Cigarette smoke: soft puffs curling up from each source.
    static func smoke(_ g: inout GraphicsContext, _ kit: MegaKit, _ sources: [CGPoint]) {
        guard !sources.isEmpty else { return }
        let f = kit.f
        let amt = amount(kit, base: max(0.25, f.s.mood.smoke))
        let n = Int(8 + 10 * amt)
        let c: NeonRGB = switch kit.look {
        case .deco: MegaKit.gold.mixed(.white, 0.5)
        case .noir: NeonRGB(0.9, 0.9, 0.92)
        case .comic: NeonRGB(1, 1, 1)
        case .neon: kit.pal.pop.mixed(.white, 0.4)
        }
        for (si, s) in sources.enumerated() {
            for k in 0..<n {
                let life = (f.t * 0.16 + Double(k) / Double(n) + Double(si) * 0.37).truncatingRemainder(dividingBy: 1)
                let rise = CGFloat(life) * 300
                let x = s.x + CGFloat(sin(life * 9 + Double(si) + f.t * 0.6)) * (8 + rise * 0.2) + rise * 0.15
                let y = s.y - rise
                let r = 5 + CGFloat(life) * 34
                let a = (1 - life) * min(1, life * 8) * 0.22 * amt
                let puff = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                if kit.look == .comic {
                    g.stroke(puff, with: .color(MegaKit.ink.color(a * 2.2)), lineWidth: 1.5 * kit.u)
                    g.fill(puff, with: .color(c.color(a * 2)))
                } else {
                    g.fill(puff, with: .radialGradient(Gradient(colors: [c.color(a), c.color(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                }
            }
        }
    }

    /// Weather drawn in the scene: Neon steam from vents, Comic dust clouds at the floor.
    static func weatherStage(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        let f = kit.f
        switch kit.look {
        case .neon:
            let amt = amount(kit, base: 0.7)
            for (vi, v) in sc.vents.enumerated() {
                for k in 0..<10 {
                    let life = (f.t * 0.12 + Double(k) / 10 + Double(vi) * 0.5).truncatingRemainder(dividingBy: 1)
                    let r = 30 + CGFloat(life) * 120
                    let p = CGPoint(x: v.x + CGFloat(sin(life * 5 + Double(vi))) * 30, y: v.y - CGFloat(life) * 380)
                    let a = (1 - life) * min(1, life * 5) * 0.16 * amt
                    g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .radialGradient(Gradient(colors: [kit.pal.accent.mixed(.white, 0.5).color(a), .clear]), center: p, startRadius: 0, endRadius: r))
                }
            }
        case .comic:
            // Dust clouds puff up at the feet on beats.
            guard f.beat > 0.2, kit.weather > 0 else { return }
            let k = 1 - f.beat
            var p = Path()
            for m in sc.cast {
                let (feet, _) = m.feetNow(f.t)
                for j in 0..<5 {
                    let dx = CGFloat(j - 2) * 34 * CGFloat(1 + k)
                    let r = CGFloat(18 + 10 * k) * CGFloat(j % 2 == 0 ? 1 : 0.75)
                    p.addEllipse(in: CGRect(x: feet.x + dx - r, y: feet.y - r * 1.2 - CGFloat(k) * 20, width: r * 2, height: r * 1.6))
                }
            }
            let a = f.beat * min(1, kit.weather)
            g.fill(p, with: .color(NeonRGB(0.95, 0.9, 0.78).color(a * 0.9)))
            g.stroke(p, with: .color(MegaKit.ink.color(a)), lineWidth: 2 * kit.u)
        default: break
        }
    }

    /// Weather on the screen: rain (outdoors), haze, Comic speed lines.
    static func weatherScreen(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        let f = kit.f
        let w = f.size.width, h = f.size.height
        var rain = f.s.mood.rain
        if kit.look == .noir { rain = max(rain, f.s[.noirRain]) }
        if sc.outdoor, rain > 0.02 {
            let amt = amount(kit, base: rain)
            let n = Int(40 + 260 * amt)
            var r = Seeded(99)
            var p = Path()
            let slant = 0.18
            for _ in 0..<n {
                let speed = 900 + r.next() * 700
                let len = 14 + r.next() * 22
                let x0 = r.next() * (w + 200) - 100
                let y = (r.next() * (h + 100) + f.t * speed).truncatingRemainder(dividingBy: h + 100) - 50
                let x = x0 + y * slant
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x - len * slant, y: y - len))
            }
            let c: Color = switch kit.look {
            case .deco: MegaKit.gold.mixed(.white, 0.5).color(0.35)
            case .noir: .white.opacity(0.4)
            case .comic: .white.opacity(0.75)
            case .neon: kit.pal.pop.mixed(.white, 0.5).color(0.35)
            }
            g.stroke(p, with: .color(c), lineWidth: kit.look == .comic ? 1.6 : 1.1)
        }
        // Low haze.
        let fog = f.s.mood.fog * (kit.look == .comic ? 0.3 : 1)
        if fog > 0.02 {
            let hz = amount(kit, base: fog)
            let c: NeonRGB = switch kit.look {
            case .deco: kit.pal.warm
            case .noir: NeonRGB(0.8, 0.82, 0.85)
            case .comic: NeonRGB(1, 1, 1)
            case .neon: kit.pal.accent
            }
            g.fill(Path(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55)),
                   with: .linearGradient(Gradient(colors: [c.color(0), c.color(0.12 * hz), c.color(0.04 * hz)]),
                                         startPoint: CGPoint(x: 0, y: h * 0.45), endPoint: CGPoint(x: 0, y: h)))
        }
        // Comic speed lines from the edges when it gets loud.
        if kit.look == .comic, kit.weather > 0 {
            let a = max(0, f.level - 0.55) * 2.2 * min(1, kit.weather)
            if a > 0.03 {
                var r = Seeded(UInt64(Int(f.t * 8) & 0xffff) + 1)
                var p = Path()
                let c = CGPoint(x: w / 2, y: h / 2)
                for _ in 0..<40 {
                    let ang = r.next() * .pi * 2
                    let r0 = max(w, h) * (0.42 + r.next() * 0.12), r1 = max(w, h) * 0.9
                    let spread = 0.006 + r.next() * 0.01
                    p.move(to: CGPoint(x: c.x + cos(ang) * r0, y: c.y + sin(ang) * r0))
                    p.addLine(to: CGPoint(x: c.x + cos(ang - spread) * r1, y: c.y + sin(ang - spread) * r1))
                    p.addLine(to: CGPoint(x: c.x + cos(ang + spread) * r1, y: c.y + sin(ang + spread) * r1))
                    p.closeSubpath()
                }
                g.fill(p, with: .color(MegaKit.ink.color(min(0.85, a))))
            }
        }
    }

    // MARK: Accent hits

    static func accent(_ g: inout GraphicsContext, _ kit: MegaKit, _ shot: MegaShot) {
        let f = kit.f
        guard let hit = f.hit, kit.accents > 0 else { return }
        let a = hit.age
        let w = f.size.width, h = f.size.height
        var r = Seeded(UInt64(hit.id) &* 2654435761 &+ 17)
        let strength = min(1.4, kit.accents)
        switch kit.look {
        case .deco:
            // Gold sparkle burst.
            guard a < 1.1 else { return }
            let c = CGPoint(x: w * (0.2 + r.next() * 0.6), y: h * (0.15 + r.next() * 0.4))
            let n = 14
            let k = 1 - pow(1 - min(1, a / 1.1), 3)
            var p = Path()
            for i in 0..<n {
                let ang = Double(i) / Double(n) * .pi * 2 + r.next() * 0.3
                let d = CGFloat(k) * min(w, h) * (0.12 + 0.14 * r.next())
                let s = CGFloat(1 - a / 1.1) * min(w, h) * 0.022 * (0.6 + r.next())
                let q = CGPoint(x: c.x + cos(ang) * d, y: c.y + sin(ang) * d)
                p.move(to: CGPoint(x: q.x, y: q.y - s * 2))
                p.addQuadCurve(to: CGPoint(x: q.x + s * 2, y: q.y), control: q)
                p.addQuadCurve(to: CGPoint(x: q.x, y: q.y + s * 2), control: q)
                p.addQuadCurve(to: CGPoint(x: q.x - s * 2, y: q.y), control: q)
                p.addQuadCurve(to: CGPoint(x: q.x, y: q.y - s * 2), control: q)
            }
            MegaLooks.glow(&g, MegaKit.gold, at: c, r: min(w, h) * 0.2, a: 0.35 * (1 - a / 1.1) * strength)
            g.fill(p, with: .color(MegaKit.gold.mixed(.white, 0.45).color(min(1, strength))))
        case .noir:
            // Lightning: a double flash and a bolt across the sky.
            let flash = (a < 0.08 ? 1 : (a > 0.16 && a < 0.26 ? 0.7 : 0)) * exp(-a * 2)
            if flash > 0 {
                g.fill(Path(CGRect(origin: .zero, size: f.size)), with: .color(.white.opacity(0.55 * flash * min(1, strength))))
            }
            if a < 0.3 {
                var p = Path()
                var x = w * (0.15 + r.next() * 0.7), y: CGFloat = 0
                p.move(to: CGPoint(x: x, y: y))
                while y < h * 0.5 {
                    x += (r.next() - 0.5) * w * 0.08
                    y += h * (0.04 + r.next() * 0.05)
                    p.addLine(to: CGPoint(x: x, y: y))
                }
                g.stroke(p, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineJoin: .miter))
                g.stroke(p, with: .color(.white.opacity(0.2)), style: StrokeStyle(lineWidth: 9, lineJoin: .miter))
            }
        case .comic:
            // SFX burst: a spiky star with a sound word.
            guard a < 1.0 else { return }
            let words = ["BOOM!", "WHAM!", "BWAAP!", "POW!", "KRAK!", "ZING!", "BAM!", "WHOOM!"]
            let word = words[Int(r.next() * Double(words.count)) % words.count]
            let c = CGPoint(x: w * (0.22 + r.next() * 0.56), y: h * (0.18 + r.next() * 0.3))
            let pop = a < 0.12 ? a / 0.12 * 1.2 : (a < 0.2 ? 1.2 - (a - 0.12) / 0.08 * 0.2 : 1)
            let fade = a > 0.75 ? 1 - (a - 0.75) / 0.25 : 1
            let R = min(w, h) * 0.17 * CGFloat(pop) * CGFloat(0.8 + 0.3 * min(1, strength))
            var star = Path()
            let spikes = 13
            for i in 0..<(spikes * 2) {
                let ang = Double(i) / Double(spikes * 2) * .pi * 2 - .pi / 2
                let rr = i % 2 == 0 ? R * CGFloat(0.95 + 0.25 * r.next()) : R * 0.62
                let q = CGPoint(x: c.x + cos(ang) * rr * 1.3, y: c.y + sin(ang) * rr)
                if i == 0 { star.move(to: q) } else { star.addLine(to: q) }
            }
            star.closeSubpath()
            var gg = g
            gg.opacity = fade
            gg.fill(star.offsetBy(dx: 5, dy: 5), with: .color(MegaKit.ink.color))
            gg.fill(star, with: .color(NeonRGB(1, 0.86, 0.15).color))
            gg.fill(star.applying(CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: 0.7, y: 0.7).translatedBy(x: -c.x, y: -c.y)),
                    with: .color(NeonRGB(0.95, 0.2, 0.15).color))
            gg.stroke(star, with: .color(MegaKit.ink.color), style: StrokeStyle(lineWidth: 3, lineJoin: .miter))
            let fs = R * 0.48
            let font = Font.custom("ChalkboardSE-Bold", size: fs)
            var tg = gg
            tg.translateBy(x: c.x, y: c.y)
            tg.rotate(by: .degrees(-10 + r.next() * 20))
            for (dx, dy) in [(-2.5, 0.0), (2.5, 0), (0, -2.5), (0, 2.5), (-2, -2), (2, 2), (2, -2), (-2, 2)] {
                tg.draw(Text(word).font(font).foregroundColor(MegaKit.ink.color), at: CGPoint(x: dx, y: dy))
            }
            tg.draw(Text(word).font(font).foregroundColor(NeonRGB(1, 0.95, 0.4).color), at: .zero)
        case .neon:
            // Sparks spraying from a tube; the tubes flicker (see `neonBright`).
            guard a < 1.2 else { return }
            let src = CGPoint(x: w * (0.15 + r.next() * 0.7), y: h * (0.1 + r.next() * 0.35))
            var p = Path()
            for _ in 0..<26 {
                let vx = (r.next() - 0.5) * 420, vy = -120 - r.next() * 200
                let tt = a * (0.7 + r.next() * 0.5)
                let x = src.x + CGFloat(vx * tt), y = src.y + CGFloat(vy * tt + 600 * tt * tt)
                let x2 = src.x + CGFloat(vx * (tt - 0.03)), y2 = src.y + CGFloat(vy * (tt - 0.03) + 600 * (tt - 0.03) * (tt - 0.03))
                p.move(to: CGPoint(x: x2, y: y2))
                p.addLine(to: CGPoint(x: x, y: y))
            }
            let fade = max(0, 1 - a / 1.2)
            MegaLooks.glow(&g, kit.pal.warm, at: src, r: 70, a: 0.6 * fade * (a < 0.1 ? 1.5 : 1))
            g.stroke(p, with: .color(NeonRGB(1, 0.85, 0.5).color(fade)), lineWidth: 2)
        }
    }

    // MARK: Finishing pass: paper, grain, vignette, panel border

    static func post(_ g: inout GraphicsContext, _ kit: MegaKit) {
        let f = kit.f
        let full = CGRect(origin: .zero, size: f.size)
        if kit.look == .comic {
            let paper = f.s[.comicPaper]
            if paper > 0.02 {
                var p = g
                p.blendMode = .multiply
                p.opacity = 0.25 + 0.6 * paper
                p.fill(Path(full), with: .tiledImage(Image(decorative: f.tex.paper, scale: 1), origin: .zero,
                                                     sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1))
            }
        }
        let grain = f.s[.grain]
        if grain > 0.02 {
            var gr = g
            gr.blendMode = .overlay
            gr.opacity = grain * (kit.look == .noir ? 0.55 : 0.35)
            var r = Seeded(UInt64(Int(f.t * 24) & 0xffff) + 9)
            gr.fill(Path(full), with: .tiledImage(Image(decorative: f.tex.grain, scale: 1),
                                                  origin: CGPoint(x: r.next() * 128, y: r.next() * 128),
                                                  sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1))
        }
        let vig = f.s[.vignette]
        if vig > 0.02 {
            let c = CGPoint(x: full.midX, y: full.midY)
            let rr = hypot(full.width, full.height) / 2
            g.fill(Path(full), with: .radialGradient(Gradient(stops: [.init(color: .clear, location: 0.45),
                                                                      .init(color: .black.opacity(0.75 * vig), location: 1)]),
                                                     center: c, startRadius: 0, endRadius: rr))
        }
        if kit.look == .comic {
            // The panel border: white gutter and an ink line.
            let inset: CGFloat = 7
            var frame = Path(full)
            frame.addRect(full.insetBy(dx: inset, dy: inset))
            g.fill(frame, with: .color(NeonRGB(0.97, 0.95, 0.88).color), style: FillStyle(eoFill: true))
            g.stroke(Path(full.insetBy(dx: inset, dy: inset)), with: .color(MegaKit.ink.color), lineWidth: 3)
        }
        if kit.look == .deco {
            // A thin gold double rule around the frame.
            g.stroke(Path(full.insetBy(dx: 8, dy: 8)), with: .color(MegaKit.gold.color(0.55)), lineWidth: 1.5)
            g.stroke(Path(full.insetBy(dx: 13, dy: 13)), with: .color(MegaKit.gold.color(0.3)), lineWidth: 0.8)
        }
    }
}

// MARK: - Transitions

/// Look-specific cuts: Deco iris or fan wipe, Noir ink bleed or blinds wipe, Comic panel
/// slam or page tear, Neon flicker-out. Two variants each, alternating per shot.
enum MegaTransitions {
    static func draw(_ ctx: inout GraphicsContext, _ kit: MegaKit, prev: MegaShot, next: (inout GraphicsContext) -> Void) {
        let f = kit.f
        let p = f.cut
        let w = f.size.width, h = f.size.height
        let alt = f.shot.index % 2 == 1
        let e = smoothstep(p)
        switch kit.look {
        case .deco:
            var mask = Path()
            var edge = Path()
            if alt {
                let c = CGPoint(x: w / 2, y: h * 0.55)
                let r = hypot(w, h) * 0.6 * e
                mask.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                edge = mask
            } else {
                let c = CGPoint(x: w / 2, y: h + 4)
                let R = hypot(w, h) * 1.1
                let a1 = Double.pi + Double.pi * e
                mask.move(to: c)
                mask.addArc(center: c, radius: R, startAngle: .radians(.pi), endAngle: .radians(a1), clockwise: false)
                mask.closeSubpath()
                edge.move(to: c)
                edge.addLine(to: CGPoint(x: c.x + cos(a1) * R, y: c.y + sin(a1) * R))
            }
            var g = ctx
            g.clip(to: mask)
            next(&g)
            ctx.stroke(edge, with: .color(MegaKit.gold.color), lineWidth: 6)
            ctx.stroke(edge, with: .color(MegaKit.gold.mixed(.white, 0.5).color), lineWidth: 1.5)
        case .noir:
            var mask = Path()
            if alt {
                let n = 12
                let sh = h / CGFloat(n)
                for i in 0..<n { mask.addRect(CGRect(x: 0, y: CGFloat(i) * sh, width: w, height: sh * e)) }
            } else {
                var r = Seeded(UInt64(f.shot.index) + 71)
                for _ in 0..<9 {
                    let c = CGPoint(x: r.next() * w, y: r.next() * h)
                    let rad = hypot(w, h) * 0.45 * CGFloat(e) * CGFloat(0.6 + r.next() * 0.8)
                    mask.addEllipse(in: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
                    // Ragged ink edge.
                    for k in 0..<6 {
                        let ang = r.next() * .pi * 2
                        let rr = rad * 0.35
                        let q = CGPoint(x: c.x + cos(ang) * rad * 0.9, y: c.y + sin(ang) * rad * 0.9)
                        mask.addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
                        _ = k
                    }
                }
            }
            // Ink first, then the new scene bleeding through it.
            ctx.fill(mask, with: .color(.black.opacity(min(1, p * 3))))
            var g = ctx
            let inner = alt ? mask : mask.applying(.identity)
            g.clip(to: inner)
            g.opacity = alt ? 1 : max(0, min(1, (p - 0.25) / 0.6))
            next(&g)
        case .comic:
            if alt {
                // Panel slam: the new panel slides in from the right and overshoots.
                let k = p < 0.7 ? smoothstep(p / 0.7) * 1.04 : 1.04 - 0.04 * smoothstep((p - 0.7) / 0.3)
                let x = w * (1 - CGFloat(k))
                let rect = CGRect(x: x, y: 0, width: w + 40, height: h)
                var g = ctx
                g.clip(to: Path(rect))
                g.translateBy(x: x, y: 0)
                next(&g)
                ctx.fill(Path(CGRect(x: x - 10, y: 0, width: 10, height: h)), with: .color(NeonRGB(0.97, 0.95, 0.88).color))
                ctx.stroke(Path(CGRect(x: x, y: -10, width: w + 40, height: h + 20)), with: .color(MegaKit.ink.color), lineWidth: 4)
            } else {
                // Page tear: a jagged edge sweeping right to left, a strip of white paper at the tear.
                let ex = w * (1.1 - 1.2 * CGFloat(e))
                var r = Seeded(UInt64(f.shot.index) + 5)
                var edgePts: [CGPoint] = []
                var y: CGFloat = -10
                while y < h + 20 {
                    edgePts.append(CGPoint(x: ex + (r.next() - 0.5) * 34 + (y / h) * 60, y: y))
                    y += 18 + r.next() * 22
                }
                var mask = Path()
                mask.move(to: CGPoint(x: w + 100, y: -10))
                mask.addLines(edgePts)
                mask.addLine(to: CGPoint(x: w + 100, y: h + 20))
                mask.closeSubpath()
                var g = ctx
                g.clip(to: mask)
                next(&g)
                var strip = Path()
                strip.addLines(edgePts)
                ctx.stroke(strip, with: .color(NeonRGB(0.97, 0.95, 0.88).color), style: StrokeStyle(lineWidth: 12, lineJoin: .bevel))
                ctx.stroke(strip.offsetBy(dx: -6, dy: 0), with: .color(MegaKit.ink.color(0.6)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .bevel))
            }
        case .neon:
            // Flicker out, then flicker on.
            var r = Seeded(UInt64(Int(f.t * 40) & 0xffff) + 13)
            let on = r.next() > 0.5
            if p < 0.5 {
                let dark = smoothstep(p / 0.5) * (on ? 1 : 0.7)
                ctx.fill(Path(CGRect(origin: .zero, size: f.size)), with: .color(.black.opacity(dark)))
            } else {
                ctx.fill(Path(CGRect(origin: .zero, size: f.size)), with: .color(.black))
                var g = ctx
                let k = smoothstep((p - 0.5) / 0.5)
                g.opacity = p > 0.92 ? 1 : (on ? k : k * 0.25)
                next(&g)
            }
        }
    }
}

// MARK: - Phase 2 props: billiards break, marquee chase, record crates

extension MegaFX {
    private static func outline(_ kit: MegaKit) -> CGFloat { (1.5 + kit.f.s[.comicOutline] * 4) * kit.u }

    // MARK: Billiards

    /// Ball colours by number (8 is black; 9–15 are striped 1–7).
    private static let ballColors: [NeonRGB] = [NeonRGB(0.98, 0.98, 0.94), NeonRGB(0.98, 0.8, 0.1), NeonRGB(0.1, 0.25, 0.8), NeonRGB(0.85, 0.12, 0.1),
                                                NeonRGB(0.4, 0.15, 0.6), NeonRGB(0.98, 0.5, 0.1), NeonRGB(0.1, 0.55, 0.25), NeonRGB(0.5, 0.12, 0.1),
                                                NeonRGB(0.05, 0.05, 0.05)]
    private static let rackOrder = [1, 9, 2, 10, 8, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15]

    /// Folds a coordinate back into [lo, hi] as if it bounced off the rails.
    private static func fold(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        let l = hi - lo
        var u = (v - lo).truncatingRemainder(dividingBy: 2 * l)
        if u < 0 { u += 2 * l }
        return lo + (u > l ? 2 * l - u : u)
    }

    /// The felt, the pockets and the balls. The rack breaks on each accent hit, the balls roll
    /// to a stop, and after a while they're racked again.
    static func billiards(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        guard let tb = sc.table else { return }
        let f = kit.f
        let felt = tb.felt
        switch kit.look {
        case .deco:
            g.fill(felt, with: .color(kit.color(.pop, 0.36).color))
            g.stroke(felt, with: .color(MegaKit.gold.color(0.8)), lineWidth: 2.5)
        case .noir:
            g.fill(felt, with: .color(kit.color(.pop, 0.42).color))
        case .comic:
            g.fill(felt, with: .color(kit.color(.pop, 0.4).color))
            MegaLooks.halftone(&g, kit, felt, amount: 0.2)
            g.stroke(felt, with: .color(MegaKit.ink.color), lineWidth: outline(kit))
        case .neon:
            g.fill(felt, with: .color(kit.color(.pop, 0.5).color))
            MegaLooks.tube(&g, felt, kit.pal.pop, kit, width: 2, bright: MegaLooks.neonBright(kit, 91))
        }
        // The pool of lamplight on the felt.
        let lc = kit.look == .noir ? NeonRGB(1, 1, 0.95) : kit.pal.warm
        var lit = g
        lit.clip(to: felt)
        let mid = tb.project(0.5, 0.25)
        lit.fill(Path(ellipseIn: CGRect(x: mid.x - 380, y: mid.y - 70, width: 760, height: 140)),
                 with: .radialGradient(Gradient(colors: [lc.color(0.28 * kit.pulse), lc.color(0)]), center: mid, startRadius: 0, endRadius: 380))
        // Pockets.
        var pockets = Path()
        for (x, y) in [(0.0, 0.0), (0.5, 0.0), (1.0, 0.0), (0.0, 0.5), (0.5, 0.5), (1.0, 0.5)] as [(CGFloat, CGFloat)] {
            let p = tb.project(x, y), r = tb.ball * (y > 0 ? 1.3 : 1.05)
            pockets.addEllipse(in: CGRect(x: p.x - r, y: p.y - r * 0.5, width: r * 2, height: r))
        }
        g.fill(pockets, with: .color(.black))

        // Where each ball is: racked, breaking, at rest, or gliding back to the rack.
        let d: CGFloat = 0.03, apex = CGPoint(x: 0.7, y: 0.25)
        var rack: [CGPoint] = [CGPoint(x: 0.25, y: 0.25)]
        for r in 0..<5 { for j in 0...r { rack.append(CGPoint(x: apex.x + CGFloat(r) * d * 0.87, y: apex.y + (CGFloat(j) - CGFloat(r) / 2) * d)) } }
        let a = f.lastHit.age, id = f.lastHit.id
        let breaking = kit.accents > 0 && id > 0 && a < 9.5
        var pos = rack
        if breaking {
            var rng = Seeded(UInt64(id) &* 6364136223846793005 &+ 99)
            let back = smoothstep(max(0, min(1, (a - 8) / 1.5)))
            for i in 0..<pos.count {
                let start = i == 0 ? CGPoint(x: apex.x - d, y: apex.y) : rack[i]
                var ang = i == 0 ? Double.pi + (rng.next() - 0.5) * 0.9 : atan2(Double(rack[i].y - apex.y), Double(rack[i].x - apex.x + d)) + (rng.next() - 0.5) * 1.2
                if i == 1 { ang += (rng.next() - 0.5) * 0.6 }
                let dist = CGFloat(i == 0 ? 0.1 + rng.next() * 0.25 : 0.2 + rng.next() * 0.7)
                var p: CGPoint
                if i == 0, a < 0.12 {
                    let k = CGFloat(a / 0.12)
                    p = CGPoint(x: rack[0].x + (start.x - rack[0].x) * k, y: start.y)
                } else {
                    let s = dist * CGFloat(1 - exp(-3.2 * max(0, a - 0.12)))
                    p = CGPoint(x: fold(start.x + CGFloat(cos(ang)) * s, 0.02, 0.98), y: fold(start.y + CGFloat(sin(ang)) * s * 0.6, 0.02, 0.48))
                }
                pos[i] = CGPoint(x: p.x + (rack[i].x - p.x) * back, y: p.y + (rack[i].y - p.y) * back)
            }
        }
        // Draw far to near.
        let ow = outline(kit)
        for i in pos.indices.sorted(by: { pos[$0].y < pos[$1].y }) {
            let n = i == 0 ? 0 : rackOrder[i - 1]
            let q = pos[i]
            let foot = tb.project(q.x, q.y)
            let r = tb.ball * (0.8 + 0.2 * q.y / 0.5)
            let c = CGPoint(x: foot.x, y: foot.y - r * 0.8)
            let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            g.fill(Path(ellipseIn: CGRect(x: foot.x - r * 1.1 + 3, y: foot.y - r * 0.3, width: r * 2.3, height: r * 0.7)), with: .color(.black.opacity(0.4)))
            var col = ballColors[n > 8 ? n - 8 : n]
            let striped = n > 8
            switch kit.look {
            case .deco: col = col.mixed(MegaKit.gold, 0.2)
            case .noir:
                let l = 0.3 * col.r + 0.59 * col.g + 0.11 * col.b
                col = NeonRGB(l, l, l * 1.03)
            default: break
            }
            if kit.look == .neon {
                MegaLooks.glow(&g, n == 0 ? NeonRGB(1, 1, 1) : col, at: c, r: r * 2.4, a: 0.3)
                g.fill(disc, with: .color(Color(white: 0.03)))
                g.stroke(disc, with: .color((n == 8 ? kit.pal.pop : col).mixed(.white, 0.4).color), lineWidth: 1.6 * kit.u)
                if striped { g.fill(Path(CGRect(x: c.x - r * 0.9, y: c.y - r * 0.25, width: r * 1.8, height: r * 0.5)), with: .color(col.color(0.7))) }
            } else {
                g.fill(disc, with: .color((striped ? NeonRGB(0.96, 0.95, 0.9) : col).color))
                if striped {
                    var b = g
                    b.clip(to: disc)
                    b.fill(Path(CGRect(x: c.x - r, y: c.y - r * 0.42, width: r * 2, height: r * 0.84)), with: .color(col.color))
                }
                g.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.6, width: r * 0.45, height: r * 0.35)), with: .color(.white.opacity(0.7)))
                if kit.look == .comic { g.stroke(disc, with: .color(MegaKit.ink.color), lineWidth: ow * 0.6) }
                if kit.look == .deco, n == 8 { g.stroke(disc, with: .color(MegaKit.gold.color(0.7)), lineWidth: 1.5) }
            }
        }
        // The crack of the break.
        if breaking, a < 0.4 {
            let p = tb.project(apex.x, apex.y)
            let k = 1 - a / 0.4
            switch kit.look {
            case .comic:
                var star = Path()
                let n = 10
                for j in 0..<(n * 2) {
                    let rr: CGFloat = (j % 2 == 0 ? 70 : 30) * CGFloat(0.6 + 0.4 * k)
                    let an = Double(j) / Double(n * 2) * .pi * 2
                    let pt = CGPoint(x: p.x + CGFloat(cos(an)) * rr, y: p.y - 14 + CGFloat(sin(an)) * rr * 0.6)
                    if j == 0 { star.move(to: pt) } else { star.addLine(to: pt) }
                }
                star.closeSubpath()
                g.fill(star, with: .color(NeonRGB(1, 0.92, 0.3).color(k)))
                g.stroke(star, with: .color(MegaKit.ink.color(k)), lineWidth: ow)
            default:
                MegaLooks.glow(&g, kit.look == .noir ? NeonRGB(1, 1, 1) : kit.pal.warm.mixed(.white, 0.4), at: CGPoint(x: p.x, y: p.y - 12), r: 110, a: 0.8 * k)
            }
        }
    }

    // MARK: Marquee

    /// The blade sign's letters and the chase bulbs: every third bulb lit, stepping on each beat.
    static func marquee(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        guard let m = sc.marquee else { return }
        let f = kit.f
        // Blade letters.
        let chars = Array(m.word)
        let cell = m.blade.height / CGFloat(max(1, chars.count))
        let fs = min(cell * 0.78, m.blade.width * 0.78)
        let font = MegaWords.font(kit.look, heavy: true)
        for (k, ch) in chars.enumerated() {
            let p = CGPoint(x: m.blade.midX, y: m.blade.minY + cell * (CGFloat(k) + 0.5))
            let c: NeonRGB
            var alpha = 1.0
            switch kit.look {
            case .deco: c = MegaKit.gold.mixed(.white, 0.2)
            case .noir: c = NeonRGB(0.95, 0.95, 0.92)
            case .comic: c = NeonRGB(1, 0.9, 0.3)
            case .neon:
                c = kit.pal.pop.mixed(.white, 0.25)
                alpha = MegaLooks.neonBright(kit, 120 + k)
                MegaLooks.glow(&g, kit.pal.pop, at: p, r: fs * 0.9, a: 0.4 * alpha)
            }
            if kit.look != .neon { MegaLooks.glow(&g, c, at: p, r: fs * 0.7, a: 0.18 * kit.pulse) }
            g.draw(g.resolve(Text(String(ch)).font(font(fs)).foregroundColor(c.color(alpha))), at: p, anchor: .center)
        }
        // The letterboard: the song title, unless the lyrics are using it as their sign.
        if MegaWords.mode(kit) != .sign {
            let r = sc.signRect.insetBy(dx: 30, dy: 12)
            let ink: Color = switch kit.look {
            case .deco: kit.pal.base.mixed(.black, 0.3).color
            case .noir: .black
            case .comic: MegaKit.ink.color
            case .neon: kit.pal.pop.mixed(.white, 0.35).color(MegaLooks.neonBright(kit, 130))
            }
            let small = g.resolve(Text(sc.variant == 1 ? "TONIGHT ONLY" : "NOW SHOWING").font(font(r.height * 0.2)).foregroundColor(ink.opacity(0.75)))
            g.draw(small, at: CGPoint(x: r.midX, y: r.minY + r.height * 0.12), anchor: .center)
            let title = f.title.isEmpty ? "MIDNIGHT FEATURE" : f.title.uppercased()
            var tfs = r.height * 0.5
            var t = g.resolve(Text(title).font(font(tfs)).foregroundColor(ink))
            for _ in 0..<8 where t.measure(in: CGSize(width: 10_000, height: 1000)).width > r.width {
                tfs *= 0.86
                t = g.resolve(Text(title).font(font(tfs)).foregroundColor(ink))
            }
            g.draw(t, at: CGPoint(x: r.midX, y: r.minY + r.height * 0.62), anchor: .center)
        }
        // Chase: on beats when the lights react, plus a slow drift so it never stops dead.
        let step = (kit.lights > 0 ? f.beats : 0) + Int(f.t * (kit.lights > 0 ? 0.6 : 2.5))
        let ow = outline(kit)
        var dark = Path(), lit = Path()
        let r: CGFloat = 6.5
        var litPts: [CGPoint] = []
        for (i, p) in m.bulbs.enumerated() {
            let on = ((i - step) % 3 + 3) % 3 == 0
            let disc = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            if on { lit.addEllipse(in: disc); litPts.append(p) } else { dark.addEllipse(in: disc) }
        }
        let b = 0.8 + 0.35 * f.beat * kit.lights
        var c = kit.pal.warm
        switch kit.look {
        case .deco: c = c.mixed(MegaKit.gold, 0.4).mixed(.white, 0.2)
        case .noir: c = NeonRGB(1, 0.98, 0.92)
        case .comic: c = NeonRGB(1, 0.95, 0.45)
        case .neon: break
        }
        switch kit.look {
        case .comic:
            let big = CGFloat(1.25 + 0.2 * f.beat)
            var litBig = Path()
            for p in litPts { litBig.addEllipse(in: CGRect(x: p.x - r * big, y: p.y - r * big, width: r * 2 * big, height: r * 2 * big)) }
            g.fill(dark, with: .color(NeonRGB(0.8, 0.7, 0.5).color))
            g.stroke(dark, with: .color(MegaKit.ink.color), lineWidth: ow * 0.5)
            g.fill(litBig, with: .color(c.color))
            g.stroke(litBig, with: .color(MegaKit.ink.color), lineWidth: ow * 0.6)
        default:
            g.fill(dark, with: .color(c.mixed(.black, 0.7).color))
            for p in litPts { MegaLooks.glow(&g, c, at: p, r: m.bulbSize * (kit.look == .neon ? 1.5 : 1.2), a: 0.5 * b) }
            g.fill(lit, with: .color(c.mixed(.white, 0.6).color))
        }
    }

    // MARK: Record shop

    /// A record sleeve: the cover art, or one of a few seeded designs in the look's palette.
    static func sleeve(_ g: inout GraphicsContext, _ kit: MegaKit, _ r: CGRect, seed: Int, art: Bool) {
        let f = kit.f
        let box = Path(r)
        if art, let img = f.art {
            g.draw(Image(decorative: img, scale: 1).resizable(), in: r)
            if kit.look == .comic { MegaLooks.halftone(&g, kit, box, amount: 0.12) }
            if kit.look == .neon { g.fill(box, with: .color(.black.opacity(0.2))) }
            if kit.look == .noir { g.fill(box, with: .color(.black.opacity(0.15))) }
        } else {
            var rng = Seeded(UInt64(seed &* 7919 &+ 13))
            let hues: [MegaHue] = [.accent, .pop, .warm, .mid, .sky]
            let h1 = hues[Int(rng.next() * 5)], h2 = hues[Int(rng.next() * 5)]
            let neon = kit.look == .neon
            g.fill(box, with: .color(kit.color(h1, 0.35 + rng.next() * 0.3).color))
            let fg = neon ? kit.pal[h2].color(0.55) : kit.color(h2, 0.62 + rng.next() * 0.25).color
            var d = g
            d.clip(to: box)
            switch Int(rng.next() * 4) {
            case 0:
                let rr = r.width * CGFloat(0.22 + rng.next() * 0.16)
                d.fill(Path(ellipseIn: CGRect(x: r.midX - rr, y: r.midY - rr, width: rr * 2, height: rr * 2)), with: .color(fg))
            case 1:
                var s = Path()
                for k in 0..<4 { s.addPath(Path(CGRect(x: r.minX - r.width, y: r.minY + CGFloat(k) * r.height * 0.3, width: r.width * 3, height: r.height * 0.12))
                    .applying(CGAffineTransform(translationX: r.midX, y: r.midY).rotated(by: -0.5).translatedBy(x: -r.midX, y: -r.midY))) }
                d.fill(s, with: .color(fg))
            case 2:
                let c = CGPoint(x: r.midX, y: r.maxY)
                var fan = Path()
                for k in 0..<9 where k % 2 == 0 {
                    let a0 = Double.pi + Double.pi * Double(k) / 9, a1 = Double.pi + Double.pi * Double(k + 1) / 9
                    fan.move(to: c)
                    fan.addLine(to: CGPoint(x: c.x + cos(a0) * r.width, y: c.y + sin(a0) * r.width))
                    fan.addLine(to: CGPoint(x: c.x + cos(a1) * r.width, y: c.y + sin(a1) * r.width))
                    fan.closeSubpath()
                }
                d.fill(fan, with: .color(fg))
            default:
                d.fill(Path(CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.14, width: r.width * 0.76, height: r.height * 0.14)), with: .color(fg))
                d.fill(Path(CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.36, width: r.width * 0.5, height: r.height * 0.07)), with: .color(fg))
                d.fill(Path(ellipseIn: CGRect(x: r.midX, y: r.midY, width: r.width * 0.6, height: r.width * 0.6)), with: .color(fg))
            }
        }
        switch kit.look {
        case .deco: g.stroke(box, with: .color(MegaKit.gold.color(0.75)), lineWidth: 2)
        case .noir: g.stroke(box, with: .color(.white.opacity(0.2)), lineWidth: 1.2 * kit.u)
        case .comic: g.stroke(box, with: .color(MegaKit.ink.color), lineWidth: outline(kit) * 0.7)
        case .neon: MegaLooks.tube(&g, box, kit.pal.pop, kit, width: 1.4, bright: 0.6 * MegaLooks.neonBright(kit, seed))
        }
    }

    private static func sleeveArt(_ kit: MegaKit) -> Bool {
        kit.f.s.flag(.coverArt) && kit.f.s.artSpot != .vinyl && kit.f.art != nil
    }

    /// Sleeves face-out on the shop wall; one shows the cover art.
    static func sleeveWall(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        let art = sleeveArt(kit)
        for (i, r) in sc.sleeveWall.enumerated() { sleeve(&g, kit, r, seed: 500 + i * 3 + sc.variant, art: art && i == 2) }
    }

    /// How many sleeves crate `c` has flipped by now (the fraction is the flip in progress):
    /// one every few seconds, and a quick riffle of three on each accent hit it gets.
    private static func flips(_ c: Int, _ kit: MegaKit) -> Double {
        let f = kit.f
        let period = 2.8 + Double(c) * 0.9, dur = 0.4
        let x = (f.t + Double(c) * 1.37) / period
        let n = floor(x), fr = (x - n) * period
        var count = n + (fr > period - dur ? smoothstep((fr - (period - dur)) / dur) : 0)
        let id = f.lastHit.id
        if kit.accents > 0, id > 0 {
            let mine = c == 0 ? id / 3 : (id >= c ? (id - c) / 3 + 1 : 0)
            var riffle = Double(mine) * 3
            if id % 3 == c { riffle += min(3, f.lastHit.age / 0.2) - 3 }
            count += riffle
        }
        return count
    }

    /// The crates: sleeves stand in each one and the front one tips forward to show the next.
    static func crates(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        guard !sc.crates.isEmpty else { return }
        let art = sleeveArt(kit)
        for (c, box) in sc.crates.enumerated() {
            let sw = box.width * 0.7
            let hinge = box.minY + sw * 0.42
            let count = flips(c, kit)
            let k = Int(floor(count)), p = count - floor(count)
            func jitter(_ seed: Int) -> CGFloat { var r = Seeded(UInt64(seed &* 31 &+ 7)); return CGFloat(r.next() - 0.5) * box.width * 0.12 }
            for j in stride(from: 3, through: 1, by: -1) {
                let seed = c * 1000 + k + j
                let depth = CGFloat(Double(j) - p)
                let rr = CGRect(x: box.midX - sw / 2 + jitter(seed) * depth / 3, y: hinge - sw - depth * 10, width: sw, height: sw)
                sleeve(&g, kit, rr, seed: seed, art: art && seed % 3 == 0)
                g.fill(Path(rr), with: .color(.black.opacity(0.1 * Double(depth))))
            }
            // The front sleeve, tipping toward us about its hidden bottom edge.
            let th = p * 1.4
            var d = g
            d.translateBy(x: 0, y: hinge)
            d.scaleBy(x: 1, y: CGFloat(max(0.02, cos(th))))
            d.translateBy(x: 0, y: -hinge)
            let fr = CGRect(x: box.midX - sw / 2, y: hinge - sw, width: sw, height: sw)
            let seed = c * 1000 + k
            sleeve(&d, kit, fr, seed: seed, art: art && seed % 3 == 0)
            if p > 0 { d.fill(Path(fr), with: .color(.black.opacity(0.45 * sin(th)))) }
            // The crate front.
            MegaLooks.shape(&g, kit, MegaShape(path: Path(box), role: .furniture, hue: .accent, tone: 0.3, tube: true), 60 + c)
            MegaLooks.shape(&g, kit, MegaShape(path: Path(CGRect(x: box.minX, y: box.minY + box.height * 0.48, width: box.width, height: 8)), role: .trim, hue: .accent, tone: 0.2), 64 + c)
            MegaLooks.shape(&g, kit, MegaShape(path: Path(roundedRect: CGRect(x: box.midX - 40, y: box.minY + 20, width: 80, height: 24), cornerRadius: 12), role: .mass, hue: .base, tone: 0.06), 68 + c)
        }
    }
}
