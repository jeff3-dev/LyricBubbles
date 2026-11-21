import SwiftUI

// MARK: - Postcards renderer
//
// Draws a PostcardFrame: the paper border, heading and colour chips, then the poster through a
// slowly drifting camera, layer by layer, with the lyric painted onto its surface. Glows are
// gradients and wide translucent strokes; no blur filters.

enum PostcardRenderer {
    static let paper = NeonRGB(0.925, 0.912, 0.886)
    static let ink = NeonRGB(0.17, 0.08, 0.06)

    struct Layout {
        var image: CGRect
        var radius: Double
        var framed: Bool
        var head: Double
        var margin: Double
        var bottom: Double
    }

    static func layout(_ f: PostcardFrame) -> Layout {
        let w = Double(f.size.width), h = Double(f.size.height)
        guard f.s.flag(.frame) else {
            return Layout(image: CGRect(origin: .zero, size: f.size), radius: 0, framed: false, head: 0, margin: 0, bottom: 0)
        }
        let m = max(10, min(w, h) * 0.045)
        let head = f.s.heading == .off ? 0 : max(22, min(w * 0.085, h * 0.11))
        let bottom = max(m, 24)
        let top = m + head * 0.8
        let image = CGRect(x: m, y: top, width: max(10, w - 2 * m), height: max(10, h - top - bottom))
        return Layout(image: image, radius: m * 0.22, framed: true, head: head, margin: m, bottom: bottom)
    }

    static func draw(_ ctx: inout GraphicsContext, _ f: PostcardFrame) {
        let L = layout(f)
        let full = CGRect(origin: .zero, size: f.size)
        ctx.fill(Path(full), with: .color(L.framed ? paper.color : .black))

        var img = ctx
        img.clip(to: Path(roundedRect: L.image, cornerRadius: L.radius))
        if let prev = f.prev, f.mix < 1 {
            shot(&img, prev, f, L.image)
            var top = img
            top.opacity = f.mix
            top.drawLayer { l in shot(&l, f.shot, f, L.image) }
        } else {
            shot(&img, f.shot, f, L.image)
        }

        grain(&ctx, f, full)
        if L.framed { border(&ctx, f, L) } else { caption(&ctx, f, full) }
    }

    // MARK: Border

    static func border(_ ctx: inout GraphicsContext, _ f: PostcardFrame, _ L: Layout) {
        let m = L.margin
        if L.head > 0 {
            let fs = L.head * 1.02
            let at = CGPoint(x: m - fs * 0.04, y: Double(L.image.minY) + fs * 0.13)
            func heading(_ s: String, _ a: Double) {
                guard !s.isEmpty, a > 0.01 else { return }
                ctx.draw(Text(s).font(.custom("HelveticaNeue-Bold", size: fs)).tracking(-fs * 0.035)
                            .foregroundColor(ink.color(a)), at: at, anchor: .bottomLeading)
            }
            if f.prev != nil, f.mix < 1 {
                heading(f.prevHeading, 1 - f.mix)
                heading(f.heading, f.mix)
            } else {
                heading(f.heading, 1)
            }
        }
        if f.s.flag(.chips) {
            let chips = f.shot.palette.chips
            let c = max(9, (L.head > 0 ? L.head : m * 2) * 0.36)
            let y = Double(L.image.minY) - c - max(4, m * 0.3)
            let x0 = Double(f.size.width) - m - c * Double(chips.count)
            let pulse = f.music ? f.beat : 0
            for (i, col) in chips.enumerated() {
                let lift = pulse * c * 0.18 * (i % 2 == 0 ? 1 : 0.6)
                ctx.fill(Path(CGRect(x: x0 + Double(i) * c, y: y - lift, width: c, height: c + lift)), with: .color(col.color))
            }
        }
        if !f.caption.isEmpty {
            let fs = max(9, min(13, L.bottom * 0.42))
            ctx.draw(Text(f.caption).font(.system(size: fs, weight: .medium)).foregroundColor(ink.color(0.5)),
                     at: CGPoint(x: m, y: Double(f.size.height) - L.bottom / 2), anchor: .leading)
        }
    }

    static func caption(_ ctx: inout GraphicsContext, _ f: PostcardFrame, _ full: CGRect) {
        guard !f.caption.isEmpty else { return }
        ctx.draw(Text(f.caption).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.5)),
                 at: CGPoint(x: full.midX, y: full.maxY - 14), anchor: .center)
    }

    static func grain(_ ctx: inout GraphicsContext, _ f: PostcardFrame, _ rect: CGRect) {
        guard let g = f.grain, f.s[.grain] > 0 else { return }
        var c = ctx
        c.blendMode = .overlay
        c.opacity = f.s[.grain] * 0.6
        let step = UInt64(max(0, f.t * 12))
        let ox = Double(PCRand.mix(step) % 64), oy = Double(PCRand.mix(step &+ 991) % 64)
        let side = max(Double(rect.width), Double(rect.height)) + 80
        c.draw(Image(decorative: g, scale: 1), in: CGRect(x: -72 + ox, y: -72 + oy, width: side, height: side))
    }

    // MARK: Camera

    struct Camera {
        var k: Double
        var cx: Double
        var cy: Double
        var visible: CGRect
    }

    /// Fills the image with the scene, drifts and pushes in slowly, and keeps signs on screen.
    static func camera(_ sc: PCScene, _ rect: CGRect, _ age: Double, _ s: PostcardSettings) -> Camera {
        let iw = Double(rect.width), ih = Double(rect.height)
        let drift = s[.drift]
        let k0 = max(iw / pcW, ih / pcH)
        let k = k0 * (1 + 0.07 * drift * smoothstep(age / 40))
        let vw = iw / k, vh = ih / k
        let ph = Double(sc.seed % 628) / 100
        var cx = pcW / 2 + sin(age * 0.045 + ph) * 40 * drift
        var cy = pcH / 2 + sin(age * 0.033 + ph) * 14 * drift
        let box = surfaceBox(sc)
        if sc.surface.kind == .board || sc.surface.kind == .neon {
            let pad = 30.0
            if Double(box.width) + 2 * pad < vw {
                cx = min(max(cx, Double(box.maxX) + pad - vw / 2), Double(box.minX) - pad + vw / 2)
            } else {
                cx = Double(box.midX)
            }
            if Double(box.height) + 2 * pad < vh {
                cy = min(max(cy, Double(box.maxY) + pad - vh / 2), Double(box.minY) - pad + vh / 2)
            } else {
                cy = Double(box.midY)
            }
        }
        cx = min(max(cx, vw / 2), pcW - vw / 2)
        cy = min(max(cy, vh / 2), pcH - vh / 2)
        return Camera(k: k, cx: cx, cy: cy, visible: CGRect(x: cx - vw / 2, y: cy - vh / 2, width: vw, height: vh))
    }

    /// The lyric surface in screen-facing scene coordinates (after mirroring).
    static func surfaceBox(_ sc: PCScene) -> CGRect {
        var box = sc.surface.box
        if sc.mirror { box.origin.x = pcW - box.maxX }
        return box
    }

    // MARK: Poster

    static func shot(_ ctx: inout GraphicsContext, _ sh: PCShot, _ f: PostcardFrame, _ rect: CGRect) {
        let sc = sh.scene, p = sh.palette
        let A = f.amount
        let lv = f.music ? f.level : 0, bt = f.music ? f.beat : 0
        let cam = camera(sc, rect, sh.age, f.s)
        var base = ctx
        base.translateBy(x: rect.midX, y: rect.midY)
        base.scaleBy(x: cam.k, y: cam.k)
        base.translateBy(x: -cam.cx, y: -cam.cy)

        let ph = Double(sc.seed % 1000) / 160
        let drift = f.s[.drift]
        func shift(_ depth: Double) -> Double { (depth - 0.3) * sin(sh.age * 0.08 + ph) * 26 * drift }
        func layer(_ depth: Double) -> GraphicsContext {
            var c = base
            c.translateBy(x: shift(depth), y: 0)
            if sc.mirror {
                c.translateBy(x: pcW, y: 0)
                c.scaleBy(x: -1, y: 1)
            }
            return c
        }

        // Sky
        base.fill(Path(CGRect(x: -400, y: -400, width: 2400, height: 1900)),
                  with: .linearGradient(Gradient(stops: [.init(color: p.skyTop.color, location: 0),
                                                         .init(color: p.skyMid.color, location: 0.55),
                                                         .init(color: p.skyLow.color, location: 1)]),
                                        startPoint: pp(0, 0), endPoint: pp(0, sc.horizon + 30)))
        if let st = sc.stars {
            let c = layer(0)
            let peak = p.night ? 0.85 : 0.3
            for k in 0..<3 {
                let tw = 0.65 + 0.35 * sin(f.t * (0.8 + 0.37 * Double(k)) * max(0.2, A) + Double(k) * 2.1)
                c.fill(st.buckets[k], with: .color(NeonRGB.white.mixed(p.sun, 0.3).color(peak * tw)))
            }
        }
        sunDisc(layer(0), sh, f)

        // Layers
        for item in sc.items {
            switch item {
            case .shape(let s):
                var c = layer(s.depth)
                if s.bob > 0 { c.translateBy(x: 0, y: sin(f.t * 1.1 + s.phase) * s.bob * A) }
                let col = p.color(s.role).mixed(p.skyLow, s.tint)
                if s.gradient {
                    let b = s.path.boundingRect
                    let y0 = Double(b.minY)
                    c.fill(s.path, with: .linearGradient(
                        Gradient(colors: [col.mixed(p.skyLow, 0.16).color(s.alpha), col.mixed(p.near, 0.22).color(s.alpha)]),
                        startPoint: pp(0, y0), endPoint: pp(0, y0 + min(Double(b.height), 520))))
                } else {
                    c.fill(s.path, with: .color(col.color(s.alpha)))
                }

            case .palm(let palm):
                var c = layer(palm.depth)
                let col = p.near.mixed(p.plum, 0.18).mixed(p.skyLow, palm.tint).color
                c.fill(palm.trunk, with: .color(col))
                c.translateBy(x: palm.crown.x, y: palm.crown.y)
                c.rotate(by: .radians(A * 0.035 * sin(f.t * 0.55 + palm.phase) + lv * 0.05 * sin(f.t * 2.3 + palm.phase)))
                c.fill(palm.core, with: .color(col))
                for (k, fr) in palm.fronds.enumerated() {
                    var g = c
                    g.rotate(by: .radians(A * 0.03 * sin(f.t * 1.25 + palm.phase + Double(k) * 0.9)))
                    g.fill(fr, with: .color(col))
                }

            case .lights(let l):
                let c = layer(l.depth)
                let col = p.glow.mixed(.white, 0.15)
                for k in 0..<3 {
                    let tw = 0.62 + 0.38 * sin(f.t * (0.9 + 0.41 * Double(k)) * max(0.15, A) + Double(k) * 2.3)
                    c.fill(l.buckets[k], with: .color(col.color(min(1, (p.night ? 1 : 0.85) * tw + bt * 0.5))))
                }

            case .windows(let w):
                let c = layer(w.depth)
                let litBase = p.night ? 0.85 : (sc.time == .golden ? 0.35 : 0.62)
                let lit = min(1, litBase + 0.25 * smoothstep(sh.age / 25))
                let off = p.near.mixed(p.mid, 0.45).color
                for (i, rc) in w.rects.enumerated() {
                    if w.on[i] < lit {
                        c.fill(Path(rc), with: .linearGradient(
                            Gradient(colors: [p.glow.mixed(.white, 0.3 + bt * 0.3).color, p.warm.mixed(p.glow, 0.25).color]),
                            startPoint: pp(Double(rc.midX), Double(rc.minY)), endPoint: pp(Double(rc.midX), Double(rc.maxY))))
                    } else {
                        c.fill(Path(rc), with: .color(off))
                    }
                }

            case .car(let car):
                var c = layer(car.depth)
                carShape(&c, car, p, sc, bt)

            case .sea(let sea):
                var c = layer(0.1)
                seaSurface(&c, sea, p, f, A)

            case .clouds(let cs):
                let c = layer(0.05)
                for cl in cs {
                    var g = c
                    let span = 2400.0
                    let x = (cl.x + f.t * cl.speed * A).truncatingRemainder(dividingBy: span) - 400
                    g.translateBy(x: x, y: 0)
                    g.fill(cl.path, with: .color(p.skyMid.mixed(p.sun, cl.tone).color(p.night ? 0.25 : 0.5)))
                }

            case .beam(let b):
                guard sc.time != .golden else { continue }
                let c = layer(b.depth)
                let phase = f.t * 0.5 * max(0.3, A)
                let reach = cos(phase)
                let len = b.length * abs(reach) * (1 + bt * 0.2)
                guard len > 20 else { continue }
                let dir = reach >= 0 ? 1.0 : -1.0
                let ox = Double(b.origin.x), oy = Double(b.origin.y)
                var beam = Path()
                beam.move(to: b.origin)
                beam.addLine(to: pp(ox + dir * len, oy - len * 0.07))
                beam.addLine(to: pp(ox + dir * len, oy + len * 0.07))
                beam.closeSubpath()
                c.fill(beam, with: .linearGradient(Gradient(colors: [p.glow.color(p.night ? 0.5 : 0.32), p.glow.color(0)]),
                                                   startPoint: b.origin, endPoint: pp(ox + dir * len, oy)))

            case .birds(let bd):
                let c = layer(0.3)
                var g = PCRand(bd.seed)
                var path = Path()
                for i in 0..<5 {
                    let speed = g.d(8, 16), s = g.d(5, 9)
                    let x = (g.d(0, 2400) + f.t * speed * max(0.2, A)).truncatingRemainder(dividingBy: 2400) - 400
                    let y = bd.y + g.d(-50, 50) + sin(f.t * 0.4 + Double(i)) * 8
                    let flap = sin(f.t * (4 + Double(i) * 0.4) + Double(i)) * 0.8
                    path.move(to: pp(x - 8 * s / 5, y - flap * 3))
                    path.addQuadCurve(to: pp(x, y), control: pp(x - 4 * s / 5, y - 4))
                    path.addQuadCurve(to: pp(x + 8 * s / 5, y - flap * 3), control: pp(x + 4 * s / 5, y - 4))
                }
                c.stroke(path, with: .color(p.near.mixed(p.skyMid, 0.2).color(0.8)), lineWidth: 2.2)

            case .lyric:
                var c = base
                c.translateBy(x: shift(sc.surface.depth), y: 0)
                surface(&c, sh, f, cam.visible)
            }
        }
    }

    static func sunDisc(_ ctx: GraphicsContext, _ sh: PCShot, _ f: PostcardFrame) {
        let c = ctx
        let sc = sh.scene, p = sh.palette
        let bt = f.music ? f.beat : 0
        let sink = sc.retroSun || p.night ? 0 : min(70, sh.age * 0.7 * f.amount)
        let sx = Double(sc.sun.x), sy = Double(sc.sun.y) + sink, r = sc.sunR
        let glow = r * (p.night ? 3 : 4.5) * (1 + bt * 0.1)
        c.fill(Path(ellipseIn: CGRect(x: sx - glow, y: sy - glow, width: glow * 2, height: glow * 2)),
               with: .radialGradient(Gradient(colors: [p.sun.color(p.night ? 0.25 : 0.45), p.sun.color(0)]),
                                     center: pp(sx, sy), startRadius: r * 0.8, endRadius: glow))
        let disc = Path(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2))
        if sc.retroSun {
            c.fill(disc, with: .linearGradient(Gradient(colors: [p.sun.color, p.warm.mixed(p.sun, 0.35).color]),
                                               startPoint: pp(sx, sy - r), endPoint: pp(sx, sy + r)))
            var g = c
            g.clip(to: disc)
            let gap = r * 0.17
            let roll = (f.t * 5 * f.amount).truncatingRemainder(dividingBy: gap)
            var bands = Path()
            let start = sy - r * 0.55
            for k in -1..<8 {
                let y = start + Double(k) * gap + roll
                let h = gap * (0.08 + 0.55 * (y - start) / r)
                if h > 0.5 { bands.addRect(CGRect(x: sx - r, y: y, width: r * 2, height: h)) }
            }
            g.fill(bands, with: .color(p.skyLow.color))
        } else {
            c.fill(disc, with: .color(p.sun.color(sc.time == .golden ? 0.9 : 1)))
        }
    }

    static func carShape(_ c: inout GraphicsContext, _ car: PCCar, _ p: PCPalette, _ sc: PCScene, _ bt: Double) {
        let top = p.accent.mixed(.white, 0.18), bot = p.accent.mixed(p.near, 0.45)
        let b = car.body.boundingRect
        c.fill(car.body, with: .linearGradient(Gradient(colors: [top.color, bot.color]),
                                               startPoint: pp(0, Double(b.minY)), endPoint: pp(0, Double(b.maxY))))
        let g = car.glass.boundingRect
        c.fill(car.glass, with: .linearGradient(Gradient(colors: [p.skyLow.mixed(p.near, 0.15).color, p.near.mixed(p.mid, 0.3).color]),
                                                startPoint: pp(0, Double(g.minY)), endPoint: pp(0, Double(g.maxY))))
        c.fill(car.trim, with: .color(top.mixed(bot, 0.3).color))
        for w in car.wheels {
            let wx = Double(w.x), wy = Double(w.y), r = car.r
            c.fill(Path(ellipseIn: CGRect(x: wx - r * 1.18, y: wy - r * 1.18, width: r * 2.36, height: r * 2.36)), with: .color(p.near.color))
            c.fill(Path(ellipseIn: CGRect(x: wx - r, y: wy - r, width: r * 2, height: r * 2)), with: .color(p.near.mixed(p.mid, 0.25).color))
            c.fill(Path(ellipseIn: CGRect(x: wx - r * 0.45, y: wy - r * 0.45, width: r * 0.9, height: r * 0.9)), with: .color(p.sun.color(0.6)))
        }
        let lx = Double(car.lamp.x), ly = Double(car.lamp.y), lr = car.r * 0.3
        if sc.time != .golden {
            let gr = car.r * (2.2 + bt * 1.6)
            c.fill(Path(ellipseIn: CGRect(x: lx - gr, y: ly - gr, width: gr * 2, height: gr * 2)),
                   with: .radialGradient(Gradient(colors: [p.sun.color(0.55 + bt * 0.4), p.sun.color(0)]),
                                         center: car.lamp, startRadius: 0, endRadius: gr))
        }
        c.fill(Path(ellipseIn: CGRect(x: lx - lr, y: ly - lr, width: lr * 2, height: lr * 2)), with: .color(p.sun.color))
    }

    static func seaSurface(_ c: inout GraphicsContext, _ sea: PCSea, _ p: PCPalette, _ f: PostcardFrame, _ A: Double) {
        let rect = CGRect(x: -400, y: sea.top, width: 2400, height: sea.bottom - sea.top)
        c.fill(Path(rect), with: .linearGradient(Gradient(colors: [p.skyLow.mixed(p.sea, 0.5).color, p.sea.mixed(p.near, 0.35).color]),
                                                 startPoint: pp(0, sea.top), endPoint: pp(0, sea.top + 320)))
        if !sea.mirror.isEmpty {
            var m = c
            m.clip(to: Path(rect))
            m.translateBy(x: 0, y: 2 * sea.top)
            m.scaleBy(x: 1, y: -1)
            for s in sea.mirror {
                m.fill(s.path, with: .color(p.color(s.role).mixed(p.skyLow, s.tint).mixed(p.sea, 0.45).color(0.5)))
            }
        }
        for k in 0..<3 {
            var g = c
            g.translateBy(x: sin(f.t * 0.3 * max(0.2, A) + Double(k) * 2.1) * 9 * A, y: 0)
            let a = 0.4 + 0.3 * sin(f.t * (0.9 + 0.35 * Double(k)) * max(0.2, A) + Double(k) * 1.7)
            g.fill(sea.glints[k], with: .color(p.sun.color(a * (p.night ? 0.6 : 0.85))))
        }
    }

    // MARK: Lyric surfaces

    /// Draws the sign (and the words on it) in unmirrored scene coordinates.
    static func surface(_ ctx: inout GraphicsContext, _ sh: PCShot, _ f: PostcardFrame, _ visible: CGRect) {
        let sc = sh.scene, p = sh.palette
        var box = surfaceBox(sc)
        let kind = sc.surface.kind
        if kind == .sky || kind == .banner {
            box = box.intersection(visible.insetBy(dx: 40, dy: 30))
            guard !box.isNull, box.width > 120, box.height > 40 else { return }
        }
        if kind == .board { boardBackdrop(&ctx, box, p, f) }
        let face = f.s.lettering.face(for: kind, caps: f.s.flag(.caps))
        for ly in sh.lyrics where ly.alpha > 0.01 {
            let text = f.s.flag(.caps) ? ly.text.uppercased() : ly.text
            switch kind {
            case .neon: neon(&ctx, text, ly, box, face, p, f)
            case .board: painted(&ctx, text, ly, box.insetBy(dx: box.width * 0.06, dy: box.height * 0.1), face, p, f,
                                 color: p.near.mixed(p.plum, 0.4), rise: 0.12)
            case .sky: painted(&ctx, text, ly, box, face, p, f,
                               color: sc.time == .golden ? p.plum.mixed(p.near, 0.25) : p.sun.mixed(p.skyLow, 0.12), rise: 0.3)
            case .banner: banner(&ctx, text, ly, box, face, p, f)
            }
        }
        if kind == .banner, sh.lyrics.isEmpty { plane(&ctx, box, nil, p, f) }
    }

    static func geometry(_ text: String, _ box: CGRect, _ face: GlyphFace, _ f: PostcardFrame, fill: Double = 0.86) -> NeonSignGeometry {
        let size = Double(box.height) * (0.3 + 0.45 * f.s[.size])
        return PCText.fit(text, face: face, maxSize: size.rounded(),
                          box: CGSize(width: Double(box.width) * 0.94, height: Double(box.height) * fill))
    }

    /// Word-by-word reveal: each word fades in a moment after the one before.
    static func wordAlphas(_ geo: NeonSignGeometry, _ ly: PCLyric) -> [Double] {
        let n = max(1, geo.words.count)
        let per = min(0.32, max(0.06, ly.dur * 0.6 / Double(n)))
        return geo.words.indices.map { i in smoothstep((ly.age - Double(i) * per) / 0.22) * ly.alpha }
    }

    static func neon(_ ctx: inout GraphicsContext, _ text: String, _ ly: PCLyric, _ box: CGRect, _ face: GlyphFace,
                     _ p: PCPalette, _ f: PostcardFrame) {
        let geo = geometry(text, box, face, f)
        var g = ctx
        g.translateBy(x: box.midX, y: box.midY)
        let tube = max(1.2, Double(geo.fontSize) * 0.05)
        let col = p.neon
        let bt = f.music ? f.beat : 0
        let hum = (0.95 + 0.05 * sin(f.t * 9)) * (1 + bt * 0.35)
        let alphas = wordAlphas(geo, ly)
        let n = max(1, geo.words.count)
        let per = min(0.32, max(0.06, ly.dur * 0.6 / Double(n)))
        let on = alphas.reduce(0, +) / Double(n)
        let b = geo.bounds
        let gw = Double(b.width) * 0.75 + 60, gh = Double(b.height) * 1.3 + 40
        var wash = g
        wash.translateBy(x: b.midX, y: b.midY)
        wash.scaleBy(x: 1, y: gh / gw)
        wash.fill(Path(ellipseIn: CGRect(x: -gw, y: -gw, width: gw * 2, height: gw * 2)),
                  with: .radialGradient(Gradient(colors: [col.color(0.24 * on * hum), col.color(0.08 * on * hum), col.color(0)]),
                                        center: .zero, startRadius: 0, endRadius: gw))
        let round = StrokeStyle(lineWidth: tube, lineCap: .round, lineJoin: .round)
        let salt = LyricPages.hash(text)
        for (i, w) in geo.words.enumerated() {
            g.stroke(w.path, with: .color(p.near.mixed(col, 0.3).color(0.85 * ly.alpha)), style: round)
            var a = alphas[i]
            guard a > 0.01 else { continue }
            let since = ly.age - Double(i) * per
            if since < 0.5 {
                let h = PCRand.mix(salt &+ UInt64(i * 977) &+ UInt64(max(0, since * 24))) % 100
                a *= h < 55 ? 1 : 0.15
            }
            a = min(1, a * hum)
            g.stroke(w.path, with: .color(col.color(0.12 * a)), style: StrokeStyle(lineWidth: tube * 5.5, lineCap: .round, lineJoin: .round))
            g.stroke(w.path, with: .color(col.color(0.3 * a)), style: StrokeStyle(lineWidth: tube * 2.5, lineCap: .round, lineJoin: .round))
            g.stroke(w.path, with: .color(col.mixed(.white, 0.6).color(a)), style: round)
        }
    }

    static func painted(_ ctx: inout GraphicsContext, _ text: String, _ ly: PCLyric, _ box: CGRect, _ face: GlyphFace,
                        _ p: PCPalette, _ f: PostcardFrame, color: NeonRGB, rise: Double) {
        let geo = geometry(text, box, face, f)
        let alphas = wordAlphas(geo, ly)
        for (i, w) in geo.words.enumerated() where alphas[i] > 0.01 {
            var g = ctx
            g.translateBy(x: box.midX, y: Double(box.midY) + (1 - alphas[i]) * Double(geo.fontSize) * rise)
            g.fill(w.path, with: .color(color.color(alphas[i] * 0.95)))
        }
    }

    static func boardBackdrop(_ ctx: inout GraphicsContext, _ box: CGRect, _ p: PCPalette, _ f: PostcardFrame) {
        let t = Double(min(box.width, box.height)) * 0.075
        let frame = box.insetBy(dx: -t, dy: -t)
        ctx.fill(Path(frame.offsetBy(dx: t * 0.6, dy: t * 0.6)), with: .color(p.near.color(0.3)))
        ctx.fill(Path(frame), with: .linearGradient(Gradient(colors: [p.plum.mixed(p.warm, 0.2).color, p.plum.mixed(p.near, 0.35).color]),
                                                    startPoint: pp(0, Double(frame.minY)), endPoint: pp(0, Double(frame.maxY))))
        let lit = p.night || p.skyTop.r + p.skyTop.g < 0.6
        ctx.fill(Path(box), with: .linearGradient(
            Gradient(colors: [p.sun.mixed(.white, 0.35).color, p.glow.mixed(p.warm, lit ? 0.35 : 0.2).color]),
            startPoint: pp(0, Double(box.minY)), endPoint: pp(0, Double(box.maxY))))
        // Marquee bulbs round the frame, chasing.
        let ring = box.insetBy(dx: -t / 2, dy: -t / 2)
        let gap = t * 1.15
        var pts: [CGPoint] = []
        let w = Double(ring.width), h = Double(ring.height)
        let nx = max(2, Int(w / gap)), ny = max(2, Int(h / gap))
        for i in 0..<nx { pts.append(pp(Double(ring.minX) + w * Double(i) / Double(nx), Double(ring.minY))) }
        for i in 0..<ny { pts.append(pp(Double(ring.maxX), Double(ring.minY) + h * Double(i) / Double(ny))) }
        for i in 0..<nx { pts.append(pp(Double(ring.maxX) - w * Double(i) / Double(nx), Double(ring.maxY))) }
        for i in 0..<ny { pts.append(pp(Double(ring.minX), Double(ring.maxY) - h * Double(i) / Double(ny))) }
        let bt = f.music ? f.beat : 0
        let tick = Int(f.t * 4 * max(0.25, f.amount))
        var bright = Path(), dim = Path(), halo = Path()
        let r = t * 0.26
        for (i, q) in pts.enumerated() {
            let x = Double(q.x), y = Double(q.y)
            let on = bt > 0.5 || (i + tick) % 3 == 0
            if on {
                bright.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                halo.addEllipse(in: CGRect(x: x - r * 2.4, y: y - r * 2.4, width: r * 4.8, height: r * 4.8))
            } else {
                dim.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        ctx.fill(halo, with: .color(p.glow.color(0.22)))
        ctx.fill(dim, with: .color(p.glow.mixed(p.near, 0.45).color))
        ctx.fill(bright, with: .color(p.glow.mixed(.white, 0.5).color))
    }

    static func banner(_ ctx: inout GraphicsContext, _ text: String, _ ly: PCLyric, _ box: CGRect, _ face: GlyphFace,
                       _ p: PCPalette, _ f: PostcardFrame) {
        let A = f.amount
        let geo = geometry(text, CGRect(x: 0, y: 0, width: Double(box.width) * 0.8, height: Double(box.height) * 0.62), face, f, fill: 1)
        let fs = Double(geo.fontSize)
        let bw = Double(geo.bounds.width) + fs * 1.1, bh = Double(geo.bounds.height) + fs * 0.6
        let cx = Double(box.midX) + sin(f.t * 0.05) * Double(box.width) * 0.04 + (Double(box.width) * 0.8 - bw) * 0.1
        let cy = Double(box.midY) + sin(f.t * 0.8) * 6 * A
        let rect = CGRect(x: cx - bw / 2 + Double(box.height) * 0.3, y: cy - bh / 2, width: bw, height: bh)
        var g = ctx
        g.opacity = ly.alpha
        plane(&g, box, rect, p, f)
        // Cloth with a ripple running along it.
        func wave(_ x: Double) -> Double { sin(x * 0.022 - f.t * 3 * max(0.2, A)) * 3.5 * A }
        var cloth = Path()
        var top: [CGPoint] = [], bot: [CGPoint] = []
        var x = Double(rect.minX)
        while x <= Double(rect.maxX) + 0.1 {
            let dy = wave(x) * (x - Double(rect.minX)) / bw
            top.append(pp(x, Double(rect.minY) + dy))
            bot.append(pp(x, Double(rect.maxY) + dy))
            x += 16
        }
        cloth.addLines(top + bot.reversed())
        cloth.closeSubpath()
        g.fill(cloth, with: .color(p.sun.mixed(.white, 0.45).color))
        g.stroke(cloth, with: .color(p.warm.mixed(p.near, 0.2).color(0.8)), lineWidth: 3)
        let alphas = wordAlphas(geo, PCLyric(text: text, age: ly.age, dur: ly.dur, alpha: 1))
        for (i, w) in geo.words.enumerated() where alphas[i] > 0.01 {
            var h = g
            let wx = Double(rect.midX) + Double(w.bounds.midX)
            h.translateBy(x: Double(rect.midX), y: Double(rect.midY) + wave(wx) * (wx - Double(rect.minX)) / bw)
            h.fill(w.path, with: .color(p.warm.mixed(p.near, 0.35).color(alphas[i])))
        }
    }

    /// A little prop plane flying left, towing the banner (if any) on two lines.
    static func plane(_ ctx: inout GraphicsContext, _ box: CGRect, _ banner: CGRect?, _ p: PCPalette, _ f: PostcardFrame) {
        let s = Double(box.height) / 170
        let px = banner.map { Double($0.minX) - 140 * s } ?? Double(box.midX) + sin(f.t * 0.05) * 200
        let py = banner.map { Double($0.midY) - 20 * s } ?? Double(box.midY)
        let col = p.near.mixed(p.skyMid, 0.15).color
        let c = ctx
        if let b = banner {
            var rope = Path()
            rope.move(to: pp(px + 50 * s, py))
            rope.addLine(to: pp(Double(b.minX), Double(b.minY) + 4))
            rope.move(to: pp(px + 50 * s, py))
            rope.addLine(to: pp(Double(b.minX), Double(b.maxY) - 4))
            c.stroke(rope, with: .color(col), lineWidth: 1.5)
        }
        var body = Path()
        body.addEllipse(in: CGRect(x: px - 50 * s, y: py - 8 * s, width: 100 * s, height: 16 * s))
        body.move(to: pp(px + 30 * s, py))
        body.addLine(to: pp(px + 52 * s, py - 26 * s))
        body.addLine(to: pp(px + 50 * s, py))
        body.closeSubpath()
        body.addRoundedRect(in: CGRect(x: px - 22 * s, y: py - 2 * s, width: 30 * s, height: 7 * s), cornerSize: CGSize(width: 3 * s, height: 3 * s))
        c.fill(body, with: .color(col))
        let spin = abs(sin(f.t * 30))
        c.fill(Path(CGRect(x: px - 53 * s, y: py - 14 * s * spin, width: 2.5 * s, height: 28 * s * spin)), with: .color(col))
    }
}

/// Fits a line into a box at the largest size that fits, wrapping onto more rows if that
/// lets the letters be bigger. Cached by text, face and box.
enum PCText {
    private static var cache: [String: NeonSignGeometry] = [:]
    private static let lock = NSLock()

    static func fit(_ text: String, face: GlyphFace, maxSize: Double, box: CGSize) -> NeonSignGeometry {
        let key = "\(face.name)|\(Int(maxSize))|\(Int(box.width))x\(Int(box.height))|" + text
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        var size = max(8, maxSize)
        var geo = NeonGlyphs.layout([text], face: face, fontSize: CGFloat(size), maxWidth: box.width)
        for _ in 0..<14 {
            if geo.bounds.width <= box.width + 1, geo.bounds.height <= box.height + 1 { break }
            size *= 0.9
            if size < 8 { break }
            geo = NeonGlyphs.layout([text], face: face, fontSize: CGFloat(size), maxWidth: box.width)
        }
        if geo.bounds.width > box.width + 1 || geo.bounds.height > box.height + 1 {
            geo = NeonGlyphs.sign([text], face: face, fontSize: CGFloat(size), box: box)
        }
        lock.lock()
        if cache.count > 120 { cache = [:] }
        cache[key] = geo
        lock.unlock()
        return geo
    }
}
