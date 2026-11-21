import CoreGraphics
import Foundation

/// Pre-rendered bitmaps for the glass, made once on a background thread at first use.
final class GlassTextures: @unchecked Sendable {
    /// Mottled white mist (fractal noise) that makes the fog uneven.
    let fog: CGImage
    /// Fine condensation: mist and small shaded beads, clumped unevenly.
    let drops: CGImage
    /// Densely packed tiny beads, shown along the edges of every wiped stroke.
    let beads: CGImage
    /// Thin vertical rivulets, shown inside wiped strokes.
    let streaks: CGImage

    private init(fog: CGImage, drops: CGImage, beads: CGImage, streaks: CGImage) {
        self.fog = fog; self.drops = drops; self.beads = beads; self.streaks = streaks
    }

    static let shared: Task<GlassTextures?, Never> = Task.detached(priority: .userInitiated) { make() }

    static func make() -> GlassTextures? {
        guard let fog = fogNoise(size: 512),
              let drops = mistField(width: 1100, height: 1500),
              let beads = beadField(size: 900),
              let streaks = streakField(width: 600, height: 1200) else { return nil }
        return GlassTextures(fog: fog, drops: drops, beads: beads, streaks: streaks)
    }

    // MARK: Drawing helpers

    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // y grows downward, like SwiftUI, so highlights land top-left.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        return ctx
    }

    private static func gradient(_ stops: [(CGFloat, CGFloat, CGFloat)]) -> CGGradient {
        // (gray, alpha, location)
        let colors = stops.map { CGColor(gray: $0.0, alpha: $0.1) } as CFArray
        return CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: stops.map(\.2))!
    }

    private static let edgeShade = gradient([(0, 0, 0), (0, 0.06, 0.55), (0, 0.42, 0.92), (0, 0.55, 1)])
    private static let refraction = gradient([(1, 0.6, 0), (1, 0.18, 0.55), (1, 0, 1)])
    private static let innerDark = gradient([(0, 0.18, 0), (0, 0, 1)])

    /// One water droplet seen from inside a fogged window: darker rim, a bright crescent at the
    /// bottom where it focuses the light behind it, a hard specular at top-left and a soft shadow.
    private static func drawDrop(_ ctx: CGContext, x: CGFloat, y: CGFloat, r: CGFloat, strength: CGFloat = 1) {
        let rect = CGRect(x: x - r, y: y - r * 1.06, width: r * 2, height: r * 2.12)
        ctx.setFillColor(CGColor(gray: 0, alpha: 0.2 * strength))
        ctx.fillEllipse(in: rect.offsetBy(dx: r * 0.05, dy: r * 0.2))

        ctx.saveGState()
        ctx.addEllipse(in: rect)
        ctx.clip()
        ctx.setAlpha(strength)
        let c = CGPoint(x: x, y: y)
        ctx.drawRadialGradient(innerDark, startCenter: CGPoint(x: x, y: y - r * 0.35), startRadius: 0,
                               endCenter: CGPoint(x: x, y: y - r * 0.35), endRadius: r * 0.9, options: [])
        ctx.drawRadialGradient(edgeShade, startCenter: c, startRadius: 0, endCenter: c, endRadius: r * 1.1, options: [])
        let low = CGPoint(x: x + r * 0.08, y: y + r * 0.58)
        ctx.drawRadialGradient(refraction, startCenter: low, startRadius: 0, endCenter: low, endRadius: r * 0.8, options: [])
        ctx.restoreGState()

        ctx.setFillColor(CGColor(gray: 1, alpha: 0.95 * strength))
        ctx.fillEllipse(in: CGRect(x: x - r * 0.52, y: y - r * 0.62, width: r * 0.36, height: r * 0.26))
        if r > 3 {
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.35 * strength))
            ctx.fillEllipse(in: CGRect(x: x + r * 0.2, y: y + r * 0.45, width: r * 0.22, height: r * 0.14))
        }
    }

    // MARK: Fog noise

    private static func hash(_ x: Int, _ y: Int, _ o: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ o &* 2_147_483_647))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h & 0xFFFF) / 65535
    }

    private static func valueNoise(_ x: Double, _ y: Double, _ o: Int) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = hash(xi, yi, o), b = hash(xi + 1, yi, o), c = hash(xi, yi + 1, o), d = hash(xi + 1, yi + 1, o)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    static func fogNoise(size n: Int) -> CGImage? {
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                var v = 0.0, amp = 1.0, freq = 3.0, norm = 0.0
                for o in 0..<6 {
                    v += amp * valueNoise(Double(x) / Double(n) * freq, Double(y) / Double(n) * freq, o)
                    norm += amp
                    amp *= 0.52
                    freq *= 2.05
                }
                v /= norm
                // Stretch contrast so there are clear patches and thick patches.
                let k = min(1, max(0, (v - 0.32) / 0.4))
                let a = UInt8(min(255, pow(k, 1.4) * 255))
                let i = (y * n + x) * 4
                px[i] = a; px[i + 1] = a; px[i + 2] = a; px[i + 3] = a
            }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: Droplets

    private struct RNG {
        var s: UInt64
        mutating func next() -> CGFloat {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17
            return CGFloat(s % 1_000_000) / 1_000_000
        }
    }

    static func mistField(width w: Int, height h: Int) -> CGImage? {
        guard let ctx = context(w, h) else { return nil }
        var r = RNG(s: 0x9E37_79B9_7F4A_7C15)
        let W = CGFloat(w), H = CGFloat(h)
        // Clumpiness: big soft patches where condensation is heavier, so it never reads as a
        // uniform repeating sprinkle.
        func density(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let a = valueNoise(Double(x / W) * 4, Double(y / H) * 5, 11)
            let b = valueNoise(Double(x / W) * 11, Double(y / H) * 13, 12)
            return CGFloat(pow(a * 0.7 + b * 0.3, 1.8)) * (0.55 + 0.45 * y / H)
        }
        for _ in 0..<(w * h / 45) {
            let x = r.next() * W, y = r.next() * H
            guard r.next() < density(x, y) * 1.6 else { continue }
            let d = 0.5 + pow(r.next(), 2) * 1.6
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.08 + r.next() * 0.2))
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
        }
        for _ in 0..<(w * h / 260) {
            let x = r.next() * W, y = r.next() * H
            guard r.next() < density(x, y) * 1.4 else { continue }
            drawDrop(ctx, x: x, y: y, r: 0.9 + pow(r.next(), 1.6) * 2.4, strength: 0.4 + r.next() * 0.5)
        }
        return ctx.makeImage()
    }

    static func beadField(size n: Int) -> CGImage? {
        guard let ctx = context(n, n) else { return nil }
        var r = RNG(s: 0xC0FF_EE12_3456_789B)
        let N = CGFloat(n)
        for _ in 0..<(n * n / 70) {
            drawDrop(ctx, x: r.next() * N, y: r.next() * N, r: 1.1 + pow(r.next(), 1.8) * 3.6)
        }
        return ctx.makeImage()
    }

    static func streakField(width w: Int, height h: Int) -> CGImage? {
        guard let ctx = context(w, h) else { return nil }
        var r = RNG(s: 0x51EE_D5EE_D5EE_D5ED)
        let W = CGFloat(w), H = CGFloat(h)
        ctx.setLineCap(.round)
        for _ in 0..<70 {
            let x0 = r.next() * W, y0 = r.next() * H * 0.7
            let len = 80 + r.next() * H * 0.5
            let wob = 2 + r.next() * 6, ph = r.next() * 6
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x0, y: y0))
            var y = y0
            while y < y0 + len {
                y += 6
                path.addLine(to: CGPoint(x: x0 + sin(y * 0.035 + ph) * wob, y: y))
            }
            ctx.addPath(path)
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.12 + r.next() * 0.25))
            ctx.setLineWidth(0.8 + r.next() * 2.2)
            ctx.strokePath()
            drawDrop(ctx, x: x0 + sin((y0 + len) * 0.035 + ph) * wob, y: y0 + len, r: 2 + r.next() * 2.5)
        }
        return ctx.makeImage()
    }
}
