import SwiftUI

// MARK: - Look kit

/// Per-frame values every part of the renderer shares: the look, its adjusted palette,
/// reaction strengths and the stage → screen scale.
struct MegaKit {
    let f: MegaFrame
    let look: MegaLook
    let pal: MegaPalette
    let lights, accents, camera, weather: Double     // reaction strengths (0 when off)
    var u: CGFloat = 1                               // stage units per screen point

    static let gold = NeonRGB(0.93, 0.74, 0.32)
    static let black = NeonRGB(0, 0, 0)
    static let ink = NeonRGB(0.04, 0.04, 0.05)

    init(_ f: MegaFrame) {
        self.f = f
        look = f.s.look
        var p = f.palette
        switch look {
        case .deco:
            let g = f.s[.decoGold]
            p.accent = p.accent.mixed(Self.gold, g * 0.85)
            p.warm = p.warm.mixed(NeonRGB(1, 0.9, 0.65), g * 0.4)
        case .comic:
            func sat(_ c: NeonRGB) -> NeonRGB {
                let l = (c.r + c.g + c.b) / 3
                return NeonRGB(max(0, min(1, l + (c.r - l) * 1.6)), max(0, min(1, l + (c.g - l) * 1.6)), max(0, min(1, l + (c.b - l) * 1.6)))
            }
            p = MegaPalette(base: sat(p.base), mid: sat(p.mid), accent: sat(p.accent), warm: sat(p.warm), pop: sat(p.pop), sky: sat(p.sky))
        default: break
        }
        pal = p
        lights = f.s.reaction(.lights, .lightsAmt)
        accents = f.s.reaction(.accents, .accentsAmt)
        camera = f.s.reaction(.camera, .cameraAmt)
        weather = f.s.reaction(.weather, .weatherAmt)
    }

    func shade(_ c: NeonRGB, _ tone: Double) -> NeonRGB {
        tone < 0.5 ? c.mixed(Self.black, (0.5 - tone) * 2 * 0.92) : c.mixed(.white, (tone - 0.5) * 2 * 0.85)
    }

    /// The fill colour for a hue and tone in this look.
    func color(_ hue: MegaHue, _ tone: Double) -> NeonRGB {
        switch look {
        case .deco:
            return shade(pal[hue], tone)
        case .noir:
            let c = shade(pal[hue], tone)
            var l = 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
            let ink = f.s[.noirInk]
            l = min(1, pow(l, 1 + ink * 0.9) * (1 + ink * 0.6))
            if hue == .accent, f.s.mood == .red { return NeonRGB(min(1, l * 2.2), l * 0.35, l * 0.35) }
            return NeonRGB(l * 0.96, l * 0.98, l * 1.03)
        case .comic:
            return shade(pal[hue], min(1, tone + 0.08))
        case .neon:
            return shade(pal[hue], tone * 0.42)
        }
    }

    /// The colour of a neon tube for a shape of this hue.
    func tube(_ hue: MegaHue, _ i: Int) -> NeonRGB {
        switch hue {
        case .accent, .pop, .warm: pal[hue].mixed(.white, 0.12)
        default: (i % 2 == 0 ? pal.pop : pal.accent).mixed(.white, 0.12)
        }
    }

    /// Lights brighten on the beat.
    var pulse: Double { 1 + lights * f.beat * 0.9 }
}

// MARK: - Renderer

enum MegaRenderer {
    static func draw(_ ctx: inout GraphicsContext, _ f: MegaFrame) {
        let kit = MegaKit(f)
        let full = CGRect(origin: .zero, size: f.size)
        ctx.fill(Path(full), with: .color(.black))

        var heads: [Int: CGPoint] = [:]
        if let prev = f.prev, f.cut < 1 {
            _ = drawShot(&ctx, kit, prev)
            MegaTransitions.draw(&ctx, kit, prev: prev) { g in heads = drawShot(&g, kit, f.shot) }
        } else {
            heads = drawShot(&ctx, kit, f.shot)
        }

        MegaFX.weatherScreen(&ctx, kit, f.shot.scene)
        MegaFX.accent(&ctx, kit, f.shot)
        MegaFX.post(&ctx, kit)
        MegaWords.draw(&ctx, kit, heads: heads)
    }

    /// Stage → screen for a shot: fill the window, then the shot's framing and the look's camera.
    static func camera(_ kit: MegaKit, _ shot: MegaShot) -> CGAffineTransform {
        let f = kit.f
        let w = f.size.width, h = f.size.height
        let base = max(w / MegaStage.size.width, h / MegaStage.size.height)
        let age = max(0, f.pos - max(shot.start, 0))
        var zoom = shot.zoom
        var shake = CGPoint.zero
        let cam = kit.camera
        switch kit.look {
        case .deco: zoom *= 1 + f.beat * 0.045 * cam
        case .noir: zoom *= 1 + min(age, 40) * 0.0035 * (0.4 + cam) + f.beat * 0.01 * cam
        case .comic:
            var r = Seeded(UInt64(Int(f.t * 30) & 0xffff) + 3)
            let amp = f.beat * 16 * cam
            shake = CGPoint(x: (r.next() - 0.5) * amp, y: (r.next() - 0.5) * amp)
            zoom *= 1 + f.beat * 0.02 * cam
        case .neon: zoom *= 1 + f.beat * 0.04 * cam
        }
        let drift = CGPoint(x: sin(age * 0.07 + Double(shot.index)) * 30, y: cos(age * 0.05) * 8)
        return CGAffineTransform(translationX: w / 2 + shake.x, y: h / 2 + shake.y)
            .scaledBy(x: base * zoom, y: base * zoom)
            .translatedBy(x: -MegaStage.size.width / 2 - shot.pan.x - drift.x, y: -MegaStage.size.height / 2 - shot.pan.y - drift.y)
    }

    /// One shot: backdrop, look extras, architecture, lights, cover art, figures, props, weather.
    /// Returns the screen position of each singer slot's head, for balloons.
    @discardableResult
    static func drawShot(_ ctx: inout GraphicsContext, _ kit0: MegaKit, _ shot: MegaShot) -> [Int: CGPoint] {
        let f = kit0.f
        let T = camera(kit0, shot)
        var kit = kit0
        kit.u = 1 / max(0.01, T.a)
        let sc = shot.scene
        var g = ctx
        g.concatenate(T)

        for (i, s) in sc.backdrop.enumerated() { MegaLooks.shape(&g, kit, s, i) }
        MegaLooks.backdrop(&g, kit, sc)
        for (i, s) in sc.mid.enumerated() {
            MegaLooks.shape(&g, kit, s, i + 10)
            for w in sc.windowLayers where w.after == i { MegaLooks.litWindows(&g, kit, w.buckets, base: sc.windowBase) }
        }
        MegaLooks.artSpot(&g, kit, sc)
        MegaLooks.lights(&g, kit, sc, behind: true)
        MegaFX.billiards(&g, kit, sc)
        MegaFX.marquee(&g, kit, sc)
        MegaFX.sleeveWall(&g, kit, sc)
        if sc.blinds { MegaLooks.blinds(&g, kit, sc) }

        var heads: [Int: CGPoint] = [:]
        var smoke: [CGPoint] = sc.ashtrays
        if f.s.flag(.characters) {
            for (i, m) in sc.cast.enumerated() {
                let (feet, flip) = m.feetNow(f.t)
                let pose = m.kind.pose(t: f.t, beat: f.beat, seed: m.phase + Double(i))
                let tf = CGAffineTransform(translationX: feet.x, y: feet.y).scaledBy(x: flip ? -m.height : m.height, y: m.height)
                MegaLooks.figure(&g, kit, pose.parts.map { $0.applying(tf) }, i)
                for (j, hp) in pose.heads.enumerated() where j < m.slots.count {
                    heads[m.slots[j]] = hp.applying(tf).applying(T)
                }
                if let sm = pose.smoke { smoke.append(sm.applying(tf)) }
            }
        }
        MegaFX.smoke(&g, kit, smoke)
        MegaLooks.street(&g, kit, sc)
        for (i, s) in sc.front.enumerated() { MegaLooks.shape(&g, kit, s, i + 40) }
        MegaFX.crates(&g, kit, sc)
        MegaLooks.vinyl(&g, kit, sc)
        MegaLooks.lights(&g, kit, sc, behind: false)
        MegaFX.weatherStage(&g, kit, sc)
        return heads
    }
}

// MARK: - The four looks

enum MegaLooks {
    static func glow(_ g: inout GraphicsContext, _ c: NeonRGB, at p: CGPoint, r: CGFloat, a: Double) {
        guard a > 0.003, r > 0 else { return }
        g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
               with: .radialGradient(Gradient(colors: [c.color(a), c.color(a * 0.35), c.color(0)]), center: p, startRadius: 0, endRadius: r))
    }

    /// A tube: three strokes, wide and faint to thin and bright. No blur.
    static func tube(_ g: inout GraphicsContext, _ path: Path, _ c: NeonRGB, _ kit: MegaKit, width: CGFloat = 2.4, bright: Double = 1) {
        let glow = kit.f.s[.neonGlow]
        let u = kit.u
        g.stroke(path, with: .color(c.color(0.1 * bright * (0.4 + glow))), style: StrokeStyle(lineWidth: (width * 6 + 14 * glow) * u, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(c.color(0.32 * bright)), style: StrokeStyle(lineWidth: (width * 2.6 + 4 * glow) * u, lineCap: .round, lineJoin: .round))
        g.stroke(path, with: .color(c.mixed(.white, 0.55).color(min(1, 0.95 * bright))), style: StrokeStyle(lineWidth: width * u, lineCap: .round, lineJoin: .round))
    }

    /// Neon brightness for tube `i`: beat brightening, random stutter, and accent-hit flicker.
    static func neonBright(_ kit: MegaKit, _ i: Int, stutter: Double = 1) -> Double {
        let f = kit.f
        var b = 0.75 + 0.25 * kit.pulse
        let fl = f.s[.neonFlicker]
        var r = Seeded(UInt64(i &* 977 &+ Int(f.t * 14) &* 31) + 5)
        if r.next() < fl * 0.025 * stutter { b *= 0.15 }
        if let h = f.hit, h.age < 0.35, kit.accents > 0 {
            var q = Seeded(UInt64(i &* 131 &+ Int(f.t * 30) &+ h.id))
            if q.next() < 0.45 { b *= 0.2 }
        }
        return b
    }

    static func shape(_ g: inout GraphicsContext, _ kit: MegaKit, _ s: MegaShape, _ i: Int) {
        let f = kit.f
        switch kit.look {
        case .deco:
            if s.role == .trim {
                g.fill(s.path, with: .color(MegaKit.gold.mixed(kit.pal.accent, 0.3).mixed(kit.color(s.hue, s.tone), 1 - f.s[.decoGold]).color))
            } else if s.role == .lit {
                g.fill(s.path, with: .color(kit.pal.warm.mixed(.white, 0.2).color(min(1, 0.85 * kit.pulse))))
            } else if s.role == .sky {
                skyGradient(&g, kit, s.path, top: kit.pal.sky.mixed(.black, 0.3), bottom: kit.pal.mid.mixed(kit.pal.accent, 0.25))
            } else {
                g.fill(s.path, with: .color(kit.color(s.hue, s.tone).color))
                if s.tube {
                    g.stroke(s.path, with: .color(MegaKit.gold.color(0.25 + 0.6 * f.s[.decoGold])), lineWidth: 2.2 * kit.u)
                }
            }
        case .noir:
            if s.role == .lit {
                g.fill(s.path, with: .color(NeonRGB(0.95, 0.94, 0.88).color(0.85)))
                return
            }
            if s.role == .sky {
                skyGradient(&g, kit, s.path, top: NeonRGB(0.02, 0.02, 0.03), bottom: NeonRGB(0.2, 0.21, 0.23))
                return
            }
            let c = kit.color(s.hue, s.role == .trim ? s.tone + 0.15 : s.tone)
            g.fill(s.path, with: .color(c.color))
            let hatch = f.s[.noirHatch]
            if hatch > 0.02, s.role != .trim, s.role != .metal, s.tone < 0.75 {
                let img = Image(decorative: s.tone < 0.25 ? f.tex.crosshatch : f.tex.hatch, scale: 1)
                var h = g
                h.opacity = hatch * (0.75 - s.tone) * 0.9
                h.fill(s.path, with: .tiledImage(img, origin: .zero, sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 0.75 * kit.u))
            }
            if s.tube, s.role != .trim {
                g.stroke(s.path, with: .color(.white.opacity(0.12 + 0.1 * f.s[.noirInk])), lineWidth: 1.5 * kit.u)
            }
        case .comic:
            let c = s.role == .lit ? NeonRGB(1, 0.92, 0.45) : kit.color(s.hue, s.tone)
            let mis = f.s[.comicMisreg] * 6 * kit.u
            if s.role == .sky {
                skyGradient(&g, kit, s.path.offsetBy(dx: mis, dy: mis * 0.6), top: kit.pal.sky.mixed(.black, 0.1), bottom: kit.pal.mid.mixed(kit.pal.pop, 0.4))
            } else {
                g.fill(s.path.offsetBy(dx: mis, dy: mis * 0.6), with: .color(c.color))
            }
            if s.tone < 0.5 || s.role == .sky || s.role == .fabric {
                halftone(&g, kit, s.path, amount: s.role == .sky ? 0.22 : (0.5 - s.tone) * 0.55 + 0.1)
            }
            let ow = (1 + f.s[.comicOutline] * 4.5) * kit.u
            if s.role != .sky && s.role != .wall && s.role != .floor && s.role != .ground {
                g.stroke(s.path, with: .color(MegaKit.ink.color), style: StrokeStyle(lineWidth: s.role == .trim ? ow * 0.6 : ow, lineJoin: .round))
            }
        case .neon:
            if s.role == .sky {
                skyGradient(&g, kit, s.path, top: NeonRGB(0.0, 0.0, 0.02), bottom: kit.pal.sky.mixed(kit.pal.accent, 0.15).mixed(.black, 0.35))
                return
            }
            if s.role == .lit {
                g.fill(s.path, with: .color(kit.pal.warm.color(0.35 * kit.pulse)))
                tube(&g, s.path, kit.pal.warm, kit, width: 2, bright: neonBright(kit, i))
                return
            }
            g.fill(s.path, with: .color(kit.color(s.hue, s.tone).color))
            if s.tube {
                let c = kit.tube(s.hue, i)
                let b = neonBright(kit, i)
                tube(&g, s.path, c, kit, bright: b)
                // Chromatic smear on the beat.
                let smear = kit.camera * kit.f.beat
                if smear > 0.08 {
                    let d = smear * 9 * kit.u
                    g.stroke(s.path.offsetBy(dx: -d, dy: 0), with: .color(Color(red: 1, green: 0.1, blue: 0.3).opacity(0.35 * smear)), lineWidth: 2 * kit.u)
                    g.stroke(s.path.offsetBy(dx: d, dy: 0), with: .color(Color(red: 0.1, green: 0.8, blue: 1).opacity(0.35 * smear)), lineWidth: 2 * kit.u)
                }
                reflect(&g, kit, s.path, c, b)
            }
        }
    }

    static func skyGradient(_ g: inout GraphicsContext, _ kit: MegaKit, _ p: Path, top: NeonRGB, bottom: NeonRGB) {
        var b = bottom
        if kit.f.s.mood.dusk, kit.look != .noir { b = b.mixed(kit.pal.accent, 0.45) }
        g.fill(p, with: .linearGradient(Gradient(colors: [top.color, top.mixed(b, 0.5).color, b.color]),
                                        startPoint: CGPoint(x: 0, y: -200), endPoint: CGPoint(x: 0, y: 780)))
    }

    /// Comic shading: black Ben-Day dots over a shape.
    static func halftone(_ g: inout GraphicsContext, _ kit: MegaKit, _ p: Path, amount: Double) {
        var h = g
        h.opacity = max(0, min(1, amount))
        let scale = (0.35 + kit.f.s[.comicDot] * 0.75) * kit.u
        h.fill(p, with: .tiledImage(Image(decorative: kit.f.tex.dots, scale: 1), origin: .zero,
                                    sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: scale))
    }

    /// Neon: the wet ground mirrors tubes below the floor line.
    static func reflect(_ g: inout GraphicsContext, _ kit: MegaKit, _ p: Path, _ c: NeonRGB, _ b: Double) {
        let amt = kit.f.s[.neonReflect]
        guard amt > 0.02 else { return }
        let fy = kit.f.shot.scene.floorY
        let br = p.boundingRect
        guard br.maxY <= fy + 4, br.maxY > fy - 600 else { return }
        var r = g
        r.clip(to: Path(CGRect(x: -3000, y: fy, width: 8000, height: 3000)))
        let m = CGAffineTransform(translationX: 0, y: fy * 2).scaledBy(x: 1, y: -1)
        r.stroke(p.applying(m), with: .color(c.color(0.16 * amt * b)), lineWidth: 5 * kit.u)
    }

    /// What each look adds right behind the architecture.
    static func backdrop(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        let f = kit.f
        switch kit.look {
        case .deco:
            // Sunburst: alternating rays fanning up from behind the scene.
            let n = 10 + Int(f.s[.decoRays] * 26)
            let o = sc.sunburst
            let a = (0.07 + 0.1 * f.s[.decoRays]) * (1 + kit.lights * f.beat * 1.2)
            var rays = Path()
            for i in 0..<n where i % 2 == 0 {
                let a0 = Double.pi + Double.pi * Double(i) / Double(n), a1 = Double.pi + Double.pi * Double(i + 1) / Double(n)
                rays.move(to: o)
                rays.addLine(to: CGPoint(x: o.x + cos(a0) * 2400, y: o.y + sin(a0) * 2400))
                rays.addLine(to: CGPoint(x: o.x + cos(a1) * 2400, y: o.y + sin(a1) * 2400))
                rays.closeSubpath()
            }
            g.fill(rays, with: .radialGradient(Gradient(colors: [MegaKit.gold.color(a * 2.2), MegaKit.gold.color(a), MegaKit.gold.color(0)]),
                                               center: o, startRadius: 40, endRadius: 1300))
            if sc.outdoor { moon(&g, kit, sc) }
        case .neon:
            if sc.outdoor {
                stars(&g, kit, count: 160, color: NeonRGB(0.9, 0.9, 1))
                moon(&g, kit, sc)
            } else {
                // Faint grid on the back wall, like a dark club.
                var grid = Path()
                for x in stride(from: CGFloat(-400), to: 2000, by: 80) { grid.addRect(CGRect(x: x, y: -300, width: 1.2, height: 1060)) }
                g.fill(grid, with: .color(kit.pal.accent.color(0.05)))
            }
        case .noir:
            if sc.outdoor { moon(&g, kit, sc) }
        case .comic:
            if sc.outdoor {
                stars(&g, kit, count: 50, color: NeonRGB(1, 1, 0.85))
                moon(&g, kit, sc)
            }
        }
    }

    static func stars(_ g: inout GraphicsContext, _ kit: MegaKit, count: Int, color: NeonRGB) {
        var r = Seeded(4242)
        var p = Path()
        for i in 0..<count {
            let x = -300 + r.next() * 2200, y = -300 + r.next() * 820, s = 1.2 + r.next() * 2.6
            let tw = 0.5 + 0.5 * sin(kit.f.t * (1 + r.next() * 2) + Double(i))
            if tw > 0.25 { p.addEllipse(in: CGRect(x: x, y: y, width: s, height: s)) }
        }
        g.fill(p, with: .color(color.color(0.8)))
    }

    static func moon(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        guard let m = sc.moon else { return }
        let r: CGFloat = 70
        let disc = Path(ellipseIn: CGRect(x: m.x - r, y: m.y - r, width: r * 2, height: r * 2))
        switch kit.look {
        case .deco:
            glow(&g, MegaKit.gold, at: m, r: r * 3, a: 0.18)
            g.fill(disc, with: .color(kit.pal.pop.mixed(MegaKit.gold, 0.4).color))
            var rings = Path()
            for k in 1...3 { rings.addEllipse(in: CGRect(x: m.x - r - CGFloat(k) * 22, y: m.y - r - CGFloat(k) * 22, width: (r + CGFloat(k) * 22) * 2, height: (r + CGFloat(k) * 22) * 2)) }
            g.stroke(rings, with: .color(MegaKit.gold.color(0.25)), lineWidth: 2)
        case .noir:
            glow(&g, .white, at: m, r: r * 3.4, a: 0.16)
            g.fill(disc, with: .color(Color(white: 0.92)))
        case .comic:
            g.fill(disc, with: .color(NeonRGB(1, 0.95, 0.6).color))
            halftone(&g, kit, Path(ellipseIn: CGRect(x: m.x - r * 0.4, y: m.y - r, width: r * 1.4, height: r * 2)).intersection(disc), amount: 0.25)
            g.stroke(disc, with: .color(MegaKit.ink.color), lineWidth: (1.5 + kit.f.s[.comicOutline] * 4) * kit.u)
        case .neon:
            tube(&g, disc, kit.pal.warm.mixed(.white, 0.4), kit, width: 2.5, bright: 0.9)
        }
    }

    /// Lit windows are drawn after the buildings (called from `lights(behind:)`).
    static func litWindows(_ g: inout GraphicsContext, _ kit: MegaKit, _ buckets: [Path], base: Double) {
        let f = kit.f
        let frac = base + (1 - base) * min(1, f.level * (0.5 + 0.8 * max(kit.lights, 0.3)))
        let lit = frac * 10
        let c: NeonRGB
        switch kit.look {
        case .deco: c = kit.pal.warm.mixed(MegaKit.gold, 0.4)
        case .noir: c = NeonRGB(0.92, 0.92, 0.86)
        case .comic: c = NeonRGB(1, 0.9, 0.35)
        case .neon: c = kit.pal.warm
        }
        for (i, p) in buckets.enumerated() {
            var a = 0.0
            if Double(i) < lit - 1 { a = 1 } else if Double(i) < lit {
                let edge = lit - Double(i)
                a = sin(f.t * 23 + Double(i)) > 1 - edge * 2 ? 1 : 0.15
            } else { a = 0.08 }
            guard a > 0 else { continue }
            g.fill(p, with: .color(c.color(a * (kit.look == .neon ? 0.85 : 0.95))))
            if kit.look == .comic, a > 0.5 { g.stroke(p, with: .color(MegaKit.ink.color(0.8)), lineWidth: 1.2 * kit.u) }
        }
    }

    // MARK: Lights

    static func lights(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene, behind: Bool) {
        let f = kit.f
        // Noir key-light flicker on beats.
        var flick = 1.0
        if kit.look == .noir {
            var r = Seeded(UInt64(Int(f.t * 12) & 0xffff) + 11)
            if r.next() < f.beat * 0.6 * kit.lights { flick = 0.55 }
        }
        for (i, l) in sc.lights.enumerated() {
            let isBeam = l.kind == .spot || l.kind == .pendant || l.kind == .lamp
            if behind != isBeam { continue }
            var c = kit.pal[l.hue]
            if kit.look == .noir { c = NeonRGB(1, 0.98, 0.92) }
            if kit.look == .deco, l.hue == .warm { c = c.mixed(MegaKit.gold, 0.3) }
            let pulse = kit.pulse * flick * (0.92 + 0.08 * sin(f.t * 2 + l.phase))
            switch l.kind {
            case .bulb:
                if kit.look == .neon {
                    glow(&g, c, at: l.pos, r: l.size * 1.4, a: 0.5 * pulse)
                    g.fill(Path(ellipseIn: CGRect(x: l.pos.x - 5, y: l.pos.y - 5, width: 10, height: 10)), with: .color(c.mixed(.white, 0.6).color))
                } else if kit.look == .comic {
                    let r = l.size * 0.55 * CGFloat(pulse)
                    let disc = Path(ellipseIn: CGRect(x: l.pos.x - r, y: l.pos.y - r, width: r * 2, height: r * 2))
                    g.fill(disc, with: .color(NeonRGB(1, 0.95, 0.5).color(0.9)))
                    g.stroke(disc, with: .color(MegaKit.ink.color), lineWidth: 1.5 * kit.u)
                } else {
                    glow(&g, c, at: l.pos, r: l.size * 1.2, a: 0.45 * pulse)
                    g.fill(Path(ellipseIn: CGRect(x: l.pos.x - 5, y: l.pos.y - 5, width: 10, height: 10)), with: .color(c.mixed(.white, 0.5).color))
                }
            case .sconce:
                if kit.look == .deco {
                    // A gold fan flaring up from the sconce.
                    var fan = Path()
                    let n = 7
                    for k in 0..<n {
                        let a0 = Double.pi * (1.15 + 0.7 * Double(k) / Double(n)), a1 = a0 + 0.05
                        let len = l.size * (0.8 + 0.5 * CGFloat(pulse - 1)) * (k % 2 == 0 ? 1.1 : 0.8)
                        fan.move(to: l.pos)
                        fan.addLine(to: CGPoint(x: l.pos.x + cos(a0) * len, y: l.pos.y + sin(a0) * len))
                        fan.addLine(to: CGPoint(x: l.pos.x + cos(a1) * len, y: l.pos.y + sin(a1) * len))
                        fan.closeSubpath()
                    }
                    g.fill(fan, with: .color(MegaKit.gold.color(0.35 * pulse)))
                }
                if kit.look == .comic {
                    let r = l.size * 0.6 * CGFloat(0.85 + 0.25 * pulse)
                    let disc = Path(ellipseIn: CGRect(x: l.pos.x - r, y: l.pos.y - r, width: r * 2, height: r * 2))
                    g.fill(disc, with: .color(kit.pal.warm.mixed(.white, 0.3).color(0.55 + 0.3 * (pulse - 1))))
                    halftone(&g, kit, disc, amount: 0.18)
                } else {
                    glow(&g, c, at: l.pos, r: l.size * CGFloat(0.9 + 0.3 * (pulse - 1)), a: 0.55 * pulse)
                }
            case .spot, .pendant, .lamp:
                beam(&g, kit, l, c, pulse, i)
            }
        }
    }

    /// A cone of light: hard-edged in Noir, a flat tint in Deco and Comic, coloured haze in Neon.
    static func beam(_ g: inout GraphicsContext, _ kit: MegaKit, _ l: MegaLight, _ c: NeonRGB, _ pulse: Double, _ i: Int) {
        let f = kit.f
        var src = l.pos
        var aim = l.aim == .zero ? CGPoint(x: l.pos.x, y: l.pos.y + 500) : l.aim
        var spread: CGFloat = l.kind == .spot ? 150 : l.size * 1.1
        switch l.kind {
        case .spot:
            // Sweeps slowly, kicks across on the beat.
            let sweep = sin(f.t * 0.45 + l.phase) * 230 + f.beat * kit.lights * 90 * (l.phase > 1 ? -1 : 1)
            aim.x += sweep
            spread = 170
        case .pendant, .lamp:
            if kit.look == .noir {
                // Lamps swing.
                let a = 0.07 * sin(f.t * 0.9 + l.phase) + 0.12 * f.beat * kit.lights
                let len = aim.y - src.y
                aim.x += CGFloat(sin(a)) * len
                src.x += CGFloat(sin(a)) * 12
            }
        default: break
        }
        let dx = aim.x - src.x, dy = aim.y - src.y
        let len = max(1, sqrt(dx * dx + dy * dy))
        let nx = -dy / len, ny = dx / len
        let w0: CGFloat = l.kind == .spot ? 24 : 26
        var cone = Path()
        cone.move(to: CGPoint(x: src.x + nx * w0, y: src.y + ny * w0))
        cone.addLine(to: CGPoint(x: aim.x + nx * spread, y: aim.y + ny * spread))
        cone.addLine(to: CGPoint(x: aim.x - nx * spread, y: aim.y - ny * spread))
        cone.addLine(to: CGPoint(x: src.x - nx * w0, y: src.y - ny * w0))
        cone.closeSubpath()
        let pool = Path(ellipseIn: CGRect(x: aim.x - spread * 1.1, y: aim.y - spread * 0.18, width: spread * 2.2, height: spread * 0.36))
        switch kit.look {
        case .noir:
            g.fill(cone, with: .linearGradient(Gradient(colors: [c.color(0.32 * pulse), c.color(0.12 * pulse)]), startPoint: src, endPoint: aim))
            g.fill(pool, with: .color(c.color(0.16 * pulse)))
        case .deco:
            g.fill(cone, with: .linearGradient(Gradient(colors: [c.color(0.26 * pulse), c.color(0.04)]), startPoint: src, endPoint: aim))
            g.fill(pool, with: .radialGradient(Gradient(colors: [c.color(0.22 * pulse), c.color(0)]), center: aim, startRadius: 0, endRadius: spread * 1.1))
            dust(&g, kit, src: src, aim: aim, spread: spread, i: i)
        case .comic:
            g.fill(cone, with: .color(NeonRGB(1, 0.95, 0.55).color(0.22 * pulse)))
            g.stroke(cone, with: .color(MegaKit.ink.color(0.25)), style: StrokeStyle(lineWidth: 1.2 * kit.u, dash: [10 * kit.u, 8 * kit.u]))
        case .neon:
            g.fill(cone, with: .linearGradient(Gradient(colors: [c.color(0.3 * pulse), c.color(0.0)]), startPoint: src, endPoint: aim))
            g.fill(pool, with: .radialGradient(Gradient(colors: [c.color(0.3 * pulse), c.color(0)]), center: aim, startRadius: 0, endRadius: spread * 1.1))
        }
        glow(&g, c, at: src, r: l.size * 0.7, a: (kit.look == .noir ? 0.6 : 0.5) * pulse)
        if kit.look == .neon, kit.f.s[.neonReflect] > 0.02 {
            // Light streaks on the wet floor.
            let fy = kit.f.shot.scene.floorY
            let w: CGFloat = 26
            g.fill(Path(CGRect(x: aim.x - w / 2, y: fy, width: w, height: 260)),
                   with: .linearGradient(Gradient(colors: [c.color(0.3 * kit.f.s[.neonReflect]), c.color(0)]),
                                         startPoint: CGPoint(x: 0, y: fy), endPoint: CGPoint(x: 0, y: fy + 260)))
        }
    }

    /// Deco: dust motes drifting in the light beams, more with energy.
    static func dust(_ g: inout GraphicsContext, _ kit: MegaKit, src: CGPoint, aim: CGPoint, spread: CGFloat, i: Int) {
        let f = kit.f
        let n = Int(10 + 50 * kit.weather * (0.3 + f.level))
        var r = Seeded(UInt64(i * 31 + 7))
        var p = Path()
        for _ in 0..<n {
            let along = (r.next() + f.t * 0.02 * (0.5 + r.next())).truncatingRemainder(dividingBy: 1)
            let across = (r.next() - 0.5) * 2 * along
            let x = src.x + (aim.x - src.x) * along + spread * across + sin(f.t * 0.7 + r.next() * 6) * 8
            let y = src.y + (aim.y - src.y) * along
            let s = 2 + r.next() * 3
            p.addEllipse(in: CGRect(x: x, y: y, width: s, height: s))
        }
        g.fill(p, with: .color(MegaKit.gold.mixed(.white, 0.4).color(0.6)))
    }

    /// Noir: venetian-blind shadows slanting across the back wall.
    static func blinds(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        guard kit.look == .noir else { return }
        var p = Path()
        let x0: CGFloat = 520 + CGFloat(sin(kit.f.t * 0.2) * 10)
        for k in 0..<9 {
            let y = 120 + CGFloat(k) * 46
            p.addLines([CGPoint(x: x0, y: y), CGPoint(x: x0 + 560, y: y + 120), CGPoint(x: x0 + 560, y: y + 146), CGPoint(x: x0, y: y + 26)])
            p.closeSubpath()
        }
        g.fill(p, with: .color(.white.opacity(0.1 * kit.pulse)))
    }

    // MARK: Figures

    static func figure(_ g: inout GraphicsContext, _ kit: MegaKit, _ parts: [Path], _ i: Int) {
        var body = Path()
        for p in parts { body.addPath(p) }
        switch kit.look {
        case .deco:
            g.fill(body, with: .color(kit.pal.base.mixed(.black, 0.6).color))
            g.stroke(body.union(Path()), with: .color(MegaKit.gold.color(0.35 + 0.4 * kit.f.s[.decoGold])), lineWidth: 2 * kit.u)
        case .noir:
            g.fill(body, with: .color(Color(white: 0.015)))
            // Rim light from the key.
            g.stroke(body.union(Path()).offsetBy(dx: -2 * kit.u, dy: -1 * kit.u), with: .color(.white.opacity(0.22)), lineWidth: 1.4 * kit.u)
            g.fill(body, with: .color(Color(white: 0.015)))
        case .comic:
            let merged = body.union(Path())
            let mis = kit.f.s[.comicMisreg] * 6 * kit.u
            g.fill(merged.offsetBy(dx: mis, dy: mis * 0.6), with: .color(kit.shade(kit.pal.pop.mixed(kit.pal.mid, 0.35), 0.36).color))
            halftone(&g, kit, merged, amount: 0.22)
            g.stroke(merged, with: .color(MegaKit.ink.color), style: StrokeStyle(lineWidth: (1.5 + kit.f.s[.comicOutline] * 5) * kit.u, lineJoin: .round))
        case .neon:
            let merged = body.union(Path())
            g.fill(merged, with: .color(Color(white: 0.01)))
            tube(&g, merged, kit.tube(i % 2 == 0 ? .pop : .accent, i), kit, width: 2, bright: neonBright(kit, 90 + i))
        }
    }

    // MARK: Cover art

    static func artSpot(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        guard let spot = sc.art else { return }
        let f = kit.f
        let showArt = f.s.flag(.coverArt) && f.s.artSpot != .vinyl
        let r = spot.rect
        let frame = r.insetBy(dx: spot.kind == .painting ? -22 : -8, dy: spot.kind == .painting ? -22 : -8)
        let framePath = Path(frame)
        // The frame.
        switch kit.look {
        case .deco:
            g.fill(framePath, with: .color(MegaKit.gold.mixed(.black, 0.25).color))
            g.stroke(Path(frame.insetBy(dx: 7, dy: 7)), with: .color(MegaKit.gold.mixed(.white, 0.3).color), lineWidth: 3)
            if spot.kind == .painting {
                // Stepped corners.
                for c in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX - 24, y: frame.minY),
                          CGPoint(x: frame.minX, y: frame.maxY - 24), CGPoint(x: frame.maxX - 24, y: frame.maxY - 24)] {
                    g.fill(Path(CGRect(x: c.x, y: c.y, width: 24, height: 24)), with: .color(kit.pal.mid.color))
                    g.stroke(Path(CGRect(x: c.x + 5, y: c.y + 5, width: 14, height: 14)), with: .color(MegaKit.gold.color), lineWidth: 2)
                }
            }
        case .noir:
            g.fill(framePath, with: .color(Color(white: spot.kind == .painting ? 0.1 : 0.75)))
            g.stroke(framePath, with: .color(.white.opacity(0.25)), lineWidth: 1.5 * kit.u)
        case .comic:
            g.fill(framePath, with: .color(spot.kind == .painting ? NeonRGB(0.62, 0.38, 0.16).color : Color.white))
            g.stroke(framePath, with: .color(MegaKit.ink.color), lineWidth: (1.5 + f.s[.comicOutline] * 4) * kit.u)
        case .neon:
            g.fill(framePath, with: .color(Color(white: 0.02)))
            tube(&g, framePath, kit.pal.pop, kit, width: 2.4, bright: neonBright(kit, 77))
        }

        // The picture area: art square plus a title band for posters and billboards.
        var pic = r
        var band: CGRect?
        switch spot.kind {
        case .painting: break
        case .poster:
            pic = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.width)
            band = CGRect(x: r.minX, y: r.minY + r.width, width: r.width, height: r.height - r.width)
        case .billboard:
            pic = CGRect(x: r.minX, y: r.minY, width: r.height, height: r.height)
            band = CGRect(x: r.minX + r.height, y: r.minY, width: r.width - r.height, height: r.height)
        }
        if showArt, let art = f.art {
            g.draw(Image(decorative: art, scale: 1).resizable(), in: pic)
            if kit.look == .comic { halftone(&g, kit, Path(pic), amount: 0.12) }
            if kit.look == .neon { g.fill(Path(pic), with: .color(.black.opacity(0.15))) }
        } else {
            placeholder(&g, kit, pic)
        }
        if let band {
            let bg: Color, fg: Color
            switch kit.look {
            case .deco: bg = kit.pal.base.color; fg = MegaKit.gold.color
            case .noir: bg = Color(white: 0.9); fg = .black
            case .comic: bg = NeonRGB(1, 0.85, 0.2).color; fg = MegaKit.ink.color
            case .neon: bg = Color(white: 0.02); fg = kit.pal.pop.mixed(.white, 0.35).color
            }
            g.fill(Path(band), with: .color(bg))
            let title = f.title.isEmpty ? "TONIGHT" : f.title.uppercased()
            let sub = f.artist.uppercased()
            let font = MegaWords.font(kit.look, heavy: true)
            var fs = min(band.height * (spot.kind == .billboard ? 0.2 : 0.36), band.width * 0.16)
            var inner = band.insetBy(dx: band.width * 0.08, dy: band.height * 0.1)
            if !sub.isEmpty, spot.kind == .billboard {
                let sr = g.resolve(Text(sub).font(MegaWords.font(kit.look, heavy: false)(fs * 0.55)).foregroundColor(fg.opacity(0.8)))
                g.draw(sr, in: CGRect(x: inner.minX, y: inner.maxY - fs * 0.8, width: inner.width, height: fs))
                inner.size.height -= fs
            }
            // Shrink until the longest word fits on a row and the title fits the band.
            let longest: String = title.components(separatedBy: " ").max { $0.count < $1.count } ?? title
            var t = g.resolve(Text(title).font(font(fs)).foregroundColor(fg))
            for _ in 0..<8 {
                let lw = g.resolve(Text(longest).font(font(fs))).measure(in: CGSize(width: 10_000, height: 1000)).width
                t = g.resolve(Text(title).font(font(fs)).foregroundColor(fg))
                if lw < inner.width * 0.96, t.measure(in: CGSize(width: inner.width, height: 10_000)).height <= inner.height { break }
                fs *= 0.86
            }
            g.draw(t, in: inner)
        }
    }

    /// A stand-in picture when the cover art is off or hasn't loaded: an abstract in the look.
    static func placeholder(_ g: inout GraphicsContext, _ kit: MegaKit, _ r: CGRect) {
        g.fill(Path(r), with: .color(kit.color(.mid, 0.35).color))
        let c = CGPoint(x: r.midX, y: r.maxY)
        var fan = Path()
        for k in 0..<9 where k % 2 == 0 {
            let a0 = Double.pi + Double.pi * Double(k) / 9, a1 = Double.pi + Double.pi * Double(k + 1) / 9
            fan.move(to: c)
            fan.addLine(to: CGPoint(x: c.x + cos(a0) * r.width, y: c.y + sin(a0) * r.width))
            fan.addLine(to: CGPoint(x: c.x + cos(a1) * r.width, y: c.y + sin(a1) * r.width))
            fan.closeSubpath()
        }
        var gg = g
        gg.clip(to: Path(r))
        gg.fill(fan, with: .color(kit.color(.accent, 0.5).color(0.6)))
        gg.fill(Path(ellipseIn: CGRect(x: r.midX - r.width * 0.18, y: r.maxY - r.width * 0.36, width: r.width * 0.36, height: r.width * 0.36)),
                with: .color(kit.color(.warm, 0.6).color))
    }

    /// The turntable: the cover art printed on the label, spinning.
    static func vinyl(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        guard let v = sc.vinyl else { return }
        let f = kit.f
        let plinth = Path(roundedRect: v.plinth, cornerRadius: 8)
        let ow = (1.5 + f.s[.comicOutline] * 4) * kit.u
        switch kit.look {
        case .deco:
            g.fill(plinth, with: .color(kit.pal.mid.mixed(.black, 0.3).color))
            g.stroke(plinth, with: .color(MegaKit.gold.color(0.8)), lineWidth: 2.5)
        case .noir: g.fill(plinth, with: .color(Color(white: 0.12)))
        case .comic:
            g.fill(plinth, with: .color(NeonRGB(0.6, 0.35, 0.18).color))
            g.stroke(plinth, with: .color(MegaKit.ink.color), lineWidth: ow)
        case .neon:
            g.fill(plinth, with: .color(Color(white: 0.03)))
            tube(&g, plinth, kit.pal.accent, kit, width: 2, bright: neonBright(kit, 55))
        }
        var d = g
        d.translateBy(x: v.center.x, y: v.center.y)
        d.scaleBy(x: 1, y: v.squash)
        let R = v.radius
        let disc = Path(ellipseIn: CGRect(x: -R, y: -R, width: R * 2, height: R * 2))
        d.fill(disc, with: .color(Color(white: 0.04)))
        var grooves = Path()
        for k in stride(from: 0.45, to: 0.97, by: 0.07) {
            let rr = R * CGFloat(k)
            grooves.addEllipse(in: CGRect(x: -rr, y: -rr, width: rr * 2, height: rr * 2))
        }
        let grooveColor: Color = switch kit.look {
        case .deco: MegaKit.gold.color(0.35)
        case .neon: kit.pal.pop.color(0.4)
        default: Color.white.opacity(0.12)
        }
        d.stroke(grooves, with: .color(grooveColor), lineWidth: 1.5 * kit.u / v.squash)
        // Sheen that stays put while the record turns under it.
        var sheen = Path()
        sheen.move(to: .zero)
        sheen.addArc(center: .zero, radius: R * 0.97, startAngle: .degrees(-60), endAngle: .degrees(-35), clockwise: false)
        sheen.closeSubpath()
        sheen.move(to: .zero)
        sheen.addArc(center: .zero, radius: R * 0.97, startAngle: .degrees(120), endAngle: .degrees(145), clockwise: false)
        sheen.closeSubpath()
        d.fill(sheen, with: .color(.white.opacity(kit.look == .noir ? 0.18 : 0.1)))
        // Label: the art, spinning at 33⅓ with a nudge on the beat.
        var lab = d
        lab.rotate(by: .radians(f.t * 3.49 + f.beat * 0.2))
        let lr = R * 0.38
        let label = Path(ellipseIn: CGRect(x: -lr, y: -lr, width: lr * 2, height: lr * 2))
        if f.s.flag(.coverArt), f.s.artSpot != .frame, let art = f.art {
            var cl = lab
            cl.clip(to: label)
            cl.draw(Image(decorative: art, scale: 1).resizable(), in: CGRect(x: -lr, y: -lr, width: lr * 2, height: lr * 2))
        } else {
            lab.fill(label, with: .color(kit.color(.accent, 0.5).color))
            lab.fill(Path(CGRect(x: -lr, y: -lr * 0.12, width: lr * 2, height: lr * 0.24)), with: .color(kit.color(.pop, 0.6).color(0.8)))
        }
        lab.fill(Path(ellipseIn: CGRect(x: -6, y: -6, width: 12, height: 12)), with: .color(Color(white: 0.85)))
        if kit.look == .comic { d.stroke(disc, with: .color(MegaKit.ink.color), lineWidth: ow / v.squash) }
        if kit.look == .neon { tube(&d, disc, kit.pal.pop, kit, width: 1.8, bright: neonBright(kit, 56)) }
        // Tonearm.
        let base = CGPoint(x: v.center.x + R * 1.05, y: v.center.y - R * v.squash * 0.9)
        var arm = Path()
        arm.move(to: base)
        arm.addQuadCurve(to: CGPoint(x: v.center.x + R * 0.55, y: v.center.y + R * v.squash * 0.15),
                         control: CGPoint(x: v.center.x + R * 1.0, y: v.center.y + R * v.squash * 0.25))
        let armColor: Color = kit.look == .deco ? MegaKit.gold.color : (kit.look == .neon ? kit.pal.warm.color : Color(white: 0.75))
        g.stroke(arm, with: .color(armColor), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        g.fill(Path(ellipseIn: CGRect(x: base.x - 14, y: base.y - 14, width: 28, height: 28)), with: .color(armColor))
    }

    // MARK: Street: puddles and the passing car

    static func street(_ g: inout GraphicsContext, _ kit: MegaKit, _ sc: MegaScene) {
        let f = kit.f
        for (i, p) in sc.puddles.enumerated() {
            let shape = Path(ellipseIn: p)
            let c: Color
            switch kit.look {
            case .deco: c = MegaKit.gold.color(0.22)
            case .noir: c = .white.opacity(0.14)
            case .comic: c = kit.pal.pop.mixed(.white, 0.3).color(0.7)
            case .neon: c = kit.pal.accent.color(0.25)
            }
            g.fill(shape, with: .color(c))
            if kit.look == .comic { g.stroke(shape, with: .color(MegaKit.ink.color), lineWidth: 1.5 * kit.u) }
            // Ripples: one ring per beat, plus raindrops.
            let ringC: Color = kit.look == .noir || kit.look == .comic ? .white : kit.pal.warm.color
            var rings = Path()
            let k = 1 - f.beat
            if f.beat > 0.05 {
                rings.addEllipse(in: CGRect(x: p.midX - p.width * 0.45 * k - 6, y: p.midY - p.height * 0.45 * k - 2,
                                            width: p.width * 0.9 * k + 12, height: p.height * 0.9 * k + 4))
            }
            let rain = f.s.mood.rain + (kit.look == .noir ? f.s[.noirRain] : 0)
            if rain > 0.05 {
                var r = Seeded(UInt64(i * 17 + 3))
                for d in 0..<3 {
                    let ph = (f.t * 0.9 + r.next() + Double(d) * 0.33).truncatingRemainder(dividingBy: 1)
                    let cx = p.minX + p.width * (0.2 + 0.6 * ((r.next() + floor(f.t * 0.9 + Double(d) * 0.33) * 0.37).truncatingRemainder(dividingBy: 1)))
                    let rr = 6 + ph * 40
                    rings.addEllipse(in: CGRect(x: cx - rr, y: p.midY - rr * 0.22, width: rr * 2, height: rr * 0.44))
                }
            }
            g.stroke(rings, with: .color(ringC.opacity(0.35 + 0.4 * f.beat)), lineWidth: 2 * kit.u)
        }
        guard let lane = sc.carLane else { return }
        // A car glides through every 18 s.
        let cycle = (f.t / 18).truncatingRemainder(dividingBy: 1)
        guard cycle < 0.3 else { return }
        let x = -500 + CGFloat(cycle / 0.3) * 2700
        let y = lane + 70
        var car = Path()
        car.move(to: CGPoint(x: x - 230, y: y - 20))
        car.addLine(to: CGPoint(x: x - 220, y: y - 70))
        car.addQuadCurve(to: CGPoint(x: x - 90, y: y - 80), control: CGPoint(x: x - 160, y: y - 92))
        car.addQuadCurve(to: CGPoint(x: x + 40, y: y - 140), control: CGPoint(x: x - 60, y: y - 140))
        car.addLine(to: CGPoint(x: x + 110, y: y - 140))
        car.addQuadCurve(to: CGPoint(x: x + 170, y: y - 82), control: CGPoint(x: x + 150, y: y - 138))
        car.addQuadCurve(to: CGPoint(x: x + 250, y: y - 50), control: CGPoint(x: x + 250, y: y - 80))
        car.addLine(to: CGPoint(x: x + 250, y: y - 20))
        car.closeSubpath()
        var wheels = Path()
        for wx in [x - 140, x + 150] { wheels.addEllipse(in: CGRect(x: wx - 40, y: y - 60, width: 80, height: 80)) }
        let head = CGPoint(x: x + 245, y: y - 50)
        // Headlight beam ahead.
        var beam = Path()
        beam.move(to: head)
        beam.addLine(to: CGPoint(x: head.x + 520, y: head.y - 60))
        beam.addLine(to: CGPoint(x: head.x + 520, y: head.y + 70))
        beam.closeSubpath()
        let hc = kit.look == .noir ? NeonRGB(1, 1, 0.95) : kit.pal.warm
        g.fill(beam, with: .linearGradient(Gradient(colors: [hc.color(0.45), hc.color(0)]), startPoint: head, endPoint: CGPoint(x: head.x + 520, y: head.y)))
        switch kit.look {
        case .deco:
            g.fill(car, with: .color(kit.pal.base.mixed(.black, 0.4).color))
            g.stroke(car, with: .color(MegaKit.gold.color(0.8)), lineWidth: 3)
            g.fill(wheels, with: .color(.black))
            g.stroke(wheels, with: .color(MegaKit.gold.color(0.7)), lineWidth: 3)
        case .noir:
            g.fill(car, with: .color(Color(white: 0.02)))
            g.fill(wheels, with: .color(Color(white: 0.02)))
            g.stroke(car, with: .color(.white.opacity(0.25)), lineWidth: 1.5 * kit.u)
        case .comic:
            g.fill(car.union(wheels), with: .color(kit.pal.pop.color))
            halftone(&g, kit, car, amount: 0.25)
            g.stroke(car.union(wheels), with: .color(MegaKit.ink.color), lineWidth: (1.5 + f.s[.comicOutline] * 4) * kit.u)
            // Speed lines behind it.
            var lines = Path()
            for k in 0..<5 { lines.addRect(CGRect(x: x - 520, y: y - 130 + CGFloat(k) * 24, width: 260 - CGFloat(k % 2) * 80, height: 4)) }
            g.fill(lines, with: .color(MegaKit.ink.color(0.8)))
        case .neon:
            g.fill(car.union(wheels), with: .color(Color(white: 0.02)))
            tube(&g, car, kit.pal.pop, kit, width: 2.2, bright: 1)
            tube(&g, wheels, kit.pal.accent, kit, width: 1.6, bright: 0.8)
        }
        glow(&g, hc, at: head, r: 60, a: 0.9)
        glow(&g, NeonRGB(1, 0.1, 0.1), at: CGPoint(x: x - 228, y: y - 50), r: 30, a: 0.8)
    }
}
