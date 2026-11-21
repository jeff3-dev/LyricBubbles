import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

// MARK: - Textures (built once)

/// Crosshatch, halftone dots, newsprint paper and film grain, as small tiles.
final class MegaTextures: @unchecked Sendable {
    let hatch: CGImage       // one direction of pen lines
    let crosshatch: CGImage  // both directions
    let dots: CGImage        // one Ben-Day dot per tile
    let paper: CGImage
    let grain: CGImage

    static let shared = MegaTextures()

    private init() {
        hatch = Self.tile(48) { ctx, n in
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(2.2)
            for k in stride(from: -n, through: n * 2, by: 8) {
                ctx.move(to: CGPoint(x: k, y: 0)); ctx.addLine(to: CGPoint(x: k + n, y: n))
            }
            ctx.strokePath()
        }
        crosshatch = Self.tile(48) { ctx, n in
            ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
            ctx.setLineWidth(2)
            for k in stride(from: -n, through: n * 2, by: 8) {
                ctx.move(to: CGPoint(x: k, y: 0)); ctx.addLine(to: CGPoint(x: k + n, y: n))
                ctx.move(to: CGPoint(x: k, y: n)); ctx.addLine(to: CGPoint(x: k + n, y: 0))
            }
            ctx.strokePath()
        }
        dots = Self.tile(16) { ctx, n in
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: 2.5, y: 2.5, width: 11, height: 11))
        }
        paper = Self.tile(256) { ctx, n in
            var rng = Seeded(77)
            ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.92, blue: 0.8, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
            for _ in 0..<2600 {
                let g = 0.75 + rng.next() * 0.25
                ctx.setFillColor(CGColor(srgbRed: g * 0.95, green: g * 0.9, blue: g * 0.78, alpha: 0.35))
                ctx.fill(CGRect(x: rng.next() * n, y: rng.next() * n, width: 1 + rng.next() * 2, height: 1 + rng.next() * 2))
            }
            ctx.setStrokeColor(CGColor(srgbRed: 0.7, green: 0.64, blue: 0.5, alpha: 0.18))
            ctx.setLineWidth(0.7)
            for _ in 0..<70 {
                let x = rng.next() * n, y = rng.next() * n
                ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + rng.next() * 14 - 7, y: y + rng.next() * 6 - 3))
            }
            ctx.strokePath()
        }
        grain = Self.tile(128) { ctx, n in
            var rng = Seeded(31)
            for y in 0..<Int(n) {
                for x in 0..<Int(n) {
                    let g = rng.next()
                    ctx.setFillColor(CGColor(gray: g, alpha: 1))
                    ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    private static func tile(_ size: Int, _ draw: (CGContext, Double) -> Void) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx, Double(size))
        return ctx.makeImage()!
    }
}

// MARK: - Cover art, restyled for each look

/// Downloads album art once and keeps restyled copies: posterized gold for Deco, ink
/// threshold for Noir, halftone for Comic and edge glow for Neon.
actor MegaArtStore {
    static let shared = MegaArtStore()
    private var raw: [URL: CGImage] = [:]
    private var treated: [String: CGImage] = [:]

    func image(for url: URL, look: MegaLook, strength: Double) async -> CGImage? {
        let key = "\(url.absoluteString)|\(look.rawValue)|\(Int(strength * 10))"
        if let hit = treated[key] { return hit }
        var src = raw[url]
        if src == nil {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = NSImage(data: data),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            if raw.count > 8 { raw.removeAll() }
            raw[url] = cg
            src = cg
        }
        guard let src, let out = MegaArtTreatment.apply(src, look: look, strength: strength) else { return nil }
        if treated.count > 24 { treated.removeAll() }
        treated[key] = out
        return out
    }
}

enum MegaArtTreatment {
    private static let ci = CIContext(options: [.cacheIntermediates: false])

    static func apply(_ cg: CGImage, look: MegaLook, strength: Double) -> CGImage? {
        let target: CGFloat = 320
        let k = target / CGFloat(max(cg.width, cg.height))
        let base = CIImage(cgImage: cg).transformed(by: CGAffineTransform(scaleX: k, y: k))
        let extent = base.extent
        var styled: CIImage?
        switch look {
        case .deco:
            let pop = CIFilter.colorControls()
            pop.inputImage = base; pop.saturation = 1.25; pop.contrast = 1.15
            let post = CIFilter.colorPosterize()
            post.inputImage = pop.outputImage; post.levels = 4
            let gold = CIFilter.colorMonochrome()
            gold.inputImage = post.outputImage; gold.color = CIColor(red: 0.93, green: 0.74, blue: 0.36); gold.intensity = 0.35
            styled = gold.outputImage
        case .noir:
            let mono = CIFilter.photoEffectNoir()
            mono.inputImage = base
            let contrast = CIFilter.colorControls()
            contrast.inputImage = mono.outputImage; contrast.contrast = 1.6; contrast.brightness = -0.05
            let ink = CIFilter.colorThreshold()
            ink.inputImage = contrast.outputImage; ink.threshold = 0.42
            let mix = CIFilter.dissolveTransition()
            mix.inputImage = contrast.outputImage; mix.targetImage = ink.outputImage; mix.time = 0.7
            styled = mix.outputImage
        case .comic:
            let pop = CIFilter.colorControls()
            pop.inputImage = base; pop.saturation = 1.5; pop.contrast = 1.1
            let tone = CIFilter.cmykHalftone()
            tone.inputImage = pop.outputImage; tone.width = 7; tone.sharpness = 0.8; tone.center = CGPoint(x: 0, y: 0)
            styled = tone.outputImage
        case .neon:
            let edges = CIFilter.edges()
            edges.inputImage = base; edges.intensity = 6
            let sat = CIFilter.colorControls()
            sat.inputImage = edges.outputImage; sat.saturation = 2; sat.brightness = 0.02
            let dim = CIFilter.colorControls()
            dim.inputImage = base; dim.brightness = -0.35; dim.saturation = 1.3
            let add = CIFilter.additionCompositing()
            add.inputImage = sat.outputImage; add.backgroundImage = dim.outputImage
            styled = add.outputImage
        }
        guard let styled else { return nil }
        let mix = CIFilter.dissolveTransition()
        mix.inputImage = base
        mix.targetImage = styled.cropped(to: extent)
        // Noir never keeps much colour: even a light treatment is mostly monochrome.
        mix.time = Float(max(0, min(1, look == .noir ? 0.55 + strength * 0.45 : strength)))
        guard let out = mix.outputImage?.cropped(to: extent) else { return nil }
        return ci.createCGImage(out, from: extent)
    }
}
