import SwiftUI

// MARK: - Gotham Night settings

/// Lettering for the projected lyrics. All ship with macOS.
enum GothamFont: Int, CaseIterable, Identifiable {
    case condensed, serif, typewriter

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .condensed: "Condensed"
        case .serif: "Serif"
        case .typewriter: "Typewriter"
        }
    }

    var postScriptName: String {
        switch self {
        case .condensed: "AvenirNextCondensed-Bold"
        case .serif: "Didot-Bold"
        case .typewriter: "AmericanTypewriter-Semibold"
        }
    }

    func font(_ size: CGFloat) -> Font { .custom(postScriptName, size: size) }
}

enum GothamColorMode: Int, CaseIterable, Identifiable {
    case projector, cold, signal, album
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .projector: "Searchlight"
        case .cold: "Cold white"
        case .signal: "Signal yellow"
        case .album: "Album art"
        }
    }
}

enum GothamSignalMode: Int, CaseIterable, Identifiable {
    case off, breaks, always
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .breaks: "In breaks"
        case .always: "Always"
        }
    }
}

/// Every Gotham Night control, stored as one JSON dictionary in UserDefaults.
/// Missing keys fall back to defaults, so adding a control never resets the others.
struct GothamSettings: RawRepresentable, Equatable {
    enum Key: String, CaseIterable {
        // City
        case speed, lights, clouds, fog, rain, lightning
        // Lyrics
        case font, size, glow, caps, nextLine, color
        // Extras
        case signal, batman, characters, traffic, blimp, bats
        // Music
        case pulse

        var fallback: Double {
            switch self {
            case .speed: 0.4
            case .lights: 0.6
            case .clouds: 0.6
            case .fog: 0.5
            case .rain: 0.35
            case .lightning: 0.3
            case .font: 0
            case .size: 0.5
            case .glow: 0.6
            case .caps: 1
            case .nextLine: 1
            case .color: 0
            case .signal: 2
            case .batman: 0.5
            case .characters: 0.5
            case .traffic: 0.6
            case .blimp: 1
            case .bats: 0.5
            case .pulse: 0.5
            }
        }
    }

    static let storageKey = "gothamSettings"

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
    var font: GothamFont { GothamFont(rawValue: Int(self[.font])) ?? .condensed }
    var colorMode: GothamColorMode { GothamColorMode(rawValue: Int(self[.color])) ?? .projector }
    var signal: GothamSignalMode { GothamSignalMode(rawValue: Int(self[.signal])) ?? .always }

    // MARK: Weather presets

    enum Preset: String, CaseIterable, Identifiable {
        case clear, drizzle, storm
        var id: String { rawValue }
        var label: String {
            switch self {
            case .clear: "Clear night"
            case .drizzle: "Drizzle"
            case .storm: "Storm"
            }
        }
        var values: [Key: Double] {
            switch self {
            case .clear: [.rain: 0, .lightning: 0, .fog: 0.3, .clouds: 0.4]
            case .drizzle: [.rain: 0.35, .lightning: 0.3, .fog: 0.5, .clouds: 0.6]
            case .storm: [.rain: 0.85, .lightning: 0.8, .fog: 0.6, .clouds: 0.9]
            }
        }
    }

    mutating func apply(_ preset: Preset) {
        for (k, v) in preset.values { self[k] = v }
    }
}

// MARK: - Controls

/// Controls for the Gotham Night style. Shown in the window's popover and in Settings.
struct GothamControls: View {
    @AppStorage(GothamSettings.storageKey) private var settings = GothamSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("City")
                HStack(spacing: 6) {
                    ForEach(GothamSettings.Preset.allCases) { p in
                        Button(p.label) { withAnimation { settings.apply(p) } }
                    }
                }
                .controlSize(.small)
                slider("Drift", "arrow.left.and.right", .speed, hint: "How fast the city slides past")
                slider("Window lights", "building.2", .lights, hint: nil)
                slider("Clouds", "cloud", .clouds, hint: "The low cloud deck the lights land on")
                slider("Fog", "cloud.fog", .fog, hint: "Mist between the buildings")
                slider("Rain", "cloud.rain", .rain, hint: nil)
                slider("Lightning", "cloud.bolt", .lightning, hint: nil)

                Divider()
                section("Lyrics")
                picker("Lettering", "textformat", .font, GothamFont.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(GothamFont(rawValue: v)?.label ?? "").font(GothamFont(rawValue: v)?.font(14))
                }
                slider("Size", "textformat.size", .size, hint: nil)
                slider("Glow", "sun.max", .glow, hint: "How much the light bleeds into the fog")
                toggle("Capitals", "textformat.abc", .caps)
                toggle("Show next line", "text.append", .nextLine)
                picker("Colour", "paintpalette", .color, GothamColorMode.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(GothamColorMode(rawValue: v)?.label ?? "")
                }

                Divider()
                section("Extras")
                picker("Bat-signal", "light.beacon.max", .signal, GothamSignalMode.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(GothamSignalMode(rawValue: v)?.label ?? "")
                }
                slider("Caped flyer", "wind", .batman, hint: "How often a caped figure glides past")
                slider("Rooftop figures", "figure.stand", .characters, hint: "Familiar shadows on the ledges")
                slider("Traffic", "car.rear", .traffic, hint: "Highway lights, police and the occasional black car")
                toggle("Blimp", "airplane", .blimp)
                slider("Bats", "bird", .bats, hint: nil)

                Divider()
                section("Music")
                slider("Beat reaction", "waveform", .pulse, hint: "Lightning and light swells on big beats (needs React to music)")

                Divider()
                HStack {
                    Spacer()
                    Button("Reset All") { withAnimation { settings = GothamSettings() } }
                        .controlSize(.small)
                }
            }
            .padding(16)
        }
        .playbackSettings("gotham")
        .frame(width: 320)
        .frame(maxHeight: 640)
    }

    private func binding(_ key: GothamSettings.Key) -> Binding<Double> {
        Binding(get: { settings[key] }, set: { settings[key] = $0 })
    }

    private func section(_ title: String) -> some View {
        SettingSection(title)
    }

    private func picker<L: View>(_ title: String, _ symbol: String, _ key: GothamSettings.Key,
                                 _ options: [(Int, String)], @ViewBuilder label: @escaping (Int) -> L) -> some View {
        Picker(selection: Binding(get: { Int(settings[key]) }, set: { settings[key] = Double($0) })) {
            ForEach(options, id: \.0) { v, _ in label(v).tag(v) }
        } label: {
            SettingLabel(title: title, symbol: symbol)
        }
    }

    private func toggle(_ title: String, _ symbol: String, _ key: GothamSettings.Key) -> some View {
        SettingToggle(title: title, symbol: symbol, isOn: Binding(get: { settings.flag(key) }, set: { settings[key] = $0 ? 1 : 0 }))
    }

    private func slider(_ title: String, _ symbol: String, _ key: GothamSettings.Key, hint: String?) -> some View {
        SettingSlider(title: title, symbol: symbol, value: Binding(get: { settings[key] }, set: { settings[key] = $0 }), hint: hint)
    }
}
