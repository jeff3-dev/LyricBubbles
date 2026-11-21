import SwiftUI

// MARK: - Fogged Glass settings

/// Handwriting faces for the glass. All ship with macOS.
enum GlassFont: Int, CaseIterable, Identifiable {
    case bradley, noteworthy, marker, chalkboard, snell

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .bradley: "Fingertip"
        case .noteworthy: "Notebook"
        case .marker: "Marker"
        case .chalkboard: "Chalky"
        case .snell: "Script"
        }
    }

    var postScriptName: String {
        switch self {
        case .bradley: "BradleyHandITCTT-Bold"
        case .noteworthy: "Noteworthy-Bold"
        case .marker: "MarkerFelt-Wide"
        case .chalkboard: "ChalkboardSE-Bold"
        case .snell: "SnellRoundhand-Black"
        }
    }

    /// Rough average glyph width as a fraction of the point size (for camera framing).
    var widthFactor: CGFloat {
        switch self {
        case .bradley: 0.46
        case .noteworthy: 0.47
        case .marker: 0.5
        case .chalkboard: 0.53
        case .snell: 0.42
        }
    }

    func font(_ size: CGFloat) -> Font { .custom(postScriptName, size: size) }
}

/// Every Fogged Glass control, stored as one JSON dictionary in UserDefaults.
/// Missing keys fall back to defaults, so adding a control never resets the others.
struct GlassSettings: RawRepresentable, Equatable {
    enum Key: String, CaseIterable {
        // Camera
        case zoom, pan, smooth, tilt, parallax, motionBlur
        // Glass
        case fog, texture, droplets, wetness, reflections, drips, breath
        // Writing
        case font, size, speed, lines, fadeOld
        // Behind the glass
        case lights, pulse, art

        var fallback: Double {
            switch self {
            case .zoom: 0.5
            case .pan: 0.65
            case .smooth: 0.5
            case .tilt: 0.4
            case .parallax: 0.55
            case .motionBlur: 0.5
            case .fog: 0.5
            case .texture: 0.6
            case .droplets: 0.6
            case .wetness: 0.7
            case .reflections: 0.45
            case .drips: 0.5
            case .breath: 1
            case .font: 0
            case .size: 0.5
            case .speed: 0.5
            case .lines: 4
            case .fadeOld: 0.5
            case .lights: 0.6
            case .pulse: 0.5
            case .art: 1
            }
        }
    }

    static let storageKey = "glassSettings"

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
    var font: GlassFont { GlassFont(rawValue: Int(self[.font])) ?? .bradley }
    var lines: Int { max(1, min(4, Int(self[.lines].rounded()))) }

    // MARK: Camera presets

    enum Preset: String, CaseIterable, Identifiable {
        case still, gentle, cinematic, wild
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var values: [Key: Double] {
            switch self {
            case .still: [.zoom: 0, .pan: 0, .tilt: 0, .motionBlur: 0, .smooth: 0.5, .parallax: 0.3]
            case .gentle: [.zoom: 0.3, .pan: 0.4, .tilt: 0.2, .motionBlur: 0.3, .smooth: 0.75, .parallax: 0.45]
            case .cinematic: [.zoom: 0.55, .pan: 0.65, .tilt: 0.4, .motionBlur: 0.5, .smooth: 0.5, .parallax: 0.55]
            case .wild: [.zoom: 0.95, .pan: 1, .tilt: 0.9, .motionBlur: 0.85, .smooth: 0.18, .parallax: 0.8]
            }
        }
    }

    mutating func apply(_ preset: Preset) {
        for (k, v) in preset.values { self[k] = v }
    }
}

// MARK: - Controls

/// Controls for the Fogged Glass style. Shown in the window's popover and in Settings.
struct GlassControls: View {
    @AppStorage(GlassSettings.storageKey) private var settings = GlassSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("Camera")
                HStack(spacing: 6) {
                    ForEach(GlassSettings.Preset.allCases) { p in
                        Button(p.label) { withAnimation { settings.apply(p) } }
                    }
                }
                .controlSize(.small)
                slider("Zoom", "plus.magnifyingglass", .zoom, hint: "How close the camera moves in on each line")
                slider("Follow the finger", "hand.point.right", .pan, hint: "Pan along with the words as they're written")
                slider("Smoothness", "water.waves", .smooth, hint: "Low is snappy, high is slow and floaty")
                slider("Roll", "rotate.right", .tilt, hint: "Tilt with the handwriting and sway gently")
                slider("Depth", "square.3.layers.3d", .parallax, hint: "How far the lights sit behind the glass")
                slider("Motion blur", "wind", .motionBlur, hint: "Streaks while the camera moves or zooms")

                Divider()
                section("Glass")
                slider("Fog", "cloud.fog", .fog, hint: "How thick the condensation is")
                slider("Fog texture", "aqi.medium", .texture, hint: "Uneven, mottled patches of mist")
                slider("Droplets", "drop", .droplets, hint: "Beads of water scattered over the pane")
                slider("Wetness", "drop.halffull", .wetness, hint: "Beaded edges and wet streaks in the writing")
                slider("Reflections", "light.max", .reflections, hint: "Glints of room light sliding across the glass")
                slider("Drips", "drop.triangle", .drips, hint: "Water running down from the letters")
                toggle("Breathe between parts", "wind.circle", .breath)

                Divider()
                section("Writing")
                Picker(selection: Binding(get: { Int(settings[.font]) }, set: { settings[.font] = Double($0) })) {
                    ForEach(GlassFont.allCases) { f in
                        Text(f.label).font(f.font(15)).tag(f.rawValue)
                    }
                } label: {
                    Label("Hand", systemImage: "signature").font(.system(size: 12, weight: .medium))
                }
                slider("Size", "textformat.size", .size, hint: nil)
                slider("Writing speed", "hare", .speed, hint: "How quickly each line is traced")
                Stepper(value: Binding(get: { Double(settings.lines) }, set: { settings[.lines] = $0 }), in: 1...4) {
                    HStack {
                        Label("Lines per pane", systemImage: "list.bullet").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(settings.lines)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                slider("Fade older lines", "circle.lefthalf.filled", .fadeOld, hint: "How fast earlier lines fog back over")

                Divider()
                section("Behind the glass")
                slider("Lights", "light.recessed", .lights, hint: "Blurry city lights in the album's colors")
                slider("Beat pulse", "waveform", .pulse, hint: "Lights and camera bump on kicks (needs React to music)")
                toggle("Album art", "photo", .art)

                Divider()
                HStack {
                    Spacer()
                    Button("Reset All") { withAnimation { settings = GlassSettings() } }
                        .controlSize(.small)
                }
            }
            .padding(16)
        }
        .playbackSettings("glass")
        .frame(width: 320)
        .frame(maxHeight: 640)
    }

    private func binding(_ key: GlassSettings.Key) -> Binding<Double> {
        Binding(get: { settings[key] }, set: { settings[key] = $0 })
    }

    private func section(_ title: String) -> some View {
        SettingSection(title)
    }

    private func toggle(_ title: String, _ symbol: String, _ key: GlassSettings.Key) -> some View {
        SettingToggle(title: title, symbol: symbol, isOn: Binding(get: { settings.flag(key) }, set: { settings[key] = $0 ? 1 : 0 }))
    }

    private func slider(_ title: String, _ symbol: String, _ key: GlassSettings.Key, hint: String?) -> some View {
        SettingSlider(title: title, symbol: symbol, value: Binding(get: { settings[key] }, set: { settings[key] = $0 }), hint: hint)
    }
}
