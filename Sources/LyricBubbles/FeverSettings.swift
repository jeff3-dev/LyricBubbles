import SwiftUI

// MARK: - Fever City settings

enum FeverFont: Int, CaseIterable, Identifiable {
    case rounded, marker, futura, chalk

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .rounded: "Bubbly"
        case .marker: "Marker"
        case .futura: "Poster"
        case .chalk: "Chalk"
        }
    }

    func font(_ size: CGFloat) -> Font {
        switch self {
        case .rounded: .system(size: size, weight: .black, design: .rounded)
        case .marker: .custom("MarkerFelt-Wide", size: size)
        case .futura: .custom("Futura-CondensedExtraBold", size: size)
        case .chalk: .custom("ChalkboardSE-Bold", size: size)
        }
    }
}

/// Where the lyrics go. Each song section keeps one carrier; the mixes change it per section.
enum FeverPlace: Int, CaseIterable, Identifiable {
    // Raw values 0...3 are the original options, so stored choices keep working.
    case everywhere, billboards, sky, caption, blimp, tower, banner, skywriting
    var id: Int { rawValue }
    static let menuOrder: [FeverPlace] = [.everywhere, .sky, .billboards, .blimp, .tower, .banner, .skywriting, .caption]
    var label: String {
        switch self {
        case .everywhere: "Mix"
        case .billboards: "Billboards"
        case .sky: "Sky mix"
        case .caption: "Caption"
        case .blimp: "Blimp"
        case .tower: "Tower"
        case .banner: "Banner"
        case .skywriting: "Skywriting"
        }
    }
    var symbol: String {
        switch self {
        case .everywhere: "sparkles"
        case .billboards: "rectangle.split.3x1"
        case .sky: "cloud.sun"
        case .caption: "captions.bubble"
        case .blimp: "capsule"
        case .tower: "building.2"
        case .banner: "flag"
        case .skywriting: "scribble"
        }
    }
}

enum FeverCamera: Int, CaseIterable, Identifiable {
    case driveBy, cuts, wild
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .driveBy: "Drive-by"
        case .cuts: "Close-ups"
        case .wild: "Wild"
        }
    }
    var symbol: String {
        switch self {
        case .driveBy: "car.side"
        case .cuts: "scope"
        case .wild: "tornado"
        }
    }
}

/// The time of day, kept apart from the colours. Auto uses the palette's own light.
enum FeverTime: Int, CaseIterable, Identifiable {
    case auto, dawn, day, sunset, night, cycle
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .auto: "Auto"
        case .dawn: "Dawn"
        case .day: "Day"
        case .sunset: "Sunset"
        case .night: "Night"
        case .cycle: "Cycle"
        }
    }
    var symbol: String {
        switch self {
        case .auto: "wand.and.stars"
        case .dawn: "sunrise"
        case .day: "sun.max"
        case .sunset: "sunset"
        case .night: "moon.stars"
        case .cycle: "arrow.triangle.2.circlepath"
        }
    }
}

enum FeverWeather: Int, CaseIterable, Identifiable {
    case clear, rain, snow, fog, storm
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .clear: "Clear"
        case .rain: "Rain"
        case .snow: "Snow"
        case .fog: "Fog"
        case .storm: "Storm"
        }
    }
    var symbol: String {
        switch self {
        case .clear: "sun.max"
        case .rain: "cloud.rain"
        case .snow: "cloud.snow"
        case .fog: "cloud.fog"
        case .storm: "cloud.bolt.rain"
        }
    }
}

/// Every Fever City control, stored as one JSON dictionary in UserDefaults.
/// Missing keys fall back to defaults, so adding a control never resets the others.
struct FeverSettings: RawRepresentable, Equatable {
    enum Key: String, CaseIterable {
        // City
        case speed, palette, lights, clouds, camera, traffic
        case time, weather, intensity
        // Lyrics
        case lyrics, place, font, size, caps
        // Chaos
        case chaos
        case ufo, rocket, balloons, fireworks, moon
        case parade, donut, signals, hop, train
        case kaiju, cat, whale
        case stretch, flip, swap
        // Music
        case pulse

        var fallback: Double {
            switch self {
            case .speed: 0.45
            case .palette: 0
            case .lights: 0.7
            case .clouds: 0.6
            case .camera: 1
            case .traffic: 0.6
            case .lyrics: 1
            case .place: 0
            case .font: 0
            case .size: 0.5
            case .caps: 0
            case .chaos: 0.6
            case .stretch: 0.4
            case .flip: 0
            case .swap: 0
            case .time: 0
            case .weather: 0
            case .intensity: 0.6
            case .pulse: 0.6
            default: 0.5
            }
        }

        /// The keys that make up the chaos (what the presets and Randomize touch).
        static let events: [Key] = [.ufo, .rocket, .balloons, .fireworks, .moon, .parade, .donut, .signals, .hop,
                                    .train, .kaiju, .cat, .whale, .stretch]
    }

    static let storageKey = "feverSettings"

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
    var font: FeverFont { FeverFont(rawValue: Int(self[.font])) ?? .rounded }
    var place: FeverPlace { FeverPlace(rawValue: Int(self[.place])) ?? .everywhere }
    var camera: FeverCamera { FeverCamera(rawValue: Int(self[.camera])) ?? .cuts }
    var time: FeverTime { FeverTime(rawValue: Int(self[.time])) ?? .auto }
    var weather: FeverWeather { FeverWeather(rawValue: Int(self[.weather])) ?? .clear }

    /// How often an event comes round: its slider times the master Chaos slider.
    func rate(_ key: Key) -> Double { self[key] * (0.25 + 1.75 * self[.chaos]) }

    // MARK: Presets

    enum Preset: String, CaseIterable, Identifiable {
        case chill, fever, overdose
        var id: String { rawValue }
        var label: String {
            switch self {
            case .chill: "Chill"
            case .fever: "Fever"
            case .overdose: "Overdose"
            }
        }
    }

    mutating func apply(_ preset: Preset) {
        switch preset {
        case .chill:
            for k in Key.events { self[k] = 0.2 }
            self[.chaos] = 0.2
            self[.stretch] = 0.1; self[.balloons] = 0.5; self[.moon] = 0.5
        case .fever:
            for k in Key.events + [.chaos] { values[k.rawValue] = nil }
        case .overdose:
            for k in Key.events + [.chaos] { self[k] = 1 }
        }
    }

    mutating func randomize() {
        for k in Key.events { self[k] = [0, 0.3, 0.6, 1].randomElement()! }
        self[.chaos] = Double.random(in: 0.4...1)
    }
}

// MARK: - Controls

/// Controls for the Fever City style, in four tabs. Shown in the window's popover and in Settings.
/// Presets and the dice only touch the chaos; the scene (time, weather, colours) stays put.
struct FeverControls: View {
    @AppStorage(FeverSettings.storageKey) private var settings = FeverSettings()
    @AppStorage("feverMenuTab") private var tab = Tab.scene.rawValue

    enum Tab: Int, CaseIterable, Identifiable {
        case scene, lyrics, chaos, camera
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .scene: "Scene"
            case .lyrics: "Lyrics"
            case .chaos: "Chaos"
            case .camera: "Camera"
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            presetRow
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch Tab(rawValue: tab) ?? .scene {
                    case .scene: sceneTab
                    case .lyrics: lyricsTab
                    case .chaos: chaosTab
                    case .camera: cameraTab
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            HStack {
                Spacer()
                Button("Reset All") { withAnimation { settings = FeverSettings() } }
                    .controlSize(.small)
            }
        }
        .padding(14)
        .playbackSettings("fever")
        .frame(width: 340, height: 540)
        .animation(.easeInOut(duration: 0.15), value: settings)
    }

    // MARK: Tabs

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(FeverSettings.Preset.allCases) { p in
                Button { withAnimation { settings.apply(p) } } label: {
                    Text(p.label).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity)
                }
            }
            Button { withAnimation { settings.randomize() } } label: { Image(systemName: "dice") }
                .help("Random chaos (keeps your scene)")
        }
        .controlSize(.regular)
    }

    @ViewBuilder private var sceneTab: some View {
        section("Time of day")
        chipGrid(FeverTime.allCases, columns: 3, selected: { settings.time == $0 }, label: \.label, symbol: \.symbol) {
            settings[.time] = Double($0.rawValue)
        }
        if settings.time == .auto {
            note("Uses each colour palette's own light.")
        } else if settings.time == .cycle {
            note("Dawn, day, sunset and night, slowly, about 8 minutes round.")
        }

        section("Weather")
        chipGrid(FeverWeather.allCases, columns: 5, selected: { settings.weather == $0 }, label: \.label, symbol: \.symbol) {
            settings[.weather] = Double($0.rawValue)
        }
        if settings.weather != .clear {
            slider("Intensity", "drop", .intensity)
        }

        section("Colours")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(0..<FeverPalette.count, id: \.self) { i in swatch(i) }
        }

        section("City")
        slider("Window lights", "building.2", .lights)
        slider("Clouds", "cloud", .clouds)
        slider("Traffic", "car.side", .traffic)

        section("Surprises")
        toggle("Day/night flips", "circle.lefthalf.filled", .flip, on: 0.5)
        note("Some song sections flip the sky to the other end of the day.")
        toggle("Colour swaps", "swatchpalette", .swap, on: 0.5)
        note("Some song sections swap to another palette, with a flash.")
    }

    @ViewBuilder private var lyricsTab: some View {
        toggle("Show lyrics", "text.bubble", .lyrics, on: 1)
        if settings.flag(.lyrics) {
            section("Where")
            chipGrid(FeverPlace.menuOrder, columns: 4, selected: { settings.place == $0 }, label: \.label, symbol: \.symbol) {
                settings[.place] = Double($0.rawValue)
            }
            note(settings.place == .everywhere || settings.place == .sky
                 ? "Each song section stays on one carrier and hands off to the next when the section changes."
                 : "Every line goes here, flowing on from the one before.")

            section("Lettering")
            HStack(spacing: 6) {
                ForEach(FeverFont.allCases) { font in
                    Button { settings[.font] = Double(font.rawValue) } label: {
                        VStack(spacing: 2) {
                            Text("Aa").font(font.font(20))
                            Text(font.label).font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .chipBackground(settings.font == font)
                    }
                    .buttonStyle(.plain)
                }
            }
            slider("Size", "textformat.size", .size)
            toggle("Capitals", "textformat.abc", .caps, on: 1)
        }
    }

    private static let tiles: [(FeverSettings.Key, String, String, String?)] = [
        (.ufo, "UFOs", "circle.dashed", "Abducts cars"),
        (.rocket, "Rockets", "airplane.departure", nil),
        (.balloons, "Balloons", "balloon", nil),
        (.fireworks, "Fireworks", "sparkles", "Shows now and then, plus bursts on big beats"),
        (.moon, "Moon face", "moon", "How often it winks"),
        (.whale, "Sky whale", "fish", nil),
        (.kaiju, "Kaiju", "lizard", nil),
        (.cat, "Giant cat", "cat", nil),
        (.parade, "Parades", "figure.walk", nil),
        (.donut, "Donut", "circle.circle", "A runaway giant donut"),
        (.signals, "Dancing lights", "light.beacon.min", "Traffic lights dance"),
        (.hop, "Hopping cars", "car.rear", "Cars jump on the beat (needs React to music)"),
        (.train, "Coaster", "tram", "A train that loops over the rooftops"),
        (.stretch, "Stretchy", "arrow.up.and.down", "Buildings bounce to the bass"),
    ]

    @ViewBuilder private var chaosTab: some View {
        slider("How often", "tornado", .chaos)
        note("Tap a tile to turn it on or off. Right-click it to set how often it happens.")
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Self.tiles, id: \.0) { key, label, symbol, hint in tile(key, label, symbol, hint) }
        }
    }

    @ViewBuilder private var cameraTab: some View {
        section("Camera")
        chipGrid(FeverCamera.allCases, columns: 3, selected: { settings.camera == $0 }, label: \.label, symbol: \.symbol) {
            settings[.camera] = Double($0.rawValue)
        }
        note(cameraNote)
        slider("Drift", "arrow.left.and.right", .speed)
        note("How fast the city slides past.")
        slider("Beat reaction", "waveform", .pulse)
        note("Needs React to music.")
    }

    private var cameraNote: String {
        switch settings.camera {
        case .driveBy: "A steady pan along the street."
        case .cuts: "Glides in close on new lyrics and big events, then eases back out."
        case .wild: "Drifts, tilts and speeds up on loud parts."
        }
    }

    // MARK: Pieces

    private func section(_ title: String) -> some View {
        SettingSection(title)
    }

    private func note(_ text: String) -> some View {
        SettingHint(text)
    }

    private func chipGrid<T: Identifiable>(_ items: [T], columns: Int, selected: @escaping (T) -> Bool,
                                           label: KeyPath<T, String>, symbol: KeyPath<T, String>,
                                           pick: @escaping (T) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(items) { item in
                Button { pick(item) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item[keyPath: symbol]).font(.system(size: 15))
                        Text(item[keyPath: label]).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .chipBackground(selected(item))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func swatch(_ i: Int) -> some View {
        let p = FeverPalette.preset(i, art: [])
        let isArt = i == FeverPalette.count - 1
        let on = Int(settings[.palette]) == i
        return Button { settings[.palette] = Double(i) } label: {
            VStack(spacing: 3) {
                ZStack {
                    LinearGradient(colors: isArt ? [.gray, .secondary] : [p.skyTop.color, p.skyMid.color, p.skyLow.color],
                                   startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(0..<4, id: \.self) { b in
                            Rectangle().fill(p.bldg[b].color).frame(height: [12, 18, 9, 15][b])
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .opacity(isArt ? 0 : 1)
                    if isArt { Image(systemName: "photo").foregroundStyle(.white) }
                }
                .frame(height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                Text(FeverPalette.names[i]).font(.system(size: 10, weight: .medium))
            }
            .padding(4)
            .chipBackground(on)
        }
        .buttonStyle(.plain)
    }

    private func tile(_ key: FeverSettings.Key, _ label: String, _ symbol: String, _ hint: String?) -> some View {
        let v = settings[key]
        let on = v > 0
        return Button {
            settings[key] = on ? 0 : 0.5
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 16))
                Text(label).font(.system(size: 9.5, weight: .medium)).lineLimit(1).minimumScaleFactor(0.75)
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { b in
                        Capsule().fill(v > Double(b) * 0.25 + 0.01 ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 7, height: 3)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .opacity(on ? 1 : 0.5)
            .chipBackground(on)
        }
        .buttonStyle(.plain)
        .help(hint ?? label)
        .contextMenu {
            ForEach([("Off", 0.0), ("Rare", 0.25), ("Some", 0.5), ("Lots", 0.75), ("Non-stop", 1.0)], id: \.0) { name, value in
                Button(name) { settings[key] = value }
            }
        }
    }

    private func toggle(_ title: String, _ symbol: String, _ key: FeverSettings.Key, on: Double) -> some View {
        SettingToggle(title: title, symbol: symbol, isOn: Binding(get: { settings[key] > 0 }, set: { settings[key] = $0 ? on : 0 }))
    }

    private func slider(_ title: String, _ symbol: String, _ key: FeverSettings.Key) -> some View {
        SettingSlider(title: title, symbol: symbol, value: Binding(get: { settings[key] }, set: { settings[key] = $0 }))
    }
}

private extension View {
    func chipBackground(_ selected: Bool) -> some View {
        self
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1.2))
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
