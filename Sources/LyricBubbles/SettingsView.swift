import SwiftUI

/// Settings as a sidebar list. (A tab toolbar can't fit seven tabs in a 320 pt window, and
/// macOS greys out the tabs it moves into the overflow menu.)
struct SettingsView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("settingsPane") private var pane = "general"

    private static let panes: [(id: String, name: String, symbol: String)] = [
        ("general", "General", "gearshape"),
        ("messages", "Messages", "bubble.left.and.bubble.right"),
        ("glass", "Fogged Glass", "hand.draw"),
        ("neon", "Neon Sign", "lightbulb.max"),
        ("gotham", "Gotham Night", "moon.stars"),
        ("postcards", "Postcards", "sun.horizon"),
        ("sky", "Night Sky", "sparkles"),
        ("kinetic", "Kinetic", "textformat.size.larger"),
        ("megaverse", "Megaverse", "theatermasks"),
        ("fever", "Fever City", "building.2"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { Optional(pane) }, set: { if let p = $0 { pane = p } })) {
                ForEach(Self.panes, id: \.id) { p in
                    Label(p.name, systemImage: p.symbol).tag(p.id)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 170)
            Divider()
            detail
                .frame(minWidth: 460, maxHeight: .infinity, alignment: .top)
        }
        .frame(minHeight: 460)
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case "glass": GlassControls()
        case "neon": NeonControls()
        case "gotham": GothamControls()
        case "postcards": PostcardControls()
        case "sky": SkyControls()
        case "kinetic": KineticControls()
        case "megaverse": MegaControls()
        case "fever": FeverControls()
        case "general": GeneralSettings(audio: model.audio, model: model)
        default: ExtrasPanel()
        }
    }
}

/// Settings that apply to every style.
struct GeneralSettings: View {
    @ObservedObject var audio: AudioReactor
    @ObservedObject var model: PlayerModel
    @AppStorage(LaunchPrefs.styleKey) private var launchStyle = ""
    @AppStorage("floatOnTop") private var floatOnTop = true
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(AudioReactor.sourceKey) private var audioSource = AudioReactor.Source.off.rawValue
    @AppStorage(GlowPrefs.sensitivity) private var sensitivity = 0.6
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingSection("Startup")
                HStack {
                    SettingLabel(title: "At launch, open", symbol: "power")
                    Spacer()
                    Picker("At launch, open", selection: $launchStyle) {
                        Text("Dashboard").tag("")
                        Divider()
                        ForEach(LyricStyle.all) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Divider()
                SettingSection("Windows")
                SettingToggle(title: "Float on top", symbol: "pin", isOn: $floatOnTop,
                              hint: "Keeps style windows above other apps. Full screen always works either way. (⇧⌘T)")

                Divider()
                SettingSection("Lyric timing")
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        SettingLabel(title: "Show lyrics", symbol: "clock.arrow.2.circlepath")
                        Spacer()
                        Text(timingLabel).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                        Button("Reset") { leadTime = 0.25 }
                            .controlSize(.small)
                            .disabled(abs(leadTime - 0.25) < 0.001)
                    }
                    Slider(value: $leadTime, in: -1...1.5, step: 0.05).controlSize(.small)
                    SettingHint("Nudge this if lyrics land early or late for you. ⌘[ and ⌘] work from any window.")
                }
                if model.snapshot != nil {
                    HStack {
                        SettingLabel(title: "This song", symbol: "music.note")
                        Spacer()
                        Text(songNudgeLabel).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                        Button("Reset") { model.resetSongNudge() }
                            .controlSize(.small)
                            .disabled(model.songNudge == 0)
                    }
                    SettingHint("If only one song is off, fix just that song with ⌥⌘[ and ⌥⌘]. It's remembered.")
                }

                Divider()
                SettingSection("React to music")
                Picker("Listen to", selection: $audioSource) {
                    ForEach(AudioReactor.Source.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: audioSource) {
                    audio.setSource(AudioReactor.Source(rawValue: audioSource) ?? .off)
                }
                SettingSlider(title: "Sensitivity", symbol: "waveform", value: $sensitivity, offAtZero: false)
                    .disabled(audioSource == AudioReactor.Source.off.rawValue)
                    .opacity(audioSource == AudioReactor.Source.off.rawValue ? 0.45 : 1)
                if !audio.status.isEmpty {
                    SettingHint(audio.status)
                }
                SettingHint("Lets the Messages glow and each style's beat effects move with the song. System audio hears whatever your Mac plays; macOS asks once for permission. Nothing is recorded.")

                Divider()
                SettingSection("About")
                HStack {
                    Button("Show Welcome Notice") { openWindow(id: "welcome") }
                    Button("About LyricBubbles") { Notice.showAbout() }
                }
                .controlSize(.small)
            }
            .padding(16)
        }
        .frame(width: 320)
        .frame(maxHeight: 640)
    }

    private var songNudgeLabel: String {
        let ms = Int((model.songNudge * 1000).rounded())
        if ms == 0 { return "As above" }
        return ms > 0 ? "\(ms) ms earlier" : "\(-ms) ms later"
    }

    private var timingLabel: String {
        let ms = Int((leadTime * 1000).rounded())
        if ms == 250 { return "On time" }
        let shift = ms - 250
        return shift > 0 ? "\(shift) ms earlier" : "\(-shift) ms later"
    }
}
