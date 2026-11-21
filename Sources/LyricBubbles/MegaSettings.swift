import AppKit
import SwiftUI

// MARK: - Megaverse choices

/// The four art styles. Each one is its own renderer of the same scene description.
enum MegaLook: Int, CaseIterable, Identifiable {
    case deco, noir, comic, neon
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .deco: "Art Deco"
        case .noir: "Jazz Noir"
        case .comic: "Comic Book"
        case .neon: "Neon Retro"
        }
    }
    var short: String {
        switch self {
        case .deco: "Deco"
        case .noir: "Noir"
        case .comic: "Comic"
        case .neon: "Neon"
        }
    }
    /// Swatch colours for the look tiles.
    var swatch: [Color] {
        switch self {
        case .deco: [Color(red: 0.92, green: 0.72, blue: 0.3), Color(red: 0.05, green: 0.1, blue: 0.24)]
        case .noir: [Color(white: 0.85), Color(white: 0.04)]
        case .comic: [Color(red: 1, green: 0.85, blue: 0.2), Color(red: 0.9, green: 0.15, blue: 0.2)]
        case .neon: [Color(red: 1, green: 0.25, blue: 0.65), Color(red: 0.06, green: 0.03, blue: 0.16)]
        }
    }
    var symbol: String {
        switch self {
        case .deco: "sun.max.fill"
        case .noir: "cloud.rain.fill"
        case .comic: "burst.fill"
        case .neon: "lightbulb.max.fill"
        }
    }
}

/// The ten places. Only the built ones are drawn; the rest arrive in later phases.
enum MegaLocation: Int, CaseIterable, Identifiable {
    case lounge, stage, street, rooftop, billiards, marquee, records, train, staircase, office
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .lounge: "Lounge"
        case .stage: "Jazz Stage"
        case .street: "Rainy Street"
        case .rooftop: "Rooftop"
        case .billiards: "Billiard Room"
        case .marquee: "Theater Marquee"
        case .records: "Record Shop"
        case .train: "Train Platform"
        case .staircase: "Grand Staircase"
        case .office: "Detective Office"
        }
    }
    var symbol: String {
        switch self {
        case .lounge: "sofa.fill"
        case .stage: "music.mic"
        case .street: "cloud.rain"
        case .rooftop: "building.2.fill"
        case .billiards: "circle.circle"
        case .marquee: "theatermasks.fill"
        case .records: "opticaldisc"
        case .train: "tram.fill"
        case .staircase: "stairs"
        case .office: "magnifyingglass"
        }
    }
    var built: Bool { rawValue < 7 }
    var key: MegaSettings.Key { MegaSettings.Key(rawValue: "loc\(rawValue)")! }
    static var builtCases: [MegaLocation] { allCases.filter(\.built) }
}

/// A colour set for the scene: deep background, mid tone, accent, warm lamp light and a pop.
struct MegaPalette: Equatable {
    var base, mid, accent, warm, pop, sky: NeonRGB

    subscript(_ hue: MegaHue) -> NeonRGB {
        switch hue {
        case .base: base
        case .mid: mid
        case .accent: accent
        case .warm: warm
        case .pop: pop
        case .sky: sky
        }
    }
}

enum MegaHue { case base, mid, accent, warm, pop, sky }

/// Mood presets: palette plus time of day, weather and fog.
enum MegaMood: Int, CaseIterable, Identifiable {
    case smoky, rain, gala, red, blue, album
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .smoky: "Smoky Lounge"
        case .rain: "Midnight Rain"
        case .gala: "Gilded Gala"
        case .red: "Red Room"
        case .blue: "Blue Hour"
        case .album: "Album Colours"
        }
    }

    var palette: MegaPalette {
        switch self {
        case .smoky, .album:
            MegaPalette(base: NeonRGB(0.09, 0.06, 0.07), mid: NeonRGB(0.38, 0.24, 0.19), accent: NeonRGB(0.88, 0.58, 0.26),
                        warm: NeonRGB(1, 0.78, 0.48), pop: NeonRGB(0.22, 0.6, 0.6), sky: NeonRGB(0.06, 0.05, 0.1))
        case .rain:
            MegaPalette(base: NeonRGB(0.03, 0.05, 0.11), mid: NeonRGB(0.16, 0.24, 0.38), accent: NeonRGB(0.36, 0.64, 0.9),
                        warm: NeonRGB(0.96, 0.86, 0.6), pop: NeonRGB(0.95, 0.3, 0.42), sky: NeonRGB(0.04, 0.06, 0.13))
        case .gala:
            MegaPalette(base: NeonRGB(0.04, 0.08, 0.19), mid: NeonRGB(0.08, 0.36, 0.4), accent: NeonRGB(0.93, 0.73, 0.3),
                        warm: NeonRGB(1, 0.9, 0.68), pop: NeonRGB(0.96, 0.9, 0.78), sky: NeonRGB(0.03, 0.06, 0.16))
        case .red:
            MegaPalette(base: NeonRGB(0.12, 0.02, 0.03), mid: NeonRGB(0.48, 0.07, 0.09), accent: NeonRGB(0.97, 0.22, 0.2),
                        warm: NeonRGB(1, 0.62, 0.45), pop: NeonRGB(0.97, 0.86, 0.68), sky: NeonRGB(0.1, 0.02, 0.04))
        case .blue:
            MegaPalette(base: NeonRGB(0.08, 0.1, 0.23), mid: NeonRGB(0.3, 0.34, 0.6), accent: NeonRGB(0.97, 0.56, 0.4),
                        warm: NeonRGB(1, 0.82, 0.55), pop: NeonRGB(0.56, 0.76, 1), sky: NeonRGB(0.22, 0.2, 0.42))
        }
    }

    /// Rain amount, smoke, fog and whether the sky is dusk rather than night.
    var rain: Double { switch self { case .rain: 1; case .blue: 0.25; case .smoky: 0; case .red: 0.1; default: 0 } }
    var smoke: Double { switch self { case .smoky: 1; case .red: 0.6; case .gala: 0.25; case .rain: 0.3; default: 0.35 } }
    var fog: Double { switch self { case .rain: 0.55; case .blue: 0.4; case .smoky: 0.45; default: 0.3 } }
    var dusk: Bool { self == .blue }

    var dot: Color { palette.accent.color }

    /// Album Colours: build a palette from the artwork's vivid colours.
    static func albumPalette(_ art: [Color]) -> MegaPalette? {
        guard !art.isEmpty else { return nil }
        let c = art.map(NeonRGB.init)
        let a = c[0], b = c.count > 1 ? c[1] : c[0].mixed(.white, 0.4), m = c.count > 2 ? c[2] : a.mixed(b, 0.5)
        let black = NeonRGB(0, 0, 0)
        return MegaPalette(base: a.mixed(black, 0.88), mid: m.mixed(black, 0.55), accent: a, warm: b.mixed(.white, 0.45),
                           pop: b, sky: a.mixed(black, 0.9))
    }
}

enum MegaOrder: Int, CaseIterable, Identifiable {
    case shuffle, inOrder, stay
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .shuffle: "Seeded shuffle"
        case .inOrder: "In order"
        case .stay: "Stay in one place"
        }
    }
}

enum MegaPacing: Int, CaseIterable, Identifiable {
    case section, lines, energy
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .section: "Every section"
        case .lines: "Every N lines"
        case .energy: "On energy shifts"
        }
    }
}

/// How the words sit in the scene. Auto picks the look's own: balloons for Comic, title
/// cards for Deco, signage for Neon and typewriter captions for Noir.
enum MegaPlacement: Int, CaseIterable, Identifiable {
    case auto, balloons, cards, signage
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .auto: "Auto"
        case .balloons: "Balloons & captions"
        case .cards: "Title cards"
        case .signage: "Signage"
        }
    }
}

enum MegaArtSpot: Int, CaseIterable, Identifiable {
    case frame, vinyl, both
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .frame: "Frame"
        case .vinyl: "Vinyl"
        case .both: "Both"
        }
    }
}

// MARK: - Settings

/// Every Megaverse control, stored as one JSON dictionary in UserDefaults.
/// Missing keys fall back to defaults, so adding a control never resets the others.
struct MegaSettings: RawRepresentable, Equatable {
    enum Key: String, CaseIterable {
        // Quick
        case look, mood, energy, lyrics, coverArt, characters, pin
        // Locations
        case loc0, loc1, loc2, loc3, loc4, loc5, loc6, loc7, loc8, loc9, order, pacing, cutLines
        // Look tuning
        case decoGold, decoRays, noirInk, noirHatch, noirRain, comicDot, comicMisreg, comicOutline, comicPaper
        case neonGlow, neonFlicker, neonReflect, grain, vignette
        // Reactions
        case lights, lightsAmt, accents, accentsAmt, camera, cameraAmt, weather, weatherAmt
        // Lyrics
        case placement, textSize, showNext
        // Cover art
        case artSpot, artStrength

        var fallback: Double {
            switch self {
            case .look: 0
            case .mood: 0
            case .energy: 0.55
            case .lyrics, .coverArt, .characters: 1
            case .loc0, .loc1, .loc2, .loc3, .loc4, .loc5, .loc6, .loc7, .loc8, .loc9: 1
            case .order: 0
            case .pin: -1
            case .pacing: 0
            case .cutLines: 4
            case .decoGold: 0.7
            case .decoRays: 0.5
            case .noirInk: 0.6
            case .noirHatch: 0.5
            case .noirRain: 0.6
            case .comicDot: 0.5
            case .comicMisreg: 0.4
            case .comicOutline: 0.55
            case .comicPaper: 0.5
            case .neonGlow: 0.6
            case .neonFlicker: 0.35
            case .neonReflect: 0.6
            case .grain: 0.3
            case .vignette: 0.5
            case .lights, .accents, .camera, .weather: 1
            case .lightsAmt: 0.6
            case .accentsAmt: 0.5
            case .cameraAmt: 0.5
            case .weatherAmt: 0.6
            case .placement: 0
            case .textSize: 0.5
            case .showNext: 0
            case .artSpot: 2
            case .artStrength: 0.65
            }
        }
    }

    static let storageKey = "megaverseSettings"

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

    var look: MegaLook { MegaLook(rawValue: Int(self[.look])) ?? .deco }
    var mood: MegaMood { MegaMood(rawValue: Int(self[.mood])) ?? .smoky }
    var order: MegaOrder { MegaOrder(rawValue: Int(self[.order])) ?? .shuffle }
    var pacing: MegaPacing { MegaPacing(rawValue: Int(self[.pacing])) ?? .section }
    var placement: MegaPlacement { MegaPlacement(rawValue: Int(self[.placement])) ?? .auto }
    var artSpot: MegaArtSpot { MegaArtSpot(rawValue: Int(self[.artSpot])) ?? .both }

    /// The locations that will be visited: switched on and built. Never empty.
    var locations: [MegaLocation] {
        if let p = pinned { return [p] }
        let on = MegaLocation.builtCases.filter { flag($0.key) }
        return on.isEmpty ? [.lounge] : on
    }

    /// The one scene to stay in, or nil to tour the switched-on locations.
    var pinned: MegaLocation? {
        guard let l = MegaLocation(rawValue: Int(self[.pin])), l.built else { return nil }
        return l
    }

    /// A reaction's strength (0 when switched off), scaled by Energy.
    func reaction(_ on: Key, _ amount: Key) -> Double {
        guard flag(on) else { return 0 }
        return self[amount] * (0.35 + 1.3 * self[.energy])
    }

    func palette(_ art: [Color]) -> MegaPalette {
        if mood == .album, let p = MegaMood.albumPalette(art) { return p }
        return mood.palette
    }

    /// Random look, mood and locations (always at least two built ones).
    mutating func surprise() {
        self[.look] = Double(Int.random(in: 0..<MegaLook.allCases.count))
        self[.mood] = Double(Int.random(in: 0..<MegaMood.allCases.count))
        for l in MegaLocation.allCases { self[l.key] = Bool.random() ? 1 : 0 }
        let built = MegaLocation.builtCases.shuffled()
        if locations.count < 2 { for l in built.prefix(2) { self[l.key] = 1 } }
        self[.energy] = Double.random(in: 0.3...0.85)
        self[.pin] = -1
    }
}

/// Named snapshots of the settings, saved by the user.
struct MegaPresets: RawRepresentable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
        var name: String
        var raw: String
        var id: String { name }
    }
    static let storageKey = "megaversePresets"
    var entries: [Entry] = []

    init() {}
    init?(rawValue: String) {
        entries = (try? JSONDecoder().decode([Entry].self, from: Data(rawValue.utf8))) ?? []
    }
    var rawValue: String {
        guard let data = try? JSONEncoder().encode(entries) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    mutating func save(_ name: String, _ s: MegaSettings) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        entries.removeAll { $0.name == n }
        entries.append(Entry(name: n, raw: s.rawValue))
    }
}

// MARK: - Controls

/// The Quick row: look, mood, energy, the three toggles, Surprise me and presets.
/// Shown alone in the window's popover and at the top of Settings ▸ Megaverse.
struct MegaQuickControls: View {
    @AppStorage(MegaSettings.storageKey) private var settings = MegaSettings()
    @AppStorage(MegaPresets.storageKey) private var presets = MegaPresets()
    @AppStorage("settingsPane") private var settingsPane = "messages"
    var showsMoreButton = false
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(MegaLook.allCases) { look in lookTile(look) }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Mood").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                FlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(MegaMood.allCases) { m in moodChip(m) }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label("Energy", systemImage: "bolt.fill").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(energyWord).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    SettingHint("Chill")
                    Slider(value: binding(.energy), in: 0...1).controlSize(.small)
                    SettingHint("Wild")
                }
            }

            MegaScenePicker()

            HStack(spacing: 14) {
                toggle("Lyrics", "text.quote", .lyrics)
                toggle("Cover art", "photo.artframe", .coverArt)
                toggle("Characters", "figure.stand", .characters)
            }

            HStack(spacing: 8) {
                Button { withAnimation { settings.surprise() } } label: { Label("Surprise me", systemImage: "dice.fill") }
                Button { newName = ""; naming = true } label: { Label("Save as preset", systemImage: "square.and.arrow.down") }
                Menu {
                    if presets.entries.isEmpty { Text("No saved presets yet") }
                    ForEach(presets.entries) { e in
                        Button(e.name) { if let s = MegaSettings(rawValue: e.raw) { withAnimation { settings = s } } }
                    }
                    if !presets.entries.isEmpty {
                        Divider()
                        Menu("Delete") {
                            ForEach(presets.entries) { e in
                                Button(e.name, role: .destructive) { presets.entries.removeAll { $0.name == e.name } }
                            }
                        }
                    }
                } label: { Label("My presets", systemImage: "star") }
                .fixedSize()
                if showsMoreButton {
                    Spacer(minLength: 0)
                    SettingsLink { Image(systemName: "gearshape") }
                        .simultaneousGesture(TapGesture().onEnded { settingsPane = "megaverse" })
                        .help("All Megaverse settings")
                }
            }
            .controlSize(.small)
        }
        .alert("Save as preset", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Save") { presets.save(newName, settings) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves every Megaverse setting under this name.")
        }
    }

    private var energyWord: String {
        switch settings[.energy] {
        case ..<0.25: "Chill"
        case ..<0.5: "Easy"
        case ..<0.75: "Lively"
        default: "Wild"
        }
    }

    private func lookTile(_ look: MegaLook) -> some View {
        let on = settings.look == look
        return Button { withAnimation { settings[.look] = Double(look.rawValue) } } label: {
            VStack(spacing: 4) {
                ZStack {
                    LinearGradient(colors: look.swatch, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: look.symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 2)
                }
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Color.accentColor : .clear, lineWidth: 2.5))
                Text(look.short).font(.system(size: 11, weight: on ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(look.label)
    }

    private func moodChip(_ m: MegaMood) -> some View {
        let on = settings.mood == m
        return Button { withAnimation { settings[.mood] = Double(m.rawValue) } } label: {
            HStack(spacing: 4) {
                if m == .album {
                    Image(systemName: "photo").font(.system(size: 9))
                } else {
                    Circle().fill(m.dot).frame(width: 8, height: 8)
                }
                Text(m.label).font(.system(size: 11))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(on ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12)))
            .overlay(Capsule().stroke(on ? Color.accentColor : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func binding(_ key: MegaSettings.Key) -> Binding<Double> {
        Binding(get: { settings[key] }, set: { settings[key] = $0 })
    }

    private func toggle(_ title: String, _ symbol: String, _ key: MegaSettings.Key) -> some View {
        SettingToggle(title: title, symbol: symbol, isOn: Binding(get: { settings.flag(key) }, set: { settings[key] = $0 ? 1 : 0 }))
    }
}

/// The full menu, coarse to fine: Quick, Locations, Look tuning, Reactions, Lyrics, Cover art.
struct MegaControls: View {
    @AppStorage(MegaSettings.storageKey) private var settings = MegaSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("Quick")
                MegaQuickControls()

                Divider()
                section("Locations")
                if let p = settings.pinned {
                    hint("Staying in the \(p.label). Pick Tour in the Scene picker above to visit the locations switched on here.")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 6)], spacing: 6) {
                    ForEach(MegaLocation.allCases) { l in locationChip(l) }
                }
                picker("Visit order", "shuffle", .order, MegaOrder.allCases.map { ($0.rawValue, $0.label) })
                picker("Pacing", "metronome", .pacing, MegaPacing.allCases.map { ($0.rawValue, $0.label) })
                if settings.pacing == .lines {
                    Stepper(value: Binding(get: { Int(settings[.cutLines]) }, set: { settings[.cutLines] = Double($0) }), in: 1...12) {
                        Label("Cut every \(Int(settings[.cutLines])) lines", systemImage: "scissors").font(.system(size: 12, weight: .medium))
                    }
                }
                hint("Without lyrics the scene cuts on energy changes or every few bars.")

                Divider()
                section("Look tuning · \(settings.look.label)")
                switch settings.look {
                case .deco:
                    slider("Gold", "sparkles", .decoGold, hint: "How much of the trim turns to gold leaf")
                    slider("Sunburst rays", "sun.max", .decoRays, hint: "Rays fanning out behind the scene")
                case .noir:
                    slider("Ink weight", "paintbrush.pointed", .noirInk, hint: "How hard the blacks are")
                    slider("Crosshatch", "number", .noirHatch, hint: "Pen hatching in the shadows")
                    slider("Rain", "cloud.rain", .noirRain, hint: "Rain on top of the mood's own weather")
                case .comic:
                    slider("Halftone dots", "circle.grid.3x3.fill", .comicDot, hint: "Size of the Ben-Day dots")
                    slider("Misregistration", "square.on.square", .comicMisreg, hint: "Colour printed slightly off the lines")
                    slider("Outline", "pencil.tip", .comicOutline, hint: "Ink line weight")
                    slider("Paper tone", "doc", .comicPaper, hint: "Yellowed newsprint")
                case .neon:
                    slider("Glow", "light.max", .neonGlow, hint: "Halo around the tubes")
                    slider("Tube flicker", "bolt.horizontal", .neonFlicker, hint: "Tubes stutter now and then")
                    slider("Reflections", "drop", .neonReflect, hint: "Wet ground mirroring the lights")
                }
                slider("Grain", "aqi.medium", .grain, hint: nil)
                slider("Vignette", "circle.dashed", .vignette, hint: nil)

                Divider()
                section("Reactions")
                hint("Each look has its own version. Energy sets the overall level on top. Needs React to music in Messages settings.")
                reaction("Lights", "lightbulb.led", .lights, .lightsAmt, reactionHint(0))
                reaction("Accent hits", "burst", .accents, .accentsAmt, reactionHint(1))
                reaction("Camera", "camera.aperture", .camera, .cameraAmt, reactionHint(2))
                reaction("Weather & smoke", "cloud.fog", .weather, .weatherAmt, reactionHint(3))

                Divider()
                section("Lyrics")
                picker("Placement", "text.bubble", .placement, MegaPlacement.allCases.map { ($0.rawValue, $0.label) })
                slider("Text size", "textformat.size", .textSize, hint: nil)
                toggle("Show the next line", "text.append", .showNext)

                Divider()
                section("Cover art")
                picker("Where", "photo.artframe", .artSpot, MegaArtSpot.allCases.map { ($0.rawValue, $0.label) })
                slider("Treatment", "wand.and.stars", .artStrength, hint: "How strongly the look restyles the album art")
                hint("Shown only where a place has a spot for it: a wall painting, poster, billboard or turntable.")

                Divider()
                HStack {
                    Spacer()
                    Button("Reset All") { withAnimation { settings = MegaSettings() } }
                        .controlSize(.small)
                }
            }
            .padding(16)
        }
        .playbackSettings("megaverse")
        .frame(minWidth: 340)
    }

    private func reactionHint(_ i: Int) -> String {
        let table: [MegaLook: [String]] = [
            .deco: ["Sunburst and sconces flare", "Gold sparkle bursts", "Punch zoom", "Dust in the light beams"],
            .noir: ["Lamps swing, key light flickers", "Lightning flashes", "Slow push", "Rain and cigarette smoke"],
            .comic: ["Colour pops in the halftone", "SFX bursts", "Panel jolts and shakes", "Speed lines and dust clouds"],
            .neon: ["Tubes brighten", "Tubes flicker and spark", "Punch and colour smear", "Steam and haze"],
        ]
        return table[settings.look]?[i] ?? ""
    }

    private func locationChip(_ l: MegaLocation) -> some View {
        let on = settings.flag(l.key)
        return Button { if l.built { settings[l.key] = on ? 0 : 1 } } label: {
            HStack(spacing: 5) {
                Image(systemName: l.symbol).font(.system(size: 11)).frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(l.label).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if !l.built { Text("Coming soon").font(.system(size: 9)).foregroundStyle(.tertiary) }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 7).fill(on && l.built ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(on && l.built ? Color.accentColor : .clear, lineWidth: 1))
            .opacity(l.built ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!l.built)
    }

    private func section(_ title: String) -> some View {
        SettingSection(title)
    }

    private func hint(_ text: String) -> some View {
        SettingHint(text)
    }

    private func picker(_ title: String, _ symbol: String, _ key: MegaSettings.Key, _ options: [(Int, String)]) -> some View {
        Picker(selection: Binding(get: { Int(settings[key]) }, set: { settings[key] = Double($0) })) {
            ForEach(options, id: \.0) { v, label in Text(label).tag(v) }
        } label: {
            SettingLabel(title: title, symbol: symbol)
        }
    }

    private func toggle(_ title: String, _ symbol: String, _ key: MegaSettings.Key) -> some View {
        Toggle(isOn: Binding(get: { settings.flag(key) }, set: { settings[key] = $0 ? 1 : 0 })) {
            SettingLabel(title: title, symbol: symbol)
        }
    }

    private func reaction(_ title: String, _ symbol: String, _ on: MegaSettings.Key, _ amt: MegaSettings.Key, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Toggle(isOn: Binding(get: { settings.flag(on) }, set: { settings[on] = $0 ? 1 : 0 })) {
                    SettingLabel(title: title, symbol: symbol)
                }
                Spacer()
                Text("\(Int((settings[amt] * 100).rounded()))%").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { settings[amt] }, set: { settings[amt] = $0 }), in: 0...1)
                .controlSize(.small)
                .disabled(!settings.flag(on))
            SettingHint(hint)
        }
    }

    private func slider(_ title: String, _ symbol: String, _ key: MegaSettings.Key, hint: String?) -> some View {
        SettingSlider(title: title, symbol: symbol, value: Binding(get: { settings[key] }, set: { settings[key] = $0 }), hint: hint)
    }
}

extension NeonRGB {
    static let black = NeonRGB(0, 0, 0)
}

// MARK: - Scene picker

/// Live thumbnails of each place, drawn in the current look and mood. Tour visits every
/// switched-on location; picking a place stays there for the whole song (the camera still
/// reframes on each cut). Picking it again goes back to the tour.
struct MegaScenePicker: View {
    @AppStorage(MegaSettings.storageKey) private var settings = MegaSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Scene").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(settings.pinned.map { "Staying in the \($0.label)" } ?? "Touring \(settings.locations.count) places")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
                tourTile
                ForEach(MegaLocation.builtCases) { l in sceneTile(l) }
            }
        }
    }

    private var tourTile: some View {
        let on = settings.pinned == nil
        return Button { withAnimation { settings[.pin] = -1 } } label: {
            VStack(spacing: 3) {
                ZStack {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
                        ForEach(MegaLocation.builtCases.prefix(4)) { l in
                            MegaThumb(location: l, settings: settings, size: CGSize(width: 48, height: 29))
                                .opacity(settings.flag(l.key) ? 1 : 0.25)
                        }
                    }
                    Image(systemName: "shuffle").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .shadow(color: .black, radius: 3)
                }
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.accentColor : .clear, lineWidth: 2.5))
                Text("Tour").font(.system(size: 11, weight: on ? .semibold : .regular))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Visit every switched-on location, a new one each section")
    }

    private func sceneTile(_ l: MegaLocation) -> some View {
        let on = settings.pinned == l
        return Button { withAnimation { settings[.pin] = on ? -1 : Double(l.rawValue) } } label: {
            VStack(spacing: 3) {
                MegaThumb(location: l, settings: settings, size: CGSize(width: 97, height: 60))
                    .frame(height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.accentColor : .clear, lineWidth: 2.5))
                    .overlay(alignment: .topTrailing) {
                        if on {
                            Image(systemName: "pin.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                .padding(4).background(Circle().fill(Color.accentColor)).padding(4)
                        }
                    }
                Text(l.label).font(.system(size: 11, weight: on ? .semibold : .regular)).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "Staying here. Click again to tour." : "Stay in the \(l.label) for the whole song")
    }
}

/// A still frame of one location in the current look and mood.
struct MegaThumb: View {
    let location: MegaLocation
    let settings: MegaSettings
    let size: CGSize

    var body: some View {
        MegaCanvas(frame: MegaFrame.thumbnail(location, settings: settings, size: CGSize(width: size.width * 2, height: size.height * 2)))
            .frame(width: size.width * 2, height: size.height * 2)
            .scaleEffect(0.5)
            .frame(width: size.width, height: size.height)
    }
}

extension MegaFrame {
    static func thumbnail(_ l: MegaLocation, settings: MegaSettings, size: CGSize) -> MegaFrame {
        var s = settings
        s[.grain] = 0
        let shot = MegaShot(index: 0, scene: MegaScenes.scene(l, variant: 0), start: 0, zoom: 1, pan: .zero)
        return MegaFrame(size: size, pos: 20, t: 40, beat: 0, level: 0.5, s: s, palette: s.palette([]), shot: shot, prev: nil,
                         cut: 1, lyric: nil, header: nil, card: nil, hit: nil, art: nil, title: "", artist: "", singers: 1)
    }
}
