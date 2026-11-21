import SwiftUI

// MARK: - Words in the scene
//
// Balloons from the singing silhouette (Comic's own), deco title cards, neon signage and noir
// typewriter captions. Any look can use any placement; each draws it in its own style.

enum MegaWords {
    enum Mode { case balloon, card, sign, typewriter }

    static func mode(_ kit: MegaKit) -> Mode {
        switch kit.f.s.placement {
        case .balloons: return kit.look == .noir ? .typewriter : .balloon
        case .cards: return .card
        case .signage: return .sign
        case .auto:
            switch kit.look {
            case .comic: return .balloon
            case .deco: return .card
            case .neon: return .sign
            case .noir: return .typewriter
            }
        }
    }

    /// The look's typeface at a size.
    static func font(_ look: MegaLook, heavy: Bool) -> (CGFloat) -> Font {
        switch look {
        case .deco: { .custom(heavy ? "Futura-CondensedExtraBold" : "Futura-Medium", size: $0) }
        case .noir: { .custom(heavy ? "AmericanTypewriter-Bold" : "AmericanTypewriter", size: $0) }
        case .comic: { .custom("ChalkboardSE-Bold", size: $0) }
        case .neon: { .custom(heavy ? "Futura-Bold" : "Futura-Medium", size: $0) }
        }
    }

    static func baseSize(_ kit: MegaKit) -> CGFloat {
        let f = kit.f
        return max(13, min(f.size.width * 0.75, f.size.height) * CGFloat(0.042 + 0.04 * f.s[.textSize]))
    }

    static func draw(_ g: inout GraphicsContext, _ kit: MegaKit, heads: [Int: CGPoint]) {
        let f = kit.f
        if kit.look == .comic || mode(kit) == .balloon { headerBox(&g, kit) }
        if let card = f.card, card.alpha > 0.01 {
            titleCard(&g, kit, card)
        }
        guard let l = f.lyric else { return }
        let age = f.pos - l.start
        let out = min(1, max(0, (l.end - f.pos) / 0.25))
        let a = min(1, age / 0.18) * out
        guard a > 0.01 else { return }
        let text = kit.look == .comic || kit.look == .deco ? l.text.uppercased() : l.text
        switch mode(kit) {
        case .balloon: balloon(&g, kit, text, l, heads: heads, alpha: a)
        case .card: card(&g, kit, text, alpha: a, rise: age)
        case .sign: sign(&g, kit, text, alpha: out, age: age)
        case .typewriter: typewriter(&g, kit, l, alpha: out)
        }
        if let next = l.next, !next.isEmpty {
            let fs = baseSize(kit) * 0.5
            let c: Color = kit.look == .comic ? MegaKit.ink.color(0.7) : .white.opacity(0.55)
            let t = g.resolve(Text(kit.look == .comic || kit.look == .deco ? next.uppercased() : next).font(font(kit.look, heavy: false)(fs)).foregroundColor(c))
            let y = f.size.height - fs * 3.2
            if kit.look == .comic {
                let m = t.measure(in: CGSize(width: f.size.width * 0.8, height: 200))
                let box = CGRect(x: f.size.width / 2 - m.width / 2 - 8, y: y - m.height / 2 - 4, width: m.width + 16, height: m.height + 8)
                g.fill(Path(box), with: .color(.white.opacity(0.85)))
            }
            g.draw(t, at: CGPoint(x: f.size.width / 2, y: y))
        }
    }

    // MARK: Balloons

    static func balloon(_ g: inout GraphicsContext, _ kit: MegaKit, _ text: String, _ l: MegaLyric,
                        heads: [Int: CGPoint], alpha: Double) {
        let f = kit.f
        let w = f.size.width, h = f.size.height
        let fs = baseSize(kit) * 0.9
        let t = g.resolve(Text(text).font(font(kit.look, heavy: true)(fs)).foregroundColor(textColor(kit)))
        let m = t.measure(in: CGSize(width: w * 0.34, height: h))
        // Which head speaks: the line's singer slot (duets), or everyone.
        let slots = heads.keys.sorted()
        var anchors: [CGPoint] = []
        if !slots.isEmpty {
            if l.singer == Cast.everyone, f.singers > 1 {
                anchors = slots.prefix(min(slots.count, max(2, f.singers))).compactMap { heads[$0] }
            } else {
                let s = f.singers > 1 ? max(0, l.singer) % slots.count : 0
                anchors = [heads[slots[s]]].compactMap { $0 }
            }
        }
        let anchor = anchors.first ?? CGPoint(x: w / 2, y: h * 1.1)
        let padX = fs * 1.1, padY = fs * 0.75
        var size = CGSize(width: m.width + padX * 2, height: m.height + padY * 2)
        if kit.look == .comic { size.width *= 1.12; size.height *= 1.2 }
        // Above the head if there's room, else beside it; never over the singer.
        let margin: CGFloat = 16
        let topMin = margin + (kit.look == .comic ? fs * 1.4 : 0)
        let guardBox = anchors.reduce(CGRect.null) { $0.union(CGRect(x: $1.x - fs * 1.3, y: $1.y - fs * 1.5, width: fs * 2.6, height: fs * 4.5)) }
        func clamp(_ c: CGPoint) -> CGRect {
            let x = min(max(c.x, margin + size.width / 2), w - margin - size.width / 2)
            let y = min(max(c.y, topMin + size.height / 2), h * 0.74 - size.height / 2)
            return CGRect(x: x - size.width / 2, y: y - size.height / 2, width: size.width, height: size.height)
        }
        let ax = anchors.isEmpty ? anchor.x : anchors.map(\.x).reduce(0, +) / CGFloat(anchors.count)
        let ay = anchors.map(\.y).min() ?? anchor.y
        let side: CGFloat = ax > w / 2 ? -1 : 1
        let candidates = [
            CGPoint(x: ax + side * size.width * 0.2, y: ay - size.height * 0.5 - fs * 3),
            CGPoint(x: ax + side * (size.width / 2 + fs * 2.4), y: ay - size.height * 0.45),
            CGPoint(x: ax - side * (size.width / 2 + fs * 2.4), y: ay - size.height * 0.45),
        ]
        func overlap(_ r: CGRect) -> CGFloat {
            let i = r.intersection(guardBox)
            return i.isNull ? 0 : i.width * i.height
        }
        let options = candidates.map(clamp)
        let rect = anchors.isEmpty ? options[0] : (options.first { overlap($0) == 0 } ?? options.min { overlap($0) < overlap($1) }!)
        let cx = rect.midX, cy = rect.midY
        // Pop in with a little overshoot.
        let age = f.pos - l.start
        let pop = age < 0.16 ? 0.6 + age / 0.16 * 0.5 : (age < 0.26 ? 1.1 - (age - 0.16) / 0.1 * 0.1 : 1)

        var body = kit.look == .comic ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: min(rect.height / 2, fs * 1.1))
        for a in anchors where !rect.insetBy(dx: 4, dy: 4).contains(a) {
            // Tail from the balloon's edge toward the mouth, stopping short.
            let dx = a.x - cx, dy = a.y - cy
            let len = max(1, hypot(dx, dy))
            let ux = dx / len, uy = dy / len
            let base = CGPoint(x: cx + ux * size.width * 0.38, y: cy + uy * size.height * 0.38)
            let tip = CGPoint(x: base.x + (a.x - base.x) * 0.72, y: base.y + (a.y - base.y) * 0.72)
            let px = -uy * fs * 0.6, py = ux * fs * 0.6
            let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
            var tail = Path()
            tail.move(to: CGPoint(x: base.x + px, y: base.y + py))
            tail.addQuadCurve(to: tip, control: CGPoint(x: mid.x + px * 0.3, y: mid.y + py * 0.3))
            tail.addQuadCurve(to: CGPoint(x: base.x - px, y: base.y - py), control: CGPoint(x: mid.x - px * 0.6, y: mid.y - py * 0.6))
            tail.closeSubpath()
            body = body.union(tail)
        }
        var gg = g
        gg.opacity = alpha
        gg.translateBy(x: cx, y: cy)
        gg.scaleBy(x: pop, y: pop)
        gg.translateBy(x: -cx, y: -cy)
        switch kit.look {
        case .comic:
            gg.fill(body.offsetBy(dx: 4, dy: 4), with: .color(MegaKit.ink.color(0.35)))
            gg.fill(body, with: .color(.white))
            gg.stroke(body, with: .color(MegaKit.ink.color), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        case .deco:
            gg.fill(body, with: .color(NeonRGB(0.97, 0.93, 0.82).color))
            gg.stroke(body, with: .color(MegaKit.gold.color), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        case .noir:
            gg.fill(body, with: .color(.white))
            gg.stroke(body, with: .color(.black), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        case .neon:
            gg.fill(body, with: .color(Color(white: 0.02).opacity(0.85)))
            var k = kit
            k.u = 1
            MegaLooks.tube(&gg, body, kit.pal.pop, k, width: 2, bright: 1)
        }
        gg.draw(t, in: CGRect(x: cx - m.width / 2, y: cy - m.height / 2, width: m.width, height: m.height))
    }

    static func textColor(_ kit: MegaKit) -> Color {
        switch kit.look {
        case .comic: MegaKit.ink.color
        case .deco: kit.pal.base.mixed(.black, 0.3).color
        case .noir: .black
        case .neon: kit.pal.warm.mixed(.white, 0.6).color
        }
    }

    // MARK: Comic caption boxes

    /// Section headers ("CHORUS", "VERSE 2") in a yellow caption box, plus "Meanwhile…" at cuts.
    static func headerBox(_ g: inout GraphicsContext, _ kit: MegaKit) {
        let f = kit.f
        var lines: [String] = []
        let shotAge = f.pos - f.shot.start
        if f.shot.start > -100, shotAge < 4.5, f.shot.index > 0 { lines.append(meanwhile(f.shot.scene.location)) }
        if let h = f.header, h.age < 5, h.age > -0.2 { lines.append(h.text) }
        guard !lines.isEmpty else { return }
        let fs = max(11, baseSize(kit) * 0.48)
        let text = lines.joined(separator: " — ")
        let fg: Color, bg: Color
        switch kit.look {
        case .comic: fg = MegaKit.ink.color; bg = NeonRGB(1, 0.86, 0.3).color
        case .deco: fg = MegaKit.gold.color; bg = kit.pal.base.color
        case .noir: fg = .black; bg = Color(white: 0.92)
        case .neon: fg = kit.pal.pop.mixed(.white, 0.5).color; bg = Color(white: 0.03)
        }
        let t = g.resolve(Text(kit.look == .comic ? text.uppercased() : text).font(font(kit.look, heavy: true)(fs)).foregroundColor(fg))
        let m = t.measure(in: CGSize(width: f.size.width * 0.6, height: 300))
        let box = CGRect(x: 18, y: 18, width: m.width + fs * 1.2, height: m.height + fs * 0.8)
        g.fill(Path(box).offsetBy(dx: 3, dy: 3), with: .color(.black.opacity(0.4)))
        g.fill(Path(box), with: .color(bg))
        g.stroke(Path(box), with: .color(kit.look == .comic ? MegaKit.ink.color : fg.opacity(0.7)), lineWidth: 2)
        g.draw(t, in: CGRect(x: box.minX + fs * 0.6, y: box.minY + fs * 0.4, width: m.width, height: m.height))
    }

    static func meanwhile(_ l: MegaLocation) -> String {
        switch l {
        case .lounge: "Meanwhile, in the lounge…"
        case .stage: "Meanwhile, at the club…"
        case .street: "Meanwhile, out in the rain…"
        case .rooftop: "Meanwhile, up on the roof…"
        case .billiards: "Meanwhile, in the back room…"
        case .marquee: "Meanwhile, under the marquee…"
        case .records: "Meanwhile, down at the record shop…"
        default: "Meanwhile…"
        }
    }

    // MARK: Title cards

    static func card(_ g: inout GraphicsContext, _ kit: MegaKit, _ text: String, alpha: Double, rise: Double) {
        let f = kit.f
        let fs = baseSize(kit)
        let w = f.size.width, h = f.size.height
        let fg: Color
        switch kit.look {
        case .deco: fg = MegaKit.gold.mixed(.white, 0.15).color
        case .noir: fg = .white
        case .comic: fg = MegaKit.ink.color
        case .neon: fg = kit.pal.warm.mixed(.white, 0.6).color
        }
        let t = g.resolve(Text(text).font(kit.look == .noir ? .custom("Baskerville-SemiBoldItalic", size: fs * 1.05) : font(kit.look, heavy: kit.look != .deco)(fs))
                            .foregroundColor(fg))
        let m = t.measure(in: CGSize(width: w * 0.66, height: h))
        let pad = fs * 1.1
        let size = CGSize(width: max(m.width + pad * 2.4, w * 0.3), height: m.height + pad * 1.6)
        let y = h * 0.8 - size.height / 2 + CGFloat(max(0, 0.3 - rise)) * 30
        let rect = CGRect(x: w / 2 - size.width / 2, y: min(y, h - size.height - 30), width: size.width, height: size.height)
        var gg = g
        gg.opacity = alpha
        frameCard(&gg, kit, rect)
        gg.draw(t, in: CGRect(x: rect.midX - m.width / 2, y: rect.midY - m.height / 2, width: m.width, height: m.height))
    }

    /// The card's box in the look: deco double gold rule and stepped corners, a silent-film
    /// intertitle, a comic caption box, or a neon-tube frame.
    static func frameCard(_ g: inout GraphicsContext, _ kit: MegaKit, _ rect: CGRect) {
        switch kit.look {
        case .deco:
            g.fill(Path(rect), with: .color(kit.pal.base.mixed(.black, 0.35).color(0.94)))
            g.stroke(Path(rect.insetBy(dx: 5, dy: 5)), with: .color(MegaKit.gold.color), lineWidth: 2.5)
            g.stroke(Path(rect.insetBy(dx: 11, dy: 11)), with: .color(MegaKit.gold.color(0.6)), lineWidth: 1)
            let s: CGFloat = 14
            for c in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX - s, y: rect.minY),
                      CGPoint(x: rect.minX, y: rect.maxY - s), CGPoint(x: rect.maxX - s, y: rect.maxY - s)] {
                g.fill(Path(CGRect(x: c.x, y: c.y, width: s, height: s)), with: .color(MegaKit.gold.color))
            }
            // A small fan crowning the card.
            let o = CGPoint(x: rect.midX, y: rect.minY)
            var fan = Path()
            for k in 0..<9 where k % 2 == 0 {
                let a0 = Double.pi + Double.pi * Double(k) / 9, a1 = Double.pi + Double.pi * Double(k + 1) / 9
                fan.move(to: o)
                fan.addLine(to: CGPoint(x: o.x + cos(a0) * 34, y: o.y + sin(a0) * 34))
                fan.addLine(to: CGPoint(x: o.x + cos(a1) * 34, y: o.y + sin(a1) * 34))
                fan.closeSubpath()
            }
            g.fill(fan, with: .color(MegaKit.gold.color))
        case .noir:
            g.fill(Path(rect), with: .color(.black.opacity(0.94)))
            g.stroke(Path(rect.insetBy(dx: 6, dy: 6)), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
            g.stroke(Path(rect.insetBy(dx: 10, dy: 10)), with: .color(.white.opacity(0.4)), lineWidth: 0.8)
        case .comic:
            g.fill(Path(rect).offsetBy(dx: 5, dy: 5), with: .color(MegaKit.ink.color(0.5)))
            g.fill(Path(rect), with: .color(NeonRGB(1, 0.88, 0.32).color))
            g.stroke(Path(rect), with: .color(MegaKit.ink.color), lineWidth: 3)
        case .neon:
            let p = Path(roundedRect: rect, cornerRadius: 14)
            g.fill(p, with: .color(Color(white: 0.02).opacity(0.85)))
            var k = kit
            k.u = 1
            MegaLooks.tube(&g, p, kit.pal.pop, k, width: 2.2, bright: MegaLooks.neonBright(kit, 300))
        }
    }

    /// Song and artist at the start (and status messages), in the look.
    static func titleCard(_ g: inout GraphicsContext, _ kit: MegaKit, _ c: MegaCard) {
        let f = kit.f
        let w = f.size.width, h = f.size.height
        let fs = baseSize(kit) * 1.35
        let fg: Color = switch kit.look {
        case .deco: MegaKit.gold.mixed(.white, 0.15).color
        case .noir: .white
        case .comic: MegaKit.ink.color
        case .neon: kit.pal.pop.mixed(.white, 0.5).color
        }
        let titleFont: Font = kit.look == .noir ? .custom("Baskerville-SemiBoldItalic", size: fs) : font(kit.look, heavy: true)(fs)
        let t = g.resolve(Text(kit.look == .noir ? c.title : c.title.uppercased()).font(titleFont).foregroundColor(fg))
        let s = g.resolve(Text(c.sub.isEmpty ? "" : (kit.look == .deco || kit.look == .comic ? c.sub.uppercased() : c.sub))
            .font(font(kit.look, heavy: false)(fs * 0.45)).foregroundColor(fg.opacity(0.8)))
        let mt = t.measure(in: CGSize(width: w * 0.7, height: h))
        let ms = s.measure(in: CGSize(width: w * 0.7, height: h))
        let pad = fs * 0.8
        let size = CGSize(width: max(mt.width, ms.width) + pad * 2.6, height: mt.height + (c.sub.isEmpty ? 0 : ms.height + fs * 0.3) + pad * 2)
        let rect = CGRect(x: w / 2 - size.width / 2, y: h * 0.42 - size.height / 2, width: size.width, height: size.height)
        var gg = g
        gg.opacity = c.alpha
        frameCard(&gg, kit, rect)
        gg.draw(t, in: CGRect(x: rect.midX - mt.width / 2, y: rect.minY + pad, width: mt.width, height: mt.height))
        if !c.sub.isEmpty {
            gg.draw(s, in: CGRect(x: rect.midX - ms.width / 2, y: rect.minY + pad + mt.height + fs * 0.3, width: ms.width, height: ms.height))
        }
    }

    // MARK: Signage

    /// The words as a sign in the scene's sign spot: neon tubes in Neon (from `NeonGlyphs`),
    /// a painted or gilded board in the other looks.
    static func sign(_ g: inout GraphicsContext, _ kit: MegaKit, _ text: String, alpha: Double, age: Double) {
        let f = kit.f
        let T = MegaRenderer.camera(kit, f.shot)
        var r = f.shot.scene.signRect.applying(T)
        let w = f.size.width, h = f.size.height
        // Keep it on screen and readable.
        r.size.width = min(max(r.width, w * 0.7), w * 0.9)
        r.size.height = min(max(r.height, h * 0.26), h * 0.34)
        r.origin.x = min(max(r.minX, w * 0.05), w * 0.95 - r.width)
        r.origin.y = min(max(r.minY, 14), h * 0.45)
        if kit.look == .neon {
            let face = GlyphFace(name: "Futura-Medium", space: 0.3, lineHeight: 1.1)
            let geo = NeonGlyphs.sign([text], face: face, fontSize: baseSize(kit) * 1.6, box: CGSize(width: r.width * 0.92, height: r.height * 0.86))
            var gg = g
            gg.translateBy(x: r.midX, y: r.midY)
            var k = kit
            k.u = 1
            let tube = max(1.6, geo.tube(0.4))
            // Raceway behind the letters.
            let b = geo.bounds.insetBy(dx: -tube * 4, dy: -tube * 3)
            gg.fill(Path(roundedRect: b, cornerRadius: tube * 2), with: .color(Color(white: 0.02).opacity(0.6 * alpha)))
            let n = geo.letters.count
            for (i, letter) in geo.letters.enumerated() {
                // Letters ignite left to right.
                let on = age * 2.5 * Double(max(1, n)) / 2 - Double(i)
                guard on > 0 else { continue }
                var b = min(1, on) * alpha * MegaLooks.neonBright(kit, 400 + i, stutter: 0.3)
                if on < 1.4 { var q = Seeded(UInt64(i * 13 + Int(f.t * 30))); if q.next() < 0.4 { b *= 0.3 } }
                let c = i % 2 == 0 || f.singers < 2 ? kit.pal.pop : kit.pal.accent
                MegaLooks.tube(&gg, letter.path, c, k, width: tube, bright: b)
            }
            return
        }
        let fs = baseSize(kit) * 1.15
        let fg: Color, bg: Color
        switch kit.look {
        case .deco: fg = MegaKit.gold.mixed(.white, 0.2).color; bg = kit.pal.base.mixed(.black, 0.3).color
        case .noir: fg = Color(white: 0.95); bg = Color(white: 0.05)
        default: fg = NeonRGB(1, 0.9, 0.3).color; bg = NeonRGB(0.85, 0.12, 0.12).color
        }
        var t = g.resolve(Text(text).font(font(kit.look, heavy: true)(fs)).foregroundColor(fg))
        var m = t.measure(in: CGSize(width: r.width * 0.9, height: 2000))
        if m.height > r.height * 0.85 {
            t = g.resolve(Text(text).font(font(kit.look, heavy: true)(fs * 0.72)).foregroundColor(fg))
            m = t.measure(in: CGSize(width: r.width * 0.9, height: 2000))
        }
        let board = CGRect(x: r.midX - min(r.width, m.width + fs * 2) / 2, y: r.midY - (m.height + fs) / 2,
                           width: min(r.width, m.width + fs * 2), height: m.height + fs)
        var gg = g
        gg.opacity = alpha * min(1, age / 0.2)
        gg.fill(Path(board), with: .color(bg))
        switch kit.look {
        case .deco:
            gg.stroke(Path(board.insetBy(dx: 4, dy: 4)), with: .color(MegaKit.gold.color), lineWidth: 2)
        case .noir:
            // Marquee bulbs around the board.
            var bulbs = Path()
            let step: CGFloat = 16
            for x in stride(from: board.minX + 6, to: board.maxX - 4, by: step) {
                bulbs.addEllipse(in: CGRect(x: x - 2.5, y: board.minY + 3, width: 5, height: 5))
                bulbs.addEllipse(in: CGRect(x: x - 2.5, y: board.maxY - 8, width: 5, height: 5))
            }
            gg.fill(bulbs, with: .color(.white.opacity(0.5 + 0.5 * f.beat)))
        default:
            gg.stroke(Path(board), with: .color(MegaKit.ink.color), lineWidth: 3)
        }
        gg.draw(t, in: CGRect(x: board.midX - m.width / 2, y: board.midY - m.height / 2, width: m.width, height: m.height))
    }

    // MARK: Typewriter captions

    /// Noir: the line typed out on a strip of paper, a letter at a time.
    static func typewriter(_ g: inout GraphicsContext, _ kit: MegaKit, _ l: MegaLyric, alpha: Double) {
        let f = kit.f
        let w = f.size.width, h = f.size.height
        let fs = baseSize(kit) * 0.82
        let chars = Array(l.text)
        let per = min(0.055, max(0.02, (l.end - l.start) * 0.5 / Double(max(1, chars.count))))
        let n = min(chars.count, Int((f.pos - l.start) / per) + 1)
        let shown = String(chars.prefix(n))
        let caret = n < chars.count || Int(f.t * 2.5) % 2 == 0 ? "▌" : " "
        let fontT = Font.custom("AmericanTypewriter", size: fs)
        let full = g.resolve(Text(l.text + "▌").font(fontT))
        let m = full.measure(in: CGSize(width: w * 0.7, height: h))
        let t = g.resolve(Text(shown).font(fontT).foregroundColor(Color(white: 0.06)) + Text(caret).font(fontT).foregroundColor(Color(white: 0.06).opacity(0.7)))
        let pad = fs * 0.8
        let rect = CGRect(x: w / 2 - m.width / 2 - pad, y: h * 0.82 - m.height / 2 - pad * 0.7, width: m.width + pad * 2, height: m.height + pad * 1.4)
        var gg = g
        gg.opacity = alpha
        gg.translateBy(x: rect.midX, y: rect.midY)
        gg.rotate(by: .degrees(-0.8))
        gg.translateBy(x: -rect.midX, y: -rect.midY)
        gg.fill(Path(rect).offsetBy(dx: 3, dy: 4), with: .color(.black.opacity(0.5)))
        gg.fill(Path(rect), with: .color(NeonRGB(0.93, 0.91, 0.84).color))
        gg.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 3)), with: .color(.black.opacity(0.08)))
        gg.draw(t, in: CGRect(x: rect.minX + pad, y: rect.minY + pad * 0.7, width: m.width + 2, height: m.height + 2))
    }
}
