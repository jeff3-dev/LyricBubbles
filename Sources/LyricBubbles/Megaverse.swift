import AppKit
import SwiftUI

// MARK: - View

/// Megaverse: a procedural, music-reactive world in one of four looks (Art Deco, Jazz Noir,
/// Comic Book, Neon Retro). Each song section cuts to a new place, with the words placed in
/// the scene: balloons, title cards, signage or typewriter captions.
struct MegaverseView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(MegaSettings.storageKey) private var settings = MegaSettings()
    @State private var director = MegaDirector()
    @State private var art: CGImage?
    @State private var hovering = false
    @State private var showControls = false

    var body: some View {
        // Every display frame (no minimum interval): a 60 fps cap stutters on 120 Hz screens.
        TimelineView(.animation) { ctx in
            let s = settings
            let pos = model.position(at: ctx.date) + leadTime
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let audio = model.audio.sample(at: ctx.date)
            GeometryReader { geo in
                MegaCanvas(frame: director.frame(size: geo.size, pos: pos, t: t, audio: audio, s: s, input: input(s),
                                                 palette: s.palette(model.artPalette), art: s.flag(.coverArt) ? art : nil))
            }
        }
        .overlay(alignment: .bottom) { caption }
        .overlay(alignment: .topTrailing) { controlsButton }
        .background(Color.black)
        .ignoresSafeArea()
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hovering = h } }
        .task(id: "\(model.snapshot?.artworkURL?.absoluteString ?? "")|\(settings.look.rawValue)|\(Int(settings[.artStrength] * 10))") {
            guard let url = model.snapshot?.artworkURL else { art = nil; return }
            let img = await MegaArtStore.shared.image(for: url, look: settings.look, strength: settings[.artStrength])
            if model.snapshot?.artworkURL == url { art = img }
        }
    }

    private func input(_ s: MegaSettings) -> MegaInput {
        let snap = model.snapshot
        var i = MegaInput(songKey: snap.map { $0.trackID.isEmpty ? "\($0.title)|\($0.artist)" : $0.trackID } ?? "",
                          title: snap?.title ?? "", artist: snap?.artist ?? "", singers: max(1, model.cast.names.count))
        switch model.status {
        case .notRunning: i.message = "Open Spotify"
        case .stopped: i.message = "Press play"
        case .error: i.message = "No signal"
        case .active:
            if model.loadingLyrics { break }
            if case .synced(let lines) = model.lyrics, s.flag(.lyrics) { i.lines = lines }
        }
        return i
    }

    private var caption: some View {
        Group {
            if let s = model.snapshot {
                Text("\(s.title) · \(s.artist)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .shadow(color: .black.opacity(0.6), radius: 2)
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
        .popover(isPresented: $showControls, arrowEdge: .bottom) {
            MegaQuickControls(showsMoreButton: true).padding(16).frame(width: 360)
        }
        .help("Megaverse controls")
        .padding(.top, 10)
        .padding(.trailing, 12)
        .opacity(hovering || showControls ? 1 : 0)
    }
}

/// The whole scene in one GPU-backed canvas.
struct MegaCanvas: View {
    let frame: MegaFrame

    var body: some View {
        Canvas { ctx, _ in
            MegaRenderer.draw(&ctx, frame)
        }
        .drawingGroup()
        .clipped()
    }
}

// MARK: - Frame

/// What the view knows about the song this frame.
struct MegaInput {
    var songKey: String
    var title: String
    var artist: String
    var singers: Int
    var lines: [LyricLine]? = nil
    var message: String? = nil
}

/// One shot: a location, its variant and the camera framing, from one cut to the next.
struct MegaShot {
    var index: Int
    var scene: MegaScene
    var start: Double
    var zoom: Double
    var pan: CGPoint
}

struct MegaLyric {
    var text: String
    var start: Double
    var end: Double
    var singer: Int
    var next: String?
}

struct MegaCard {
    var title: String
    var sub: String
    var alpha: Double
}

struct MegaFrame {
    var size: CGSize
    var pos: Double
    var t: Double
    var beat: Double
    var level: Double
    var s: MegaSettings
    var palette: MegaPalette
    var shot: MegaShot
    var prev: MegaShot?
    var cut: Double               // transition progress, 1 when done
    var lyric: MegaLyric?
    var header: (text: String, age: Double)?
    var card: MegaCard?
    var hit: (age: Double, id: Int)?
    var art: CGImage?
    var title: String
    var artist: String
    var singers: Int
    var tex: MegaTextures = .shared
    var beats = 0                                     // beats counted so far (marquee chase)
    var lastHit: (age: Double, id: Int) = (100, 0)    // the latest accent hit, however old (billiards, crates)
}

// MARK: - Director: cuts, words and accent hits

/// Works out the shot, the words on screen and the accent hits. Cuts are planned from the
/// lyrics (per section or every N lines), or follow energy changes and a timer when there
/// are no lyrics. Everything is seeded per song, so a song always looks the same.
final class MegaDirector {
    private var planKey = ""
    private var cuts: [Double] = []
    private var labels: [Int: String] = [:]
    private var sectionStart: [Int: Double] = [:]
    // Energy pacing state.
    private var dynIndex = 0, dynStart = -1.0, lastPos = -1.0, lastT = 0.0
    private var slow = 0.0, fast = 0.0
    private var dynKey = ""
    // Accent hits.
    private var hitID = 0, hitT = -100.0, armed = true
    private var beatCount = 0, beatArmed = true

    func frame(size: CGSize, pos: Double, t: Double, audio: (level: Double, beat: Double), s: MegaSettings,
               input: MegaInput, palette: MegaPalette, art: CGImage?) -> MegaFrame {
        let seed = LyricPages.hash(input.songKey.isEmpty ? "megaverse" : input.songKey)
        let lines = (input.lines ?? []).filter { !Self.blank($0.text) }
        let live = audio.level > 0.001 || audio.beat > 0.001

        // Without audio, pulse on each new line so the scene still reacts.
        var level = audio.level, beat = audio.beat
        if !live {
            level = 0.42 + 0.08 * sin(t * 0.7)
            if let l = lines.last(where: { $0.time <= pos }) { beat = exp(-(pos - l.time) / 0.25) * 0.85 }
        }

        // Shot index and its start.
        let dt = max(0, min(0.2, t - lastT))
        lastT = t
        slow += (level - slow) * (1 - exp(-dt / 4))
        fast += (level - fast) * (1 - exp(-dt / 0.5))
        var index = 0, start = 0.0, prevStart = -1.0
        let energy = s[.energy]
        if !lines.isEmpty, s.pacing != .energy {
            plan(lines, s, key: "\(input.songKey)|\(lines.count)|\(s.pacing.rawValue)|\(Int(s[.cutLines]))")
            let k = cuts.lastIndex { $0 <= pos } ?? -1
            index = k + 1
            start = k >= 0 ? cuts[k] : -1000
            prevStart = k >= 1 ? cuts[k - 1] : -1000
        } else {
            if !lines.isEmpty { plan(lines, s, key: "\(input.songKey)|\(lines.count)|labels") }
            let maxLen = 22 - 10 * energy, minLen = 7 - 3 * energy
            let key = input.songKey
            if key != dynKey || pos < lastPos - 1.5 || pos > lastPos + 6 || dynStart < 0 {
                dynKey = key
                dynIndex = Int(max(0, pos) / maxLen)
                dynStart = pos < maxLen ? -1000 : pos - max(0, pos).truncatingRemainder(dividingBy: maxLen)
            }
            let age = pos - max(0, dynStart)
            if age > maxLen || (age > minLen && abs(fast - slow) > 0.22 - 0.08 * energy && live) {
                dynIndex += 1
                dynStart = pos
                slow = fast
            }
            index = dynIndex
            start = dynStart
        }
        lastPos = pos

        let shot = Self.shot(index, start: start, seed: seed, s: s)
        let dur = 1.15 - 0.55 * energy
        let cutP = index == 0 || start < -100 ? 1 : max(0, min(1, (pos - start) / dur))
        let prev = cutP < 1 ? Self.shot(index - 1, start: prevStart, seed: seed, s: s) : nil

        // Words.
        var lyric: MegaLyric?
        var header: (String, Double)?
        if let i = (input.lines ?? []).lastIndex(where: { $0.time <= pos }), let all = input.lines {
            let l = all[i]
            let nextT = i + 1 < all.count ? all[i + 1].time : l.time + 6
            let end = min(nextT, l.time + 8)
            if !Self.blank(l.text), pos < end {
                let next = all[(i + 1)...].first { !Self.blank($0.text) }
                lyric = MegaLyric(text: l.text.trimmingCharacters(in: .whitespaces), start: l.time, end: end, singer: l.singer,
                                  next: s.flag(.showNext) ? next?.text : nil)
            }
            if let label = labels[l.section], let st = sectionStart[l.section] { header = (label, pos - st) }
        }

        // Title card at the start (and for status messages).
        var card: MegaCard?
        if let m = input.message {
            card = MegaCard(title: m, sub: "", alpha: 1)
        } else if !input.title.isEmpty {
            let firstLine = lines.first?.time ?? .infinity
            let until = lines.isEmpty ? 8.0 : min(firstLine - 0.3, 12)
            if pos < until {
                let a = min(1, max(0, (pos + 0.5) / 0.8)) * min(1, max(0, (until - pos) / 0.6))
                card = MegaCard(title: input.title, sub: input.artist, alpha: a)
            }
        }

        // Accent hits on strong beats, rate-limited by energy and the Accent amount.
        let minGap = 1.5 - 0.7 * energy
        if beat > 0.72, armed, t - hitT > minGap {
            armed = false
            var r = Seeded(seed &+ UInt64(hitID + 1) &* 7919)
            if r.next() < 0.3 + 0.7 * s[.accentsAmt] {
                hitID += 1
                hitT = t
            }
        }
        if beat < 0.4 { armed = true }
        if beat > 0.6, beatArmed { beatCount += 1; beatArmed = false }
        if beat < 0.35 { beatArmed = true }
        let hitAge = t - hitT
        let hit: (Double, Int)? = hitAge < 1.3 && hitAge >= 0 ? (hitAge, hitID) : nil

        return MegaFrame(size: size, pos: pos, t: t, beat: beat, level: level, s: s, palette: palette, shot: shot, prev: prev,
                         cut: cutP, lyric: lyric, header: header, card: card, hit: hit, art: art,
                         title: input.title, artist: input.artist, singers: input.singers,
                         beats: beatCount, lastHit: (max(0, hitAge), hitID))
    }

    static func blank(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t == "♪"
    }

    /// Cut times (sections or every N lines) and the section labels: a section whose first
    /// line comes back later is a chorus, the rest are verses.
    private func plan(_ lines: [LyricLine], _ s: MegaSettings, key: String) {
        guard key != planKey else { return }
        planKey = key
        cuts = []
        labels = [:]
        sectionStart = [:]
        var firsts: [Int: String] = [:]
        for l in lines where sectionStart[l.section] == nil {
            sectionStart[l.section] = l.time
            firsts[l.section] = l.text.lowercased().filter { $0.isLetter }
        }
        var counts: [String: Int] = [:]
        for f in firsts.values { counts[f, default: 0] += 1 }
        var verse = 0
        for sec in sectionStart.keys.sorted() {
            if counts[firsts[sec] ?? ""] ?? 0 > 1 {
                labels[sec] = "CHORUS"
            } else {
                verse += 1
                labels[sec] = sec == sectionStart.keys.sorted().last && verse > 2 ? "OUTRO" : "VERSE \(verse)"
            }
        }
        switch s.pacing {
        case .lines:
            let n = max(1, Int(s[.cutLines]))
            for (i, l) in lines.enumerated() where i > 0 && i % n == 0 { cuts.append(l.time - 0.15) }
        default:
            for sec in sectionStart.keys.sorted() where sec != lines.first?.section {
                if let t = sectionStart[sec] { cuts.append(t - 0.15) }
            }
        }
        // Long gaps (intro, solos) still cut every ~14 s.
        var filled: [Double] = []
        var last = 0.0
        for c in cuts + [lines.last.map { $0.time + 30 } ?? 0] {
            var x = last + 14
            while c - x > 6 { filled.append(x); x += 14 }
            filled.append(c)
            last = c
        }
        filled.removeLast()
        cuts = filled.filter { $0 > 0.5 }.sorted()
    }

    /// The location, variant and framing of shot `k` for this song.
    static func shot(_ k: Int, start: Double, seed: UInt64, s: MegaSettings) -> MegaShot {
        let locs = s.locations
        let n = locs.count
        var loc = locs[0]
        switch s.order {
        case .inOrder: loc = locs[((k % n) + n) % n]
        case .stay: loc = locs[Int(seed % UInt64(n))]
        case .shuffle:
            func perm(_ b: Int) -> [MegaLocation] {
                var r = Seeded(seed &+ UInt64(max(0, b) + 1) &* 104_729)
                var p = locs
                for i in stride(from: p.count - 1, to: 0, by: -1) { p.swapAt(i, Int(r.next() * Double(i + 1))) }
                return p
            }
            let b = max(0, k) / n, i = max(0, k) % n
            var p = perm(b)
            if b > 0, n > 1, p[0] == perm(b - 1)[n - 1] { p.swapAt(0, 1) }
            loc = p[i]
        }
        var r = Seeded(seed &+ UInt64(max(0, k) + 7) &* 15_485_863)
        let variant = Int(r.next() * 3)
        let zoom = 1.0 + r.next() * 0.16
        let pan = CGPoint(x: (r.next() - 0.5) * 180, y: (r.next() - 0.5) * 50)
        return MegaShot(index: k, scene: MegaScenes.scene(loc, variant: variant), start: start, zoom: zoom, pan: pan)
    }
}

// MARK: - Dashboard preview

struct MegaversePreview: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.2), Color(red: 0.02, green: 0.03, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            // Sunburst over a stepped skyline with neon edges.
            Canvas { ctx, size in
                let o = CGPoint(x: size.width / 2, y: size.height * 0.95)
                let gold = Color(red: 0.93, green: 0.73, blue: 0.3)
                for i in 0..<16 where i % 2 == 0 {
                    let a0 = Double.pi + Double.pi * Double(i) / 16, a1 = Double.pi + Double.pi * Double(i + 1) / 16
                    var p = Path()
                    p.move(to: o)
                    p.addLine(to: CGPoint(x: o.x + cos(a0) * 400, y: o.y + sin(a0) * 400))
                    p.addLine(to: CGPoint(x: o.x + cos(a1) * 400, y: o.y + sin(a1) * 400))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(gold.opacity(0.16)))
                }
                let heights: [CGFloat] = [40, 64, 52, 90, 70, 104, 66, 84, 50, 72, 44, 58]
                let bw = size.width / CGFloat(heights.count)
                for (i, h) in heights.enumerated() {
                    let r = CGRect(x: CGFloat(i) * bw + 1.5, y: size.height - h, width: bw - 3, height: h)
                    ctx.fill(Path(r), with: .color(Color(red: 0.03, green: 0.05, blue: 0.12)))
                    if i % 3 == 0 { ctx.stroke(Path(r), with: .color(Color(red: 1, green: 0.3, blue: 0.65).opacity(0.85)), lineWidth: 1.5) }
                    for y in stride(from: r.minY + 8, to: r.maxY - 6, by: 12) where (Int(y) + i) % 3 != 0 {
                        ctx.fill(Path(CGRect(x: r.midX - 3, y: y, width: 6, height: 5)), with: .color(gold.opacity(0.7)))
                    }
                }
            }
            // Comic balloon.
            Text("MEANWHILE…")
                .font(.custom("ChalkboardSE-Bold", size: 11))
                .foregroundStyle(.black)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Rectangle().fill(Color(red: 1, green: 0.88, blue: 0.3)))
                .overlay(Rectangle().stroke(.black, lineWidth: 1.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
            Text("SING IT!")
                .font(.custom("ChalkboardSE-Bold", size: 16))
                .foregroundStyle(.black)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Ellipse().fill(.white))
                .overlay(Ellipse().stroke(.black, lineWidth: 2))
                .offset(x: 60, y: -18)
        }
    }
}
