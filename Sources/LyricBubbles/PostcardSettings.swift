import SwiftUI

// MARK: - Postcards settings

enum PostcardLettering: Int, CaseIterable, Identifiable {
    case auto, poster, script, deco, serif
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .auto: "Matches the sign"
        case .poster: "Poster"
        case .script: "Script"
        case .deco: "Deco"
        case .serif: "Serif"
        }
    }

    static let posterFace = GlyphFace(name: "AvenirNext-Heavy", space: 0.28, lineHeight: 1.05)
    static let scriptFace = GlyphFace(name: "SnellRoundhand-Black", space: 0.26, lineHeight: 1.0)
    static let decoFace = GlyphFace(name: "Futura-CondensedExtraBold", space: 0.26, lineHeight: 1.02)
    static let serifFace = GlyphFace(name: "Didot-Bold", space: 0.3, lineHeight: 1.08)

    /// The face for a sign. Auto picks script for neon, deco for the sky, poster otherwise.
    func face(for kind: PCSurfaceKind, caps: Bool = false) -> GlyphFace {
        switch self {
        case .auto:
            switch kind {
            case .neon: caps ? Self.decoFace : Self.scriptFace
            case .sky: Self.decoFace
            case .board, .banner: Self.posterFace
            }
        case .poster: Self.posterFace
        case .script: Self.scriptFace
        case .deco: Self.decoFace
        case .serif: Self.serifFace
        }
    }

    var previewFont: String {
        switch self {
        case .auto, .poster: Self.posterFace.name
        case .script: Self.scriptFace.name
        case .deco: Self.decoFace.name
        case .serif: Self.serifFace.name
        }
    }
}

enum PostcardPaletteMode: Int, CaseIterable, Identifiable {
    case poster, album
    var id: Int { rawValue }
    var label: String { self == .poster ? "Poster colours" : "Album art" }
}

enum PostcardMotion: Int, CaseIterable, Identifiable {
    case ambient, music
    var id: Int { rawValue }
    var label: String { self == .ambient ? "Gentle ambient" : "Ambient + music" }
}

enum PostcardHeading: Int, CaseIterable, Identifiable {
    case place, song, off
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .place: "Place name"
        case .song: "Song title"
        case .off: "None"
        }
    }
}

/// Which place a song's poster shows: decoded from the song, random, or one the user picked.
enum PostcardVibe: Int, CaseIterable, Identifiable {
    case decode, random, coast, beach, desert, city, harbor, lake, forest, mountains
    var id: Int { rawValue }

    /// The picked place, or nil for decode and random.
    var kind: PCKind? { rawValue >= 2 ? PCKind(rawValue: rawValue - 2) : nil }

    var label: String {
        switch self {
        case .decode: "Decode from song"
        case .random: "Surprise me"
        default: kind?.label ?? ""
        }
    }

    var symbol: String {
        switch self {
        case .decode: "wand.and.stars"
        case .random: "dice"
        default: kind?.symbol ?? "photo"
        }
    }
}

/// Guesses a song's place from its words, then its album art, then its title.
enum PCVibeDecoder {
    static let words: [PCKind: [String]] = [
        .city: ["city", "cities", "street", "downtown", "uptown", "neon", "traffic", "subway", "skyline", "taxi",
                "avenue", "boulevard", "building", "rooftop", "club", "party", "dance", "dancing", "lights", "town",
                "block", "hood", "concrete", "elevator", "penthouse", "broadway", "tokyo", "york", "paris", "london",
                "money", "cash", "metro", "sirens", "billboard", "apartment"],
        .beach: ["beach", "sand", "sandy", "summer", "surf", "surfing", "island", "tropical", "paradise", "bikini",
                 "palm", "palms", "margarita", "vacation", "hawaii", "sunshine", "tan", "coconut", "waves", "cabana",
                 "barefoot", "malibu", "miami", "caribbean"],
        .coast: ["coast", "cliff", "cliffs", "riviera", "ocean", "oceans", "sea", "seas", "shore", "breeze", "salt",
                 "horizon", "seaside", "coastline", "california", "pacific", "atlantic", "tide", "tides"],
        .harbor: ["harbor", "harbour", "boat", "boats", "ship", "ships", "sail", "sailing", "sailor", "dock", "docks",
                  "port", "anchor", "lighthouse", "captain", "pier", "bay", "marina", "ferry", "yacht", "voyage"],
        .desert: ["desert", "dust", "dusty", "highway", "road", "roads", "drive", "driving", "miles", "cowboy",
                  "western", "vegas", "heat", "dry", "cactus", "outlaw", "gasoline", "truck", "route", "motel",
                  "canyon", "texas", "nevada", "arizona", "mirage", "thirst"],
        .lake: ["lake", "lakes", "pond", "reflection", "reflections", "cabin", "calm", "stillness", "dock",
                "mirror", "canoe", "loon", "shallow", "drown", "drowning", "ripple", "ripples"],
        .forest: ["forest", "forests", "woods", "tree", "trees", "leaves", "leaf", "green", "wolf", "wolves", "deer",
                  "moss", "river", "rivers", "creek", "stream", "pine", "pines", "branches", "roots", "garden",
                  "flowers", "flower", "bloom", "wilderness", "rain", "fern", "owl", "bear"],
        .mountains: ["mountain", "mountains", "hill", "hills", "valley", "valleys", "peak", "peaks", "climb",
                     "climbing", "summit", "snow", "snowy", "eagle", "eagles", "rocky", "heights", "alps", "altitude",
                     "glacier", "avalanche", "ridge", "everest"],
    ]

    private static let index: [String: [PCKind]] = {
        var d: [String: [PCKind]] = [:]
        for (k, ws) in words { for w in ws { d[w, default: []].append(k) } }
        return d
    }()

    static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    /// Scores each place by its words. Title words count three times.
    static func scores(title: String, lyrics: [String]) -> [PCKind: Double] {
        var score: [PCKind: Double] = [:]
        func count(_ text: String, _ weight: Double) {
            for t in tokens(text) {
                guard let ks = index[t] ?? (t.hasSuffix("s") ? index[String(t.dropLast())] : nil) else { continue }
                for k in ks { score[k, default: 0] += weight }
            }
        }
        count(title, 3)
        for l in lyrics { count(l, 1) }
        return score
    }

    static func decode(title: String, lyrics: [String], art: [NeonRGB], seed: UInt64) -> PCKind {
        let score = scores(title: title, lyrics: lyrics)
        let ranked = score.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
        if let best = ranked.first, best.value >= 2, best.value > (ranked.dropFirst().first?.value ?? 0) {
            return best.key
        }
        let pick = Int(PCRand.mix(seed ^ 0xA5A5) % 1000)
        if let byArt = fromArt(art) { return byArt[pick % byArt.count] }
        return PCKind.allCases[pick % PCKind.allCases.count]
    }

    /// Places that suit the album art's main colour, or nil if there's no art.
    static func fromArt(_ art: [NeonRGB]) -> [PCKind]? {
        guard !art.isEmpty else { return nil }
        var hx = 0.0, hy = 0.0, lum = 0.0
        for c in art {
            let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), sat = mx - mn
            lum += (0.3 * c.r + 0.59 * c.g + 0.11 * c.b) / Double(art.count)
            guard sat > 0.15 else { continue }
            var h: Double
            if mx == c.r { h = (c.g - c.b) / sat } else if mx == c.g { h = 2 + (c.b - c.r) / sat } else { h = 4 + (c.r - c.g) / sat }
            h *= .pi / 3
            hx += cos(h) * sat
            hy += sin(h) * sat
        }
        guard hx * hx + hy * hy > 0.01 else { return lum < 0.35 ? [.city] : [.lake, .mountains] }
        var deg = atan2(hy, hx) * 180 / .pi
        if deg < 0 { deg += 360 }
        switch deg {
        case ..<20, 330...: return [.desert, .city]
        case ..<50: return [.desert, .beach]
        case ..<80: return [.beach, .coast]
        case ..<170: return [.forest, .mountains]
        case ..<250: return lum < 0.3 ? [.mountains, .lake] : [.coast, .harbor, .lake]
        default: return [.city, .harbor]
        }
    }
}

/// Postcards settings, stored as one JSON dictionary.
struct PostcardSettings: RawRepresentable, Equatable {
    enum Key: String, CaseIterable {
        case palette, motion, amount, drift, grain, frame, heading, chips, lettering, size, caps, vibe

        var fallback: Double {
            switch self {
            case .palette: 0
            case .motion: 0
            case .amount: 0.5
            case .drift: 0.5
            case .grain: 0.5
            case .frame: 1
            case .heading: 0
            case .chips: 1
            case .lettering: 0
            case .size: 0.6
            case .caps: 0
            case .vibe: 0
            }
        }
    }

    static let storageKey = "postcardSettings"

    var values: [String: Double] = [:]

    init() {}

    init?(rawValue: String) {
        values = (try? JSONDecoder().decode([String: Double].self, from: Data(rawValue.utf8))) ?? [:]
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(values) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    subscript(_ key: Key) -> Double {
        get { values[key.rawValue] ?? key.fallback }
        set { values[key.rawValue] = newValue }
    }

    func flag(_ key: Key) -> Bool { self[key] > 0.5 }
    var paletteMode: PostcardPaletteMode { PostcardPaletteMode(rawValue: Int(self[.palette])) ?? .poster }
    var motion: PostcardMotion { PostcardMotion(rawValue: Int(self[.motion])) ?? .ambient }
    var heading: PostcardHeading { PostcardHeading(rawValue: Int(self[.heading])) ?? .place }
    var lettering: PostcardLettering { PostcardLettering(rawValue: Int(self[.lettering])) ?? .auto }
    var vibe: PostcardVibe { PostcardVibe(rawValue: Int(self[.vibe])) ?? .decode }
}

// MARK: - Controls

/// Controls for the Postcards style. Shown in the window's popover and in Settings.
struct PostcardControls: View {
    @AppStorage(PostcardSettings.storageKey) private var settings = PostcardSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("Vibe")
                picker("Scene", "photo", .vibe, PostcardVibe.allCases.map { ($0.rawValue, $0.label) }) { v in
                    let vibe = PostcardVibe(rawValue: v) ?? .decode
                    Label(vibe.label, systemImage: vibe.symbol)
                }
                SettingHint(vibeHint)

                Divider()
                section("Poster")
                picker("Colours", "paintpalette", .palette, PostcardPaletteMode.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(PostcardPaletteMode(rawValue: v)?.label ?? "")
                }
                toggle("Paper border", "rectangle.inset.filled", .frame)
                picker("Heading", "textformat.size.larger", .heading, PostcardHeading.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(PostcardHeading(rawValue: v)?.label ?? "")
                }
                .disabled(!settings.flag(.frame))
                toggle("Colour chips", "square.grid.3x1.below.line.grid.1x2", .chips)
                    .disabled(!settings.flag(.frame))
                slider("Film grain", "circle.dotted", .grain, hint: nil)

                Divider()
                section("Motion")
                picker("Mode", "waveform", .motion, PostcardMotion.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(PostcardMotion(rawValue: v)?.label ?? "")
                }
                Text("Ambient + music flashes lights and signs on the beat (needs React to music).")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                slider("Liveliness", "wind", .amount, hint: "Palm sway, twinkling lights, waves and clouds")
                slider("Camera drift", "camera", .drift, hint: "A slow push in and pan across each poster")

                Divider()
                section("Lyrics")
                picker("Lettering", "textformat", .lettering, PostcardLettering.allCases.map { ($0.rawValue, $0.label) }) { v in
                    let l = PostcardLettering(rawValue: v) ?? .auto
                    Text(l.label).font(.custom(l.previewFont, size: 13))
                }
                slider("Size", "textformat.size", .size, hint: nil)
                toggle("Capitals", "textformat.abc", .caps)

                Divider()
                HStack {
                    Spacer()
                    Button("Reset All") { withAnimation { settings = PostcardSettings() } }
                        .controlSize(.small)
                }
            }
            .padding(16)
        }
        .playbackSettings("postcards")
        .frame(width: 320)
        .frame(maxHeight: 640)
    }

    private var vibeHint: String {
        switch settings.vibe {
        case .decode:
            let found = PostcardScriptCache.lastDecoded.map { " This song: \($0.label)." } ?? ""
            return "Reads the title and lyrics for places (city, ocean, trees…), then the album art's colours." + found
        case .random: return "Each song gets a place of its own, picked from its title."
        default: return "Every song is set here. Each one still gets its own time of day and colours."
        }
    }

    private func binding(_ key: PostcardSettings.Key) -> Binding<Double> {
        Binding(get: { settings[key] }, set: { settings[key] = $0 })
    }

    private func section(_ title: String) -> some View {
        SettingSection(title)
    }

    private func picker<L: View>(_ title: String, _ symbol: String, _ key: PostcardSettings.Key,
                                 _ options: [(Int, String)], @ViewBuilder label: @escaping (Int) -> L) -> some View {
        Picker(selection: Binding(get: { Int(settings[key]) }, set: { settings[key] = Double($0) })) {
            ForEach(options, id: \.0) { v, _ in label(v).tag(v) }
        } label: {
            SettingLabel(title: title, symbol: symbol)
        }
    }

    private func toggle(_ title: String, _ symbol: String, _ key: PostcardSettings.Key) -> some View {
        SettingToggle(title: title, symbol: symbol, isOn: Binding(get: { settings.flag(key) }, set: { settings[key] = $0 ? 1 : 0 }))
    }

    private func slider(_ title: String, _ symbol: String, _ key: PostcardSettings.Key, hint: String?) -> some View {
        SettingSlider(title: title, symbol: symbol, value: Binding(get: { settings[key] }, set: { settings[key] = $0 }), hint: hint)
    }
}
