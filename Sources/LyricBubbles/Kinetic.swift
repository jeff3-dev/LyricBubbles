import AppKit
import SwiftUI

// MARK: - View

/// Kinetic: each line builds as a small stack of words, then its strongest word flies at the
/// camera and fills the screen, tilted, before the line flies past and the next one pops in.
struct KineticView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(KineticSettings.storageKey) private var settings = KineticSettings()
    @State private var scripts = KineticScriptCache()
    @State private var art: CGImage?
    @State private var textures: KineticTextures?
    @State private var hovering = false
    @State private var showControls = false

    var body: some View {
        // Every display frame (no minimum interval): a 60 fps cap stutters on 120 Hz screens.
        TimelineView(.animation) { ctx in
            let s = settings
            let pos = model.position(at: ctx.date) + leadTime
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let audio = model.audio.sample(at: ctx.date)
            let lines = currentLines(s)

            GeometryReader { geo in
                KineticCanvas(frame: KineticFrame(size: geo.size, pos: pos, t: t, beat: audio.beat, level: audio.level,
                                                  lines: KineticScript.visible(lines, at: pos, s: s), s: s,
                                                  palette: s.palette(model.artPalette), art: art, tex: textures))
            }
        }
        .overlay(alignment: .bottom) { caption }
        .overlay(alignment: .topTrailing) { controlsButton }
        .background(Color.black)
        .ignoresSafeArea()
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hovering = h } }
        .task { textures = await KineticTextures.shared.value }
        .task(id: model.snapshot?.artworkURL) {
            guard let url = model.snapshot?.artworkURL else { art = nil; return }
            let img = await KineticArtStore.shared.image(for: url)
            if model.snapshot?.artworkURL == url { art = img }
        }
    }

    private func currentLines(_ s: KineticSettings) -> [KineticLine] {
        switch model.status {
        case .notRunning: return KineticScript.message("Open Spotify")
        case .stopped: return KineticScript.message("press play")
        case .error: return KineticScript.message("no signal")
        case .active:
            if model.loadingLyrics { return KineticScript.message("…") }
            switch model.lyrics {
            case .synced(let lines): return scripts.lines(lines, bigChance: s[.bigWords], emoji: s.flag(.emoji))
            case .instrumental: return KineticScript.message("no words just vibes")
            case .plainOnly: return KineticScript.message("no timed lyrics")
            case .notFound, .none: return KineticScript.message("no lyrics found")
            }
        }
    }

    private var caption: some View {
        Group {
            if let s = model.snapshot {
                Text("\(s.title) · \(s.artist)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .padding(.bottom, 12)
                    .padding(.horizontal, 20)
            }
        }
        .allowsHitTesting(false)
    }

    private var controlsButton: some View {
        Button { showControls.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showControls, arrowEdge: .bottom) { KineticControls() }
        .help("Kinetic controls")
        .padding(.top, 10)
        .padding(.trailing, 12)
        .opacity(hovering || showControls ? 1 : 0)
    }
}

/// The whole scene in one GPU-backed canvas.
struct KineticCanvas: View {
    let frame: KineticFrame

    var body: some View {
        Canvas { ctx, _ in
            KineticScenes.draw(&ctx, frame)
            KineticRenderer.draw(&ctx, frame)
        }
        .drawingGroup()
        .clipped()
    }
}

struct KineticFrame {
    var size: CGSize
    var pos: Double
    var t: Double
    var beat: Double
    var level: Double
    var lines: [KineticLine]
    var s: KineticSettings
    var palette: [NeonRGB]
    var art: CGImage?
    var tex: KineticTextures?
}

// MARK: - Script: which words, when, and which one goes big

struct KineticLine {
    struct Word {
        let text: String
        let emoji: String?
        let time: Double
        var small: String { text + (emoji ?? "") }
        /// The huge version: no emoji, no trailing comma.
        var big: String {
            var t = text
            while let c = t.last, ",.;:".contains(c), t.count > 1 { t.removeLast() }
            return t
        }
    }
    let id: Int
    let start: Double
    let end: Double          // when it flies away
    let words: [Word]
    let rows: [[Int]]        // word indices on each row of the small stack
    let big: Int?            // the word that flies in huge
    let seed: UInt64
}

enum KineticScript {
    static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "so", "to", "of", "in", "on", "at", "for", "by", "with", "from",
        "i", "im", "i'm", "me", "my", "you", "your", "youre", "you're", "we", "our", "us", "he", "she", "it", "its",
        "it's", "they", "them", "their", "is", "am", "are", "was", "were", "be", "been", "do", "did", "does", "dont",
        "don't", "can", "cant", "can't", "will", "would", "could", "should", "just", "that", "this", "these", "those",
        "oh", "ooh", "yeah", "ya", "uh", "na", "la", "hey", "if", "when", "then", "than", "up", "out", "all", "got",
        "get", "like", "what", "who", "how", "now", "no", "not", "yes", "too", "into", "onto", "ill", "i'll", "ive",
        "i've", "id", "i'd", "let", "lets", "let's", "gonna", "wanna", "gotta", "there", "here", "where", "some",
    ]

    /// Extra emoji the shared table doesn't have.
    static let extraEmoji: [String: String] = [
        "eye": "👁️", "eyes": "👁️", "smoke": "💨", "smokin": "💨", "green": "💚", "blue": "💙", "gold": "🪙",
        "diamond": "💎", "diamonds": "💎", "devil": "😈", "angel": "😇", "ghost": "👻", "crown": "👑",
    ]

    static func key(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0 == "'" }.replacingOccurrences(of: "’", with: "'")
    }

    static func emoji(for word: String) -> String? {
        let k = key(word)
        if let e = extraEmoji[k] { return e }
        return EmojiMap.table.first { $0.0.contains(k) }?.1.first
    }

    static func make(lines: [LyricLine], bigChance: Double, emoji: Bool) -> [KineticLine] {
        var out: [KineticLine] = []
        for (i, l) in lines.enumerated() {
            let text = l.text.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text != "♪" else { continue }
            // Ends when the next line (blank or not) starts, held at most 7 s.
            let next = i + 1 < lines.count ? lines[i + 1].time : l.time + 5
            let end = min(next, l.time + 7)
            out.append(line(id: l.id, text: text, start: l.time, end: max(l.time + 0.4, end),
                            bigChance: bigChance, emoji: emoji))
        }
        return out
    }

    static func line(id: Int, text: String, start: Double, end: Double, bigChance: Double, emoji: Bool) -> KineticLine {
        var raw = text.split(separator: " ").map(String.init)
        if raw.isEmpty { raw = [text] }
        let seed = LyricPages.hash("\(id)|\(text)")

        // Words reveal across most of the line, letter-weighted, ~0.4 s each at most.
        let span = min((end - start) * 0.72, Double(raw.count) * 0.42)
        let weights = raw.map { Double(max(1, key($0).count)) + 1.5 }
        let total = weights.reduce(0, +)
        var acc = 0.0
        // At most one emoji per line, after the last word that has one.
        let emojiAt = emoji ? raw.indices.last { self.emoji(for: raw[$0]) != nil } : nil
        var words: [KineticLine.Word] = []
        for (j, w) in raw.enumerated() {
            words.append(.init(text: w, emoji: j == emojiAt ? self.emoji(for: w) : nil, time: start + span * acc / total))
            acc += weights[j]
        }

        // The strongest word: longest that isn't filler, nudged toward emoji words and the rhyme.
        var big: Int?
        var rng = Seeded(seed)
        if bigChance > 0, raw.count <= 2 || rng.next() < bigChance {
            var best = -1.0
            for (j, w) in raw.enumerated() {
                let k = key(w)
                guard k.count >= 2, !stopWords.contains(k) || raw.count <= 2 else { continue }
                var score = Double(k.count)
                if self.emoji(for: w) != nil { score += 2 }
                if j == raw.count - 1 { score += 1.2 }
                if score >= best { best = score; big = j }   // ties go to the later word
            }
        }

        // Rows: one word each, two short neighbours may share. The big word gets its own.
        var rows: [[Int]] = []
        for j in raw.indices {
            if let last = rows.last, last.count == 1, last[0] != big, j != big,
               key(raw[last[0]]).count + key(raw[j]).count <= 7 {
                rows[rows.count - 1].append(j)
            } else {
                rows.append([j])
            }
        }
        return KineticLine(id: id, start: start, end: end, words: words, rows: rows, big: big, seed: seed)
    }

    static func message(_ text: String) -> [KineticLine] {
        [line(id: -7, text: text, start: -1_000_000, end: .infinity, bigChance: 0, emoji: false)]
    }

    /// Lines on screen now: the current one and any still flying away.
    static func visible(_ lines: [KineticLine], at pos: Double, s: KineticSettings) -> [KineticLine] {
        let exit = KineticTiming(s).exit
        return lines.filter { pos >= $0.start - 0.05 && pos < $0.end + exit * 0.3 }
    }
}

/// Built once per song and setting change.
final class KineticScriptCache {
    private var key = ""
    private var cached: [KineticLine] = []

    func lines(_ lines: [LyricLine], bigChance: Double, emoji: Bool) -> [KineticLine] {
        let k = "\(lines.count)|\(lines.first?.id ?? 0)|\(lines.first?.time ?? 0)|\(lines.last?.time ?? 0)|\(lines.first?.text ?? "")|\(bigChance)|\(emoji)"
        if k != key {
            key = k
            cached = KineticScript.make(lines: lines, bigChance: bigChance, emoji: emoji)
        }
        return cached
    }
}

struct KineticTiming {
    let pop, fly, exit, back, hold: Double
    init(_ s: KineticSettings) {
        let sp = 0.6 + s[.speed] * 0.9
        pop = 0.24 / sp
        fly = 0.42 / sp
        exit = 0.34 / sp
        back = 0.3 / sp
        hold = 1.1 / sp
    }
}

// MARK: - Renderer

enum KineticRenderer {
    /// Where one word sits at a moment.
    struct Placement {
        var word: Int
        var center: CGPoint
        var scale: Double      // relative to the text it is drawn with
        var rotation: Double
        var shear: Double
        var alpha: Double
        var bigText: Bool      // drawn with the big resolved text
    }

    static func draw(_ ctx: inout GraphicsContext, _ f: KineticFrame) {
        let W = f.size.width, H = f.size.height
        guard W > 10, H > 10 else { return }
        let fs = min(W, H) * 0.085 * (0.6 + f.s[.size] * 0.8)
        let pal = f.palette.isEmpty ? KineticColors.sunset.fixed : f.palette
        let timing = KineticTiming(f.s)
        let blur = f.s[.motionBlur]

        for line in f.lines {
            var rng = Seeded(line.seed)
            let shift = Int(rng.next() * 9)
            let font = f.s.font

            // Resolve every word once: small, and the big one at full size.
            var small: [GraphicsContext.ResolvedText] = []
            var widths: [CGFloat] = []
            for (j, w) in line.words.enumerated() {
                let c = pal[(shift + j) % pal.count]
                let r = ctx.resolve(Text(w.small).font(font.font(fs)).foregroundColor(c.color))
                small.append(r)
                widths.append(r.measure(in: CGSize(width: 10_000, height: 10_000)).width)
            }
            var bigResolved: GraphicsContext.ResolvedText?
            var bigFS = fs
            if let b = line.big {
                let bw = ctx.resolve(Text(line.words[b].big).font(font.font(fs))).measure(in: CGSize(width: 10_000, height: 10_000)).width
                let k = min(W * 0.86 / max(1, bw), H * 0.48 / fs)
                bigFS = fs * max(1, k)
                let c = pal[(shift + b) % pal.count]
                bigResolved = ctx.resolve(Text(line.words[b].big).font(font.font(bigFS)).foregroundColor(c.color))
            }
            let geo = Geo(W: W, H: H, fs: fs, bigFS: bigFS, widths: widths)

            // Motion blur: earlier moments drawn faintly behind, while things move fast.
            if blur > 0 {
                let now = placements(line, f.pos, f.t, f, timing, geo)
                for k in stride(from: 4, through: 1, by: -1) {
                    let then = placements(line, f.pos - Double(k) * 0.014, f.t, f, timing, geo)
                    for p in then {
                        guard let q = now.first(where: { $0.word == p.word && $0.bigText == p.bigText }) else { continue }
                        let moved = abs(q.scale - p.scale) / max(0.05, q.scale) + hypot(q.center.x - p.center.x, q.center.y - p.center.y) / fs
                        guard moved > 0.02 else { continue }
                        var g = p
                        g.alpha *= min(1, moved * 3) * blur * 0.32 * (1 - Double(k) / 5)
                        render(&ctx, g, small, bigResolved)
                    }
                }
            }
            for p in placements(line, f.pos, f.t, f, timing, geo) {
                render(&ctx, p, small, bigResolved)
            }
        }
    }

    struct Geo {
        let W, H, fs, bigFS: CGFloat
        let widths: [CGFloat]
    }

    private static func render(_ ctx: inout GraphicsContext, _ p: Placement,
                               _ small: [GraphicsContext.ResolvedText], _ big: GraphicsContext.ResolvedText?) {
        guard p.alpha > 0.004, p.scale > 0.001 else { return }
        let text: GraphicsContext.ResolvedText
        if p.bigText, let big { text = big } else { text = small[p.word] }
        var c = ctx
        c.opacity = min(1, p.alpha)
        c.translateBy(x: p.center.x, y: p.center.y)
        c.rotate(by: .radians(p.rotation))
        c.concatenate(CGAffineTransform(a: 1, b: 0, c: p.shear, d: 1, tx: 0, ty: 0))
        c.scaleBy(x: p.scale, y: p.scale)
        c.draw(text, at: .zero, anchor: .center)
    }

    /// Every visible word of a line at time `pos`.
    static func placements(_ line: KineticLine, _ pos: Double, _ t: Double, _ f: KineticFrame,
                           _ tm: KineticTiming, _ g: Geo) -> [Placement] {
        var rng = Seeded(line.seed)
        _ = rng.next()
        let tilt = f.s[.tilt]
        let ox = (rng.next() - 0.5) * g.W * 0.16
        let oy = (rng.next() - 0.5) * g.H * 0.1
        let stackRot = (rng.next() - 0.5) * 0.14 * tilt
        let side: Double = rng.next() < 0.5 ? -1 : 1
        let bigDX = (rng.next() - 0.5) * g.W * 0.06
        let floatPhase = rng.next() * 6.28

        let pulse = 1 + 0.05 * f.beat * f.s[.pulse]
        // The exit starts a little before the next line so the two barely overlap.
        let ex = max(0, min(1, (pos - line.end + tm.exit * 0.7) / tm.exit))
        let exitScale = 1 + 2.4 * ex * ex
        let exitAlpha = 1 - smoothstep(ex)

        // Big word phases.
        let b = line.big
        let tb = b.map { line.words[$0].time } ?? .infinity
        let hasAfter = b.map { $0 < line.words.count - 1 } ?? false
        let holdEnd = hasAfter ? min(line.end - 0.15, tb + tm.hold) : .infinity
        let bigIn = max(0, min(1, (pos - tb) / tm.fly))
        let back = hasAfter ? max(0, min(1, (pos - holdEnd) / tm.back)) : 0
        let recede = easeOut(bigIn) * (1 - easeInOut(back))

        // The stack.
        let center = CGPoint(x: g.W / 2 + ox, y: g.H / 2 + oy + sin(t * 0.8 + floatPhase) * g.fs * 0.06)
        let rowH = g.fs * 1.04
        let stackH = rowH * CGFloat(line.rows.count)
        let gap = g.fs * 0.26
        let S = (1 - 0.3 * recede) * exitScale * pulse
        let stackAlpha = (1 - 0.88 * recede) * exitAlpha

        func toScreen(_ local: CGPoint) -> CGPoint {
            let x = local.x * S, y = local.y * S
            return CGPoint(x: center.x + x * cos(stackRot) - y * sin(stackRot),
                           y: center.y + x * sin(stackRot) + y * cos(stackRot))
        }

        var out: [Placement] = []
        var afterCount = 0
        for (r, row) in line.rows.enumerated() {
            let rowW = row.map { g.widths[$0] }.reduce(0, +) + gap * CGFloat(row.count - 1)
            var x = -rowW / 2
            let y = -stackH / 2 + rowH * (CGFloat(r) + 0.5)
            for j in row {
                let local = CGPoint(x: x + g.widths[j] / 2, y: y)
                x += g.widths[j] + gap
                if j == b && back < 1 { continue }   // the big word is drawn on its own until it has landed back
                var appear = line.words[j].time
                if j == b { appear = -.infinity }
                if let b, j > b {
                    appear = max(appear, holdEnd + 0.05 + 0.08 * Double(afterCount))
                    afterCount += 1
                }
                let a = max(0, min(1, (pos - appear) / tm.pop))
                guard a > 0 else { continue }
                var p = toScreen(local)
                p.y += (1 - easeOut(a)) * g.fs * 0.5 * S
                out.append(Placement(word: j, center: p, scale: S * (0.4 + 0.6 * easeOutBack(a)),
                                     rotation: stackRot, shear: 0, alpha: stackAlpha * smoothstep(a * 1.6), bigText: false))
            }
        }

        // The big word: flies in from behind the camera, settles tilted, creeps closer, then
        // either drops back into its slot in the stack or leaves with the line.
        if let b, pos >= tb, back < 1 {
            let e = easeOut3(bigIn)
            let creep = 1 + 0.05 * min(2, max(0, pos - tb - tm.fly))
            let bigCenter = CGPoint(x: g.W / 2 + bigDX, y: g.H / 2)
            let rot = side * tilt * (0.09 + 0.3 * (1 - e))
            let shear = side * tilt * 0.24 * (1 - 0.45 * e)
            var big = Placement(word: b, center: bigCenter, scale: (3.2 + (1 - 3.2) * e) * creep * pulse,
                                rotation: rot, shear: shear, alpha: smoothstep(bigIn * 2.5), bigText: true)
            if back > 0 {
                // Find the slot.
                var slot = CGPoint.zero
                for (r, row) in line.rows.enumerated() where row.contains(b) {
                    slot = CGPoint(x: 0, y: -stackH / 2 + rowH * (CGFloat(r) + 0.5))
                }
                let k = easeInOut(back)
                let target = toScreen(slot)
                let smallScale = S * g.fs / g.bigFS
                big.center = CGPoint(x: big.center.x + (target.x - big.center.x) * k,
                                     y: big.center.y + (target.y - big.center.y) * k)
                big.scale = big.scale + (smallScale - big.scale) * k
                big.rotation = rot + (stackRot - rot) * k
                big.shear = shear * (1 - k)
                big.alpha = stackAlpha
            } else {
                big.scale *= exitScale
                big.alpha *= 1 - smoothstep(ex * 1.6)
            }
            out.append(big)
        }
        return out
    }

    static func easeOut(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }
    static func easeOut3(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func easeInOut(_ x: Double) -> Double { x * x * (3 - 2 * x) }
    static func easeOutBack(_ x: Double) -> Double {
        let c = 1.9
        return 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2)
    }
}

// MARK: - Dashboard preview

struct KineticPreview: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.2, green: 0.38, blue: 0.95), Color(red: 0.12, green: 0.2, blue: 0.62)],
                           startPoint: .top, endPoint: .bottom)
            Capsule()
                .fill(Color(red: 0.95, green: 0.82, blue: 0.7).opacity(0.55))
                .frame(width: 240, height: 34)
                .rotationEffect(.degrees(-8))
                .blur(radius: 14)
                .offset(x: 10, y: -8)
            VStack(spacing: -4) {
                Text("look").foregroundStyle(Color(red: 0.98, green: 0.8, blue: 0.3))
                Text("in my").foregroundStyle(Color(red: 0.96, green: 0.27, blue: 0.2))
            }
            .font(.custom("Futura-Bold", size: 15))
            .offset(x: -70, y: -28)
            .opacity(0.6)
            Text("eyes")
                .font(.custom("Futura-Bold", size: 84))
                .foregroundStyle(Color(red: 0.96, green: 0.27, blue: 0.2))
                .rotation3DEffect(.degrees(22), axis: (x: 0.2, y: 1, z: -0.15), perspective: 0.6)
                .offset(x: 18, y: 8)
        }
    }
}
