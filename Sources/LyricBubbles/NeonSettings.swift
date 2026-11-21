import AppKit
import SwiftUI

// MARK: - Neon Sign settings

/// Lettering for the tubes. All ship with macOS.
enum NeonFont: Int, CaseIterable, Identifiable {
    case script, block, hand

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .script: "Script"
        case .block: "Block"
        case .hand: "Hand"
        }
    }

    var postScriptName: String {
        switch self {
        case .script: "SnellRoundhand-Black"
        case .block: "Futura-Medium"
        case .hand: "BradleyHandITCTT-Bold"
        }
    }

    /// Row height as a multiple of the point size.
    var lineHeight: CGFloat {
        switch self {
        case .script: 1.0
        case .block: 1.12
        case .hand: 1.08
        }
    }

    func font(_ size: CGFloat) -> Font { .custom(postScriptName, size: size) }

    var face: GlyphFace { GlyphFace(name: postScriptName, space: self == .script ? 0.26 : 0.3, lineHeight: lineHeight) }
}

enum NeonWall: Int, CaseIterable, Identifiable {
    case brick, concrete, wood
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .brick: "Brick"
        case .concrete: "Concrete"
        case .wood: "Wood"
        }
    }
}

enum NeonColorMode: Int, CaseIterable, Identifiable {
    case album, classic, single, singer
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .album: "Album art"
        case .classic: "Classic"
        case .single: "One colour"
        case .singer: "Per singer"
        }
    }
}

/// Every Neon Sign control, stored as one JSON dictionary in UserDefaults.
/// Missing keys fall back to defaults, so adding a control never resets the others.
struct NeonSettings: RawRepresentable, Equatable {
    enum Key: String, CaseIterable {
        // Camera
        case zoom, pan, smooth, tilt, parallax, motionBlur
        // Tubes
        case font, tube, thickness, glow, brightness, size
        // Character
        case flicker, broken, ignition, gasFill, sparks, hum, humVolume
        // Scene
        case wall, wallLight, wet, rain, hardware, pulse
        // Colour
        case color, colorR, colorG, colorB
        // Layout
        case lines

        var fallback: Double {
            switch self {
            case .zoom: 0.45
            case .pan: 0.6
            case .smooth: 0.5
            case .tilt: 0.3
            case .parallax: 0.5
            case .motionBlur: 0.45
            case .font: 0
            case .tube: 0
            case .thickness: 0.5
            case .glow: 0.6
            case .brightness: 0.8
            case .size: 0.5
            case .flicker: 0.5
            case .broken: 0
            case .ignition: 0.5
            case .gasFill: 0
            case .sparks: 0.4
            case .hum: 0
            case .humVolume: 0.35
            case .wall: 0
            case .wallLight: 0.6
            case .wet: 0.6
            case .rain: 0
            case .hardware: 1
            case .pulse: 0.5
            case .color: 0
            case .colorR: 1
            case .colorG: 0.25
            case .colorB: 0.6
            case .lines: 3
            }
        }
    }

    static let storageKey = "neonSettings"

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
    var font: NeonFont { NeonFont(rawValue: Int(self[.font])) ?? .script }
    var wall: NeonWall { NeonWall(rawValue: Int(self[.wall])) ?? .brick }
    var colorMode: NeonColorMode { NeonColorMode(rawValue: Int(self[.color])) ?? .album }
    var solidTubes: Bool { flag(.tube) }
    var lines: Int { max(1, min(4, Int(self[.lines].rounded()))) }
    var singleColor: NeonRGB { NeonRGB(self[.colorR], self[.colorG], self[.colorB]) }

    // MARK: Camera presets

    enum Preset: String, CaseIterable, Identifiable {
        case still, gentle, cinematic, wild
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var values: [Key: Double] {
            switch self {
            case .still: [.zoom: 0, .pan: 0, .tilt: 0, .motionBlur: 0, .smooth: 0.5, .parallax: 0.3]
            case .gentle: [.zoom: 0.25, .pan: 0.35, .tilt: 0.15, .motionBlur: 0.3, .smooth: 0.75, .parallax: 0.4]
            case .cinematic: [.zoom: 0.45, .pan: 0.6, .tilt: 0.3, .motionBlur: 0.45, .smooth: 0.5, .parallax: 0.5]
            case .wild: [.zoom: 0.9, .pan: 1, .tilt: 0.8, .motionBlur: 0.85, .smooth: 0.18, .parallax: 0.8]
            }
        }
    }

    mutating func apply(_ preset: Preset) {
        for (k, v) in preset.values { self[k] = v }
    }
}

/// A plain sRGB colour, so tube colours can be mixed toward white for the hot core.
struct NeonRGB: Equatable {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
    func color(_ opacity: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: max(0, min(1, opacity))) }
    func mixed(_ o: NeonRGB, _ k: Double) -> NeonRGB { NeonRGB(r + (o.r - r) * k, g + (o.g - g) * k, b + (o.b - b) * k) }

    static let white = NeonRGB(1, 1, 1)
    static let classic = [NeonRGB(1, 0.22, 0.58), NeonRGB(0.2, 0.88, 1), NeonRGB(1, 0.66, 0.16)]
    /// Extra colours for songs with more than three singers.
    static let extra = [NeonRGB(0.5, 1, 0.3), NeonRGB(0.7, 0.4, 1)]
}

// MARK: - Controls

/// Controls for the Neon Sign style. Shown in the window's popover and in Settings.
struct NeonControls: View {
    @AppStorage(NeonSettings.storageKey) private var settings = NeonSettings()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                section("Camera")
                HStack(spacing: 6) {
                    ForEach(NeonSettings.Preset.allCases) { p in
                        Button(p.label) { withAnimation { settings.apply(p) } }
                    }
                }
                .controlSize(.small)
                slider("Zoom", "plus.magnifyingglass", .zoom, hint: "How close the camera moves in on each line")
                slider("Follow", "hand.point.right", .pan, hint: "Pan along to each word as it lights up")
                slider("Smoothness", "water.waves", .smooth, hint: "Low is snappy, high is slow and floaty")
                slider("Roll", "rotate.right", .tilt, hint: "Gentle sway and tilt")
                slider("Depth", "square.3.layers.3d", .parallax, hint: "How far the wall sits behind the tubes")
                slider("Motion blur", "wind", .motionBlur, hint: "Streaks while the camera moves")

                Divider()
                section("Tubes")
                picker("Lettering", "signature", .font, NeonFont.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(NeonFont(rawValue: v)?.label ?? "").font(NeonFont(rawValue: v)?.font(15))
                }
                picker("Tube style", "scribble", .tube, [(0, "Outline"), (1, "Single tube")]) { v in
                    Text(v == 1 ? "Single tube" : "Outline")
                }
                slider("Thickness", "line.3.horizontal", .thickness, hint: nil)
                slider("Glow", "sun.max", .glow, hint: "How far the light spreads")
                slider("Brightness", "lightbulb", .brightness, hint: nil)
                slider("Size", "textformat.size", .size, hint: nil)

                Divider()
                section("Character")
                slider("Flicker", "bolt", .flicker, hint: "Hum, shimmer and the odd weak letter")
                toggle("Broken letter", "bolt.slash", .broken)
                slider("Ignition speed", "hare", .ignition, hint: "How quickly each word sputters on")
                toggle("Gas fill", "arrow.right.to.line", .gasFill)
                SettingHint("Light runs along each letter instead of switching on")
                slider("Sparks", "sparkles", .sparks, hint: "When letters ignite or fail")
                toggle("Hum", "speaker.wave.1", .hum)
                if settings.flag(.hum) {
                    slider("Hum volume", "speaker.wave.2", .humVolume, hint: "A quiet electrical buzz while the sign is lit")
                }

                Divider()
                section("Scene")
                picker("Wall", "square.grid.3x3", .wall, NeonWall.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(NeonWall(rawValue: v)?.label ?? "")
                }
                slider("Wall lighting", "light.recessed", .wallLight, hint: "How much the sign lights up the wall")
                slider("Wet reflection", "drop", .wet, hint: "Reflections on the pavement below")
                slider("Rain", "cloud.rain", .rain, hint: nil)
                toggle("Hardware", "wrench.and.screwdriver", .hardware)
                slider("Beat pulse", "waveform", .pulse, hint: "Glow swells on kicks (needs React to music)")

                Divider()
                section("Colour")
                picker("Colours", "paintpalette", .color, NeonColorMode.allCases.map { ($0.rawValue, $0.label) }) { v in
                    Text(NeonColorMode(rawValue: v)?.label ?? "")
                }
                if settings.colorMode == .single {
                    ColorPicker(selection: Binding(get: { settings.singleColor.color }, set: { c in
                        let rgb = NeonRGB(c)
                        settings[.colorR] = rgb.r; settings[.colorG] = rgb.g; settings[.colorB] = rgb.b
                    }), supportsOpacity: false) {
                        Label("Tube colour", systemImage: "eyedropper").font(.system(size: 12, weight: .medium))
                    }
                }

                Divider()
                section("Layout")
                Stepper(value: Binding(get: { Double(settings.lines) }, set: { settings[.lines] = $0 }), in: 1...4) {
                    HStack {
                        Label("Lines per sign", systemImage: "list.bullet").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(settings.lines)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }

                Divider()
                HStack {
                    Spacer()
                    Button("Reset All") { withAnimation { settings = NeonSettings() } }
                        .controlSize(.small)
                }
            }
            .padding(16)
        }
        .playbackSettings("neon")
        .frame(width: 320)
        .frame(maxHeight: 640)
    }

    private func binding(_ key: NeonSettings.Key) -> Binding<Double> {
        Binding(get: { settings[key] }, set: { settings[key] = $0 })
    }

    private func section(_ title: String) -> some View {
        SettingSection(title)
    }

    private func picker<L: View>(_ title: String, _ symbol: String, _ key: NeonSettings.Key,
                                 _ options: [(Int, String)], @ViewBuilder label: @escaping (Int) -> L) -> some View {
        Picker(selection: Binding(get: { Int(settings[key]) }, set: { settings[key] = Double($0) })) {
            ForEach(options, id: \.0) { v, _ in label(v).tag(v) }
        } label: {
            SettingLabel(title: title, symbol: symbol)
        }
    }

    private func toggle(_ title: String, _ symbol: String, _ key: NeonSettings.Key) -> some View {
        SettingToggle(title: title, symbol: symbol, isOn: Binding(get: { settings.flag(key) }, set: { settings[key] = $0 ? 1 : 0 }))
    }

    private func slider(_ title: String, _ symbol: String, _ key: NeonSettings.Key, hint: String?) -> some View {
        SettingSlider(title: title, symbol: symbol, value: Binding(get: { settings[key] }, set: { settings[key] = $0 }), hint: hint)
    }
}
