import AppKit
import CoreImage
import SwiftUI

// MARK: - City lights behind the glass

struct BokehLight {
    let p: CGPoint
    let r: CGFloat
    let color: Color
    let alpha: Double
}

/// The drifting lights, computed once per frame and shared by the backdrop and every droplet
/// (which shows its own tiny upside-down view of them).
enum BokehField {
    private static let fallback: [Color] = [
        Color(red: 1, green: 0.62, blue: 0.25), Color(red: 0.25, green: 0.6, blue: 1),
        Color(red: 1, green: 0.3, blue: 0.45), Color(red: 0.55, green: 0.9, blue: 0.75),
    ]

    static func lights(t: Double, beat: Double, size: CGSize, amount: Double, palette: [Color]) -> [BokehLight] {
        guard amount > 0 else { return [] }
        let colors = palette.count >= 2 ? palette : fallback
        var r = Seeded(42)
        let count = Int(8 + amount * 26)
        return (0..<count).map { i in
            let bx = r.next(), by = r.next(), rad = 12 + r.next() * 44, sp = 0.02 + r.next() * 0.05
            let ph = r.next() * 6.28
            let x = (bx + 0.05 * sin(t * sp * 3 + ph)) * size.width
            let y = (0.12 + by * 0.88 + 0.03 * cos(t * sp * 2 + ph)) * size.height
            let twinkle = 0.5 + 0.25 * sin(t * (0.6 + sp * 8) + ph) + 0.35 * beat
            return BokehLight(p: CGPoint(x: x, y: y), r: rad, color: colors[i % colors.count],
                              alpha: min(1, min(1, twinkle) * (0.45 + amount * 0.7)))
        }
    }

    /// Out-of-focus disc: slightly brighter toward its rim, like real lens bokeh.
    static func drawCrisp(_ ctx: inout GraphicsContext, _ l: BokehLight, scale: CGFloat = 1) {
        let r = l.r * scale
        let rect = CGRect(x: l.p.x - r, y: l.p.y - r, width: r * 2, height: r * 2)
        let a = l.alpha * 0.9
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(stops: [
            .init(color: l.color.opacity(a * 0.6), location: 0),
            .init(color: l.color.opacity(a * 0.72), location: 0.72),
            .init(color: l.color.opacity(a), location: 0.9),
            .init(color: l.color.opacity(0), location: 1),
        ]), center: l.p, startRadius: 0, endRadius: r))
        if l.r > 30 {
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: r * 0.6, dy: r * 0.6)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.3 * a), .clear]),
                                           center: l.p, startRadius: 0, endRadius: r * 0.4))
        }
    }

    /// Seen through fog: a wide soft glow.
    static func drawSoft(_ ctx: inout GraphicsContext, _ l: BokehLight, spread: CGFloat) {
        let r = l.r * spread
        let rect = CGRect(x: l.p.x - r, y: l.p.y - r, width: r * 2, height: r * 2)
        let a = l.alpha * 0.75
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(stops: [
            .init(color: l.color.opacity(a), location: 0),
            .init(color: l.color.opacity(a * 0.45), location: 0.45),
            .init(color: l.color.opacity(0), location: 1),
        ]), center: l.p, startRadius: 0, endRadius: r))
    }
}

// MARK: - Album art, blurred once

/// Pre-blurred, pre-saturated album art, so no blur runs per frame.
struct ArtLayers: @unchecked Sendable {
    let soft: CGImage    // seen through fog
    let clear: CGImage   // seen through the wiped writing and through droplets

    static func make(from data: Data) async -> ArtLayers? {
        await Task.detached(priority: .userInitiated) { () -> ArtLayers? in
            guard let src = CIImage(data: data) else { return nil }
            let ctx = CIContext(options: [.useSoftwareRenderer: false])
            func render(maxDim: CGFloat, blur: Double, saturation: Double) -> CGImage? {
                let scale = maxDim / max(src.extent.width, src.extent.height)
                let small = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let extent = small.extent
                let out = small.clampedToExtent()
                    .applyingGaussianBlur(sigma: blur)
                    .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
                    .cropped(to: extent)
                return ctx.createCGImage(out, from: extent)
            }
            guard let soft = render(maxDim: 220, blur: 9, saturation: 1.3),
                  let clear = render(maxDim: 640, blur: 5, saturation: 1.3) else { return nil }
            return ArtLayers(soft: soft, clear: clear)
        }.value
    }
}

// MARK: - Droplet simulation

/// Condensation that lives: droplets slowly grow, touch and merge, and once heavy enough they
/// slide down in fits and starts, leaving a clear trail (which fogs back over) dotted with
/// tiny leftovers. All in pane coordinates; the camera moves the result.
final class DropletSim {
    struct Drop {
        var x, y, r: CGFloat
        var growth: CGFloat
        var slideAt: CGFloat
        var sliding = false
        var speed: CGFloat = 0
        var seed: Double
        var lastTrailY: CGFloat = 0
        var lastLeftover: CGFloat = 0
        var stretch: CGFloat { sliding ? min(0.38, speed / 110) : 0 }
    }

    struct TrailDot {
        let x, y, w: CGFloat
        let born: Double
    }

    private(set) var drops: [Drop] = []
    private(set) var trail: [TrailDot] = []
    private(set) var time = 0.0
    private var size = CGSize.zero
    private var last: Date?
    private var rng = Seeded(0xD20_9E7)
    private var spawnCredit = 0.0

    func step(at date: Date, size newSize: CGSize, amount: Double, boost: Double,
              wipe: (point: CGPoint, radius: CGFloat)?) {
        guard newSize.width > 10, newSize.height > 10 else { return }
        if size != newSize {
            if size.width > 0 {
                let sx = newSize.width / size.width, sy = newSize.height / size.height
                for i in drops.indices { drops[i].x *= sx; drops[i].y *= sy }
                trail.removeAll()
            }
            size = newSize
        }
        let dt: Double
        if let l = last {
            dt = min(1.0 / 20, max(0, date.timeIntervalSince(l)))
        } else {
            dt = 0
        }
        last = date
        guard dt > 0 || drops.isEmpty else { return }
        time += dt

        let area = Double(size.width * size.height) / (440 * 600)
        let target = amount <= 0 ? 0 : Int((14 + amount * 46) * area)

        // Fill the pane right away the first time, then condense new ones gradually.
        if drops.isEmpty, target > 0 {
            for _ in 0..<target { drops.append(newDrop(initial: true)) }
        }
        spawnCredit += dt * (1.5 + boost * 12)
        while drops.count < target, spawnCredit >= 1 {
            drops.append(newDrop(initial: false))
            spawnCredit -= 1
        }
        spawnCredit = min(spawnCredit, 3)
        if drops.count > target + 4 { drops.removeLast(drops.count - target) }

        let dtf = CGFloat(dt)
        var leftovers: [Drop] = []
        for i in drops.indices {
            var d = drops[i]
            if !d.sliding {
                d.r += d.growth * dtf * CGFloat(1 + boost * 6)
                if d.r >= d.slideAt { d.sliding = true; d.lastTrailY = d.y; d.lastLeftover = d.y }
            } else {
                // Real drops lurch: run, catch, run.
                let phase = sin(time * (1.3 + d.seed) + d.seed * 20) * 0.5 + 0.5
                let stick = 0.12 + 0.88 * pow(phase, 2.2)
                d.speed = (22 + d.r * 5) * CGFloat(stick)
                d.y += d.speed * dtf
                d.x += CGFloat(sin(Double(d.y) * 0.045 + d.seed * 9)) * 0.35 * d.speed * dtf * 0.1
                d.r -= d.speed * dtf * 0.0045
                if d.y - d.lastTrailY > 2 {
                    trail.append(TrailDot(x: d.x, y: d.y, w: d.r * 0.62, born: time))
                    d.lastTrailY = d.y
                }
                if d.y - d.lastLeftover > 18 + CGFloat(rng.next()) * 30 {
                    var left = newDrop(initial: false)
                    left.x = d.x + CGFloat(rng.next() - 0.5) * d.r * 0.8
                    left.y = d.y - d.r * 1.4
                    left.r = 1.2 + CGFloat(rng.next()) * d.r * 0.22
                    leftovers.append(left)
                    d.lastLeftover = d.y
                }
                if d.r < 4.5 { d.sliding = false; d.speed = 0; d.slideAt = d.r + 4 + CGFloat(rng.next()) * 4 }
            }
            drops[i] = d
        }
        drops += leftovers

        // A finger writing through droplets wipes them up.
        if let wipe {
            drops.removeAll { hypot($0.x - wipe.point.x, $0.y - wipe.point.y) < wipe.radius + $0.r * 0.5 }
        }

        mergeTouching()
        drops.removeAll { $0.y - $0.r > size.height + 4 || $0.r < 0.8 }
        trail.removeAll { time - $0.born > 16 }
        if trail.count > 2400 { trail.removeFirst(trail.count - 2400) }
    }

    private func newDrop(initial: Bool) -> Drop {
        let big = initial ? pow(rng.next(), 2.4) : 0
        let r = CGFloat(1.4 + rng.next() * 2.2 + big * 10)
        // Water collects lower on the pane.
        let y = CGFloat(pow(rng.next(), 0.75)) * size.height
        return Drop(x: CGFloat(rng.next()) * size.width, y: y, r: r,
                    growth: CGFloat(0.05 + rng.next() * 0.22),
                    slideAt: CGFloat(9 + rng.next() * 6),
                    seed: rng.next())
    }

    private func mergeTouching() {
        guard drops.count > 1 else { return }
        var i = 0
        while i < drops.count {
            var j = i + 1
            while j < drops.count {
                let a = drops[i], b = drops[j]
                let dist = hypot(a.x - b.x, a.y - b.y)
                if dist < (a.r + b.r) * 0.85 {
                    // Volume adds (area, near enough); the merged drop sits where the bigger was.
                    let big = a.r >= b.r ? a : b
                    var m = big
                    m.r = (a.r * a.r + b.r * b.r).squareRoot()
                    m.sliding = a.sliding || b.sliding || m.r >= m.slideAt
                    m.y = max(a.y, b.y) - m.r * 0.3
                    if m.sliding, !big.sliding { m.lastTrailY = m.y; m.lastLeftover = m.y }
                    drops[i] = m
                    drops.remove(at: j)
                } else {
                    j += 1
                }
            }
            i += 1
        }
    }
}

// MARK: - Drawing droplets

/// Each droplet is a tiny lens: it shows an upside-down, shrunken view of the lights and art
/// behind it, darkens toward its edge, focuses a bright crescent at the bottom, catches a
/// specular highlight at the top and sits on a soft contact shadow.
struct DropsLayer: View {
    let drops: [DropletSim.Drop]
    let lights: [BokehLight]        // in pane coordinates
    let art: CGImage?
    let artRect: CGRect             // where the art covers, in pane coordinates
    let shine: Double

    var body: some View {
        Canvas { ctx, _ in
            let artImage = art.map { ctx.resolve(Image(decorative: $0, scale: 1)) }
            for d in drops {
                draw(&ctx, d, artImage)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ ctx: inout GraphicsContext, _ d: DropletSim.Drop, _ artImage: GraphicsContext.ResolvedImage?) {
        let r = d.r
        let h = r * (1 + d.stretch)
        let c = CGPoint(x: d.x, y: d.y - (h - r) * 0.6)
        let rect = CGRect(x: c.x - r, y: c.y - h, width: r * 2, height: h * 2)
        let body = Path(ellipseIn: rect)

        // Contact shadow.
        let sh = rect.offsetBy(dx: r * 0.06, dy: r * 0.28).insetBy(dx: -r * 0.18, dy: -r * 0.18)
        ctx.fill(Path(ellipseIn: sh), with: .radialGradient(
            Gradient(colors: [.black.opacity(0.32), .black.opacity(0.12), .clear]),
            center: CGPoint(x: sh.midX, y: sh.midY), startRadius: 0, endRadius: max(sh.width, sh.height) / 2))

        if r < 2.6 {
            // Too small to show anything through: a dark bead with a glint.
            ctx.fill(body, with: .color(.black.opacity(0.28)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.5, y: c.y - r * 0.55, width: r * 0.55, height: r * 0.45)),
                     with: .color(.white.opacity(0.85 * (0.6 + shine * 0.4))))
            return
        }

        // What the lens sees: the scene behind, flipped and shrunk around the drop.
        ctx.drawLayer { l in
            l.clip(to: body)
            l.fill(body, with: .color(Color(red: 0.11, green: 0.12, blue: 0.15)))
            let k: CGFloat = 4
            l.translateBy(x: c.x, y: c.y)
            l.scaleBy(x: -1 / k, y: -(1 + d.stretch) / k)
            l.translateBy(x: -c.x, y: -c.y)
            if let artImage {
                l.opacity = 0.55
                l.draw(artImage, in: artRect)
                l.opacity = 1
            }
            let reach = r * k * 1.15
            for light in lights where hypot(light.p.x - c.x, light.p.y - c.y) < reach + light.r {
                // Through a lens the lights come into focus: smaller, brighter.
                var lit = light
                lit = BokehLight(p: lit.p, r: lit.r, color: lit.color, alpha: min(1, lit.alpha * 1.5))
                BokehField.drawCrisp(&l, lit, scale: 0.75)
            }
        }

        let span = max(r, h)
        // Thickness at the edge: darker, plus a cool tint.
        ctx.fill(body, with: .radialGradient(Gradient(stops: [
            .init(color: .clear, location: 0.5),
            .init(color: .black.opacity(0.2), location: 0.8),
            .init(color: .black.opacity(0.45), location: 1),
        ]), center: c, startRadius: 0, endRadius: span))
        // The fogged pane around it, reflected in the top of the dome.
        ctx.fill(body, with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0.04), .clear]),
                                             startPoint: CGPoint(x: c.x, y: rect.minY),
                                             endPoint: CGPoint(x: c.x, y: c.y + h * 0.2)))
        // Light focused through the drop pools at the bottom.
        ctx.fill(body, with: .radialGradient(Gradient(colors: [.white.opacity(0.38), .white.opacity(0.1), .clear]),
                                             center: CGPoint(x: c.x + r * 0.08, y: c.y + h * 0.6),
                                             startRadius: 0, endRadius: r * 0.8))
        // Thin bright rim, strongest at the top.
        ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.45), .clear, .white.opacity(0.2)]),
                                         startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                         endPoint: CGPoint(x: rect.midX, y: rect.maxY)),
                   lineWidth: max(0.7, r * 0.07))
        // Specular highlight with a soft halo.
        let sp = CGRect(x: c.x - r * 0.58, y: c.y - h * 0.64, width: r * 0.4, height: r * 0.28)
        ctx.fill(Path(ellipseIn: sp.insetBy(dx: -r * 0.15, dy: -r * 0.15)),
                 with: .radialGradient(Gradient(colors: [.white.opacity(0.28 * (0.5 + shine)), .clear]),
                                       center: CGPoint(x: sp.midX, y: sp.midY), startRadius: 0, endRadius: r * 0.42))
        ctx.fill(Path(ellipseIn: sp), with: .color(.white.opacity(0.95)))
        if r > 5 {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.22, y: c.y + h * 0.42, width: r * 0.2, height: r * 0.12)),
                     with: .color(.white.opacity(0.35)))
        }
    }
}

/// Where sliding drops have run: clear glass that slowly fogs back over.
struct TrailMask: View {
    let trail: [DropletSim.TrailDot]
    let now: Double

    var body: some View {
        Canvas { ctx, _ in
            // Solid dots (no per-dot alpha, so overlaps never band); the fog closes back in
            // from the edges, so the trail narrows rather than fades.
            var path = Path()
            for dot in trail {
                let age = now - dot.born
                let w = dot.w * CGFloat(1 - smoothstep((age - 1.5) / 11))
                guard w > 0.4 else { continue }
                path.addEllipse(in: CGRect(x: dot.x - w / 2, y: dot.y - w, width: w, height: w * 2))
            }
            ctx.fill(path, with: .color(.white.opacity(0.8)))
        }
        .allowsHitTesting(false)
    }
}
