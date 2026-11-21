import SwiftUI

// MARK: - Playback controls
//
// Play/pause, previous and next for Spotify, shown as a small glass capsule at the bottom of
// every style window. Each style has its own setting (Off, Show on Hover, Always). The buttons
// drive Spotify through its AppleScript dictionary (`SpotifyBridge.send`), the same channel the
// app already reads the track from. That dictionary can't read the play queue, so there's no
// "Next Up" display.

enum PlaybackPrefs {
    enum Mode: Int, CaseIterable, Identifiable {
        case off, hover, always
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .off: "Off"
            case .hover: "On Hover"
            case .always: "Always"
            }
        }
    }

    static let defaultMode = Mode.hover
    static func key(_ styleID: String) -> String { "playbackControls.\(styleID)" }
}

/// The capsule of transport buttons over a style window.
struct PlaybackBar: View {
    @ObservedObject var model: PlayerModel
    let mode: PlaybackPrefs.Mode
    /// The pointer is over the window (and hasn't gone idle in full screen).
    let visible: Bool
    @State private var hoverBar = false

    var body: some View {
        let show = model.snapshot != nil && (mode == .always || (mode == .hover && visible))
        HStack(spacing: 2) {
            PlaybackButton(symbol: "backward.fill", size: 13, help: "Previous track") { model.control(.previous) }
            PlaybackButton(symbol: model.snapshot?.state == .playing ? "pause.fill" : "play.fill", size: 17,
                           help: model.snapshot?.state == .playing ? "Pause" : "Play") { model.control(.playPause) }
            PlaybackButton(symbol: "forward.fill", size: 13, help: "Next track") { model.control(.next) }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .environment(\.colorScheme, .dark)
        // "Always" stays quiet until you reach for it, so it doesn't compete with the lyrics.
        .opacity(show ? (mode == .always && !hoverBar && !visible ? 0.55 : 1) : 0)
        .offset(y: show ? 0 : 8)
        .animation(.easeOut(duration: 0.22), value: show)
        .animation(.easeOut(duration: 0.22), value: hoverBar || visible)
        .onHover { hoverBar = $0 }
        .allowsHitTesting(show)
        .padding(.bottom, 34)   // sits above each style's title/artist caption
        .help(model.playbackError ?? "")
    }
}

private struct PlaybackButton: View {
    let symbol: String
    let size: CGFloat
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(.white.opacity(hover ? 1 : 0.85))
                .frame(width: 38, height: 32)
                .background(Circle().fill(.white.opacity(hover ? 0.14 : 0)).frame(width: 32, height: 32))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Shrinks a touch while pressed, like the system's own media buttons.
private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Settings

/// The "Playback" group pinned to the bottom of every style's settings, so it's in the same
/// place whichever style you're adjusting.
struct PlaybackSettingsFooter: View {
    @AppStorage private var mode: Int

    init(styleID: String) {
        _mode = AppStorage(wrappedValue: PlaybackPrefs.defaultMode.rawValue, PlaybackPrefs.key(styleID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack {
                SettingLabel(title: "Playback", symbol: "playpause")
                Spacer()
                Picker("Playback controls", selection: $mode) {
                    ForEach(PlaybackPrefs.Mode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            SettingHint("Play, pause and skip buttons for Spotify in this style's window.")
                .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
        .background(.bar)
    }
}

extension View {
    /// Pins the shared Playback group under a style's settings.
    func playbackSettings(_ styleID: String) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { PlaybackSettingsFooter(styleID: styleID) }
    }
}
