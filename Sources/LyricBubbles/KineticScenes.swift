import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Backgrounds

enum KineticScenes {
    static func draw(_ ctx: inout GraphicsContext, _ f: KineticFrame) {
        let rect = CGRect(origin: .zero, size: f.size)
        let motion = f.s[.bgMotion]
        switch f.s.background {
        case .album: album(&ctx, f, rect, motion)
        case .nebula: nebula(&ctx, f, rect, motion)
        case .particles: particles(&ctx, f, rect, motion)
        case .ocean: ocean(&ctx, f, rect, motion)
        }
        // Dim and a soft vignette so the words always read.
        ctx.fill(Path(rect), with: .color(.black.opacity(f.s[.dim] * 0.7)))
        let c = CGPoint(x: rect.midX, y: rect.midY)
        ctx.fill(Path(rect), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.45)]), center: c,
                                                   startRadius: min(rect.width, rect.height) * 0.35,
                                                   endRadius: hypot(rect.width, rect.height) * 0.62))
    }

    /// The album art, blurred and smeared sideways, drifting slowly.
    private static func album(_ ctx: inout GraphicsContext, _ f: KineticFrame, _ rect: CGRect, _ motion: Double) {
        guard let art = f.art else {
            let cols = (f.palette.isEmpty ? KineticColors.ocean.fixed : f.palette).map { $0.mixed(NeonRGB(0, 0, 0.1), 0.45).color }
            ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: cols + [cols[0]]), startPoint: .zero,
                                                       endPoint: CGPoint(x: rect.width, y: rect.height)))
            return
        }
        let t = f.t
        let aspect = CGFloat(art.width) / CGFloat(max(1, art.height))
        var w = rect.width, h = rect.width / aspect
        if h < rect.height { h = rect.height; w = h * aspect }
        let zoom = 1.25 + 0.1 * sin(t * 0.05) * motion + 0.04 * f.level * f.s[.pulse]
        w *= zoom; h *= zoom
        let dx = sin(t * 0.07) * rect.width * 0.08 * motion
        let dy = cos(t * 0.053) * rect.height * 0.06 * motion
        var c = ctx
        c.translateBy(x: rect.midX + dx, y: rect.midY + dy)
        c.rotate(by: .radians(sin(t * 0.031) * 0.06 * motion))
        c.draw(Image(decorative: art, scale: 1), in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }

    /// Purple clouds of gas, twinkling stars and the odd shooting star.
    private static func nebula(_ ctx: inout GraphicsContext, _ f: KineticFrame, _ rect: CGRect, _ motion: Double) {
        let t = f.t
        ctx.fill(Path(rect), with: .color(Color(red: 0.03, green: 0.02, blue: 0.11)))
        if let neb = f.tex?.nebula {
            let side = max(rect.width, rect.height) * 1.35
            for layer in 0..<2 {
                var c = ctx
                let L = Double(layer)
                c.opacity = layer == 0 ? 1 : 0.55
                c.blendMode = layer == 0 ? .normal : .plusLighter
                c.translateBy(x: rect.midX + sin(t * (0.02 + 0.015 * L) + L * 2) * rect.width * 0.08 * motion,
                              y: rect.midY + cos(t * 0.017 + L) * rect.height * 0.06 * motion)
                c.rotate(by: .radians(t * 0.004 * motion * (layer == 0 ? 1 : -1.6) + L * 2.1))
                let s = side * (1 + 0.25 * L)
                c.draw(Image(decorative: neb, scale: 1), in: CGRect(x: -s / 2, y: -s * 0.33, width: s, height: s * 0.66))
            }
        }
        // Stars in three brightness buckets.
        var buckets = [Path(), Path(), Path()]
        for st in KineticStars.points {
            let tw = 0.5 + 0.5 * sin(t * st.speed + st.phase)
            let x = st.x * rect.width, y = st.y * rect.height
            let r = st.size * (0.7 + 0.5 * tw)
            buckets[min(2, Int(tw * 3))].addRect(CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r))
        }
        for (i, p) in buckets.enumerated() { ctx.fill(p, with: .color(.white.opacity(0.3 + 0.3 * Double(i)))) }

        // Shooting stars: every few seconds a streak crosses from the top right.
        let period = 3.6 - 1.6 * motion
        let n = floor(t / period)
        var rng = Seeded(UInt64(abs(n)) &* 2654435761 &+ 7)
        let u = (t - n * period) / 0.55
        if u < 1, motion > 0 {
            let start = CGPoint(x: rect.width * (0.45 + 0.5 * rng.next()), y: rect.height * (0.05 + 0.4 * rng.next()))
            let dir = CGVector(dx: -0.86, dy: 0.5)
            let len = rect.width * 0.28
            let head = CGPoint(x: start.x + dir.dx * len * 1.6 * u, y: start.y + dir.dy * len * 1.6 * u)
            let tail = CGPoint(x: head.x - dir.dx * len, y: head.y - dir.dy * len)
            var p = Path(); p.move(to: tail); p.addLine(to: head)
            let hue = rng.next() < 0.5 ? Color(red: 0.4, green: 1, blue: 0.85) : Color(red: 0.85, green: 0.6, blue: 1)
            ctx.stroke(p, with: .linearGradient(Gradient(colors: [hue.opacity(0), hue.opacity(0.9 * sin(u * .pi))]),
                                                startPoint: tail, endPoint: head),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }

    /// A glowing mound of particles turning slowly, seen from above.
    private static func particles(_ ctx: inout GraphicsContext, _ f: KineticFrame, _ rect: CGRect, _ motion: Double) {
        let t = f.t
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(red: 0.01, green: 0.02, blue: 0.08),
                                                                     Color(red: 0.03, green: 0.07, blue: 0.2)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: rect.height)))
        let c = CGPoint(x: rect.midX, y: rect.height * 0.6)
        let R = min(rect.width * 0.42, rect.height * 0.7)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - R, y: c.y - R * 0.45, width: R * 2, height: R * 0.9)),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.3, green: 0.55, blue: 1).opacity(0.3), .clear]),
                                       center: c, startRadius: 0, endRadius: R))
        let a = t * 0.1 * (0.2 + motion)
        let ca = cos(a), sa = sin(a)
        let pitch = 0.5, cp = cos(pitch), sp = sin(pitch)
        let swell = 1 + 0.12 * f.level * f.s[.pulse] + 0.05 * f.beat * f.s[.pulse]
        let dot = max(1.1, min(rect.width, rect.height) / 360)
        var buckets = [Path(), Path(), Path()]
        for q in KineticMound.points {
            let x = q.x * ca - q.z * sa
            let z = q.x * sa + q.z * ca
            let y = q.y * swell * (1 + 0.06 * sin(t * 1.3 + q.phase) * motion)
            let y2 = y * cp - z * sp
            let z2 = y * sp + z * cp
            let k = 2.6 / (2.6 + z2)
            let px = c.x + x * R * k, py = c.y - y2 * R * k
            let s = dot * k * q.size
            let b = q.bright * (0.55 + 0.45 * k) * (0.75 + 0.25 * sin(t * 2 + q.phase * 3))
            buckets[min(2, max(0, Int(b * 3)))].addRect(CGRect(x: px - s / 2, y: py - s / 2, width: s, height: s))
        }
        let cols = [Color(red: 0.35, green: 0.55, blue: 0.95).opacity(0.45),
                    Color(red: 0.55, green: 0.8, blue: 1).opacity(0.7),
                    Color(red: 0.85, green: 0.95, blue: 1).opacity(0.95)]
        for (i, p) in buckets.enumerated() { ctx.fill(p, with: .color(cols[i])) }
    }

    /// Deep blue water, shafts of light and a school of fish circling.
    private static func ocean(_ ctx: inout GraphicsContext, _ f: KineticFrame, _ rect: CGRect, _ motion: Double) {
        let t = f.t
        let W = rect.width, H = rect.height
        ctx.fill(Path(rect), with: .linearGradient(Gradient(colors: [Color(red: 0.07, green: 0.32, blue: 0.6),
                                                                     Color(red: 0.02, green: 0.12, blue: 0.3),
                                                                     Color(red: 0.0, green: 0.03, blue: 0.1)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: H)))
        // Light shafts swaying from the surface.
        for i in 0..<6 {
            let d = Double(i)
            let x = W * (0.1 + 0.16 * d) + sin(t * 0.2 * motion + d * 1.7) * W * 0.04
            let spread = W * (0.05 + 0.02 * sin(d * 2.3))
            var p = Path()
            p.move(to: CGPoint(x: x - spread * 0.3, y: 0))
            p.addLine(to: CGPoint(x: x + spread * 0.3, y: 0))
            p.addLine(to: CGPoint(x: x + spread * 2.5 - W * 0.12, y: H))
            p.addLine(to: CGPoint(x: x - spread * 2.5 - W * 0.12, y: H))
            p.closeSubpath()
            let a = 0.05 + 0.04 * sin(t * 0.5 + d * 2)
            ctx.fill(p, with: .linearGradient(Gradient(colors: [.white.opacity(a), .clear]),
                                              startPoint: .zero, endPoint: CGPoint(x: 0, y: H * 0.85)))
        }
        // Surface ripples.
        var ripple = Path()
        for r in 0..<5 {
            let y0 = H * (0.015 + 0.022 * Double(r))
            ripple.move(to: CGPoint(x: 0, y: y0))
            for xi in stride(from: 0.0, through: Double(W), by: 12) {
                ripple.addLine(to: CGPoint(x: xi, y: y0 + sin(xi / 40 + t * (0.6 + 0.2 * Double(r)) * (0.3 + motion)) * 3))
            }
        }
        ctx.stroke(ripple, with: .color(.white.opacity(0.12)), lineWidth: 1)

        // The school: each fish rides its own tilted orbit around a wandering centre.
        let center = CGPoint(x: W * (0.5 + 0.12 * sin(t * 0.06)), y: H * (0.56 + 0.06 * sin(t * 0.09)))
        let unit = min(W, H) / 400
        let spin = 0.22 * (0.3 + motion) * (1 + 0.4 * f.level * f.s[.pulse])
        var near = Path(), far = Path()
        for fish in KineticSchool.fish {
            let th = fish.phase + t * spin * fish.speed
            let rx = W * 0.36 * fish.radius, ry = H * 0.13 * fish.radius
            let wob = sin(th * 2 + fish.phase) * H * 0.02
            let x = center.x + rx * cos(th)
            let y = center.y + ry * sin(th) + fish.lift * H * 0.14 + wob
            let depth = (sin(th) + 1) / 2              // 1 = nearest
            let hx = -rx * sin(th), hy = ry * cos(th)
            let ang = atan2(hy, hx)
            let len = unit * (4 + 6 * depth) * fish.size
            let fishPath = Path(ellipseIn: CGRect(x: -len / 2, y: -len * 0.14, width: len, height: len * 0.28))
            let xf = CGAffineTransform(translationX: x, y: y).rotated(by: ang)
            if depth > 0.5 { near.addPath(fishPath, transform: xf) } else { far.addPath(fishPath, transform: xf) }
        }
        ctx.fill(far, with: .color(Color(red: 0.6, green: 0.78, blue: 0.9).opacity(0.45)))
        ctx.fill(near, with: .color(Color(red: 0.88, green: 0.95, blue: 1).opacity(0.85)))
    }
}

// MARK: - Seeded point sets (built once)

enum KineticStars {
    struct Star { let x, y, size, speed, phase: Double }
    static let points: [Star] = {
        var r = Seeded(31)
        return (0..<220).map { _ in
            Star(x: r.next(), y: r.next(), size: 0.6 + 1.6 * pow(r.next(), 3), speed: 0.5 + 2 * r.next(), phase: r.next() * 6.28)
        }
    }()
}

enum KineticMound {
    struct Dot { let x, y, z, size, bright, phase: Double }
    static let points: [Dot] = {
        var r = Seeded(77)
        return (0..<1500).map { _ in
            let rad = sqrt(r.next())
            let a = r.next() * 6.283
            let h = 0.55 * pow(max(0, 1 - rad * rad), 0.8) + (r.next() - 0.5) * 0.06
            return Dot(x: rad * cos(a), y: h, z: rad * sin(a), size: 0.8 + 1.4 * r.next(),
                       bright: min(0.99, 0.3 + h * 0.9 + 0.3 * r.next()), phase: r.next() * 6.28)
        }
    }()
}

enum KineticSchool {
    struct Fish { let phase, speed, radius, lift, size: Double }
    static let fish: [Fish] = {
        var r = Seeded(19)
        return (0..<480).map { _ in
            Fish(phase: r.next() * 6.283, speed: 0.85 + 0.3 * r.next(), radius: 0.55 + 0.6 * r.next(),
                 lift: (r.next() - 0.5) * (r.next() + 0.3), size: 0.8 + 0.5 * r.next())
        }
    }()
}

// MARK: - Textures

/// Costly images, made once off the main thread.
struct KineticTextures {
    let nebula: CGImage?

    static let shared = Task.detached(priority: .userInitiated) { KineticTextures.make() }

    static func make() -> KineticTextures {
        KineticTextures(nebula: makeNebula())
    }

    private static func makeNebula() -> CGImage? {
        let w = 640, h = 420
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 0.03, green: 0.02, blue: 0.11, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let hues: [(CGFloat, CGFloat, CGFloat)] = [(0.45, 0.2, 0.85), (0.25, 0.25, 0.9), (0.7, 0.25, 0.85),
                                                   (0.15, 0.35, 0.95), (0.55, 0.35, 1)]
        var r = Seeded(5)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        for i in 0..<26 {
            let (cr, cg, cb) = hues[i % hues.count]
            let a = CGFloat(0.12 + 0.25 * r.next())
            let grad = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: cr, green: cg, blue: cb, alpha: a),
                                                               CGColor(srgbRed: cr, green: cg, blue: cb, alpha: 0)] as CFArray,
                                  locations: [0, 1])!
            let p = CGPoint(x: CGFloat(r.next()) * CGFloat(w), y: CGFloat(0.15 + 0.7 * r.next()) * CGFloat(h))
            ctx.drawRadialGradient(grad, startCenter: p, startRadius: 0, endCenter: p,
                                   endRadius: CGFloat(60 + 170 * r.next()), options: [])
        }
        // Dark lanes cut through the gas.
        for _ in 0..<8 {
            let grad = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: 0.01, green: 0.01, blue: 0.05, alpha: 0.5),
                                                               CGColor(srgbRed: 0.01, green: 0.01, blue: 0.05, alpha: 0)] as CFArray,
                                  locations: [0, 1])!
            let p = CGPoint(x: CGFloat(r.next()) * CGFloat(w), y: CGFloat(r.next()) * CGFloat(h))
            ctx.drawRadialGradient(grad, startCenter: p, startRadius: 0, endCenter: p,
                                   endRadius: CGFloat(40 + 90 * r.next()), options: [])
        }
        guard let raw = ctx.makeImage() else { return nil }
        let ci = CIImage(cgImage: raw).clampedToExtent()
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = ci
        blur.radius = 14
        guard let out = blur.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: w, height: h)) else { return raw }
        return CIContext().createCGImage(out, from: out.extent) ?? raw
    }
}

/// The song's artwork, shrunk, smeared sideways and blurred once per track.
actor KineticArtStore {
    static let shared = KineticArtStore()
    private var cache: [URL: CGImage] = [:]

    func image(for url: URL) async -> CGImage? {
        if let hit = cache[url] { return hit }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let img = NSImage(data: data),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let out = Self.smear(cg)
        if let out {
            if cache.count > 12 { cache.removeAll() }
            cache[url] = out
        }
        return out
    }

    static func smear(_ cg: CGImage) -> CGImage? {
        let target: CGFloat = 220
        let k = target / CGFloat(max(cg.width, cg.height))
        let base = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: k, y: k))
        let extent = base.extent
        let motion = CIFilter.motionBlur()
        motion.inputImage = base.clampedToExtent()
        motion.radius = 26
        motion.angle = 0.12
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = motion.outputImage
        blur.radius = 7
        let color = CIFilter.colorControls()
        color.inputImage = blur.outputImage
        color.saturation = 1.35
        color.brightness = -0.03
        guard let out = color.outputImage?.cropped(to: extent) else { return nil }
        return CIContext().createCGImage(out, from: out.extent)
    }
}
