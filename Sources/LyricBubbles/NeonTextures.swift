import CoreGraphics
import Foundation

/// Wall and pavement images for the Neon Sign, drawn once on a background thread.
/// Every image tiles seamlessly in both directions. They're drawn as if fully lit; the scene
/// darkens them and the sign's light brings them back up.
final class NeonTextures: @unchecked Sendable {
    let brick: CGImage
    let concrete: CGImage
    let wood: CGImage
    let asphalt: CGImage

    private init(brick: CGImage, concrete: CGImage, wood: CGImage, asphalt: CGImage) {
        self.brick = brick; self.concrete = concrete; self.wood = wood; self.asphalt = asphalt
    }

    static let shared: Task<NeonTextures?, Never> = Task.detached(priority: .userInitiated) { make() }

    static func make() -> NeonTextures? {
        guard let brick = brickWall(), let concrete = concreteWall(), let wood = woodWall(),
              let asphalt = asphaltTile() else { return nil }
        return NeonTextures(brick: brick, concrete: concrete, wood: wood, asphalt: asphalt)
    }

    func wall(_ w: NeonWall) -> CGImage {
        switch w {
        case .brick: brick
        case .concrete: concrete
        case .wood: wood
        }
    }

    /// Pixel density each image was drawn at (so tiles come out at a sensible size in points).
    static func scale(_ w: NeonWall) -> CGFloat { w == .concrete ? 1 : 2 }

    // MARK: Helpers

    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        return ctx
    }

    private struct RNG {
        var s: UInt64
        init(_ seed: UInt64) { s = seed | 1 }
        mutating func next() -> CGFloat {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17
            return CGFloat(s % 1_000_000) / 1_000_000
        }
        mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
    }

    private static func hash(_ x: Int, _ y: Int, _ o: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ o &* 2_147_483_647))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h & 0xFFFF) / 65535
    }

    /// Value noise that repeats every `period` cells, so images built from it tile.
    private static func noise(_ x: Double, _ y: Double, period: Int, _ o: Int) -> Double {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func h(_ a: Int, _ b: Int) -> Double {
            hash(((a % period) + period) % period, ((b % period) + period) % period, o)
        }
        let a = h(xi, yi), b = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1)
        let top = a + (b - a) * sx, bottom = c + (d - c) * sx
        return top + (bottom - top) * sy
    }

    private static func fractal(_ x: Double, _ y: Double, n: Int, base: Int, octaves: Int, seed: Int) -> Double {
        var v = 0.0, amp = 1.0, norm = 0.0, period = base
        for o in 0..<octaves {
            v += amp * noise(x / Double(n) * Double(period), y / Double(n) * Double(period), period: period, seed + o)
            norm += amp
            amp *= 0.5
            period *= 2
        }
        return v / norm
    }

    /// A greyscale tileable noise field (0…1) of side `n`.
    private static func field(_ n: Int, base: Int, octaves: Int, seed: Int) -> [Double] {
        var out = [Double](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                out[y * n + x] = fractal(Double(x), Double(y), n: n, base: base, octaves: octaves, seed: seed)
            }
        }
        return out
    }

    private static func image(_ n: Int, _ pixel: (Int, Int) -> (Double, Double, Double)) -> CGImage? {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let (r, g, b) = pixel(x, y)
                let i = (y * n + x) * 4
                px[i] = UInt8(max(0, min(255, r * 255)))
                px[i + 1] = UInt8(max(0, min(255, g * 255)))
                px[i + 2] = UInt8(max(0, min(255, b * 255)))
            }
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: Brick

    static func brickWall() -> CGImage? {
        let cols = 8, rows = 22
        let bw: CGFloat = 128, bh: CGFloat = 48, mortar: CGFloat = 9
        let W = Int(bw) * cols, H = Int(bh) * rows
        guard let ctx = context(W, H) else { return nil }

        // Mortar, slightly uneven.
        ctx.setFillColor(red: 0.36, green: 0.34, blue: 0.32, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var m = RNG(0xB21C)
        for _ in 0..<5000 {
            let g = m.range(0.2, 0.5)
            ctx.setFillColor(red: g, green: g * 0.96, blue: g * 0.92, alpha: 0.5)
            ctx.fill(CGRect(x: m.next() * CGFloat(W), y: m.next() * CGFloat(H), width: 2, height: 2))
        }

        for r in 0..<rows {
            let offset: CGFloat = r % 2 == 0 ? 0 : bw / 2
            for c in -1...cols {
                let x0 = CGFloat(c) * bw + offset
                guard x0 < CGFloat(W), x0 + bw > 0 else { continue }
                // Same brick on both sides of the wrap, so the tile is seamless.
                var rng = RNG(UInt64(((c + cols) % cols) * 977 + r * 131 + 7))
                let rect = CGRect(x: x0 + mortar / 2, y: CGFloat(r) * bh + mortar / 2,
                                  width: bw - mortar, height: bh - mortar)
                let kind = rng.next()
                var (cr, cg, cb) = (0.62, 0.3, 0.22)
                if kind < 0.12 { (cr, cg, cb) = (0.38, 0.2, 0.17) }        // burnt
                else if kind > 0.9 { (cr, cg, cb) = (0.7, 0.45, 0.34) }   // pale
                let v = Double(rng.range(0.82, 1.12))
                cr *= v; cg *= v * Double(rng.range(0.92, 1.06)); cb *= v

                ctx.saveGState()
                let shape = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                ctx.addPath(shape)
                ctx.clip()
                ctx.setFillColor(red: cr, green: cg, blue: cb, alpha: 1)
                ctx.fill(rect)
                // Speckles and pits.
                for _ in 0..<70 {
                    let d = rng.range(-0.18, 0.12)
                    ctx.setFillColor(red: cr + d, green: cg + d * 0.8, blue: cb + d * 0.7, alpha: 0.6)
                    let s = rng.range(1.5, 4)
                    ctx.fillEllipse(in: CGRect(x: rect.minX + rng.next() * rect.width, y: rect.minY + rng.next() * rect.height,
                                               width: s, height: s))
                }
                // Soot and wear patches.
                for _ in 0..<3 {
                    ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: rng.range(0.03, 0.1))
                    let w = rng.range(20, 70), h = rng.range(10, 30)
                    ctx.fillEllipse(in: CGRect(x: rect.minX + rng.next() * rect.width - w / 2,
                                               y: rect.minY + rng.next() * rect.height - h / 2, width: w, height: h))
                }
                // Lit from above: bright top lip, dark underside.
                ctx.setFillColor(red: 1, green: 0.9, blue: 0.8, alpha: 0.12)
                ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 3))
                ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.28)
                ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 4, width: rect.width, height: 4))
                ctx.restoreGState()
            }
        }
        return ctx.makeImage()
    }

    // MARK: Concrete

    static func concreteWall() -> CGImage? {
        let n = 512
        let big = field(n, base: 4, octaves: 5, seed: 3)
        let fine = field(n, base: 64, octaves: 2, seed: 40)
        guard let base = image(n, { x, y in
            let v = 0.42 + (big[y * n + x] - 0.5) * 0.28 + (fine[y * n + x] - 0.5) * 0.12
            return (v, v * 0.99, v * 0.97)
        }), let ctx = context(n, n) else { return nil }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: n, height: n))

        // Formwork panel seams and tie holes, two panels per tile each way.
        let N = CGFloat(n)
        for k in 0..<2 {
            let p = CGFloat(k) * N / 2
            ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.28)
            ctx.fill(CGRect(x: 0, y: p, width: N, height: 2))
            ctx.fill(CGRect(x: p, y: 0, width: 2, height: N))
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.08)
            ctx.fill(CGRect(x: 0, y: p + 2, width: N, height: 1))
            ctx.fill(CGRect(x: p + 2, y: 0, width: 1, height: N))
        }
        for i in 0..<4 {
            for j in 0..<4 {
                let c = CGPoint(x: N / 8 + CGFloat(i) * N / 4, y: N / 8 + CGFloat(j) * N / 4)
                ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.45)
                ctx.fillEllipse(in: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12))
                ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.1)
                ctx.fillEllipse(in: CGRect(x: c.x - 6, y: c.y + 3, width: 12, height: 4))
            }
        }
        return ctx.makeImage()
    }

    // MARK: Wood

    static func woodWall() -> CGImage? {
        let W = 1024, plank = 128, planks = 8
        guard let ctx = context(W, plank * planks) else { return nil }
        let w = CGFloat(W)
        for p in 0..<planks {
            var r = RNG(UInt64(p * 7919 + 11))
            let y0 = CGFloat(p * plank)
            let v = Double(r.range(0.85, 1.15))
            ctx.setFillColor(red: 0.5 * v, green: 0.33 * v, blue: 0.2 * v, alpha: 1)
            ctx.fill(CGRect(x: 0, y: y0, width: w, height: CGFloat(plank)))
            // Grain: wavy lines whose waves repeat exactly across the tile.
            for _ in 0..<26 {
                let gy = y0 + r.next() * CGFloat(plank)
                let amp = r.range(1, 6)
                let k1 = CGFloat(Int(r.range(1, 4))), k2 = CGFloat(Int(r.range(3, 9)))
                let ph = r.next() * 6.28
                let dark = r.next() < 0.6
                ctx.setStrokeColor(red: dark ? 0.2 : 0.75, green: dark ? 0.12 : 0.55, blue: dark ? 0.06 : 0.38,
                                   alpha: r.range(0.12, 0.35))
                ctx.setLineWidth(r.range(0.8, 2.6))
                ctx.move(to: CGPoint(x: 0, y: gy + amp * sin(ph)))
                var x: CGFloat = 0
                while x <= w {
                    x += 8
                    let a = x / w * 2 * .pi
                    ctx.addLine(to: CGPoint(x: x, y: gy + amp * sin(a * k1 + ph) + amp * 0.4 * sin(a * k2)))
                }
                ctx.strokePath()
            }
            // A knot or two (drawn on both sides of the wrap).
            for _ in 0..<Int(r.range(0, 2.6)) {
                let kx = r.next() * w, ky = y0 + r.range(25, CGFloat(plank) - 25)
                for dx in [-w, 0, w] {
                    for ring in stride(from: 16.0, to: 2, by: -3.5) {
                        ctx.setFillColor(red: 0.18, green: 0.1, blue: 0.05, alpha: 0.22)
                        ctx.fillEllipse(in: CGRect(x: kx + dx - ring * 1.7, y: ky - ring, width: ring * 3.4, height: ring * 2))
                    }
                }
            }
            // Gap to the next plank, and a butt joint with two nails.
            ctx.setFillColor(red: 0.05, green: 0.03, blue: 0.02, alpha: 0.9)
            ctx.fill(CGRect(x: 0, y: y0 + CGFloat(plank) - 5, width: w, height: 5))
            ctx.setFillColor(red: 1, green: 0.85, blue: 0.6, alpha: 0.1)
            ctx.fill(CGRect(x: 0, y: y0, width: w, height: 2))
            let jx = r.range(80, w - 80)
            ctx.setFillColor(red: 0.05, green: 0.03, blue: 0.02, alpha: 0.8)
            ctx.fill(CGRect(x: jx, y: y0, width: 3, height: CGFloat(plank)))
            for ny in [y0 + 30, y0 + CGFloat(plank) - 36] {
                for nx in [jx - 14, jx + 14] {
                    ctx.setFillColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1)
                    ctx.fillEllipse(in: CGRect(x: nx - 4, y: ny - 4, width: 8, height: 8))
                    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.25)
                    ctx.fillEllipse(in: CGRect(x: nx - 2.5, y: ny - 3, width: 3, height: 2))
                }
            }
        }
        return ctx.makeImage()
    }

    // MARK: Asphalt

    static func asphaltTile() -> CGImage? {
        let n = 512
        let big = field(n, base: 8, octaves: 3, seed: 70)
        guard let base = image(n, { x, y in
            let v = 0.2 + (big[y * n + x] - 0.5) * 0.12
            return (v, v, v * 1.03)
        }), let ctx = context(n, n) else { return nil }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: n, height: n))
        var r = RNG(0xA59)
        for _ in 0..<9000 {
            let g = r.range(0.05, 0.5)
            ctx.setFillColor(red: g, green: g, blue: g, alpha: r.range(0.3, 0.8))
            let s = r.range(1, 3)
            let x = r.next() * CGFloat(n), y = r.next() * CGFloat(n)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: s, height: s))
        }
        return ctx.makeImage()
    }
}
