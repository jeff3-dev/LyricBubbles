import SwiftUI

// MARK: - Style: Postcards
//
// Each song is one retro travel poster in a cream paper border: a coast, a beach, a desert
// road, a rooftop, a harbour, a lake, a forest or the mountains, gently alive (palms sway,
// lights twinkle, water glints, clouds drift, windows come on). The place is the song's
// "vibe": decoded from its words and album art, random, or picked in the controls. The lyrics
// live inside the picture (neon on a wall, a roadside billboard, a banner towed by a plane,
// or letters painted across the sky) and change page by page on the same poster.
//
// Scenes are built once per seed (PostcardScene) and drawn in one Canvas (PostcardRenderer).

struct PostcardView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(PostcardSettings.storageKey) private var settings = PostcardSettings()
    @State private var grain: CGImage?
    @State private var script: PostcardScriptCache
    @State private var hovering = false
    @State private var showControls = false

    /// The demo reel passes a script it has already built, so switching is instant.
    init(model: PlayerModel, script: PostcardScriptCache? = nil) {
        self.model = model
        _script = State(initialValue: script ?? PostcardScriptCache())
    }

    var body: some View {
        // Every display frame (no minimum interval): a 60 fps cap stutters on 120 Hz screens.
        TimelineView(.animation) { ctx in
            let s = settings
            let pos = model.position(at: ctx.date) + leadTime
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let audio = model.audio.sample(at: ctx.date)
            let pages = currentPages()
            let snap = model.snapshot
            let kind = sceneKind(s.vibe)

            GeometryReader { geo in
                let frame = PostcardFrame.make(pages: pages, pos: pos, t: t, size: geo.size, s: s, kind: kind, art: model.artPalette,
                                               title: snap?.title ?? "",
                                               caption: snap.map { "\($0.title) · \($0.artist)" } ?? "",
                                               level: audio.level, beat: audio.beat, grain: grain)
                PostcardCanvas(frame: frame)
            }
        }
        .overlay(alignment: .topTrailing) { controlsButton }
        .background(Color(red: 0.925, green: 0.912, blue: 0.886))
        .ignoresSafeArea()
        .onHover { h in withAnimation(.easeInOut(duration: 0.2)) { hovering = h } }
        .task { grain = await PostcardGrain.shared.value }
    }

    /// The place for the current song's poster, or nil to let the seed pick.
    private func sceneKind(_ vibe: PostcardVibe) -> PCKind? {
        switch vibe {
        case .random: return nil
        case .decode:
            guard case .active(let snap) = model.status, !model.loadingLyrics else { return nil }
            var lyrics: [String] = []
            if case .synced(let lines) = model.lyrics { lyrics = lines.map(\.text) }
            return script.decoded(title: snap.title, artist: snap.artist, lyrics: lyrics, art: model.artPalette)
        default: return vibe.kind
        }
    }

    private func currentPages() -> [PCPage] {
        switch model.status {
        case .notRunning: return PostcardScript.message("Open Spotify")
        case .stopped: return PostcardScript.message("press play")
        case .error: return PostcardScript.message("no signal")
        case .active(let snap):
            if model.loadingLyrics { return PostcardScript.message("…") }
            switch model.lyrics {
            case .synced(let lines): return script.pages(lines, title: snap.title)
            case .instrumental: return PostcardScript.instrumental(snap.title)
            case .plainOnly: return PostcardScript.message("no timed lyrics")
            case .notFound, .none: return PostcardScript.message("no lyrics found")
            }
        }
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
        .popover(isPresented: $showControls, arrowEdge: .bottom) { PostcardControls() }
        .help("Postcards controls")
        .padding(.top, 10)
        .padding(.trailing, 12)
        .opacity(hovering || showControls ? 1 : 0)
    }
}

/// The whole poster in one GPU-backed canvas.
struct PostcardCanvas: View {
    let frame: PostcardFrame

    var body: some View {
        Canvas { ctx, _ in PostcardRenderer.draw(&ctx, frame) }
            .drawingGroup()
    }
}

// MARK: - Script

struct PCLine: Equatable {
    var text: String
    var start: Double
    var end: Double
}

/// One page of lyrics (or a quiet stretch) and the seed its poster grows from (the same for the whole song).
struct PCPage: Equatable {
    var start: Double
    var seed: UInt64
    var lines: [PCLine]
}

enum PostcardScript {
    /// Crossfade between posters, in seconds.
    static let transition = 1.6

    static func make(lines: [LyricLine], title: String) -> [PCPage] {
        let seed = LyricPages.hash(title)   // one poster for the whole song
        return LyricPages.make(lines: lines, intro: title.isEmpty ? nil : title, maxRows: 8).map { p in
            PCPage(start: p.start, seed: seed,
                   lines: p.lines.map { PCLine(text: $0.line.text.trimmingCharacters(in: .whitespaces), start: $0.line.time, end: $0.next) })
        }
    }

    /// A single poster holding a status message.
    static func message(_ text: String) -> [PCPage] {
        [PCPage(start: -1000, seed: LyricPages.hash("message|" + text), lines: text.isEmpty ? [] : [PCLine(text: text, start: -1000, end: .infinity)])]
    }

    /// No words: the song's poster on its own.
    static func instrumental(_ title: String) -> [PCPage] {
        [PCPage(start: -1000, seed: LyricPages.hash(title), lines: [])]
    }

    static func index(_ pages: [PCPage], pos: Double) -> Int {
        var i = 0
        for (k, p) in pages.enumerated() where p.start <= pos { i = k }
        return i
    }
}

final class PostcardScriptCache {
    private var key = ""
    private var cached: [PCPage] = []

    func pages(_ lines: [LyricLine], title: String) -> [PCPage] {
        let k = "\(title)|\(lines.count)|\(lines.first?.id ?? 0)|\(lines.last?.time ?? 0)|\(lines.map(\.section).reduce(0, &+))"
        if k != key {
            key = k
            cached = PostcardScript.make(lines: lines, title: title)
        }
        return cached
    }

    /// The last place decoded, shown in the controls.
    nonisolated(unsafe) static var lastDecoded: PCKind?
    private var vibeKey = ""
    private var vibe: PCKind = .coast

    /// The song's decoded place, worked out once per song (again if the album art arrives later).
    func decoded(title: String, artist: String, lyrics: [String], art: [Color]) -> PCKind {
        let k = "\(title)|\(artist)|\(lyrics.count)|\(art.isEmpty)"
        if k != vibeKey {
            vibeKey = k
            vibe = PCVibeDecoder.decode(title: title, lyrics: lyrics, art: art.map { NeonRGB($0) },
                                        seed: LyricPages.hash(title + "|" + artist))
            Self.lastDecoded = vibe
        }
        return vibe
    }
}

/// Built scenes, kept by seed (a song has a dozen or so).
enum PCSceneCache {
    private static var cache: [UInt64: PCScene] = [:]
    private static let lock = NSLock()

    static func scene(_ seed: UInt64, kind: PCKind? = nil) -> PCScene {
        let key = kind.map { seed ^ (UInt64($0.rawValue + 1) << 56) } ?? seed
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let s = PCScene.make(seed: seed, kind: kind)
        lock.lock()
        if cache.count > 40 { cache = [:] }
        cache[key] = s
        lock.unlock()
        return s
    }
}

// MARK: - Frame

struct PCLyric {
    var text: String
    var age: Double     // seconds since the line started
    var dur: Double
    var alpha: Double
}

struct PCShot {
    var scene: PCScene
    var palette: PCPalette
    var age: Double     // seconds since the poster appeared
    var lyrics: [PCLyric]
}

struct PostcardFrame {
    var size: CGSize
    var s: PostcardSettings
    var t: Double
    var level = 0.0
    var beat = 0.0
    var shot: PCShot
    var prev: PCShot?
    var mix = 1.0
    var heading = ""
    var prevHeading = ""
    var caption = ""
    var grain: CGImage?

    var music: Bool { s.motion == .music }
    /// Ambient motion multiplier (1 at the default "mild").
    var amount: Double { s[.amount] * 2 }

    static func make(pages: [PCPage], pos: Double, t: Double, size: CGSize, s: PostcardSettings, kind: PCKind? = nil,
                     art: [Color], title: String, caption: String, level: Double, beat: Double, grain: CGImage?) -> PostcardFrame {
        let album = s.paletteMode == .album ? PCPalette.album(art) : nil
        let pages = pages.isEmpty ? PostcardScript.message("") : pages
        let i = PostcardScript.index(pages, pos: pos)
        let cur = shot(pages[i], pos: pos, album: album, kind: kind, since: pages[0].start)
        var f = PostcardFrame(size: size, s: s, t: t, level: level, beat: beat, shot: cur, grain: grain)
        f.caption = caption
        f.heading = heading(cur.scene, s, title)
        if i > 0, pages[i - 1].seed != pages[i].seed {
            let k = (pos - pages[i].start) / PostcardScript.transition
            if k < 1 {
                let pv = shot(pages[i - 1], pos: pos, album: album, kind: kind)
                f.prev = pv
                f.mix = smoothstep(k)
                f.prevHeading = heading(pv.scene, s, title)
            }
        }
        return f
    }

    static func heading(_ scene: PCScene, _ s: PostcardSettings, _ title: String) -> String {
        switch s.heading {
        case .place: scene.place
        case .song: title
        case .off: ""
        }
    }

    /// A page on its poster. `since` is when the poster first showed (the song's start), so
    /// the camera drift carries on smoothly across pages; nil starts it at the page.
    static func shot(_ page: PCPage, pos: Double, album: [NeonRGB]?, kind: PCKind? = nil, since: Double? = nil) -> PCShot {
        let scene = PCSceneCache.scene(page.seed, kind: kind)
        let palette = PCPalette.make(album ?? PCPalette.bases[scene.paletteIndex], time: scene.time)
        var lyrics: [PCLyric] = []
        if let j = page.lines.lastIndex(where: { $0.start <= pos }) {
            let l = page.lines[j]
            let out = smoothstep((pos - l.end) / 0.5)
            if out < 1 { lyrics.append(PCLyric(text: l.text, age: pos - l.start, dur: l.end - l.start, alpha: 1 - out)) }
            if j > 0 {
                let p = page.lines[j - 1]
                let k = (pos - l.start) / 0.35
                if k < 1 { lyrics.insert(PCLyric(text: p.text, age: pos - p.start, dur: 99, alpha: 1 - smoothstep(k)), at: 0) }
            }
        }
        return PCShot(scene: scene, palette: palette, age: pos - max(since ?? page.start, pos - 3600), lyrics: lyrics)
    }

    /// One poster with one line, for the dashboard card and preview renders.
    static func still(seed: UInt64, kind: PCKind?, text: String, lineAge: Double, age: Double, t: Double,
                      size: CGSize, s: PostcardSettings, grain: CGImage?) -> PostcardFrame {
        let scene = PCSceneCache.scene(seed, kind: kind)
        let pal = PCPalette.make(PCPalette.bases[scene.paletteIndex], time: scene.time)
        let lyrics = text.isEmpty ? [] : [PCLyric(text: text, age: lineAge, dur: 3, alpha: 1)]
        var f = PostcardFrame(size: size, s: s, t: t, shot: PCShot(scene: scene, palette: pal, age: age, lyrics: lyrics), grain: grain)
        f.heading = heading(scene, s, "Song")
        f.caption = "Song · Artist"
        return f
    }
}

// MARK: - Grain

enum PostcardGrain {
    static let shared: Task<CGImage?, Never> = Task.detached(priority: .userInitiated) { make() }

    /// Grey noise around mid-grey, drawn with an overlay blend for film grain.
    static func make(side: Int = 1024) -> CGImage? {
        var px = [UInt8](repeating: 128, count: side * side)
        var s: UInt64 = 0x2545_F491_4F6C_DD1D
        for i in 0..<px.count {
            s ^= s << 13; s ^= s >> 7; s ^= s << 17
            px[i] = UInt8(truncatingIfNeeded: 64 + Int(s % 128))
        }
        guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - Dashboard preview

struct PostcardPreview: View {
    @State private var grain: CGImage?
    private static let lines = ["golden hour", "drive me home", "under palm trees", "say it again", "city lights", "hold on"]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let slot = Int(t / 5)
            let age = t - Double(slot) * 5
            Canvas { g, size in
                var s = PostcardSettings()
                s[.size] = 0.8
                let kind = PCKind.allCases[slot % PCKind.allCases.count]
                let f = PostcardFrame.still(seed: UInt64(slot % 24) &* 7919 &+ 3, kind: kind, text: Self.lines[slot % Self.lines.count],
                                            lineAge: age, age: age + 10, t: t, size: size, s: s, grain: grain)
                PostcardRenderer.draw(&g, f)
            }
        }
        .drawingGroup()
        .task { grain = await PostcardGrain.shared.value }
    }
}
