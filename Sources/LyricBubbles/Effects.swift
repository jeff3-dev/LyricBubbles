import SwiftUI

// MARK: - Spring

/// Closed-form damped spring (unit step), so motion is a pure function of time:
/// smooth at any frame rate, and seeking or pausing just works.
enum Spring {
    /// Returns (progress 0→1 with overshoot, velocity in progress/second).
    static func step(_ t: Double, response: Double = 0.45, damping: Double = 0.75) -> (Double, Double) {
        guard t > 0 else { return (0, 0) }
        let w0 = 2 * .pi / response
        if damping < 1 {
            let wd = w0 * (1 - damping * damping).squareRoot()
            let e = exp(-damping * w0 * t)
            let x = 1 - e * (cos(wd * t) + (damping * w0 / wd) * sin(wd * t))
            let v = e * (w0 * w0 / wd) * sin(wd * t)
            return (x, v)
        }
        let e = exp(-w0 * t)
        return (1 - e * (1 + w0 * t), w0 * w0 * t * e)
    }
}

/// Settings shared by everything that moves.
enum MotionPrefs {
    static let blurKey = "motionBlurAmount"
    static let zoomKey = "focusZoom"

    /// Slider 0...1 -> blur multiplier: 0 = off, 0.5 = normal (1x), 1 = extreme (4x).
    static func multiplier(_ amount: Double) -> Double {
        amount <= 0.5 ? amount * 2 : 1 + (amount - 0.5) * 6
    }

    static func label(_ amount: Double) -> String {
        switch amount {
        case ..<0.01: "Off"
        case ..<0.3: "Subtle"
        case ..<0.6: "Normal"
        case ..<0.85: "Strong"
        default: "Extreme"
        }
    }
}

/// Entrance for anything arriving in the thread: springs up and in, blurred while moving fast.
struct SpringEntrance: ViewModifier {
    let age: Double
    let anchor: UnitPoint
    var blur: Double = 1
    var from: Double = 0.55          // starting scale
    var distance: CGFloat = 22

    func body(content: Content) -> some View {
        let (p, v) = Spring.step(age)
        content
            .scaleEffect(from + (1 - from) * p, anchor: anchor)
            .offset(y: distance * (1 - p))
            .opacity(min(1, max(0, age / 0.14)))
            .blur(radius: min(5, abs(v) * 0.32) * blur)
    }
}

extension View {
    func springEntrance(age: Double, anchor: UnitPoint, blur: Double = 1, from: Double = 0.55, distance: CGFloat = 22) -> some View {
        modifier(SpringEntrance(age: age, anchor: anchor, blur: blur, from: from, distance: distance))
    }
}

// MARK: - Easing

enum Ease {
    static func outCubic(_ t: Double) -> Double { let u = 1 - min(max(t, 0), 1); return 1 - u * u * u }
    static func inCubic(_ t: Double) -> Double { let u = min(max(t, 0), 1); return u * u * u }
    /// Overshoots then settles: used for tapback pops.
    static func outBack(_ t: Double) -> Double {
        let u = min(max(t, 0), 1) - 1
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * u * u * u + c1 * u * u
    }
}

/// Scale and opacity for a bubble effect, from seconds since the bubble arrived.
enum BubbleMotion {
    static func scale(_ fx: BubbleEffect?, age: Double) -> Double {
        switch fx {
        case .slam: return age < 0.45 ? 1 + 1.4 * (1 - Ease.outCubic(age / 0.45)) : 1
        case .loud: return age < 0.9 ? 1 + 0.45 * sin(.pi * age / 0.9) : 1
        case .gentle: return age < 1.4 ? 0.55 + 0.45 * Ease.outCubic(age / 1.4) : 1
        case nil: return 1
        }
    }

    static func opacity(_ fx: BubbleEffect?, age: Double) -> Double {
        switch fx {
        case .slam: return min(1, age / 0.12)
        case .gentle: return min(1, age / 0.8)
        default: return 1
        }
    }

    /// Motion blur radius, highest while the bubble is moving fastest.
    static func blur(_ fx: BubbleEffect?, age: Double) -> Double {
        switch fx {
        case .slam: return age < 0.45 ? 7 * (1 - Ease.outCubic(age / 0.45)) : 0
        case .loud: return age < 0.9 ? 2.2 * abs(cos(.pi * age / 0.9)) * (1 - age / 0.9) : 0
        case .gentle: return age < 1.4 ? 6 * (1 - Ease.outCubic(age / 1.4)) : 0
        case nil: return 0
        }
    }

    /// Horizontal shake of the whole thread just after a slam lands.
    static func shake(age: Double) -> Double {
        guard age > 0.35, age < 0.8 else { return 0 }
        let k = (age - 0.35) / 0.45
        return sin(k * 40) * 6 * (1 - k)
    }
}

// MARK: - Tapback badge

struct TapbackBadge: View {
    let reaction: Reaction
    let onOutgoing: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let fill = reaction.byMe ? Palette.blue : Palette.gray(scheme)
        ZStack {
            // Two little dots trailing toward the bubble, like a thought tail.
            Circle().fill(fill).frame(width: 7, height: 7)
                .offset(x: onOutgoing ? 11 : -11, y: 12)
            Circle().fill(fill).frame(width: 3.5, height: 3.5)
                .offset(x: onOutgoing ? 15 : -15, y: 17)
            Circle()
                .fill(fill)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Palette.background(scheme), lineWidth: 2))
            glyph
        }
    }

    @ViewBuilder private var glyph: some View {
        let tint: Color = reaction.byMe ? .white : .secondary
        switch reaction.tapback {
        case .heart:
            Image(systemName: "heart.fill").font(.system(size: 13, weight: .bold))
                .foregroundStyle(reaction.byMe ? .white : Color(red: 1, green: 0.27, blue: 0.45))
        case .thumbsUp:
            Image(systemName: "hand.thumbsup.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
        case .thumbsDown:
            Image(systemName: "hand.thumbsdown.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
        case .haha:
            Text("HA\nHA").font(.system(size: 7, weight: .black)).lineSpacing(-2)
                .multilineTextAlignment(.center).foregroundStyle(tint)
        case .emphasize:
            Text("!!").font(.system(size: 14, weight: .black)).foregroundStyle(tint)
        case .question:
            Text("?").font(.system(size: 15, weight: .black)).foregroundStyle(tint)
        case .emoji(let e):
            Text(e).font(.system(size: 15))
        }
    }
}

// MARK: - Jumbo emoji

struct JumboEmoji: View {
    let text: String
    let outgoing: Bool

    var body: some View {
        HStack {
            if outgoing { Spacer() }
            Text(text).font(.system(size: 44))
            if !outgoing { Spacer() }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Link preview card

struct LinkCard: View {
    let snapshot: SpotifySnapshot
    let outgoing: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            if outgoing { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 0) {
                AsyncImage(url: snapshot.artworkURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        LinearGradient(colors: [.purple.opacity(0.7), .blue.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(width: 220, height: 220)
                .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text("\(snapshot.artist) · open.spotify.com")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: 220, alignment: .leading)
                .background(Palette.gray(scheme))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !outgoing { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Notification banner

struct NotificationBanner: View {
    let banner: Banner
    let artworkURL: URL?
    let age: Double
    var blur: Double = 1

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.9, blue: 0.4), Color(red: 0.13, green: 0.75, blue: 0.27)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: "message.fill").font(.system(size: 15)).foregroundStyle(.white))

            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(banner.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text("now").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(banner.body).font(.system(size: 12)).lineLimit(2).foregroundStyle(.primary.opacity(0.85))
            }

            if banner.showsArt {
                AsyncImage(url: artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal, 10)
        .offset(y: offsetY)
        .blur(radius: motionBlur * blur)
        .opacity(age < 0.1 ? age / 0.1 : 1)
    }

    /// Springs down from above, holds, slides back up.
    private var offsetY: Double {
        let out = Banner.duration - 0.4
        if age > out { return -130 * Ease.inCubic((age - out) / 0.4) }
        return -130 * (1 - Spring.step(age, response: 0.5, damping: 0.78).0)
    }

    private var motionBlur: Double {
        let out = Banner.duration - 0.4
        if age > out { return 6 * Ease.inCubic((age - out) / 0.4) }
        return min(6, abs(Spring.step(age, response: 0.5, damping: 0.78).1) * 0.45)
    }
}

// MARK: - Full-window effects

/// Particles are a pure function of (seed, particle, time), so seeking and pausing just work.
struct ScreenEffectCanvas: View {
    let cue: EffectCue
    let t: Double
    var blur: Double = 1

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let fade = min(1, max(0, (EffectCue.duration - t) / 0.5))
            ctx.opacity = fade
            switch cue.effect {
            case .confetti: confetti(&ctx, size)
            case .balloons: balloons(&ctx, size)
            case .hearts: hearts(&ctx, size)
            case .sparkles: sparkles(&ctx, size)
            case .fireworks: fireworks(&ctx, size)
            }
        }
        .allowsHitTesting(false)
    }

    private func r(_ i: Int, _ k: Int) -> Double {
        var x = cue.seed ^ (UInt64(i) &* 0x9E37_79B9_7F4A_7C15) ^ (UInt64(k) &* 0xD1B5_4A32_D192_ED03)
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x >> 11) / Double(1 << 53)
    }

    private static let party: [Color] = [
        Color(red: 1, green: 0.3, blue: 0.4), Color(red: 1, green: 0.75, blue: 0.2), Color(red: 0.3, green: 0.8, blue: 0.4),
        Color(red: 0.2, green: 0.6, blue: 1), Color(red: 0.7, green: 0.4, blue: 1), Color(red: 1, green: 0.5, blue: 0.8),
    ]

    private func confetti(_ ctx: inout GraphicsContext, _ size: CGSize) {
        // Ghost copies a few ms back in time read as motion blur.
        // Longer, stronger trails as the blur amount goes up.
        let ghosts: [(Double, Double)] = blur > 0.01
            ? [(0, 1)] + (1...Int(min(6, 2 + blur))).map { (0.016 * Double($0) * blur, 0.4 / Double($0)) }
            : [(0, 1)]
        for i in 0..<110 {
            for (lag, alpha) in ghosts {
                let tt = t - r(i, 0) * 0.8 - lag
                guard tt > 0 else { continue }
                let x = r(i, 1) * size.width + sin(tt * (2 + r(i, 2) * 3) + r(i, 3) * 6) * 18
                let y = -20 + tt * size.height * (0.28 + r(i, 4) * 0.22) + 40 * tt * tt
                var c = ctx
                c.opacity *= alpha
                c.translateBy(x: x, y: y)
                c.rotate(by: .radians(tt * (3 + r(i, 5) * 6)))
                c.scaleBy(x: cos(tt * (4 + r(i, 6) * 4)), y: 1)   // fake 3D flip
                c.fill(Path(CGRect(x: -3, y: -5, width: 6, height: 10)),
                       with: .color(Self.party[i % Self.party.count]))
            }
        }
    }

    private func balloons(_ ctx: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<11 {
            let start = size.height + 60 + r(i, 0) * 260
            let speed = (size.height + 400) / (2.4 + r(i, 1) * 0.8)
            let y = start - speed * t
            let x = r(i, 2) * size.width + sin(t * 1.5 + r(i, 3) * 6) * 14
            let w = 40 + r(i, 4) * 12
            let h = w * 1.22
            let color = Self.party[i % Self.party.count]
            var string = Path()
            string.move(to: CGPoint(x: x, y: y + h / 2))
            string.addCurve(to: CGPoint(x: x + 4, y: y + h / 2 + 70),
                            control1: CGPoint(x: x - 10, y: y + h / 2 + 25),
                            control2: CGPoint(x: x + 12, y: y + h / 2 + 45))
            ctx.stroke(string, with: .color(.gray.opacity(0.6)), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)), with: .color(color))
            ctx.fill(Path(ellipseIn: CGRect(x: x - w * 0.28, y: y - h * 0.32, width: w * 0.22, height: h * 0.18)),
                     with: .color(.white.opacity(0.45)))
        }
    }

    private func hearts(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let heart = ctx.resolve(Image(systemName: "heart.fill"))
        for i in 0..<24 {
            let delay = r(i, 0) * 1.4
            let tt = t - delay
            guard tt > 0 else { continue }
            let x = size.width * (0.15 + r(i, 1) * 0.7) + sin(tt * 2 + r(i, 2) * 6) * 20
            let y = size.height + 20 - tt * size.height * (0.35 + r(i, 3) * 0.25)
            let s = (14 + r(i, 4) * 26) * min(1, tt * 2.5)
            var c = ctx
            c.opacity = max(0, 1 - tt / 2.6)
            let tints = [Color(red: 1, green: 0.25, blue: 0.4), Color(red: 1, green: 0.45, blue: 0.65), Color(red: 0.95, green: 0.15, blue: 0.3)]
            c.addFilter(.colorMultiply(tints[i % 3]))
            c.draw(heart, in: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s))
        }
    }

    private func sparkles(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let star = ctx.resolve(Image(systemName: "sparkle"))
        for i in 0..<45 {
            let x = r(i, 0) * size.width
            let y = r(i, 1) * size.height + t * 18
            let twinkle = max(0, sin(t * (3 + r(i, 2) * 4) + r(i, 3) * 6))
            let s = (8 + r(i, 4) * 18) * (0.6 + 0.4 * twinkle)
            var c = ctx
            c.opacity = twinkle * min(1, t * 2)
            c.addFilter(.colorMultiply(i % 3 == 0 ? Color(red: 1, green: 0.85, blue: 0.4) : .white))
            c.draw(star, in: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s))
        }
    }

    private func fireworks(_ ctx: inout GraphicsContext, _ size: CGSize) {
        for b in 0..<4 {
            let start = Double(b) * 0.55
            let tt = t - start
            guard tt > 0, tt < 1.8 else { continue }
            let cx = size.width * (0.2 + r(b, 100) * 0.6)
            let cy = size.height * (0.15 + r(b, 101) * 0.35)
            let color = Self.party[(b * 2 + Int(r(b, 102) * 6)) % Self.party.count]
            for p in 0..<40 {
                let angle = Double(p) / 40 * 2 * .pi + r(b, p) * 0.2
                let v = 110 + r(b, p + 50) * 70
                let x = cx + cos(angle) * v * tt
                let y = cy + sin(angle) * v * tt + 60 * tt * tt
                var c = ctx
                c.opacity = max(0, 1 - tt / 1.6)
                c.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(color))
                c.fill(Path(ellipseIn: CGRect(x: x - cos(angle) * 8 * tt - 1, y: y - sin(angle) * 8 * tt - 1, width: 2, height: 2)),
                       with: .color(color.opacity(0.5)))
            }
        }
    }
}
