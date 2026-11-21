import SwiftUI

// MARK: - Fever City renderer
//
// Back to front: sky and stars, the moon (with a face), clouds with the whale between them, balloons,
// fireworks and the sky lyric carriers (blimp, tow banner, skywriting), the rocket, far city, haze,
// kaiju, middle city, the giant cat, the billboard and window-tower carriers, near city, the coaster,
// the street (lights, cars, parade, donut), the UFO, then the caption and the swap flash.
// The camera (drive-by, cuts to close-ups, or wild) wraps everything but the caption.

enum FeverRenderer {
    enum Carrier { case billboard, blimp, banner, skywriting, tower, caption }

    // MARK: Entry

    static func draw(_ g: inout GraphicsContext, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        guard W > 1, H > 1 else { return }
        let s = f.s
        let pal = f.pal
        let events = FeverEvents.active(f)
        let stages = s.flag(.lyrics) ? f.stages : []
        let weather = s.weather, wet = s[.intensity]

        // Camera.
        var world = g
        let cam = camera(f, events: events, stages: stages)
        world.translateBy(x: W / 2, y: H / 2 + cam.shake)
        world.rotate(by: .radians(cam.rot))
        world.scaleBy(x: cam.zoom, y: cam.zoom)
        world.translateBy(x: -cam.focus.x, y: -cam.focus.y)

        // Sky (oversized so a tilted camera never shows an edge).
        let sky = Path(CGRect(x: -W * 0.2, y: -H * 0.2, width: W * 1.4, height: H * 1.4))
        world.fill(sky, with: .linearGradient(Gradient(stops: [
            .init(color: pal.skyTop.color, location: 0),
            .init(color: pal.skyMid.color, location: 0.45),
            .init(color: pal.skyLow.color, location: 0.8),
        ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: H * 0.85)))
        if pal.night > 0.2 {
            var sg = world
            sg.opacity = weather == .clear ? 1 : 1 - (weather == .fog ? 0.6 : 0.9) * wet
            drawStars(&sg, f)
        }
        drawOrb(&world, f, wink: events[.wink])

        let clouds: GraphicsContext.ResolvedImage? = f.tex.map {
            world.resolve(Image(decorative: $0.clouds, scale: 1).renderingMode(.template).interpolation(.medium))
        }
        let cloudAmt = switch weather {
        case .clear: s[.clouds]
        case .rain, .storm: max(s[.clouds], 0.6 + 0.4 * wet)
        case .snow, .fog: max(s[.clouds], 0.5)
        }
        if let clouds, cloudAmt > 0 {
            cloudDeck(&world, clouds, f, color: pal.cloud.mixed(pal.skyTop, 0.3), y: -H * 0.04, h: H * 0.42, width: W * 1.6,
                      drift: 0.004, depth: 0.06, opacity: 0.6 * cloudAmt)
        }
        if let e = events[.whale] { FeverEvents.drawWhale(&world, e, f) }
        if let clouds, cloudAmt > 0 {
            cloudDeck(&world, clouds, f, color: pal.cloud, y: H * 0.1, h: H * 0.36, width: W * 2.2,
                      drift: 0.008, depth: 0.12, opacity: 0.55 * cloudAmt)
        }
        FeverEvents.drawBalloons(&world, f)
        FeverEvents.drawFireworks(&world, f, show: events[.show])
        for st in stages where [.blimp, .banner, .skywriting].contains(st.carrier) { drawStage(&world, st, f) }
        if let e = events[.rocket] { FeverEvents.drawRocket(&world, e, f) }

        // Far city, haze, kaiju, middle city.
        drawCity(&world, f, layer: 0)
        world.fill(Path(CGRect(x: -W * 0.2, y: H * 0.35, width: W * 1.4, height: H * 0.5)), with: .linearGradient(
            Gradient(colors: [.clear, pal.haze.color(0.35)]),
            startPoint: CGPoint(x: 0, y: H * 0.35), endPoint: CGPoint(x: 0, y: H * 0.8)))
        if let e = events[.kaiju] { FeverEvents.drawKaiju(&world, e, f) }
        drawCity(&world, f, layer: 1)
        if let e = events[.cat] { FeverEvents.drawCat(&world, e, f) }
        if weather == .fog, let clouds {
            cloudDeck(&world, clouds, f, color: pal.haze, y: H * 0.42, h: H * 0.3, width: W * 2.2,
                      drift: 0.012, depth: 0.3, opacity: 0.9 * wet)
        }
        for st in stages where st.carrier == .billboard || st.carrier == .tower { drawStage(&world, st, f) }

        // Near city, the coaster over it, then the street.
        drawCity(&world, f, layer: 2)
        if let e = events[.train] { FeverEvents.drawTrain(&world, e, f) }
        drawStreet(&world, f)
        if let e = events[.parade] { FeverEvents.drawParade(&world, e, f) }
        if let e = events[.donut] { FeverEvents.drawDonut(&world, e, f) }
        if let e = events[.ufo] { FeverEvents.drawUFO(&world, e, f) }

        // Outside the camera: the plain caption, the vignette and the swap flash.
        let full = Path(CGRect(origin: .zero, size: f.size))
        if weather != .clear { drawWeather(&g, f, weather, wet) }
        for st in stages where st.carrier == .caption { drawStage(&g, st, f) }
        g.fill(full, with: .radialGradient(Gradient(colors: [.clear, .clear, rgb(0, 0, 0, 0.3)]),
                                           center: CGPoint(x: W / 2, y: H * 0.5), startRadius: 0, endRadius: max(W, H) * 0.8))
        if f.swapFlash > 0 {
            g.blendMode = .plusLighter
            g.fill(full, with: .color(pal.accent.mixed(.white, 0.5).color(0.45 * f.swapFlash)))
            g.blendMode = .normal
        }
    }

    // MARK: Camera

    struct Cam {
        var zoom = 1.0
        var focus: CGPoint
        var rot = 0.0
        var shake = 0.0
    }

    static func camera(_ f: FeverFrame, events: [FeverEvent: FeverActive], stages: [FeverStage]) -> Cam {
        let W = f.size.width, H = f.size.height
        let center = CGPoint(x: W / 2, y: H / 2)
        var cam = Cam(focus: center)
        if let k = events[.kaiju] {
            cam.shake = pow(abs(sin(k.age * 1.4 * .pi)), 12) * H * 0.006
        }
        switch f.s.camera {
        case .driveBy:
            return cam
        case .wild:
            cam.zoom = 1.14 + 0.08 * sin(f.t * 0.3) + 0.05 * f.beat
            cam.rot = 0.035 * sin(f.t * 0.23)
            cam.focus = CGPoint(x: W / 2 + W * 0.06 * sin(f.t * 0.17), y: H / 2 + H * 0.04 * sin(f.t * 0.21))
        case .cuts:
            // Glide, never cut: every close-up has a weight that eases in and out, and the camera
            // aims at the weighted mix, so handing over from one target to the next is a smooth pan.
            var dx = 0.0, dy = 0.0, lyricW = 0.0
            for st in stages where st.carrier != .caption {
                let w = smoothstep((st.age - 0.4) / 1.6) * (1 - smoothstep((st.age - 5) / 2)) * (1 - smoothstep(st.leave * 1.5))
                let p = anchor(st.carrier, f)
                dx += w * (p.x - center.x); dy += w * (p.y - center.y); lyricW += w
            }
            var eventW = 0.0, ex = 0.0, ey = 0.0
            for e in events.values where e.kind.isBig {
                let w = smoothstep((e.p - 0.16) / 0.08) * (1 - smoothstep((e.p - 0.44) / 0.08))
                let p = FeverEvents.anchor(e, W: W, H: H)
                ex += w * (p.x - center.x); ey += w * (p.y - center.y); eventW += w
            }
            let lw = min(1, lyricW), ew = min(1, eventW) * (1 - lw)
            let lx = lyricW > 0 ? dx / max(1, lyricW) : 0, ly = lyricW > 0 ? dy / max(1, lyricW) : 0
            let vx = eventW > 0 ? ex / max(1, eventW) : 0, vy = eventW > 0 ? ey / max(1, eventW) : 0
            cam.zoom = 1 + 0.2 * lw + 0.3 * ew
            cam.focus = CGPoint(x: center.x + lx + vx * (1 - lw), y: center.y + ly + vy * (1 - lw))
        }
        // Keep the view inside the scene.
        let hw = W / (2 * cam.zoom), hh = H / (2 * cam.zoom)
        cam.focus.x = min(max(cam.focus.x, hw), W - hw)
        cam.focus.y = min(max(cam.focus.y, hh), H - hh)
        return cam
    }

    // MARK: Sky

    private static func drawStars(_ g: inout GraphicsContext, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        var r = Seeded(4242)
        var dots = Path()
        for i in 0..<90 {
            let x = r.next() * W, y = r.next() * H * 0.55
            let tw = 0.5 + 0.5 * sin(f.t * (1 + r.next() * 2) + Double(i))
            let d = H * (0.0015 + 0.003 * r.next()) * (0.6 + 0.4 * tw)
            dots.addEllipse(in: CGRect(x: x - d, y: y - d, width: d * 2, height: d * 2))
        }
        g.fill(dots, with: .color(.white.opacity(0.85 * min(1, (f.pal.night - 0.2) * 2))))
    }

    private static func drawOrb(_ g: inout GraphicsContext, _ f: FeverFrame, wink: FeverActive?) {
        let W = f.size.width, H = f.size.height
        let c = CGPoint(x: W * 0.8, y: H * 0.17 + H * 0.01 * sin(f.t * 0.4))
        let R = H * 0.085 * (1 + 0.04 * f.beat)
        let col = f.pal.orb
        g.fill(Path(ellipseIn: CGRect(x: c.x - R * 2.6, y: c.y - R * 2.6, width: R * 5.2, height: R * 5.2)),
               with: .radialGradient(Gradient(colors: [col.color(0.35), col.color(0)]), center: c, startRadius: R * 0.8, endRadius: R * 2.6))
        g.fill(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)), with: .color(col.color))
        guard f.s[.moon] > 0 else {
            if f.pal.night > 0.45 {
                var craters = Path()
                craters.addEllipse(in: CGRect(x: c.x - R * 0.5, y: c.y - R * 0.3, width: R * 0.35, height: R * 0.35))
                craters.addEllipse(in: CGRect(x: c.x + R * 0.15, y: c.y + R * 0.2, width: R * 0.25, height: R * 0.25))
                g.fill(craters, with: .color(col.mixed(NeonRGB(0.5, 0.5, 0.6), 0.25).color))
            }
            return
        }
        // A face: one eye winks now and then, both blink.
        let ink = col.mixed(NeonRGB(0.2, 0.1, 0.25), 0.8)
        let blink = f.t.truncatingRemainder(dividingBy: 5.3) < 0.12
        let winkK = wink.map { sin($0.p * .pi) } ?? 0
        for sx in [-1.0, 1.0] {
            let ex = c.x + sx * R * 0.35, ey = c.y - R * 0.15
            let shut = blink || (sx > 0 && winkK > 0.4)
            if shut {
                var lid = Path()
                lid.move(to: CGPoint(x: ex - R * 0.13, y: ey)); lid.addQuadCurve(to: CGPoint(x: ex + R * 0.13, y: ey), control: CGPoint(x: ex, y: ey + R * 0.1))
                g.stroke(lid, with: .color(ink.color), style: StrokeStyle(lineWidth: R * 0.06, lineCap: .round))
            } else {
                g.fill(Path(ellipseIn: CGRect(x: ex - R * 0.08, y: ey - R * 0.12, width: R * 0.16, height: R * 0.24)), with: .color(ink.color))
            }
        }
        var smile = Path()
        smile.move(to: CGPoint(x: c.x - R * 0.3, y: c.y + R * 0.25))
        smile.addQuadCurve(to: CGPoint(x: c.x + R * 0.3, y: c.y + R * 0.25), control: CGPoint(x: c.x, y: c.y + R * (0.5 + 0.2 * winkK)))
        g.stroke(smile, with: .color(ink.color), style: StrokeStyle(lineWidth: R * 0.06, lineCap: .round))
        let cheek = NeonRGB(1, 0.5, 0.6)
        for sx in [-1.0, 1.0] {
            g.fill(Path(ellipseIn: CGRect(x: c.x + sx * R * 0.55 - R * 0.12, y: c.y + R * 0.08, width: R * 0.24, height: R * 0.14)),
                   with: .color(cheek.color(0.5)))
        }
    }

    private static func cloudDeck(_ g: inout GraphicsContext, _ img: GraphicsContext.ResolvedImage, _ f: FeverFrame,
                                  color: NeonRGB, y: CGFloat, h: CGFloat, width tw: CGFloat, drift: Double, depth: Double, opacity: Double) {
        let W = f.size.width, H = f.size.height
        var im = img
        im.shading = .color(color.color)
        var u = g
        u.opacity = opacity
        let d = f.t * W * drift + f.camX * H * depth
        var x = -CGFloat(d.truncatingRemainder(dividingBy: Double(tw))) - W * 0.2
        if x > -W * 0.2 { x -= tw }
        while x < W * 1.2 {
            u.draw(im, in: CGRect(x: x, y: y, width: tw, height: h))
            x += tw
        }
    }

    // MARK: City

    private static func drawCity(_ g: inout GraphicsContext, _ f: FeverFrame, layer: Int) {
        let spec = FeverCityMap.layers[layer]
        let W = f.size.width, H = f.size.height
        let aspect = W / H
        let off = f.camX * spec.depth
        let i0 = Int(floor((off - 0.45) / spec.slot)), i1 = Int(ceil((off + aspect + 0.25) / spec.slot))
        guard i1 >= i0 else { return }
        var bodies = [Path](repeating: Path(), count: 5)
        var trims = [Path](repeating: Path(), count: 5)
        var lit = Path(), alt = Path(), dark = Path()
        let st = f.s[.stretch]
        for i in i0...i1 {
            let b = f.city.building(layer, i)
            if b.empty { continue }
            let dx = Double(i) * spec.slot - off - 0.2
            var tr = CGAffineTransform(translationX: dx, y: 0)
            if st > 0 {
                let sy = 1 + st * (0.16 * f.beat * (0.6 + 0.4 * sin(b.phase)) + 0.035 * sin(f.t * 2.2 + b.phase))
                tr = CGAffineTransform(translationX: dx, y: spec.baseY).scaledBy(x: 1, y: sy).translatedBy(x: 0, y: -spec.baseY)
            }
            bodies[b.color].addPath(b.body, transform: tr)
            trims[b.color].addPath(b.trim, transform: tr)
            lit.addPath(b.lit, transform: tr)
            alt.addPath(b.alt, transform: tr)
            dark.addPath(b.dark, transform: tr)
        }
        var u = g
        u.scaleBy(x: H, y: H)
        let pal = f.pal
        for k in 0..<5 {
            let body = pal.bldg[k].mixed(pal.haze, spec.fade)
            u.fill(bodies[k], with: .color(body.color))
            u.fill(trims[k], with: .color(body.mixed(.white, 0.28).mixed(pal.accent, 0.12).color))
        }
        let shade = pal.bldg[4].mixed(NeonRGB(0, 0, 0), 0.4).mixed(pal.haze, spec.fade)
        u.fill(dark, with: .color(shade.color(0.45)))
        let L = f.s[.lights] * (0.35 + 0.65 * pal.night) * (0.85 + 0.25 * f.level)
        if L > 0 {
            u.fill(lit, with: .color(pal.window.mixed(pal.haze, spec.fade * 0.5).color(min(1, L * 1.3))))
            u.fill(alt, with: .color(pal.windowAlt.mixed(pal.haze, spec.fade * 0.5).color(min(1, L * 1.1))))
        }
    }

    // MARK: Street

    private static func drawStreet(_ g: inout GraphicsContext, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        let pal = f.pal
        let off = f.camX * H
        g.fill(Path(CGRect(x: -W * 0.2, y: H * 0.905, width: W * 1.4, height: H * 0.025)), with: .color(pal.road.mixed(.white, 0.3).color))
        g.fill(Path(CGRect(x: -W * 0.2, y: H * 0.93, width: W * 1.4, height: H * 0.3)), with: .color(pal.road.color))
        // Dashed centre line, sliding with the near buildings.
        var dash = Path()
        let dw = H * 0.06, dg = H * 0.12
        var x = -CGFloat(off.truncatingRemainder(dividingBy: Double(dg))) - W * 0.2
        while x < W * 1.2 { dash.addRect(CGRect(x: x, y: H * 0.968, width: dw, height: H * 0.005)); x += dg }
        g.fill(dash, with: .color(pal.window.mixed(.white, 0.5).color(0.7)))

        // Street lamps and dancing traffic lights, fixed to the street.
        let lampGap = H * 0.32
        let j0 = Int(floor((off - W * 0.3) / lampGap)), j1 = Int(ceil((off + W * 1.3) / lampGap))
        let v = f.s[.signals] * (0.25 + 1.75 * f.s[.chaos])
        for j in j0...j1 {
            let lx = Double(j) * lampGap - off
            if v > 0, j % 3 == 0 {
                trafficLight(&g, x: lx, f: f, j: j, amount: min(1.5, v))
            } else {
                var pole = Path()
                pole.move(to: CGPoint(x: lx, y: H * 0.92)); pole.addLine(to: CGPoint(x: lx, y: H * 0.8))
                pole.addQuadCurve(to: CGPoint(x: lx + H * 0.03, y: H * 0.79), control: CGPoint(x: lx, y: H * 0.785))
                g.stroke(pole, with: .color(pal.sign.mixed(.white, 0.15).color), lineWidth: H * 0.005)
                let lc = CGPoint(x: lx + H * 0.03, y: H * 0.795)
                g.fill(Path(ellipseIn: CGRect(x: lc.x - H * 0.04, y: lc.y - H * 0.04, width: H * 0.08, height: H * 0.08)),
                       with: .radialGradient(Gradient(colors: [pal.window.color(0.5 * pal.night + 0.1), .clear]),
                                             center: lc, startRadius: 0, endRadius: H * 0.04))
                g.fill(Path(ellipseIn: CGRect(x: lc.x - H * 0.008, y: lc.y - H * 0.006, width: H * 0.016, height: H * 0.012)),
                       with: .color(pal.window.mixed(.white, 0.5).color))
            }
        }

        // Traffic in two lanes; everything hops on the beat.
        let n = Int((f.s[.traffic] * 7).rounded())
        guard n > 0 else { return }
        let hop = f.s[.hop] * (0.25 + 1.75 * f.s[.chaos])
        let span = W + H * 0.5
        for lane in 0..<2 {
            let y = lane == 0 ? H * 0.958 : H * 0.995
            let speed = lane == 0 ? 0.05 : -0.09
            for k in 0..<n {
                var r = Seeded(UInt64(lane * 100 + k + 3) &* 0x9E37_79B9_7F4A_7C15)
                var cx = ((Double(k) + r.next() * 0.6) / Double(n) * span + f.t * speed * H * (0.8 + 0.4 * r.next()) - off)
                    .truncatingRemainder(dividingBy: span)
                if cx < 0 { cx += span }
                cx -= H * 0.25
                let jump = hop * f.beat * H * 0.035 * (k % 2 == 0 ? 1 : 0.7)
                var u = g
                u.translateBy(x: cx, y: y - jump)
                if jump > 0 { u.rotate(by: .radians((lane == 0 ? -1 : 1) * 0.15 * f.beat * hop)) }
                car(&u, H: H, color: pal.bldg[(k + lane * 2) % 5].mixed(.white, 0.3), facingRight: lane == 0)
            }
        }
    }

    private static func trafficLight(_ g: inout GraphicsContext, x: Double, f: FeverFrame, j: Int, amount: Double) {
        let H = f.size.height
        var u = g
        u.translateBy(x: x, y: H * 0.92)
        let tempo = f.beat > 0.05 ? f.t * 4 : f.t * 2.5
        u.rotate(by: .radians(0.22 * amount * sin(tempo + Double(j))))
        u.fill(Path(CGRect(x: -H * 0.0035, y: -H * 0.15, width: H * 0.007, height: H * 0.15)), with: .color(rgb(0.15, 0.15, 0.2)))
        // Little arms waving.
        var arms = Path()
        let wave = sin(tempo * 2 + Double(j)) * 0.4 * amount
        arms.move(to: CGPoint(x: -H * 0.018, y: -H * 0.17)); arms.addLine(to: CGPoint(x: -H * 0.04, y: -H * (0.2 + 0.03 * wave)))
        arms.move(to: CGPoint(x: H * 0.018, y: -H * 0.17)); arms.addLine(to: CGPoint(x: H * 0.04, y: -H * (0.2 - 0.03 * wave)))
        u.stroke(arms, with: .color(rgb(0.15, 0.15, 0.2)), style: StrokeStyle(lineWidth: H * 0.005, lineCap: .round))
        u.fill(Path(roundedRect: CGRect(x: -H * 0.018, y: -H * 0.24, width: H * 0.036, height: H * 0.09), cornerRadius: H * 0.008),
               with: .color(rgb(0.95, 0.75, 0.15)))
        let lit = (f.beatCount + j) % 3
        let colors = [NeonRGB(1, 0.2, 0.25), NeonRGB(1, 0.8, 0.2), NeonRGB(0.2, 1, 0.45)]
        for i in 0..<3 {
            let c = CGPoint(x: 0, y: -H * (0.225 - 0.028 * Double(i)))
            let on = i == lit
            let r = H * 0.01
            if on {
                u.fill(Path(ellipseIn: CGRect(x: c.x - r * 3, y: c.y - r * 3, width: r * 6, height: r * 6)),
                       with: .radialGradient(Gradient(colors: [colors[i].color(0.5), .clear]), center: c, startRadius: 0, endRadius: r * 3))
            }
            u.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                   with: .color(on ? colors[i].mixed(.white, 0.3).color : rgb(0.2, 0.15, 0.1)))
        }
        // Googly eyes on the box, because why not.
        for sx in [-1.0, 1.0] {
            let e = CGPoint(x: sx * H * 0.009, y: -H * 0.255)
            u.fill(Path(ellipseIn: CGRect(x: e.x - H * 0.007, y: e.y - H * 0.007, width: H * 0.014, height: H * 0.014)), with: .color(.white))
            u.fill(Path(ellipseIn: CGRect(x: e.x - H * 0.003 + H * 0.003 * sin(f.t * 3), y: e.y - H * 0.003, width: H * 0.006, height: H * 0.006)),
                   with: .color(.black))
        }
    }

    /// A chunky toy car, wheels resting on y = 0.
    static func car(_ g: inout GraphicsContext, H: CGFloat, color: NeonRGB, facingRight: Bool) {
        var u = g
        if !facingRight { u.scaleBy(x: -1, y: 1) }
        let w = H * 0.085, h = H * 0.024
        u.fill(Path(roundedRect: CGRect(x: -w * 0.25, y: -h * 2, width: w * 0.55, height: h * 1.2), cornerRadius: h * 0.4),
               with: .color(color.mixed(.white, 0.15).color))
        u.fill(Path(roundedRect: CGRect(x: -w * 0.18, y: -h * 1.8, width: w * 0.4, height: h * 0.75), cornerRadius: h * 0.25),
               with: .color(rgb(0.7, 0.9, 1, 0.9)))
        u.fill(Path(roundedRect: CGRect(x: -w / 2, y: -h * 1.15, width: w, height: h), cornerRadius: h * 0.45), with: .color(color.color))
        u.fill(Path(ellipseIn: CGRect(x: w * 0.4, y: -h * 0.9, width: h * 0.35, height: h * 0.35)), with: .color(rgb(1, 1, 0.75)))
        u.fill(Path(ellipseIn: CGRect(x: -w * 0.52, y: -h * 0.9, width: h * 0.3, height: h * 0.3)), with: .color(rgb(1, 0.25, 0.3)))
        for wx in [-w * 0.28, w * 0.28] {
            u.fill(Path(ellipseIn: CGRect(x: wx - h * 0.4, y: -h * 0.6, width: h * 0.8, height: h * 0.8)), with: .color(rgb(0.1, 0.1, 0.12)))
            u.fill(Path(ellipseIn: CGRect(x: wx - h * 0.17, y: -h * 0.37, width: h * 0.34, height: h * 0.34)), with: .color(rgb(0.8, 0.8, 0.85)))
        }
    }

    // MARK: Lyric carriers

    private static func sizeK(_ f: FeverFrame) -> Double { 0.75 + 0.55 * f.s[.size] }

    /// Where a carrier sits once it has arrived (the camera's close-ups aim here).
    static func anchor(_ c: Carrier, _ f: FeverFrame) -> CGPoint {
        let W = f.size.width, H = f.size.height
        switch c {
        case .billboard: return CGPoint(x: W * 0.5, y: H * 0.5)
        case .blimp: return CGPoint(x: W * 0.5, y: H * 0.22)
        case .banner: return CGPoint(x: W * 0.5, y: H * 0.18)
        case .skywriting: return CGPoint(x: W * 0.5, y: H * 0.24)
        case .tower: return CGPoint(x: W * 0.5, y: H * 0.5)
        case .caption: return CGPoint(x: W * 0.5, y: H * 0.82)
        }
    }

    /// 0...1: a line's words fading in on a carrier that stays put, then out as the next takes over.
    private static func lineAlpha(_ line: GothamLine, out: Double, _ f: FeverFrame) -> Double {
        let inK = line.id == -100 ? 1 : smoothstep((f.pos - line.start - 0.1) / 0.35)
        return inK * (1 - smoothstep(out / 0.4))
    }

    private static func easeInOut(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Draws one section's carrier and its lines. Billboards roll past like a conveyor (each line on
    /// its own board, in lockstep with the last); the blimp, tower and banner arrive once for the whole
    /// section and their lines change on them; skywriting and captions write each line in place.
    private static func drawStage(_ g: inout GraphicsContext, _ st: FeverStage, _ f: FeverFrame) {
        let W = f.size.width, H = f.size.height
        let pal = f.pal
        let k = sizeK(f)
        let a = anchor(st.carrier, f)
        let arrive = easeInOut(st.age / FeverLyrics.handoff), gone = easeInOut(st.leave)
        let font = f.s.font
        func text(_ l: GothamLine) -> String { f.s.flag(.caps) ? l.text.uppercased() : l.text }
        func tint(_ l: GothamLine) -> NeonRGB { pal.bldg[((l.id % 5) + 5) % 5] }

        switch st.carrier {
        case .billboard:
            let bw = min(W * 0.56, H * 0.95) * k, bh = bw * 0.36
            let gap = max(bw + W * 0.06, W * 0.5 + bw / 2 + W * 0.02)
            for (line, out) in st.lines {
                let age = line.id == -100 ? 100 : f.pos - line.start
                let x = W * 0.5 + (1 - easeInOut(age)) * gap - easeInOut(out * GothamScript.exit) * gap
                billboard(&g, line, text(line), x: x, bw: bw, bh: bh, tint: tint(line), f)
            }

        case .tower:
            let tw = min(W * 0.6, H * 1.0) * k, th = H * 0.44
            let top = H * 0.3 + (1 - arrive) * H * 0.75 + gone * H * 0.75
            let rect = CGRect(x: a.x - tw / 2, y: top, width: tw, height: th + H * 0.4)
            let body = pal.bldg[st.index % 5].mixed(NeonRGB(0.05, 0.03, 0.1), 0.55)
            g.fill(Path(rect), with: .color(body.color))
            g.fill(Path(CGRect(x: rect.minX - H * 0.01, y: top - H * 0.02, width: tw + H * 0.02, height: H * 0.025)),
                   with: .color(body.mixed(.white, 0.3).color))
            // A grid of windows; the lit ones spell the line, and the lines flicker over as they change.
            let pitch = H * 0.024
            let cols = Int(tw / pitch) - 1, rows = Int(th / pitch) - 1
            let gx = rect.minX + (tw - Double(cols) * pitch) / 2, gy = top + pitch * 0.8
            var grid = Path()
            for r in 0..<max(0, rows) {
                for c in 0..<max(0, cols) {
                    grid.addRect(CGRect(x: gx + Double(c) * pitch + pitch * 0.15, y: gy + Double(r) * pitch + pitch * 0.15,
                                        width: pitch * 0.7, height: pitch * 0.7))
                }
            }
            g.fill(grid, with: .color(body.mixed(.white, 0.12).color))
            g.drawLayer { l in
                for (line, out) in st.lines {
                    var u = l
                    u.opacity = lineAlpha(line, out: out, f)
                    textBlock(&u, text(line), shown: shownWords(line, f), center: CGPoint(x: a.x, y: top + th * 0.47),
                              maxW: tw * 0.92, maxH: th * 0.8, font: font, color: pal.window.mixed(.white, 0.2).color, shadow: nil)
                }
                // Masks only act where they paint, so the grid goes in its own layer.
                l.blendMode = .destinationIn
                l.drawLayer { m in m.fill(grid, with: .color(.white)) }
            }

        case .blimp:
            let bl = min(W * 0.62, H * 1.05) * k, bh = bl * 0.3
            let cx = a.x + (1 - arrive) * (W * 0.5 + bl) - gone * (W * 0.5 + bl) + sin(st.age * 0.25) * W * 0.03
            let cy = a.y + sin(st.age * 0.8) * H * 0.008
            let body = NeonRGB(0.85, 0.86, 0.92).mixed(pal.bldg[st.index % 5], 0.2)
            var fins = Path()
            fins.addLines([CGPoint(x: cx + bl * 0.36, y: cy), CGPoint(x: cx + bl * 0.52, y: cy - bh * 0.62), CGPoint(x: cx + bl * 0.5, y: cy)]); fins.closeSubpath()
            fins.addLines([CGPoint(x: cx + bl * 0.36, y: cy), CGPoint(x: cx + bl * 0.52, y: cy + bh * 0.62), CGPoint(x: cx + bl * 0.5, y: cy)]); fins.closeSubpath()
            g.fill(fins, with: .color(pal.accent.color))
            g.fill(Path(roundedRect: CGRect(x: cx - bl * 0.08, y: cy + bh * 0.42, width: bl * 0.16, height: bh * 0.2), cornerRadius: bh * 0.06),
                   with: .color(body.mixed(NeonRGB(0, 0, 0), 0.4).color))
            g.fill(Path(ellipseIn: CGRect(x: cx - bl / 2, y: cy - bh / 2, width: bl, height: bh)), with: .linearGradient(
                Gradient(colors: [body.mixed(.white, 0.4).color, body.color, body.mixed(NeonRGB(0, 0, 0), 0.35).color]),
                startPoint: CGPoint(x: cx, y: cy - bh / 2), endPoint: CGPoint(x: cx, y: cy + bh / 2)))
            let panel = CGRect(x: cx - bl * 0.34, y: cy - bh * 0.27, width: bl * 0.64, height: bh * 0.54)
            g.fill(Path(roundedRect: panel, cornerRadius: bh * 0.08), with: .color(rgb(0.04, 0.03, 0.08)))
            // The screen scrolls: the new line rises in from below as the old one rises out of the top.
            g.drawLayer { l in
                l.clip(to: Path(roundedRect: panel, cornerRadius: bh * 0.08))
                l.blendMode = .plusLighter
                for (line, out) in st.lines {
                    let inK = line.id == -100 ? 1 : easeInOut((f.pos - line.start) / 0.5)
                    let y = panel.midY + (1 - inK) * panel.height - easeInOut(out * GothamScript.exit / 0.5) * panel.height
                    textBlock(&l, text(line), shown: shownWords(line, f), center: CGPoint(x: panel.midX, y: y),
                              maxW: panel.width * 0.92, maxH: panel.height * 0.8, font: font,
                              color: pal.windowAlt.mixed(.white, 0.3).color, shadow: nil, wrapAt: 26)
                }
            }

        case .banner:
            let bw = min(W * 0.6, H * 1.05) * k, bh = bw * 0.17
            let px = a.x + bw / 2 + H * 0.08 - (1 - arrive) * (W * 0.5 + bw + H * 0.2) + gone * (W * 0.6 + bw)
                + sin(st.age * 0.3) * W * 0.02
            let py = a.y + sin(st.age * 1.1) * H * 0.01
            let left = px - H * 0.08 - bw
            var rope = Path()
            rope.move(to: CGPoint(x: left + bw, y: py)); rope.addLine(to: CGPoint(x: px - H * 0.03, y: py))
            g.stroke(rope, with: .color(.white.opacity(0.7)), lineWidth: 1)
            var flag = Path()
            let steps = 24
            func wave(_ u: Double) -> Double { sin(u * 9 - f.t * 6) * bh * 0.08 * (1 - u * 0.6) }
            for i in 0...steps {
                let u = Double(i) / Double(steps)
                let p = CGPoint(x: left + bw * u, y: py - bh / 2 + wave(1 - u))
                if i == 0 { flag.move(to: p) } else { flag.addLine(to: p) }
            }
            for i in stride(from: steps, through: 0, by: -1) {
                let u = Double(i) / Double(steps)
                flag.addLine(to: CGPoint(x: left + bw * u, y: py + bh / 2 + wave(1 - u)))
            }
            flag.closeSubpath()
            g.fill(flag, with: .color(rgb(1, 0.98, 0.92)))
            g.stroke(flag, with: .color(pal.accent.color), lineWidth: H * 0.004)
            for (line, out) in st.lines {
                var u = g
                u.opacity = lineAlpha(line, out: out, f)
                textBlock(&u, text(line), shown: shownWords(line, f), center: CGPoint(x: left + bw / 2, y: py), maxW: bw * 0.92,
                          maxH: bh * 0.75, font: font, color: pal.accent.mixed(NeonRGB(0.1, 0.05, 0.2), 0.45).color, shadow: nil, wrapAt: 34)
            }
            plane(&g, CGPoint(x: px, y: py), H: H, color: pal.accent, t: f.t)

        case .skywriting:
            for (line, out) in st.lines {
                let age = line.id == -100 ? 100 : f.pos - line.start
                let fade = 1 - out
                let spread = 1 + out * 3
                let c = CGPoint(x: a.x + out * W * 0.04, y: a.y - out * H * 0.06)
                let maxW = min(W * 0.84, H * 1.5) * k, maxH = H * 0.24 * k
                let words = shownWords(line, f)
                var puff = g
                puff.opacity = 0.22 * fade
                for i in 0..<8 {
                    let ang = Double(i) / 8 * 2 * .pi
                    let d = H * 0.006 * spread
                    textBlock(&puff, text(line), shown: words, center: CGPoint(x: c.x + cos(ang) * d, y: c.y + sin(ang) * d),
                              maxW: maxW, maxH: maxH, font: font, color: .white, shadow: nil)
                }
                var core = g
                core.opacity = 0.9 * fade
                textBlock(&core, text(line), shown: words, center: c, maxW: maxW, maxH: maxH, font: font, color: .white, shadow: nil)
                if out == 0, age < line.reveal + 0.6 {
                    let px = c.x - maxW / 2 + maxW * min(1, age / max(0.1, line.reveal))
                    plane(&g, CGPoint(x: px + H * 0.03, y: c.y - H * 0.05), H: H * 0.7, color: pal.accent, t: f.t)
                }
            }

        case .caption:
            for (line, out) in st.lines {
                let age = line.id == -100 ? 100 : f.pos - line.start
                let fade = (1 - out) * smoothstep(age / 0.3)
                guard fade > 0 else { continue }
                var u = g
                u.opacity = fade
                let cw = min(W * 0.8, H * 1.4) * k, ch = H * 0.11 * k
                let rect = CGRect(x: W / 2 - cw / 2, y: H * 0.8 - ch / 2, width: cw, height: ch)
                u.fill(Path(roundedRect: rect, cornerRadius: ch / 2), with: .color(pal.sign.color(0.75)))
                textBlock(&u, text(line), shown: shownWords(line, f), center: CGPoint(x: rect.midX, y: rect.midY),
                          maxW: cw * 0.9, maxH: ch * 0.7, font: font, color: .white, shadow: nil)
            }
        }
    }

    private static func billboard(_ g: inout GraphicsContext, _ line: GothamLine, _ text: String, x: Double,
                                  bw: Double, bh: Double, tint: NeonRGB, _ f: FeverFrame) {
        let H = f.size.height
        let pal = f.pal
        let rect = CGRect(x: x - bw / 2, y: H * 0.64 - bh, width: bw, height: bh)
        guard rect.maxX > -H * 0.1, rect.minX < f.size.width + H * 0.1 else { return }
        for px in [x - bw * 0.3, x + bw * 0.3] {
            g.fill(Path(CGRect(x: px - H * 0.006, y: rect.maxY, width: H * 0.012, height: H)), with: .color(pal.sign.mixed(.white, 0.15).color))
        }
        g.fill(Path(roundedRect: rect.insetBy(dx: -H * 0.012, dy: -H * 0.012), cornerRadius: H * 0.02), with: .color(pal.sign.color))
        g.fill(Path(roundedRect: rect, cornerRadius: H * 0.012), with: .linearGradient(
            Gradient(colors: [tint.mixed(.white, 0.35).color, tint.mixed(pal.accent, 0.3).color]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        // Chasing bulbs round the edge.
        var on = Path(), off = Path()
        let n = 26
        for i in 0..<n {
            let u = Double(i) / Double(n)
            let p = perimeter(rect.insetBy(dx: -H * 0.006, dy: -H * 0.006), u)
            let d = H * 0.0045
            let r = CGRect(x: p.x - d, y: p.y - d, width: d * 2, height: d * 2)
            if (i + Int(f.t * 10)) % 3 == 0 { on.addEllipse(in: r) } else { off.addEllipse(in: r) }
        }
        g.fill(off, with: .color(pal.window.color(0.35)))
        g.fill(on, with: .color(pal.window.mixed(.white, 0.5).color))
        textBlock(&g, text, shown: shownWords(line, f), center: CGPoint(x: rect.midX, y: rect.midY), maxW: bw * 0.88, maxH: bh * 0.78,
                  font: f.s.font, color: .white, shadow: tint.mixed(NeonRGB(0, 0, 0), 0.55).color(0.8))
    }

    // MARK: Weather (screen space, over the scene)

    private static func drawWeather(_ g: inout GraphicsContext, _ f: FeverFrame, _ w: FeverWeather, _ amt: Double) {
        let W = f.size.width, H = f.size.height
        func rnd(_ i: Int, _ salt: Double) -> Double {
            let v = sin(Double(i) * 12.9898 + salt * 78.233) * 43758.5453
            return v - floor(v)
        }
        switch w {
        case .clear:
            return
        case .rain, .storm:
            let n = Int((w == .storm ? 200 : 120) + 220 * amt)
            var drops = Path()
            let len = H * 0.04, slant = 0.22
            for i in 0..<n {
                let v = H * (1.5 + rnd(i, 2) * 0.9)
                let span = H * 1.2
                let y = (rnd(i, 1) * span + f.t * v).truncatingRemainder(dividingBy: span) - H * 0.1
                let x = (rnd(i, 3) * W * 1.3 + y * slant).truncatingRemainder(dividingBy: W * 1.3) - W * 0.15
                drops.move(to: CGPoint(x: x, y: y))
                drops.addLine(to: CGPoint(x: x - len * slant, y: y - len))
            }
            g.stroke(drops, with: .color(.white.opacity(0.22 + 0.18 * amt)), lineWidth: max(1, H * 0.0018))
            if w == .storm {
                // A flash every few seconds, sometimes a double, with a bolt down to the skyline.
                let slot = floor(f.t / 5.5)
                let r = rnd(Int(slot), 9)
                let ft = f.t - slot * 5.5 - r * 3
                if r < 0.4 + 0.4 * amt, ft > 0, ft < 0.6 {
                    let flash = pow(1 - ft / 0.6, 2) * (ft < 0.08 || (ft > 0.16 && ft < 0.24) ? 1 : 0.45)
                    g.blendMode = .plusLighter
                    g.fill(Path(CGRect(origin: .zero, size: f.size)), with: .color(.white.opacity(0.35 * flash)))
                    if ft < 0.3 {
                        var bolt = Path()
                        var p = CGPoint(x: W * (0.15 + 0.7 * rnd(Int(slot), 4)), y: 0)
                        bolt.move(to: p)
                        for j in 0..<9 {
                            p = CGPoint(x: p.x + (rnd(Int(slot) * 10 + j, 5) - 0.5) * H * 0.09, y: p.y + H * 0.055)
                            bolt.addLine(to: p)
                        }
                        g.stroke(bolt, with: .color(.white.opacity(0.9 * flash)), lineWidth: max(1.5, H * 0.004))
                        g.stroke(bolt, with: .color(NeonRGB(0.7, 0.75, 1).color(0.35 * flash)), lineWidth: H * 0.018)
                    }
                    g.blendMode = .normal
                }
            }
        case .snow:
            let n = Int(90 + 200 * amt)
            var flakes = Path()
            for i in 0..<n {
                let z = rnd(i, 7)
                let span = H * 1.1
                let y = (rnd(i, 1) * span + f.t * H * (0.05 + 0.08 * z)).truncatingRemainder(dividingBy: span) - H * 0.05
                let x = (rnd(i, 3) * W * 1.2 + sin(f.t * (0.6 + z) + Double(i)) * H * 0.02 - f.camX * H * 0.3 * z)
                    .truncatingRemainder(dividingBy: W * 1.2)
                let xx = (x < 0 ? x + W * 1.2 : x) - W * 0.1
                let d = H * (0.0025 + 0.005 * z)
                flakes.addEllipse(in: CGRect(x: xx - d, y: y - d, width: d * 2, height: d * 2))
            }
            g.fill(flakes, with: .color(.white.opacity(0.85)))
        case .fog:
            g.fill(Path(CGRect(origin: .zero, size: f.size)), with: .linearGradient(
                Gradient(stops: [.init(color: f.pal.haze.mixed(.white, 0.3).color(0.15 * amt), location: 0),
                                 .init(color: f.pal.haze.mixed(.white, 0.35).color(0.85 * amt), location: 0.6),
                                 .init(color: f.pal.haze.mixed(.white, 0.2).color(0.6 * amt), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
        }
    }

    private static func shownWords(_ line: GothamLine, _ f: FeverFrame) -> Int {
        let n = line.text.split(separator: " ").count
        guard line.id != -100 else { return n }
        let frac = (f.pos - line.start) / max(0.01, line.reveal)
        return max(1, min(n, Int(ceil(frac * Double(n)))))
    }

    private static func springIn(_ x: Double) -> Double {
        guard x < 1 else { return 1 }
        let t = max(0, x)
        return 1 - exp(-6 * t) * cos(t * 9)
    }

    private static func perimeter(_ r: CGRect, _ u: Double) -> CGPoint {
        let total = 2 * (r.width + r.height)
        var d = u * total
        if d < r.width { return CGPoint(x: r.minX + d, y: r.minY) }
        d -= r.width
        if d < r.height { return CGPoint(x: r.maxX, y: r.minY + d) }
        d -= r.height
        if d < r.width { return CGPoint(x: r.maxX - d, y: r.maxY) }
        d -= r.width
        return CGPoint(x: r.minX, y: r.maxY - d)
    }

    private static func plane(_ g: inout GraphicsContext, _ p: CGPoint, H: CGFloat, color: NeonRGB, t: Double) {
        var u = g
        u.translateBy(x: p.x, y: p.y)
        let s = H * 0.05
        u.fill(Path(roundedRect: CGRect(x: -s, y: -s * 0.18, width: s * 1.9, height: s * 0.36), cornerRadius: s * 0.18), with: .color(color.color))
        var wing = Path()
        wing.addLines([CGPoint(x: -s * 0.1, y: 0), CGPoint(x: -s * 0.45, y: s * 0.5), CGPoint(x: s * 0.15, y: s * 0.5), CGPoint(x: s * 0.35, y: 0)])
        wing.closeSubpath()
        wing.addLines([CGPoint(x: -s * 0.95, y: 0), CGPoint(x: -s * 1.05, y: -s * 0.45), CGPoint(x: -s * 0.75, y: -s * 0.1)])
        wing.closeSubpath()
        u.fill(wing, with: .color(color.mixed(NeonRGB(0, 0, 0), 0.3).color))
        u.fill(Path(ellipseIn: CGRect(x: s * 0.2, y: -s * 0.3, width: s * 0.35, height: s * 0.25)), with: .color(rgb(0.7, 0.9, 1)))
        let blade = abs(sin(t * 40)) * s * 0.4
        u.fill(Path(ellipseIn: CGRect(x: s * 0.88, y: -blade, width: s * 0.08, height: blade * 2)), with: .color(.white.opacity(0.7)))
    }

    /// Draws `text` centred on `center`, scaled to fit, with only its first `shown` words visible
    /// (laid out as if all were there, so the words don't shift as they appear). Long lines take two rows.
    static func textBlock(_ g: inout GraphicsContext, _ text: String, shown: Int, center: CGPoint, maxW: CGFloat, maxH: CGFloat,
                          font: FeverFont, color: Color, shadow: Color?, wrapAt: Int = 18) {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty, maxW > 1, maxH > 1 else { return }
        var rows: [[String]] = [words]
        if words.count >= 3, text.count > wrapAt {
            var best = 1, bestDiff = Int.max
            for i in 1..<words.count {
                let d = abs(words[..<i].joined(separator: " ").count - words[i...].joined(separator: " ").count)
                if d < bestDiff { bestDiff = d; best = i }
            }
            rows = [Array(words[..<best]), Array(words[best...])]
        }
        let base: CGFloat = 100
        func resolve(_ s: String, _ c: Color) -> GraphicsContext.ResolvedText {
            g.resolve(Text(s).font(font.font(base)).foregroundColor(c))
        }
        let big = CGSize(width: 100_000, height: 100_000)
        let fulls = rows.map { resolve($0.joined(separator: " "), color) }
        let sizes = fulls.map { $0.measure(in: big) }
        let widest = sizes.map(\.width).max() ?? 1
        let rowH = (sizes.map(\.height).max() ?? base) * 0.92
        let scale = min(maxW / max(1, widest), maxH / max(1, rowH * Double(rows.count)))
        var u = g
        u.translateBy(x: center.x, y: center.y)
        u.scaleBy(x: scale, y: scale)
        var before = 0
        for (r, row) in rows.enumerated() {
            let visible = min(row.count, max(0, shown - before))
            before += row.count
            guard visible > 0 else { continue }
            let y = (Double(r) - Double(rows.count - 1) / 2) * rowH
            let x = -sizes[r].width / 2
            let prefix = row[..<visible].joined(separator: " ")
            if let shadow {
                u.draw(resolve(prefix, shadow), at: CGPoint(x: x + 4, y: y + 5), anchor: .leading)
            }
            u.draw(visible == row.count ? fulls[r] : resolve(prefix, color), at: CGPoint(x: x, y: y), anchor: .leading)
        }
    }
}

private func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
    Color(.sRGB, red: r, green: g, blue: b, opacity: max(0, min(1, a)))
}
