import AppKit
import SwiftUI

// MARK: - Settings

enum GlowPrefs {
    static let on = "glowOn"
    static let palette = "glowPalette"
    static let width = "glowWidth"
    static let speed = "glowSpeed"
    static let sensitivity = "glowSensitivity"
}

enum GlowPalette: String, CaseIterable, Identifiable {
    case intelligence, albumArt, sunset, ocean, neon
    var id: String { rawValue }

    var label: String {
        switch self {
        case .intelligence: "Intelligence"
        case .albumArt: "Album art"
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .neon: "Neon"
        }
    }

    func colors(art: [Color]) -> [Color] {
        switch self {
        case .intelligence:
            return [Color(red: 0.03, green: 0.58, blue: 1), Color(red: 0.79, green: 0.35, blue: 0.87),
                    Color(red: 1, green: 0.18, blue: 0.33), Color(red: 1, green: 0.56, blue: 0.02),
                    Color(red: 0.74, green: 0.5, blue: 1)]
        case .albumArt:
            return art.count >= 2 ? art : GlowPalette.intelligence.colors(art: [])
        case .sunset:
            return [Color(red: 1, green: 0.35, blue: 0.2), Color(red: 1, green: 0.7, blue: 0.2),
                    Color(red: 1, green: 0.3, blue: 0.55), Color(red: 0.6, green: 0.25, blue: 0.9)]
        case .ocean:
            return [Color(red: 0, green: 0.8, blue: 0.9), Color(red: 0.1, green: 0.45, blue: 1),
                    Color(red: 0.3, green: 1, blue: 0.75), Color(red: 0.45, green: 0.35, blue: 1)]
        case .neon:
            return [Color(red: 0.2, green: 1, blue: 0.4), Color(red: 1, green: 0.1, blue: 0.8),
                    Color(red: 0.1, green: 0.9, blue: 1), Color(red: 1, green: 0.95, blue: 0.1)]
        }
    }
}

// MARK: - Border

/// Rainbow edge glow, in the spirit of the Apple Intelligence screen edge.
/// Two gradients spin in opposite directions for a liquid shimmer; music swells and kicks it.
struct GlowBorder: View {
    @ObservedObject var model: PlayerModel
    @AppStorage(GlowPrefs.on) private var on = true
    @AppStorage(GlowPrefs.palette) private var paletteRaw = GlowPalette.intelligence.rawValue
    @AppStorage(GlowPrefs.width) private var width = 0.45
    @AppStorage(GlowPrefs.speed) private var speed = 0.35
    @AppStorage(GlowPrefs.sensitivity) private var sensitivity = 0.6

    static let cornerRadius: CGFloat = 18

    var body: some View {
        if on {
            TimelineView(.animation) { ctx in
                // Keep time and angles small: GPU gradients use 32-bit floats, and an angle of
                // billions of degrees (seconds since 2001 × speed) collapses to a single color.
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                let audio = model.audio.sample(at: ctx.date)
                let react = model.audio.isActive ? sensitivity : 0
                let colors = (GlowPalette(rawValue: paletteRaw) ?? .intelligence).colors(art: model.artPalette)
                let loop = colors + [colors[0]]

                // Calm breathing on its own; with music it swells with loudness and punches on kicks.
                let breathe = 0.5 + 0.5 * sin(t * 1.1)
                let swell = react * (audio.level * 1.1 + audio.beat * 0.9)
                let w = (0.25 + 5.5 * width * width) * (1 + swell)
                let glow = min(1, 0.75 + 0.15 * breathe * (1 - react) + 0.4 * swell)
                let spin = (t * (10 + speed * 110)).truncatingRemainder(dividingBy: 360)
                let counter = (-spin * 0.7 + 120).truncatingRemainder(dividingBy: 360)
                let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                let main = AngularGradient(colors: loop, center: .center, angle: .degrees(spin))
                let shimmer = AngularGradient(colors: loop.reversed(), center: .center, angle: .degrees(counter))

                ZStack {
                    // Wide soft bloom reaching into the window.
                    shape.strokeBorder(main, lineWidth: w * 6)
                        .blur(radius: w * 5)
                        .opacity(glow * 0.9)
                    // Counter-rotating mid glow, added on top for the liquid shimmer.
                    shape.strokeBorder(shimmer, lineWidth: w * 2.6)
                        .blur(radius: w * 1.4)
                        .opacity(glow)
                        .blendMode(.plusLighter)
                    // Crisp bright edge.
                    shape.strokeBorder(main, lineWidth: max(0.75, w * 1.1))
                        .blur(radius: 0.6)
                        .blendMode(.plusLighter)
                }
                // Render on the GPU (Metal). Without this, CoreGraphics shades the three
                // conic gradients on the CPU for the whole window, every frame.
                .drawingGroup()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

// MARK: - Album art colors

enum ArtPalette {
    /// Up to 4 vivid hues from the artwork, brightened for glowing.
    static func extract(from url: URL) async -> [Color] {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }

        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Hue histogram weighted by how colorful each pixel is.
        var buckets = [(weight: Double, h: Double, s: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let c = NSColor(srgbRed: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255,
                            blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            guard s > 0.25, b > 0.2 else { continue }
            let k = min(11, Int(h * 12))
            let w = Double(s * b)
            buckets[k].weight += w
            buckets[k].h += Double(h) * w
            buckets[k].s += Double(s) * w
            buckets[k].b += Double(b) * w
        }
        return buckets
            .filter { $0.weight > 0.5 }
            .sorted { $0.weight > $1.weight }
            .prefix(4)
            .map { Color(hue: $0.h / $0.weight, saturation: max(0.7, $0.s / $0.weight), brightness: max(0.9, $0.b / $0.weight)) }
    }
}
