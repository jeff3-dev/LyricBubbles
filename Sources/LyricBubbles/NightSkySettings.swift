import SwiftUI

// MARK: - Night Sky settings

/// Lettering for the constellations. Thin faces give the cleanest star lines. All ship with macOS.
enum SkyFont: Int, CaseIterable, Identifiable {
    case clean, rounded, hand

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .clean: "Clean"
        case .rounded: "Rounded"
        case .hand: "Hand"
        }
    }

    var postScriptName: String {
        switch self {
        case .clean: "AvenirNext-UltraLight"
        case .rounded: "HelveticaNeue-Light"
        case .hand: "Noteworthy-Light"
        }
    }

    func font(_ size: CGFloat) -> Font { .custom(postScriptName, size: size) }

    var face: GlyphFace {
        GlyphFace(name: postScriptName, space: self == .hand ? 0.32 : 0.36, lineHeight: self == .hand ? 1.1 : 1.2)
    }
}

enum SkyColorMode: Int, CaseIterable, Identifiable {
    case singer, white, album
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .singer: "Per singer"
        case .white: "Starlight"
        case .album: "Album art"
        }
    }
}

/// Every Night Sky control, stored as one JSON dictionary in UserDefaults.
/// Missing keys fall back to defaults, so adding a control never resets the others.
struct SkySettings: RawRepresentable, Equatable {
    enum Key: String, CaseIterable {
        // Flight
        case speed, warp, sway, streaks, curve
        // Layers (each has an on/off switch and a strength)
        case nebula, dust, landmarks, aurora
        case nebulaOn, dustOn, landmarksOn, auroraOn
        // Constellations
        case font, starSize, density, links, glow, twinkle
        // Sky
        case field, milkyWay, pulse
        // Colour and layout
        case color, rows

        var fallback: Double {
            switch self {
            case .speed: 0.5
            case .warp: 0.7
            case .sway: 0.4
            case .streaks: 0.6
            case .curve: 0.6
            case .nebula: 0.6
            case .dust: 0.5
            case .landmarks: 0.8
            case .aurora: 0.5
            case .nebulaOn, .dustOn, .landmarksOn, .auroraOn: 1
            case .font: 0
            case .starSize: 0.5
            case .density: 0.35
            case .links: 0.6
            case .glow: 0.6
            case .twinkle: 0.5
            case .field: 0.6
            case .milkyWay: 0.6
            case .pulse: 0.5
            case .color: 0
            case .rows: 2
            }
        }
    }

    static let storageKey = "skySettings"

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

    var font: SkyFont { SkyFont(rawValue: Int(self[.font])) ?? .clean }
    var colorMode: SkyColorMode { SkyColorMode(rawValue: Int(self[.color])) ?? .singer }
    var rows: Int { max(1, min(4, Int(self[.rows].rounded()))) }

    /// A layer's strength, or 0 when its switch is off.
    func layer(_ key: Key) -> Double {
        let on: Key = switch key {
        case .nebula: .nebulaOn
        case .dust: .dustOn
        case .landmarks: .landmarksOn
        default: .auroraOn
        }
        return self[on] > 0.5 ? self[key] : 0
    }

    // MARK: Flight presets

    enum Preset: String, CaseIterable, Identifiable {
        case drift, cruise, hyperspace
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var values: [Key: Double] {
            switch self {
            case .drift: [.speed: 0.15, .warp: 0.3, .sway: 0.6, .streaks: 0.3, .curve: 0.85]
            case .cruise: [.speed: 0.5, .warp: 0.7, .sway: 0.4, .streaks: 0.6, .curve: 0.6]
            case .hyperspace: [.speed: 0.9, .warp: 1, .sway: 0.3, .streaks: 1, .curve: 0.4]
            }
        }
    }

    mutating func apply(_ preset: Preset) {
        for (k, v) in preset.values { self[k] = v }
    }
}

// MARK: - Controls

/// Controls for the Night Sky style. Shown in the window's popover and in Settings.
struct SkyControls: View {
    @AppStorage(SkySettings.storageKey) private var settings = SkySettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("Flight")
                HStack(spacing: 6) {
                    ForEach(SkySettings.Preset.allCases) { p in
                        Button(p.label) { withAnimation { settings.apply(p) } }
                    }
                }
                .controlSize(.small)
                slider("Speed", "hare", .speed, hint: "How quickly the camera flies to the next constellation")
                slider("Warp", "sparkles", .warp, hint: "Jump to warp when a part of the song repeats (the chorus)")
                slider("Star streaks", "wind", .streaks, hint: "Stars stretch into lines while flying")
                slider("Curves", "point.bottomleft.forward.to.point.topright.scurvepath", .curve, hint: "How far the flight swings and banks between constellations")
                slider("Drift", "water.waves", .sway, hint: "Gentle floating and roll")

                Divider()
                section("Layers")
                layer("Nebulae", "cloud.fill", on: .nebulaOn, .nebula, hint: "Coloured gas clouds at many depths")
                layer("Dust & bokeh", "aqi.medium", on: .dustOn, .dust, hint: "Soft specks right by the lens")
                layer("Planets & galaxies", "globe.americas.fill", on: .landmarksOn, .landmarks, hint: "Landmarks passed between parts")
                layer("Aurora", "waveform.path", on: .auroraOn, .aurora, hint: "Light ribbons that swell with the music")

                Divider()
                section("Constellations")
                picker("Lettering", "signature", .font, SkyFont.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(SkyFont(rawValue: v)?.label ?? "").font(SkyFont(rawValue: v)?.font(15))
                }
                slider("Star size", "star", .starSize, hint: nil)
                slider("Stars per letter", "circle.grid.3x3", .density, hint: nil)
                slider("Lines", "point.topleft.down.to.point.bottomright.curvepath", .links, hint: "The lines that join the stars")
                slider("Glow", "sun.max", .glow, hint: nil)
                slider("Twinkle", "sparkle", .twinkle, hint: nil)

                Divider()
                section("Sky")
                slider("Stars", "moon.stars", .field, hint: "How many stars fill the sky")
                slider("Milky Way", "circle.dotted", .milkyWay, hint: nil)
                slider("Beat pulse", "waveform", .pulse, hint: "Stars brighten on kicks (needs React to music)")

                Divider()
                section("Colour")
                picker("Colours", "paintpalette", .color, SkyColorMode.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(SkyColorMode(rawValue: v)?.label ?? "")
                }

                Divider()
                section("Layout")
                Stepper(value: Binding(get: { Double(settings.rows) }, set: { settings[.rows] = $0 }), in: 1...4) {
                    HStack {
                        Label("Lines per constellation", systemImage: "list.bullet").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(settings.rows)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                Divider()
                HStack {
                    Spacer()
                    Button("Reset All") { withAnimation { settings = SkySettings() } }
                        .controlSize(.small)
                }
            }
            .padding(16)
        }
        .playbackSettings("sky")
        .frame(width: 320)
        .frame(maxHeight: 640)
    }

    private func layer(_ title: String, _ symbol: String, on: SkySettings.Key, _ key: SkySettings.Key, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { settings[on] > 0.5 }, set: { v in withAnimation { settings[on] = v ? 1 : 0 } })) {
                SettingLabel(title: title, symbol: symbol)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            if settings[on] > 0.5 {
                Slider(value: Binding(get: { settings[key] }, set: { settings[key] = $0 }), in: 0...1).controlSize(.small)
                SettingHint(hint)
            }
        }
    }

    private func section(_ title: String) -> some View {
        SettingSection(title)
    }

    private func picker<L: View>(_ title: String, _ symbol: String, _ key: SkySettings.Key,
                                 _ options: [(Int, String)], @ViewBuilder label: @escaping (Int) -> L) -> some View {
        Picker(selection: Binding(get: { Int(settings[key]) }, set: { settings[key] = Double($0) })) {
            ForEach(options, id: \.0) { v, _ in label(v).tag(v) }
        } label: {
            SettingLabel(title: title, symbol: symbol)
        }
    }

    private func slider(_ title: String, _ symbol: String, _ key: SkySettings.Key, hint: String?) -> some View {
        SettingSlider(title: title, symbol: symbol, value: Binding(get: { settings[key] }, set: { settings[key] = $0 }), hint: hint)
    }
}
