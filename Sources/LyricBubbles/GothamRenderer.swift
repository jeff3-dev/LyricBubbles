import SwiftUI

// MARK: - Gotham Night renderer
//
// Back to front: sky, moon, clouds, the light landing on the clouds (lyric spot, bat-signal,
// lightning; masked by the cloud texture), the beams, the lyrics, then the far, middle and
// near city with the fliers, highway and rooftop figures in between, then rain and a vignette.
// Most of the city is drawn in screen-height units (`u`), so it scales with the window.

enum GothamRenderer {
    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: max(0, min(1, a)))
    }

    static let signalLight = NeonRGB(1, 0.88, 0.55)
    static let sodium = NeonRGB(1, 0.72, 0.38)

    // MARK: Entry

    static func draw(_ g: inout GraphicsContext, _ f: GothamFrame) {
        let W = f.size.width, H = f.size.height
        guard W > 1, H > 1 else { return }
        let full = Path(CGRect(origin: .zero, size: f.size))
        let s = f.s
        let fl = lightning(f)
        let pulse = s[.pulse]
        let breathe = 1 + (f.level - 0.5) * 0.12 * pulse
        let clouds: GraphicsContext.ResolvedImage? = f.tex.map {
            g.resolve(Image(decorative: $0.clouds, scale: 1).renderingMode(.template).interpolation(.medium))
        }

        // Where the lights land.
        let spot = CGPoint(x: W * 0.5 + W * 0.012 * sin(f.t * 0.23), y: H * 0.25)
        let spotR = CGSize(width: max(W * 0.36, H * 0.4), height: H * 0.15)
        let lyricLight = lyricPresence(f) * (0.9 + 0.25 * f.beat * pulse)
        let hero = f.moment.hero
        let signal: Double = switch s.signal {
        case .off: 0
        case .breaks: hero
        case .always: 1
        }
        let corner = CGPoint(x: W - H * 0.2, y: H * 0.11)
        let emblemC = CGPoint(x: corner.x + (W * 0.5 - corner.x) * hero, y: corner.y + (H * 0.23 - corner.y) * hero)
        let emblemR = H * (0.085 + 0.12 * hero)

        // Sky: deep blue-black overhead, sodium glow from the streets below.
        g.fill(full, with: .linearGradient(Gradient(stops: [
            .init(color: rgb(0.012, 0.016, 0.03), location: 0),
            .init(color: rgb(0.035, 0.045, 0.07), location: 0.35),
            .init(color: rgb(0.12, 0.095, 0.085), location: 0.62),
            .init(color: rgb(0.22, 0.14, 0.08), location: 0.82),
        ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
        if fl.amount > 0 {
            g.fill(full, with: .linearGradient(Gradient(colors: [rgb(0.5, 0.56, 0.78, 0.32 * fl.amount),
                                                                 rgb(0.5, 0.56, 0.78, 0.08 * fl.amount)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: H * 0.8)))
        }
        drawMoon(&g, CGPoint(x: H * 0.2, y: H * 0.1), H)

        // Clouds, then the light that lands on them.
        if let clouds {
            cloudDecks(&g, clouds, f, high: rgb(0.11, 0.115, 0.14), low: rgb(0.17, 0.125, 0.10),
                       opacity: 0.35 + 0.65 * s[.clouds])
        }
        g.drawLayer { l in
            l.blendMode = .plusLighter
            if fl.amount > 0 { l.fill(full, with: .color(rgb(0.75, 0.8, 1, 0.6 * fl.amount))) }
            if lyricLight > 0 { softEllipse(&l, spot, spotR, f.ink, 0.7 * lyricLight) }
            l.blendMode = .normal
            if signal > 0 { emblem(&l, emblemC, emblemR, 0.9 * signal) }
            if let clouds {
                // Light shows most where the clouds are thick, a little in the clear haze between.
                l.blendMode = .destinationIn
                l.drawLayer { m in
                    m.fill(full, with: .color(.white.opacity(0.42)))
                    cloudDecks(&m, clouds, f, high: .white, low: .white, opacity: 1)
                }
            }
        }

        // Searchlight beams climbing out of the streets (the buildings will cut them off).
        let fogLift = 0.6 + 0.4 * s[.fog]
        if lyricLight > 0 {
            let sway = sin(f.t * 0.31) * W * 0.01
            beam(&g, from: CGPoint(x: W * 0.68 + sway, y: H * 1.05), to: spot, w0: H * 0.008, w1: spotR.width * 0.42,
                 color: f.ink, alpha: 0.12 * lyricLight * fogLift)
        }
        if signal > 0 {
            beam(&g, from: CGPoint(x: W * 0.16, y: H * 1.05), to: emblemC, w0: H * 0.01, w1: emblemR * 0.85,
                 color: signalLight, alpha: 0.11 * signal * fogLift)
        }
        if let seed = fl.boltSeed, fl.age < 0.4 { bolt(&g, seed: seed, amount: fl.amount, W: W, H: H) }

        // The lyrics, with a veil of drifting cloud over them.
        drawLyrics(&g, f, center: spot)
        if let clouds, s[.clouds] > 0 {
            var veil = clouds
            veil.shading = .color(rgb(0.1, 0.1, 0.12))
            var vg = g
            vg.opacity = 0.22 * s[.clouds]
            tile(&vg, veil, width: W * 2.3, rect: CGRect(x: 0, y: H * 0.08, width: W, height: H * 0.42),
                 drift: f.t * W * 0.009 + f.camX * H * 0.15)
        }

        // Far city, then haze.
        drawCity(&g, f, layer: 0, breathe: breathe)
        g.fill(Path(CGRect(x: 0, y: H * 0.35, width: W, height: H * 0.65)), with: .linearGradient(
            Gradient(colors: [.clear, rgb(0.30, 0.19, 0.11, 0.16 + 0.14 * s[.fog])]),
            startPoint: CGPoint(x: 0, y: H * 0.35), endPoint: CGPoint(x: 0, y: H * 0.85)))

        if s.flag(.blimp) { drawBlimp(&g, f) }
        drawBats(&g, f)
        drawGlider(&g, f, swoop: false)

        // Middle city, then ground fog.
        drawCity(&g, f, layer: 1, breathe: breathe)
        if s[.fog] > 0 {
            if let clouds {
                var mist = clouds
                mist.shading = .color(rgb(0.32, 0.25, 0.21))
                var mg = g
                mg.opacity = 0.42 * s[.fog]
                tile(&mg, mist, width: W * 1.8, rect: CGRect(x: 0, y: H * 0.6, width: W, height: H * 0.42),
                     drift: f.t * W * 0.006 + f.camX * H * 0.55)
            }
            g.fill(Path(CGRect(x: 0, y: H * 0.65, width: W, height: H * 0.35)), with: .linearGradient(
                Gradient(colors: [.clear, rgb(0.26, 0.17, 0.11, 0.3 * s[.fog])]),
                startPoint: CGPoint(x: 0, y: H * 0.65), endPoint: CGPoint(x: 0, y: H)))
        }

        drawHighway(&g, f)
        drawCity(&g, f, layer: 2, breathe: breathe)
        drawGlider(&g, f, swoop: true)
        drawRain(&g, f, flash: fl.amount)

        // Vignette, and the last of the lightning on everything.
        let m = max(W, H)
        g.fill(full, with: .radialGradient(Gradient(colors: [.clear, .clear, rgb(0, 0, 0, 0.55)]),
                                           center: CGPoint(x: W / 2, y: H * 0.45), startRadius: 0, endRadius: m * 0.78))
        if fl.amount > 0 {
            g.blendMode = .plusLighter
            g.fill(full, with: .color(rgb(0.55, 0.6, 0.8, 0.05 * fl.amount)))
            g.blendMode = .normal
        }
    }

    // MARK: Lightning

    struct Flash {
        var amount = 0.0
        var boltSeed: UInt64?
        var age = 9.0
    }

    /// Weather lightning on a loose schedule, plus any strike the beat called down.
    static func lightning(_ f: GothamFrame) -> Flash {
        func env(_ dt: Double) -> Double {
            guard dt >= 0, dt < 1.4 else { return 0 }
            let a = exp(-dt * 7) * (0.75 + 0.25 * cos(dt * 70))
            let b = dt > 0.16 ? 0.8 * exp(-(dt - 0.16) * 8) : 0
            return min(1, a + b)
        }
        var best = Flash()
        let L = f.s[.lightning]
        guard L > 0 else { return best }
        let period = 30 - 22 * L
        let k = floor(f.t / period)
        for b in [k - 1, k] {
            var r = Seeded(UInt64(bitPattern: Int64(b)) &* 0x9E37_79B9_7F4A_7C15 &+ 77)
            let happens = r.next() < 0.35 + 0.6 * L
            let at = b * period + r.next() * period * 0.8
            let e = env(f.t - at) * (0.5 + 0.5 * r.next())
            if happens, e > best.amount { best = Flash(amount: e, boltSeed: r.next() < 0.7 ? r.state : nil, age: f.t - at) }
        }
        let e = env(f.t - f.flashAt) * (0.6 + 0.4 * f.s[.pulse])
        if e > best.amount { best = Flash(amount: e, boltSeed: f.flashSeed, age: f.t - f.flashAt) }
        return best
    }

    private static func bolt(_ g: inout GraphicsContext, seed: UInt64, amount: Double, W: CGFloat, H: CGFloat) {
        var r = Seeded(seed)
        var x = W * (0.1 + 0.8 * r.next()), y = H * 0.12
        var p = Path()
        p.move(to: CGPoint(x: x, y: y))
        while y < H * 0.62 {
            x += (r.next() - 0.5) * H * 0.06
            y += H * (0.02 + 0.03 * r.next())
            p.addLine(to: CGPoint(x: x, y: y))
            if r.next() < 0.18 {
                var bx = x, by = y
                let dir = r.next() < 0.5 ? -1.0 : 1.0
                var branch = Path()
                branch.move(to: CGPoint(x: bx, y: by))
                for _ in 0..<3 {
                    bx += dir * H * (0.01 + 0.02 * r.next())
                    by += H * (0.01 + 0.025 * r.next())
                    branch.addLine(to: CGPoint(x: bx, y: by))
                }
                p.addPath(branch)
            }
        }
        g.stroke(p, with: .color(rgb(0.6, 0.68, 1, 0.25 * amount)), style: StrokeStyle(lineWidth: H * 0.008, lineCap: .round, lineJoin: .round))
        g.stroke(p, with: .color(rgb(0.95, 0.97, 1, amount)), style: StrokeStyle(lineWidth: max(1, H * 0.0018), lineCap: .round, lineJoin: .round))
    }

    // MARK: Sky pieces

    private static func drawMoon(_ g: inout GraphicsContext, _ c: CGPoint, _ H: CGFloat) {
        let r = H * 0.03
        g.fill(Path(ellipseIn: CGRect(x: c.x - r * 7, y: c.y - r * 7, width: r * 14, height: r * 14)),
               with: .radialGradient(Gradient(colors: [rgb(0.7, 0.74, 0.8, 0.13), .clear]), center: c, startRadius: r, endRadius: r * 7))
        g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(rgb(0.82, 0.84, 0.8, 0.85)))
    }

    /// Draws a horizontally tiling image across `rect`, scrolled by `drift`.
    private static func tile(_ g: inout GraphicsContext, _ img: GraphicsContext.ResolvedImage, width tw: CGFloat,
                             rect: CGRect, drift: Double) {
        guard tw > 1 else { return }
        var x = -CGFloat(drift.truncatingRemainder(dividingBy: Double(tw)))
        if x > 0 { x -= tw }
        while x < rect.maxX {
            g.draw(img, in: CGRect(x: x, y: rect.minY, width: tw, height: rect.height))
            x += tw
        }
    }

    /// Two decks: a high slow one and a lower, faster, warmer one lit from the streets.
    private static func cloudDecks(_ g: inout GraphicsContext, _ img: GraphicsContext.ResolvedImage, _ f: GothamFrame,
                                   high: Color, low: Color, opacity: Double) {
        let W = f.size.width, H = f.size.height
        var a = img
        a.shading = .color(high)
        var ga = g
        ga.opacity = opacity
        tile(&ga, a, width: W * 1.5, rect: CGRect(x: 0, y: -H * 0.06, width: W, height: H * 0.5),
             drift: f.t * W * 0.004 + f.camX * H * 0.08)
        var b = img
        b.shading = .color(low)
        ga.opacity = opacity * 0.75
        tile(&ga, b, width: W * 2.3, rect: CGRect(x: 0, y: H * 0.08, width: W, height: H * 0.42),
             drift: f.t * W * 0.009 + f.camX * H * 0.15)
    }

    private static func softEllipse(_ g: inout GraphicsContext, _ c: CGPoint, _ r: CGSize, _ color: NeonRGB, _ a: Double) {
        var e = g
        e.translateBy(x: c.x, y: c.y)
        e.scaleBy(x: 1, y: r.height / r.width)
        e.fill(Path(ellipseIn: CGRect(x: -r.width, y: -r.width, width: r.width * 2, height: r.width * 2)),
               with: .radialGradient(Gradient(stops: [
                   .init(color: color.color(a), location: 0),
                   .init(color: color.color(a * 0.6), location: 0.5),
                   .init(color: color.color(0), location: 1),
               ]), center: .zero, startRadius: 0, endRadius: r.width))
    }

    /// The signal: a bright disc on the clouds, slightly skewed by the beam's angle, with the
    /// emblem's shadow cut out of it.
    private static func emblem(_ g: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ a: Double) {
        let col = signalLight
        g.drawLayer { l in
            l.translateBy(x: c.x, y: c.y)
            l.rotate(by: .degrees(-7))
            l.scaleBy(x: 1, y: 0.62)
            l.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .radialGradient(Gradient(stops: [
                .init(color: col.color(a), location: 0),
                .init(color: col.color(a * 0.82), location: 0.8),
                .init(color: col.color(a * 0.3), location: 0.92),
                .init(color: col.color(0), location: 1),
            ]), center: .zero, startRadius: 0, endRadius: r))
            l.blendMode = .destinationOut
            l.translateBy(x: 0, y: -r * 0.03)
            l.scaleBy(x: r * 0.74, y: r * 0.74 * 1.3)
            l.fill(GothamShapes.emblem, with: .color(.black))
        }
    }

    private static func beam(_ g: inout GraphicsContext, from o: CGPoint, to p: CGPoint, w0: CGFloat, w1: CGFloat,
                             color: NeonRGB, alpha: Double) {
        let dx = p.x - o.x, dy = p.y - o.y
        let len = max(1, hypot(dx, dy))
        let nx = -dy / len, ny = dx / len
        var b = g
        b.blendMode = .plusLighter
        func cone(_ k: CGFloat, _ a: Double) {
            var path = Path()
            path.move(to: CGPoint(x: o.x + nx * w0 * k, y: o.y + ny * w0 * k))
            path.addLine(to: CGPoint(x: p.x + nx * w1 * k, y: p.y + ny * w1 * k))
            path.addLine(to: CGPoint(x: p.x - nx * w1 * k, y: p.y - ny * w1 * k))
            path.addLine(to: CGPoint(x: o.x - nx * w0 * k, y: o.y - ny * w0 * k))
            path.closeSubpath()
            b.fill(path, with: .linearGradient(Gradient(colors: [color.color(a), color.color(a * 0.2)]), startPoint: o, endPoint: p))
        }
        cone(1, alpha)
        cone(0.35, alpha * 1.2)
    }

    // MARK: Lyrics

    private struct Word {
        var text: GraphicsContext.ResolvedText
        var size: CGSize
        var at: Double          // when it appears
        var seed: Double
    }

    private struct Block {
        var rows: [[(Word, CGPoint)]]   // top-left of each word, block centred on (0, 0)
        var height: CGFloat
        var fontSize: CGFloat
    }

    /// How strongly the lyric searchlight is on (it sputters when a new part of the song starts).
    static func lyricPresence(_ f: GothamFrame) -> Double {
        var p = 0.0
        for (l, out) in f.moment.shown {
            p = max(p, smoothstep((f.pos - l.start + 0.15) / 0.5) * (1 - smoothstep(out)))
        }
        if let cur = f.moment.shown.last?.line, cur.newSection {
            let age = f.pos - cur.start
            if age >= 0, age < 0.45, sin(age * 95) < -0.2 { p *= 0.35 }
        }
        return p
    }

    private static func layout(_ g: GraphicsContext, _ line: GothamLine, s: GothamSettings, size: CGFloat, maxW: CGFloat) -> Block {
        let caps = s.flag(.caps)
        let raw = caps ? line.text.uppercased() : line.text
        let words = raw.split(separator: " ").map(String.init)
        let total = Double(max(1, words.reduce(0) { $0 + $1.count }))
        var fs = size
        var best = Block(rows: [], height: 0, fontSize: fs)
        for attempt in 0..<4 {
            var before = 0
            let resolved: [Word] = words.enumerated().map { i, w in
                let r = g.resolve(Text(w).font(s.font.font(fs)).tracking(caps ? fs * 0.06 : 0))
                let at = line.start + line.reveal * Double(before) / total
                before += w.count
                return Word(text: r, size: r.measure(in: CGSize(width: 10_000, height: 10_000)), at: at,
                            seed: Double(LyricPages.hash(w + "\(i)") % 1000) / 1000)
            }
            let space = fs * 0.3
            var rows: [[Word]] = [[]]
            var rowW: CGFloat = 0
            for w in resolved {
                let add = (rows[rows.count - 1].isEmpty ? 0 : space) + w.size.width
                if rowW + add > maxW, !rows[rows.count - 1].isEmpty {
                    rows.append([w])
                    rowW = w.size.width
                } else {
                    rows[rows.count - 1].append(w)
                    rowW += add
                }
            }
            let fits = rows.count <= 2 && resolved.allSatisfy { $0.size.width <= maxW }
            if fits || attempt == 3 {
                let rowH = fs * 1.12
                let height = rowH * CGFloat(rows.count)
                var placed: [[(Word, CGPoint)]] = []
                for (ri, row) in rows.enumerated() {
                    let width = row.reduce(0) { $0 + $1.size.width } + space * CGFloat(max(0, row.count - 1))
                    var x = -width / 2
                    let y = -height / 2 + rowH * CGFloat(ri) + (rowH - (row.first?.size.height ?? fs)) / 2
                    var out: [(Word, CGPoint)] = []
                    for w in row {
                        out.append((w, CGPoint(x: x, y: y)))
                        x += w.size.width + space
                    }
                    placed.append(out)
                }
                best = Block(rows: placed, height: height, fontSize: fs)
                break
            }
            fs *= 0.84
        }
        return best
    }

    private static func drawLyrics(_ g: inout GraphicsContext, _ f: GothamFrame, center: CGPoint) {
        let W = f.size.width, H = f.size.height
        let s = f.s
        let base = max(14, H * (0.05 + 0.055 * s[.size]))
        let maxW = W * 0.84
        let glow = s[.glow]
        let core = f.ink.mixed(.white, 0.35)
        var currentBottom: CGFloat?

        for (line, out) in f.moment.shown {
            let block = layout(g, line, s: s, size: base, maxW: maxW)
            if out == 0 { currentBottom = center.y + block.height / 2 }
            let leave = 1 - smoothstep(out * 1.6)
            let lift = H * 0.09 * (1 - (1 - out) * (1 - out))
            let rg = block.fontSize * (0.035 + 0.07 * glow) * (1 + out * 2.5)
            for row in block.rows {
                for (w, p0) in row {
                    let appear = smoothstep((f.pos - w.at) / 0.3)
                    let a = appear * leave
                    guard a > 0.003 else { continue }
                    let p = CGPoint(x: center.x + p0.x + CGFloat(w.seed - 0.5) * W * 0.03 * out,
                                    y: center.y + p0.y + (1 - appear) * block.fontSize * 0.15 - lift)
                    if glow > 0 {
                        var halo = w.text
                        halo.shading = .color(f.ink.color(a * 0.1 * glow))
                        for k in 0..<6 {
                            let ang = Double(k) * .pi / 3 + 0.4
                            g.draw(halo, at: CGPoint(x: p.x + rg * cos(ang), y: p.y + rg * sin(ang)), anchor: .topLeading)
                        }
                        halo.shading = .color(f.ink.color(a * 0.06 * glow))
                        g.draw(halo, at: CGPoint(x: p.x, y: p.y + rg * 2), anchor: .topLeading)
                        g.draw(halo, at: CGPoint(x: p.x, y: p.y - rg * 2), anchor: .topLeading)
                    }
                    var body = w.text
                    body.shading = .color(core.color(a * 0.95))
                    g.draw(body, at: p, anchor: .topLeading)
                }
            }
        }

        // The next line, waiting faintly underneath.
        if s.flag(.nextLine), let next = f.moment.next, let bottom = currentBottom {
            let until = next.start - f.pos
            let a = 0.16 * smoothstep((6 - until) / 2)
            if a > 0.003 {
                let block = layout(g, next, s: s, size: base * 0.5, maxW: maxW * 0.8)
                let c = CGPoint(x: center.x, y: bottom + block.fontSize * 0.5 + block.height / 2)
                for row in block.rows {
                    for (w, p0) in row {
                        var t = w.text
                        t.shading = .color(f.ink.color(a))
                        g.draw(t, at: CGPoint(x: c.x + p0.x, y: c.y + p0.y), anchor: .topLeading)
                    }
                }
            }
        }
    }

    // MARK: City

    private static func drawCity(_ g: inout GraphicsContext, _ f: GothamFrame, layer: Int, breathe: Double) {
        let spec = GothamCity.layers[layer]
        let H = f.size.height
        let aspect = f.size.width / H
        let off = f.camX * spec.depth
        let i0 = Int(floor((off - 0.35) / spec.slot)), i1 = Int(ceil((off + aspect + 0.1) / spec.slot))
        guard i1 >= i0 else { return }
        var body = Path(), warm = Path(), dim = Path(), cold = Path()
        var beacons: [CGPoint] = []
        var figures: [(GothamFigure, CGPoint, Bool, Double)] = []
        let showFigures = f.s[.characters] * 0.6
        for i in i0...i1 {
            let b = f.city.building(layer, i)
            if b.body.isEmpty { continue }
            let dx = Double(i) * spec.slot - off
            let tr = CGAffineTransform(translationX: dx, y: 0)
            body.addPath(b.body, transform: tr)
            warm.addPath(b.warm, transform: tr)
            dim.addPath(b.dim, transform: tr)
            cold.addPath(b.cold, transform: tr)
            for p in b.beacons { beacons.append(CGPoint(x: p.x + dx, y: p.y)) }
            if let fig = b.figure, b.figureRoll < showFigures {
                figures.append((fig, CGPoint(x: b.figureX + dx, y: b.roofY), b.flip, Double(i)))
            }
        }
        var u = g
        u.scaleBy(x: H, y: H)
        u.fill(body, with: .color(spec.color.color))
        let L = f.s[.lights], gain = spec.windowGain * breathe
        if L > 0 {
            u.fill(warm, with: .color(rgb(1, 0.78, 0.45, min(1, L * 3) * 0.9 * gain)))
            u.fill(dim, with: .color(rgb(0.85, 0.55, 0.28, min(1, max(0, L * 2.5 - 0.4)) * 0.7 * gain)))
            u.fill(cold, with: .color(rgb(0.62, 0.78, 1, min(1, max(0, L * 2 - 0.9)) * 0.6 * gain)))
        }
        // Red aircraft beacons, blinking out of step.
        for p in beacons {
            let phase = Double(LyricPages.hash("\(Int(p.x * 997))") % 100) / 100
            guard sin((f.t / 1.7 + phase) * 2 * .pi) > 0.55 else { continue }
            let r = 0.012 * (layer == 0 ? 0.7 : 1)
            u.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                   with: .radialGradient(Gradient(colors: [rgb(1, 0.2, 0.15, 0.5), .clear]), center: p, startRadius: 0, endRadius: r))
            let c = r * 0.18
            u.fill(Path(ellipseIn: CGRect(x: p.x - c, y: p.y - c, width: c * 2, height: c * 2)), with: .color(rgb(1, 0.35, 0.3)))
        }
        for (fig, at, flip, seed) in figures {
            drawFigure(&u, fig, at: at, flip: flip, seed: seed, t: f.t, color: spec.color, H: H)
        }
    }

    private static func drawFigure(_ u: inout GraphicsContext, _ fig: GothamFigure, at: CGPoint, flip: Bool, seed: Double,
                                   t: Double, color: NeonRGB, H: CGFloat) {
        let h = fig.height
        var fg = u
        fg.translateBy(x: at.x, y: at.y)
        fg.scaleBy(x: flip ? -h : h, y: h)
        let parts = fig.parts(t: t, seed: seed.truncatingRemainder(dividingBy: 7) / 7)
        let rim = 1.1 / (h * H)
        for p in parts { fg.stroke(p, with: .color(fig.rim.color(0.22)), lineWidth: rim) }
        for p in parts { fg.fill(p, with: .color(color.color)) }
    }

    // MARK: Fliers

    private static func drawGlider(_ g: inout GraphicsContext, _ f: GothamFrame, swoop: Bool) {
        let B = f.s[.batman]
        guard B > 0 else { return }
        let H = f.size.height, aspect = f.size.width / H
        let cyc = 70 - 45 * B
        let k = floor(f.t / cyc)
        let ph = f.t - k * cyc
        var r = Seeded(UInt64(bitPattern: Int64(k)) &* 0x2545_F491_4F6C_DD1D &+ 99)
        guard (r.next() < 0.3) == swoop else { return }
        let rightward = r.next() < 0.5
        let dur = swoop ? 3.0 : 12.0
        guard ph < dur else { return }
        let u = ph / dur
        var x: Double, y: Double, width: Double, angle: Double, flap: Double
        if swoop {
            x = -0.4 + u * (aspect + 0.8)
            y = 0.5 + 0.3 * u * u
            width = 0.55
            angle = 14
            flap = 0.5 * sin(f.t * 6)
        } else {
            x = -0.15 + u * (aspect + 0.3)
            y = 0.36 + 0.05 * r.next() + 0.03 * sin(u * .pi * 2)
            width = 0.08
            angle = 4 * sin(u * .pi * 3)
            flap = 0.3 * sin(f.t * 2.2)
        }
        if !rightward { x = aspect - x; angle = -angle }
        var c = g
        c.scaleBy(x: H, y: H)
        c.translateBy(x: x, y: y)
        c.rotate(by: .degrees(angle))
        c.scaleBy(x: width / 2, y: width / 2)
        let path = GothamShapes.glider(flap: flap)
        if swoop {
            c.stroke(path, with: .color(rgb(0.5, 0.55, 0.7, 0.25)), lineWidth: 3 / (width / 2 * H))
        }
        c.fill(path, with: .color(swoop ? rgb(0.006, 0.006, 0.01) : rgb(0.025, 0.027, 0.035)))
    }

    private static func drawBats(_ g: inout GraphicsContext, _ f: GothamFrame) {
        let B = f.s[.bats]
        guard B > 0 else { return }
        let H = f.size.height, aspect = f.size.width / H
        let cyc = 40 - 25 * B
        let k = floor(f.t / cyc)
        let ph = f.t - k * cyc
        guard ph < 7 else { return }
        var r = Seeded(UInt64(bitPattern: Int64(k)) &* 0x5851_F42D_4C95_7F2D &+ 7)
        let x0 = aspect * (0.2 + 0.6 * r.next())
        let dir = r.next() < 0.5 ? -1.0 : 1.0
        var c = g
        c.scaleBy(x: H, y: H)
        var flock = Path()
        for i in 0..<10 {
            let d = Double(i)
            let lag = r.next() * 1.2
            let p = max(0, ph - lag) / 6
            guard p > 0, p < 1 else { _ = r.next(); continue }
            let spread = r.next()
            let x = x0 + dir * (p * 0.7 + spread * 0.12 + 0.02 * sin(f.t * 3 + d))
            let y = 0.62 - p * 0.42 + spread * 0.06 + 0.01 * sin(f.t * 5 + d * 2)
            let sz = 0.006 + 0.005 * spread
            flock.addPath(GothamShapes.bat(flap: sin(f.t * 16 + d * 1.7)),
                          transform: CGAffineTransform(a: sz, b: 0, c: 0, d: sz, tx: x, ty: y))
        }
        c.fill(flock, with: .color(rgb(0.02, 0.02, 0.03)))
    }

    private static func drawBlimp(_ g: inout GraphicsContext, _ f: GothamFrame) {
        let H = f.size.height, aspect = f.size.width / H
        let cyc = 120.0, dur = 85.0
        let ph = f.t.truncatingRemainder(dividingBy: cyc)
        guard ph < dur else { return }
        let x = -0.2 + ph / dur * (aspect + 0.4)
        let y = 0.355
        let len = 0.13
        var c = g
        c.scaleBy(x: H, y: H)
        // Its spotlight, sweeping the streets.
        let gondola = CGPoint(x: x * H, y: (y + 0.024) * H)
        let target = CGPoint(x: (x + 0.12 * sin(f.t * 0.45)) * H, y: H * 0.9)
        beam(&g, from: gondola, to: target, w0: H * 0.002, w1: H * 0.05, color: NeonRGB(0.85, 0.9, 1), alpha: 0.05)
        var b = c
        b.translateBy(x: x, y: y)
        b.scaleBy(x: len, y: len)
        for p in GothamShapes.blimp { b.fill(p, with: .color(rgb(0.05, 0.052, 0.065))) }
        if sin(f.t * 4) > 0.6 {
            let p = CGPoint(x: x - len * 0.48, y: y - len * 0.18)
            c.fill(Path(ellipseIn: CGRect(x: p.x - 0.008, y: p.y - 0.008, width: 0.016, height: 0.016)),
                   with: .radialGradient(Gradient(colors: [rgb(1, 0.25, 0.2, 0.7), .clear]), center: p, startRadius: 0, endRadius: 0.008))
        }
        c.fill(Path(ellipseIn: CGRect(x: x + len * 0.45, y: y - 0.0015, width: 0.003, height: 0.003)), with: .color(rgb(1, 1, 0.9, 0.8)))
    }

    // MARK: Highway

    private static func drawHighway(_ g: inout GraphicsContext, _ f: GothamFrame) {
        let H = f.size.height, aspect = f.size.width / H
        let off = f.camX * 0.62
        let deck = 0.868
        var u = g
        u.scaleBy(x: H, y: H)
        let dark = rgb(0.018, 0.019, 0.026)
        u.fill(Path(CGRect(x: -0.1, y: deck, width: aspect + 0.2, height: 0.016)), with: .color(dark))
        u.fill(Path(CGRect(x: -0.1, y: deck - 0.005, width: aspect + 0.2, height: 0.0016)), with: .color(dark))
        func repeated(_ step: Double, _ draw: (Double) -> Void) {
            var x = -((off.truncatingRemainder(dividingBy: step)) + step).truncatingRemainder(dividingBy: step)
            while x < aspect + step { draw(x); x += step }
        }
        var pillars = Path()
        repeated(0.22) { x in pillars.addRect(CGRect(x: x, y: deck + 0.016, width: 0.012, height: 0.2)) }
        u.fill(pillars, with: .color(dark))
        // Sodium lamps along the rail.
        repeated(0.16) { x in
            u.fill(Path(CGRect(x: x, y: deck - 0.036, width: 0.0018, height: 0.036)), with: .color(dark))
            let p = CGPoint(x: x + 0.006, y: deck - 0.036)
            u.fill(Path(ellipseIn: CGRect(x: p.x - 0.03, y: p.y - 0.03, width: 0.06, height: 0.06)),
                   with: .radialGradient(Gradient(colors: [sodium.color(0.28), .clear]), center: p, startRadius: 0, endRadius: 0.03))
            u.fill(Path(CGRect(x: p.x - 0.003, y: p.y - 0.001, width: 0.006, height: 0.002)), with: .color(sodium.color(0.9)))
        }

        // Traffic: tiny cars with head and tail lights, both ways.
        let T = f.s[.traffic]
        guard T > 0 else { return }
        let n = Int(T * 12)
        let span = aspect + 0.4
        var bodies = Path(), heads = Path(), tails = Path()
        for lane in 0..<2 {
            for c in 0..<n {
                var r = Seeded(UInt64(lane * 131 + c + 1) &* 0x9E37_79B9_7F4A_7C15)
                let dir = lane == 0 ? 1.0 : -1.0
                let v = (0.05 + 0.04 * r.next()) * dir
                var x = (r.next() * span + v * f.t - off).truncatingRemainder(dividingBy: span)
                if x < 0 { x += span }
                x -= 0.2
                let y = deck - 0.003 - Double(lane) * 0.002
                bodies.addRect(CGRect(x: x - 0.015, y: y - 0.006, width: 0.03, height: 0.007))
                let front = x + 0.015 * dir, back = x - 0.015 * dir
                heads.addEllipse(in: CGRect(x: front - 0.002, y: y - 0.003, width: 0.004, height: 0.0025))
                tails.addEllipse(in: CGRect(x: back - 0.002, y: y - 0.003, width: 0.004, height: 0.0025))
            }
        }
        u.fill(bodies, with: .color(dark))
        u.fill(heads, with: .color(rgb(1, 0.95, 0.8, 0.9)))
        u.fill(tails, with: .color(rgb(1, 0.15, 0.1, 0.9)))

        // Now and then a black car tears through, often with the police behind it.
        let cyc = 53.0
        let k = floor(f.t / cyc)
        let ph = f.t - k * cyc
        var r = Seeded(UInt64(bitPattern: Int64(k)) &* 0xD6E8_FEB8_6659_FD93 &+ 5)
        let chase = r.next() < 0.7
        if ph < 4.5 {
            let x = -0.3 + ph / 4.5 * (aspect + 0.9)
            let y = deck - 0.001
            // Afterburner and a streak of light behind it.
            let flame = CGPoint(x: x - 0.04, y: y - 0.008)
            u.fill(Path(CGRect(x: x - 0.32, y: y - 0.011, width: 0.28, height: 0.006)), with: .linearGradient(
                Gradient(colors: [.clear, rgb(1, 0.45, 0.12, 0.35)]), startPoint: CGPoint(x: x - 0.32, y: 0), endPoint: CGPoint(x: x - 0.04, y: 0)))
            u.fill(Path(ellipseIn: CGRect(x: flame.x - 0.025, y: flame.y - 0.025, width: 0.05, height: 0.05)),
                   with: .radialGradient(Gradient(colors: [rgb(1, 0.6, 0.2, 0.75), rgb(1, 0.3, 0.05, 0.2), .clear]),
                                         center: flame, startRadius: 0, endRadius: 0.025))
            var b = u
            b.translateBy(x: x, y: y)
            b.scaleBy(x: 0.085, y: 0.085)
            for p in GothamShapes.batmobile { b.fill(p, with: .color(rgb(0.004, 0.004, 0.006))) }
            if chase {
                for (lag, i) in [(0.2, 0), (0.34, 1)] { police(&u, x: x - lag, y: y, facingRight: true, t: f.t + Double(i) * 0.07) }
            }
        } else if !chase, ph > 20, ph < 34 {
            let x = aspect + 0.2 - (ph - 20) / 14 * (aspect + 0.4)
            police(&u, x: x, y: deck - 0.001, facingRight: false, t: f.t)
        }
    }

    private static func police(_ u: inout GraphicsContext, x: Double, y: Double, facingRight: Bool, t: Double) {
        let red = sin(t * 44) > 0
        let c = CGPoint(x: x, y: y - 0.022)
        let spill = red ? NeonRGB(1, 0.12, 0.1) : NeonRGB(0.15, 0.3, 1)
        var add = u
        add.blendMode = .plusLighter
        add.fill(Path(ellipseIn: CGRect(x: c.x - 0.12, y: c.y - 0.12, width: 0.24, height: 0.24)),
                 with: .radialGradient(Gradient(colors: [spill.color(0.2), .clear]), center: c, startRadius: 0, endRadius: 0.12))
        var b = u
        b.translateBy(x: x, y: y)
        b.scaleBy(x: facingRight ? 0.05 : -0.05, y: 0.05)
        for p in GothamShapes.policeCar { b.fill(p, with: .color(rgb(0.01, 0.01, 0.015))) }
        add.fill(Path(ellipseIn: CGRect(x: c.x - 0.003, y: c.y - 0.0015, width: 0.006, height: 0.003)), with: .color(spill.color(1)))
    }

    // MARK: Rain

    private static func drawRain(_ g: inout GraphicsContext, _ f: GothamFrame, flash: Double) {
        let R = f.s[.rain]
        guard R > 0 else { return }
        let W = f.size.width, H = f.size.height
        for layer in 0..<2 {
            let n = Int(R * (layer == 0 ? 170 : 90))
            let len = H * (layer == 0 ? 0.03 : 0.07)
            let speed = H * (layer == 0 ? 1.1 : 1.9)
            let slant = 0.18
            var p = Path()
            for i in 0..<n {
                var r = Seeded(UInt64(i * 2 + layer + 1) &* 0x9E37_79B9_7F4A_7C15)
                let x0 = r.next() * (W + H * 0.3)
                let ph = r.next()
                let cycle = H + len
                let y = (ph * cycle + f.t * speed * (0.85 + 0.3 * r.next())).truncatingRemainder(dividingBy: cycle) - len
                let x = x0 - y * slant
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x - len * slant, y: y + len))
            }
            let a = (layer == 0 ? 0.14 : 0.22) * (1 + flash * 2)
            g.stroke(p, with: .color(rgb(0.72, 0.76, 0.86, a)), lineWidth: layer == 0 ? 0.7 : 1.2)
        }
    }
}
