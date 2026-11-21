import AppKit
import SwiftUI

// MARK: - Kinetic settings

/// What sits behind the words.
enum KineticBackground: Int, CaseIterable, Identifiable {
    case album, nebula, particles, ocean
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .album: "Album art"
        case .nebula: "Nebula"
        case .particles: "Particles"
        case .ocean: "Ocean"
        }
    }
}

/// Word colours. Album art reads the song's artwork; the rest are fixed sets.
enum KineticColors: Int, CaseIterable, Identifiable {
    case album, sunset, white, candy, ocean, lime
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .album: "Album art"
        case .sunset: "Sunset"
        case .white: "White"
        case .candy: "Candy"
        case .ocean: "Ocean"
        case .lime: "Lime"
        }
    }

    var fixed: [NeonRGB] {
        switch self {
        case .album, .sunset: [NeonRGB(0.96, 0.27, 0.2), NeonRGB(0.98, 0.76, 0.6), NeonRGB(0.98, 0.8, 0.3)]
        case .white: [NeonRGB(1, 1, 1), NeonRGB(0.92, 0.94, 1), NeonRGB(0.85, 0.88, 0.95)]
        case .candy: [NeonRGB(1, 0.42, 0.7), NeonRGB(0.62, 0.5, 1), NeonRGB(0.4, 0.9, 1)]
        case .ocean: [NeonRGB(0.45, 0.85, 1), NeonRGB(0.85, 0.97, 1), NeonRGB(0.35, 0.6, 1)]
        case .lime: [NeonRGB(0.75, 1, 0.3), NeonRGB(1, 1, 0.55), NeonRGB(0.4, 1, 0.65)]
        }
    }
}

/// Typefaces for the words. All ship with macOS.
enum KineticFont: Int, CaseIterable, Identifiable {
    case geometric, heavy, rounded, serif
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .geometric: "Geometric"
        case .heavy: "Heavy"
        case .rounded: "Rounded"
        case .serif: "Serif"
        }
    }

    func font(_ size: CGFloat) -> Font {
        switch self {
        case .geometric: .custom("Futura-Bold", size: size)
        case .heavy: .custom("AvenirNext-Heavy", size: size)
        case .rounded: .system(size: size, weight: .black, design: .rounded)
        case .serif: .system(size: size, weight: .bold, design: .serif)
        }
    }
}

/// Every Kinetic control, stored as one JSON dictionary in UserDefaults.
/// Missing keys fall back to defaults, so adding a control never resets the others.
struct KineticSettings: RawRepresentable, Equatable {
    enum Key: String, CaseIterable {
        // Motion
        case bigWords, speed, tilt, motionBlur, pulse
        // Words
        case font, size, color, emoji
        // Background
        case background, bgMotion, dim

        var fallback: Double {
            switch self {
            case .bigWords: 0.75
            case .speed: 0.5
            case .tilt: 0.5
            case .motionBlur: 0.5
            case .pulse: 0.5
            case .font: 0
            case .size: 0.5
            case .color: 0
            case .emoji: 1
            case .background: 0
            case .bgMotion: 0.5
            case .dim: 0.25
            }
        }
    }

    static let storageKey = "kineticSettings"

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
    var background: KineticBackground { KineticBackground(rawValue: Int(self[.background])) ?? .album }
    var colors: KineticColors { KineticColors(rawValue: Int(self[.color])) ?? .album }
    var font: KineticFont { KineticFont(rawValue: Int(self[.font])) ?? .geometric }

    /// The word colours to use now. Album art falls back to Sunset until the art loads.
    func palette(_ art: [Color]) -> [NeonRGB] {
        if colors == .album, !art.isEmpty { return art.map(NeonRGB.init) }
        return colors.fixed
    }

    // MARK: Motion presets

    enum Preset: String, CaseIterable, Identifiable {
        case calm, classic, wild
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var values: [Key: Double] {
            switch self {
            case .calm: [.bigWords: 0.4, .speed: 0.25, .tilt: 0.2, .motionBlur: 0.25, .bgMotion: 0.3]
            case .classic: [.bigWords: 0.75, .speed: 0.5, .tilt: 0.5, .motionBlur: 0.5, .bgMotion: 0.5]
            case .wild: [.bigWords: 1, .speed: 0.9, .tilt: 0.9, .motionBlur: 0.85, .bgMotion: 0.8]
            }
        }
    }

    mutating func apply(_ preset: Preset) {
        for (k, v) in preset.values { self[k] = v }
    }
}

// MARK: - Controls

/// Controls for the Kinetic style. Shown in the window's popover and in Settings.
struct KineticControls: View {
    @AppStorage(KineticSettings.storageKey) private var settings = KineticSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("Motion")
                HStack(spacing: 6) {
                    ForEach(KineticSettings.Preset.allCases) { p in
                        Button(p.label) { withAnimation { settings.apply(p) } }
                    }
                }
                .controlSize(.small)
                slider("Big words", "textformat.size.larger", .bigWords, hint: "How often a line's strongest word flies in huge")
                slider("Speed", "hare", .speed, hint: "How fast words pop in and fly away")
                slider("Tilt", "rotate.3d", .tilt, hint: "How much the big words lean")
                slider("Motion blur", "wind", .motionBlur, hint: "Streaks while words fly")
                slider("Beat pulse", "waveform", .pulse, hint: "Words bump on kicks (needs React to music)")

                Divider()
                section("Words")
                picker("Typeface", "textformat", .font, KineticFont.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(KineticFont(rawValue: v)?.label ?? "").font(KineticFont(rawValue: v)?.font(14))
                }
                picker("Colours", "paintpalette", .color, KineticColors.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(KineticColors(rawValue: v)?.label ?? "")
                }
                slider("Size", "textformat.size", .size, hint: nil)
                toggle("Emoji", "face.smiling", .emoji)
                SettingHint("Adds a matching emoji after words like eyes, heart or fire")

                Divider()
                section("Background")
                picker("Scene", "photo", .background, KineticBackground.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(KineticBackground(rawValue: v)?.label ?? "")
                }
                slider("Movement", "arrow.triangle.2.circlepath", .bgMotion, hint: "How lively the background is")
                slider("Dim", "circle.lefthalf.filled", .dim, hint: "Darkens the background so words stand out")

                Divider()
                HStack {
                    Spacer()
                    Button("Reset All") { withAnimation { settings = KineticSettings() } }
                        .controlSize(.small)
                }
            }
            .padding(16)
        }
        .playbackSettings("kinetic")
        .frame(width: 320)
        .frame(maxHeight: 640)
    }

    private func section(_ title: String) -> some View {
        SettingSection(title)
    }

    private func picker<L: View>(_ title: String, _ symbol: String, _ key: KineticSettings.Key,
                                 _ options: [(Int, String)], @ViewBuilder label: @escaping (Int) -> L) -> some View {
        Picker(selection: Binding(get: { Int(settings[key]) }, set: { settings[key] = Double($0) })) {
            ForEach(options, id: \.0) { v, _ in label(v).tag(v) }
        } label: {
            SettingLabel(title: title, symbol: symbol)
        }
    }

    private func toggle(_ title: String, _ symbol: String, _ key: KineticSettings.Key) -> some View {
        SettingToggle(title: title, symbol: symbol, isOn: Binding(get: { settings.flag(key) }, set: { settings[key] = $0 ? 1 : 0 }))
    }

    private func slider(_ title: String, _ symbol: String, _ key: KineticSettings.Key, hint: String?) -> some View {
        SettingSlider(title: title, symbol: symbol, value: Binding(get: { settings[key] }, set: { settings[key] = $0 }), hint: hint)
    }
}
