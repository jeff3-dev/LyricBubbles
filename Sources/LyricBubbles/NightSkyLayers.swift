import SwiftUI

// MARK: - Night Sky layers
//
// Extra depth around the constellations, each with its own switch in the controls:
// - Nebulae: baked gas-cloud sprites hung at many depths along the flight path.
// - Landmarks: a planet, a ringed giant or a spiral galaxy passed between parts.
// - Dust: soft out-of-focus specks right by the lens that streak when flying fast.
// - Aurora: light ribbons behind the stars that swell with the music's level and beats.
// All glow comes from gradients and cached images; nothing is blurred per frame.

/// Something hung in the sky beside the flight path.
struct SkyProp {
    enum Kind { case nebula(Int), planet, ringed, galaxy }
    let kind: Kind
    let x, y, z: Double
    let size: Double        // world radius
    let rot: Double         // degrees
    let colors: [NeonRGB]   // planet: base, band, atmosphere
}

enum SkyScenery {
    static let farthest = 9000.0
    private static var cache: (key: String, props: [SkyProp]) = ("", [])
    private static let lock = NSLock()

    static let planetColors: [[NeonRGB]] = [
        [NeonRGB(0.78, 0.42, 0.26), NeonRGB(0.95, 0.7, 0.48), NeonRGB(1, 0.6, 0.4)],     // rust
        [NeonRGB(0.2, 0.42, 0.68), NeonRGB(0.5, 0.78, 0.92), NeonRGB(0.45, 0.75, 1)],    // ocean
        [NeonRGB(0.55, 0.36, 0.7), NeonRGB(0.85, 0.6, 0.85), NeonRGB(0.8, 0.55, 1)],     // violet
        [NeonRGB(0.8, 0.66, 0.4), NeonRGB(0.98, 0.88, 0.66), NeonRGB(1, 0.85, 0.55)],    // gold
        [NeonRGB(0.3, 0.6, 0.55), NeonRGB(0.62, 0.9, 0.8), NeonRGB(0.5, 1, 0.85)],       // mint
    ]

    /// Props for a song, built once per set of pages.
    static func props(for pages: [SkyPage]) -> [SkyProp] {
        let key = "\(pages.count)|\(pages.first?.plan.seed ?? 0)|\(Int(pages.last?.z ?? 0))"
        lock.lock(); defer { lock.unlock() }
        if cache.key == key { return cache.props }
        let made = make(pages)
        cache = (key, made)
        return made
    }

    static func make(_ pages: [SkyPage]) -> [SkyProp] {
        guard !pages.isEmpty else { return [] }
        var r = Seeded(pages[0].plan.seed &+ 0x5CE7)
        var out: [SkyProp] = []
        func nearest(_ z: Double) -> SkyPage {
            pages.min { abs($0.z - z) < abs($1.z - z) }!
        }

        // Nebulae all along the path, off to the sides.
        var z = -3000.0
        let end = (pages.last?.z ?? 0) + 30000   // the flight keeps going after the last part
        while z < end {
            let base = nearest(z)
            let side = r.next() < 0.5 ? -1.0 : 1.0
            out.append(SkyProp(kind: .nebula(Int(r.next() * 4) % 4),
                               x: base.x + side * (650 + r.next() * 1700), y: base.y + (r.next() - 0.5) * 1500,
                               z: z, size: 900 + r.next() * 1500, rot: r.next() * 360, colors: []))
            z += 850 + r.next() * 900
        }

        // A landmark between some parts: every chorus, and every third part otherwise.
        var count = 0
        var lastAt = -10
        for i in pages.indices.dropFirst() where (pages[i].chorus || i % 3 == 1) && i - lastAt >= 2 {
            lastAt = i
            let a = pages[i - 1], b = pages[i]
            let side = r.next() < 0.5 ? -1.0 : 1.0
            let kinds: [SkyProp.Kind] = [.planet, .ringed, .galaxy]
            let kind = kinds[(count + Int(r.next() * 3)) % 3]
            count += 1
            let size: Double = if case .galaxy = kind { 1100 + r.next() * 500 } else { 340 + r.next() * 320 }
            out.append(SkyProp(kind: kind,
                               x: (a.x + b.x) / 2 + side * (1900 + r.next() * 600),
                               y: (a.y + b.y) / 2 + (r.next() < 0.5 ? -1 : 1) * (650 + r.next() * 450),
                               z: (a.z + b.z) / 2 + (r.next() - 0.5) * 500,
                               size: size, rot: (r.next() - 0.5) * 50,
                               colors: planetColors[Int(r.next() * Double(planetColors.count)) % planetColors.count]))
        }
        return out
    }
}

enum SkyLayers {
    // MARK: Nebulae and landmarks

    /// Draws the props (already sorted far to near) into a context whose origin is the screen centre.
    static func drawProps(_ g: inout GraphicsContext, _ f: SkyFrame, nebulae: Bool) {
        let reach = max(f.size.width, f.size.height) * 0.75
        for (depth, p) in f.props {
            let isNebula = if case .nebula = p.kind { true } else { false }
            guard isNebula == nebulae else { continue }
            let k = f.focal / depth
            let sx = (p.x - f.cam.x) * k, sy = (p.y - f.cam.y) * k
            let r = p.size * k
            guard abs(sx) - r < reach, abs(sy) - r < reach, r > 0.5 else { continue }
            let far = 1 - smoothstep((depth - (nebulae ? 5200 : 3600)) / (nebulae ? 3800 : 1600))
            switch p.kind {
            case .nebula(let i):
                guard let tex = f.tex, i < tex.nebulae.count else { continue }
                let a = f.s.layer(.nebula) * far * smoothstep((depth - 120) / 900) * (0.75 + 0.35 * f.level)
                guard a > 0.01 else { continue }
                var n = g
                n.blendMode = .plusLighter
                n.opacity = min(1, a)
                n.translateBy(x: sx, y: sy)
                n.rotate(by: .degrees(p.rot + f.t * 0.6))
                n.draw(Image(decorative: tex.nebulae[i], scale: 1), in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            case .galaxy:
                guard let tex = f.tex, let gal = tex.galaxy else { continue }
                let a = f.s.layer(.landmarks) * far * smoothstep((depth - 100) / 700)
                guard a > 0.01 else { continue }
                var n = g
                n.blendMode = .plusLighter
                n.opacity = min(1, a)
                n.translateBy(x: sx, y: sy)
                n.rotate(by: .degrees(p.rot))
                n.scaleBy(x: 1, y: 0.42)
                n.rotate(by: .degrees(f.t * 1.5))
                n.draw(Image(decorative: gal, scale: 1), in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            case .planet, .ringed:
                let a = f.s.layer(.landmarks) * far * smoothstep((depth - 100) / 600)
                guard a > 0.01 else { continue }
                var n = g
                n.opacity = min(1, a)
                n.translateBy(x: sx, y: sy)
                drawPlanet(&n, r: r, colors: p.colors, ringed: { if case .ringed = p.kind { true } else { false } }(),
                           tilt: p.rot, t: f.t)
            }
        }
    }

    /// A shaded planet at the origin, lit from the upper left, with an optional ring.
    static func drawPlanet(_ g: inout GraphicsContext, r: Double, colors c: [NeonRGB], ringed: Bool, tilt: Double, t: Double) {
        let disc = Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
        let light = CGPoint(x: -0.62, y: -0.55)

        // Atmosphere halo.
        var halo = g
        halo.blendMode = .plusLighter
        halo.fill(Path(ellipseIn: CGRect(x: -r * 1.35, y: -r * 1.35, width: r * 2.7, height: r * 2.7)),
                  with: .radialGradient(Gradient(stops: [.init(color: c[2].color(0), location: 0.7),
                                                         .init(color: c[2].color(0.35), location: 0.74),
                                                         .init(color: c[2].color(0.08), location: 0.84),
                                                         .init(color: c[2].color(0), location: 1)]),
                                        center: CGPoint(x: light.x * r * 0.12, y: light.y * r * 0.12), startRadius: 0, endRadius: r * 1.35))

        var ring = g
        ring.rotate(by: .degrees(tilt))
        func rings(_ ctx: inout GraphicsContext) {
            for (k, (w, o)) in [(2.35, 0.22), (2.0, 0.4), (1.7, 0.28)].enumerated() {
                let rw = r * w, rh = r * w * 0.24
                ctx.stroke(Path(ellipseIn: CGRect(x: -rw / 2 * 1.0, y: -rh / 2, width: rw, height: rh)),
                           with: .color(c[1].mixed(.white, 0.2).color(o)), lineWidth: r * (0.09 - 0.02 * Double(k)))
            }
        }
        if ringed { rings(&ring) }

        // Body: flat base, drifting bands, then light and shadow over the top.
        g.fill(disc, with: .color(c[0].color(1)))
        var bands = g
        bands.clip(to: disc)
        bands.rotate(by: .degrees(tilt))
        for b in 0..<6 {
            let y = (-0.8 + Double(b) * 0.3 + 0.03 * sin(t * 0.2 + Double(b))) * r
            let h = r * (0.08 + 0.06 * Double((b * 7) % 3))
            bands.fill(Path(ellipseIn: CGRect(x: -r * 1.3, y: y, width: r * 2.6, height: h)),
                       with: .color(c[1].color(b % 2 == 0 ? 0.35 : 0.18)))
        }
        g.fill(disc, with: .linearGradient(Gradient(stops: [.init(color: .white.opacity(0.28), location: 0),
                                                            .init(color: .clear, location: 0.35),
                                                            .init(color: .black.opacity(0.75), location: 0.68),
                                                            .init(color: .black.opacity(0.95), location: 1)]),
                                           startPoint: CGPoint(x: light.x * r, y: light.y * r),
                                           endPoint: CGPoint(x: -light.x * r, y: -light.y * r)))

        // The near half of the ring passes in front of the planet.
        if ringed {
            ring.clip(to: Path(CGRect(x: -r * 3, y: 0, width: r * 6, height: r * 2)))
            rings(&ring)
        }
    }

    // MARK: Dust and bokeh

    struct Mote { let x, y, z, size, hash: Double }
    static let motes: [Mote] = {
        var r = Seeded(0xD057_B0CE)
        return (0..<70).map { _ in Mote(x: r.next() * 1400, y: r.next() * 1200, z: r.next() * 1000,
                                        size: 1.6 + 4.4 * pow(r.next(), 2), hash: r.next()) }
    }()

    static func drawDust(_ g: inout GraphicsContext, _ f: SkyFrame, shutter: Double) {
        let strength = f.s.layer(.dust)
        guard strength > 0 else { return }
        var d = g
        d.blendMode = .plusLighter
        let tint = (f.pal.first ?? .white).mixed(NeonRGB(0.75, 0.85, 1), 0.6)
        func wrap(_ v: Double, _ m: Double) -> Double { let x = v.truncatingRemainder(dividingBy: m); return (x < 0 ? x + m : x) - m / 2 }
        for m in motes {
            var zr = (m.z - f.cam.z).truncatingRemainder(dividingBy: 1000)
            if zr < 0 { zr += 1000 }
            zr += 8
            let a = strength * smoothstep((zr - 14) / 70) * (1 - smoothstep((zr - 450) / 520)) * (0.35 + 0.65 * m.hash)
            guard a > 0.01 else { continue }
            let wx = wrap(m.x - f.cam.x, 1400), wy = wrap(m.y - f.cam.y, 1200)
            let k = f.focal / zr
            let sx = wx * k, sy = wy * k
            let rad = min(170, m.size * k)
            let tz = zr + f.vz * shutter * 1.4
            let k2 = f.focal / max(8, tz)
            let tx = wx * k2, ty = wy * k2
            let len = hypot(sx - tx, sy - ty)
            if len > rad * 0.7 {
                var p = Path(); p.move(to: CGPoint(x: sx, y: sy)); p.addLine(to: CGPoint(x: tx, y: ty))
                d.stroke(p, with: .color(tint.color(a * 0.16 * min(1, rad * 2 / len + 0.3))),
                         style: StrokeStyle(lineWidth: rad * 1.1, lineCap: .round))
            } else {
                // Out-of-focus disc: faint centre, slightly brighter rim.
                d.fill(Path(ellipseIn: CGRect(x: sx - rad, y: sy - rad, width: rad * 2, height: rad * 2)),
                       with: .radialGradient(Gradient(stops: [.init(color: tint.color(a * 0.06), location: 0),
                                                              .init(color: tint.color(a * 0.12), location: 0.8),
                                                              .init(color: tint.color(a * 0.05), location: 0.93),
                                                              .init(color: tint.color(0), location: 1)]),
                                             center: CGPoint(x: sx, y: sy), startRadius: 0, endRadius: rad))
            }
        }
    }

    // MARK: Aurora and sky glow

    static func drawAurora(_ g: inout GraphicsContext, _ f: SkyFrame) {
        let strength = f.s.layer(.aurora)
        guard strength > 0 else { return }
        let w = Double(f.size.width), h = Double(f.size.height)
        var a = g
        a.blendMode = .plusLighter
        let base = [NeonRGB(0.3, 1, 0.7), NeonRGB(0.25, 0.75, 1), NeonRGB(0.75, 0.4, 1)]
        let pal = f.pal.isEmpty ? base : f.pal
        let swell = 1 + 0.9 * f.level + 0.6 * f.beat

        // A soft glow that breathes with the level.
        let gc = base[0].mixed(pal[0], 0.4)
        a.fill(Path(CGRect(x: -w, y: -h, width: w * 2, height: h * 2)),
               with: .radialGradient(Gradient(colors: [gc.color(strength * (0.05 + 0.14 * f.level + 0.1 * f.beat)), gc.color(0)]),
                                     center: CGPoint(x: 0, y: h * 0.62), startRadius: 0, endRadius: max(w, h) * 0.8))

        for j in 0..<3 {
            let c = base[j].mixed(pal[j % pal.count], 0.35)
            let jj = Double(j)
            // Up near the top edge, clear of the lyrics.
            let baseY = -h * (0.33 + 0.05 * jj) - f.cam.y * 0.015
            var top: [CGPoint] = [], bottom: [CGPoint] = []
            let steps = 40
            for i in 0...steps {
                let x = -w * 0.75 + w * 1.5 * Double(i) / Double(steps)
                let xs = x / w
                let y = baseY + sin(xs * 2.3 + f.t * 0.11 * (1 + jj * 0.3) + jj * 2 - f.cam.x * 0.0004) * h * 0.05
                    + sin(xs * 5.1 - f.t * 0.23 + jj) * h * 0.02 + xs * xs * h * 0.12
                let hh = h * (0.09 + 0.07 * (0.5 + 0.5 * sin(xs * 3.7 + f.t * 0.3 + jj * 1.7))) * swell
                bottom.append(CGPoint(x: x, y: y))
                top.append(CGPoint(x: x, y: y - hh))
            }
            var band = Path()
            band.addLines(bottom)
            band.addLines(top.reversed())
            band.closeSubpath()
            let al = strength * (0.10 + 0.22 * f.level + 0.22 * f.beat) * (1 - 0.25 * jj)
            band.closeSubpath()
            a.fill(band, with: .linearGradient(Gradient(stops: [.init(color: c.color(al), location: 0),
                                                                .init(color: c.color(al * 0.35), location: 0.4),
                                                                .init(color: c.color(0), location: 1)]),
                                               startPoint: CGPoint(x: 0, y: baseY + h * 0.06),
                                               endPoint: CGPoint(x: 0, y: baseY - h * 0.24 * swell)))
            var edge = Path()
            edge.addLines(bottom)
            a.stroke(edge, with: .color(c.color(al * 0.18)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
            a.stroke(edge, with: .color(c.mixed(.white, 0.3).color(al * 0.3)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    // MARK: Textures (built once, off the main thread)

    static func nebula(_ index: Int) -> CGImage? {
        let n = 384
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let hues: [((Double, Double, Double), (Double, Double, Double))] = [
            ((0.75, 0.25, 0.9), (1.0, 0.35, 0.6)),    // violet → magenta
            ((0.15, 0.6, 1.0), (0.3, 0.95, 0.9)),     // blue → teal
            ((1.0, 0.4, 0.35), (1.0, 0.75, 0.35)),    // rose → amber
            ((0.3, 0.95, 0.55), (0.35, 0.55, 1.0)),   // green → blue
        ]
        let (h1, h2) = hues[index % hues.count]
        var r = Seeded(UInt64(0xAEB0 + index * 977))
        func gauss() -> Double { (r.next() + r.next() + r.next() + r.next() - 2) / 2 }
        func blob(_ x: Double, _ y: Double, _ rad: Double, _ c: (Double, Double, Double), _ a: Double) {
            let colors = [CGColor(colorSpace: cs, components: [c.0, c.1, c.2, a])!,
                          CGColor(colorSpace: cs, components: [c.0, c.1, c.2, 0])!] as CFArray
            guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) else { return }
            ctx.drawRadialGradient(grad, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                   endCenter: CGPoint(x: x, y: y), endRadius: rad, options: [])
        }
        let c = Double(n) / 2
        let clumps = (0..<6).map { _ in (c + gauss() * 70, c + gauss() * 70) }
        for _ in 0..<260 {
            let cl = clumps[Int(r.next() * Double(clumps.count)) % clumps.count]
            let x = cl.0 + gauss() * 55, y = cl.1 + gauss() * 55
            let edge = max(0, 1 - hypot(x - c, y - c) / (c * 0.78))
            let k = r.next()
            let col = (h1.0 + (h2.0 - h1.0) * k, h1.1 + (h2.1 - h1.1) * k, h1.2 + (h2.2 - h1.2) * k)
            blob(x, y, 14 + r.next() * 46, col, 0.05 * edge)
        }
        // Bright wisps.
        for _ in 0..<40 {
            let cl = clumps[Int(r.next() * Double(clumps.count)) % clumps.count]
            let x = cl.0 + gauss() * 35, y = cl.1 + gauss() * 35
            let edge = max(0, 1 - hypot(x - c, y - c) / (c * 0.7))
            blob(x, y, 6 + r.next() * 14, (1, 0.95, 1), 0.06 * edge)
        }
        // Dark knots.
        ctx.setBlendMode(.destinationOut)
        for _ in 0..<40 {
            blob(c + gauss() * 90, c + gauss() * 90, 8 + r.next() * 30, (0, 0, 0), 0.3)
        }
        ctx.setBlendMode(.normal)
        // A few young stars inside.
        for _ in 0..<26 {
            let x = c + gauss() * 70, y = c + gauss() * 70
            blob(x, y, 2 + r.next() * 4, (1, 1, 1), 0.7)
        }
        return ctx.makeImage()
    }

    static func galaxy() -> CGImage? {
        let n = 512
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var r = Seeded(0x6A1A_C5E5)
        func gauss() -> Double { (r.next() + r.next() + r.next() + r.next() - 2) / 2 }
        func blob(_ x: Double, _ y: Double, _ rad: Double, _ c: (Double, Double, Double), _ a: Double) {
            let colors = [CGColor(colorSpace: cs, components: [c.0, c.1, c.2, a])!,
                          CGColor(colorSpace: cs, components: [c.0, c.1, c.2, 0])!] as CFArray
            guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) else { return }
            ctx.drawRadialGradient(grad, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                   endCenter: CGPoint(x: x, y: y), endRadius: rad, options: [])
        }
        let c = Double(n) / 2
        // Two logarithmic spiral arms.
        for arm in 0..<2 {
            for _ in 0..<1400 {
                let th = r.next() * 4.2
                let rad = 14 * exp(0.62 * th)
                guard rad < c * 0.95 else { continue }
                let ang = th + Double(arm) * .pi
                let x = c + cos(ang) * rad + gauss() * (6 + rad * 0.09)
                let y = c + sin(ang) * rad + gauss() * (6 + rad * 0.09)
                let fade = 1 - rad / (c * 0.95)
                let warm = max(0, 1 - rad / 90)
                blob(x, y, 3 + r.next() * 9, (0.55 + 0.45 * warm, 0.65 + 0.25 * warm, 1 - 0.35 * warm), 0.07 * fade + 0.03)
            }
        }
        for _ in 0..<500 {
            let ang = r.next() * 2 * .pi, rad = abs(gauss()) * 150
            blob(c + cos(ang) * rad, c + sin(ang) * rad, 1 + r.next() * 1.5, (0.9, 0.93, 1), 0.5 * max(0, 1 - rad / 240))
        }
        blob(c, c, 70, (1, 0.9, 0.7), 0.55)
        blob(c, c, 22, (1, 0.97, 0.9), 0.9)
        return ctx.makeImage()
    }
}
