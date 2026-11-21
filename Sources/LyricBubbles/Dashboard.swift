import SwiftUI

// MARK: - Style registry

/// A lyric experience the dashboard can open. Add new styles here: give each one a window
/// scene in `LyricBubblesApp` with the same `windowID`.
struct LyricStyle: Identifiable {
    let id: String
    let windowID: String
    let name: String
    let windowTitle: String
    let tagline: String
    let symbol: String
    let colors: [Color]
    let preview: Preview
    let shortcut: KeyEquivalent

    enum Preview { case messages, glass, neon, gotham, postcards, sky, kinetic, megaverse, fever }

    static let all: [LyricStyle] = [
        LyricStyle(id: "messages", windowID: "messages", name: "Messages", windowTitle: "Lyric Messages",
                   tagline: "Lyrics as a live text thread, with reactions, effects and a glow that moves with the music.",
                   symbol: "bubble.left.and.bubble.right.fill",
                   colors: [Color(red: 0.04, green: 0.52, blue: 1), Color(red: 0.55, green: 0.3, blue: 1)],
                   preview: .messages, shortcut: "m"),
        LyricStyle(id: "glass", windowID: "glass", name: "Fogged Glass", windowTitle: "Fogged Glass",
                   tagline: "Each line written by fingertip into a steamy window, then breathed away.",
                   symbol: "hand.draw.fill",
                   colors: [Color(red: 0.45, green: 0.68, blue: 0.9), Color(red: 0.12, green: 0.16, blue: 0.32)],
                   preview: .glass, shortcut: "g"),
        LyricStyle(id: "neon", windowID: "neon", name: "Neon Sign", windowTitle: "Neon Sign",
                   tagline: "Every part of the song is a neon sign on a brick wall at night.",
                   symbol: "lightbulb.max.fill",
                   colors: [Color(red: 1, green: 0.22, blue: 0.58), Color(red: 0.1, green: 0.04, blue: 0.16)],
                   preview: .neon, shortcut: "n"),
        LyricStyle(id: "gotham", windowID: "gotham", name: "Gotham Night", windowTitle: "Gotham Night",
                   tagline: "A searchlight throws each line onto the clouds above a rain-soaked city.",
                   symbol: "moon.stars.fill",
                   colors: [Color(red: 1, green: 0.84, blue: 0.4), Color(red: 0.03, green: 0.04, blue: 0.07)],
                   preview: .gotham, shortcut: "b"),
        LyricStyle(id: "postcards", windowID: "postcards", name: "Postcards", windowTitle: "Postcards",
                   tagline: "Each song becomes a retro travel poster that slowly comes alive.",
                   symbol: "sun.horizon.fill",
                   colors: [Color(red: 0.93, green: 0.42, blue: 0.27), Color(red: 0.17, green: 0.24, blue: 0.5)],
                   preview: .postcards, shortcut: "p"),
        LyricStyle(id: "sky", windowID: "sky", name: "Night Sky", windowTitle: "Night Sky",
                   tagline: "Words spelled in stars, as you fly from one constellation to the next.",
                   symbol: "sparkles",
                   colors: [Color(red: 0.55, green: 0.72, blue: 1), Color(red: 0.02, green: 0.03, blue: 0.1)],
                   preview: .sky, shortcut: "k"),
        LyricStyle(id: "kinetic", windowID: "kinetic", name: "Kinetic", windowTitle: "Kinetic",
                   tagline: "Lines pop in word by word, then the biggest word flies at you.",
                   symbol: "textformat.size.larger",
                   colors: [Color(red: 0.96, green: 0.3, blue: 0.22), Color(red: 0.16, green: 0.3, blue: 0.85)],
                   preview: .kinetic, shortcut: "j"),
        LyricStyle(id: "megaverse", windowID: "megaverse", name: "Megaverse", windowTitle: "Megaverse",
                   tagline: "Each section cuts to a new scene: a deco lounge, a noir street, a comic stage.",
                   symbol: "theatermasks.fill",
                   colors: [Color(red: 0.93, green: 0.72, blue: 0.3), Color(red: 0.05, green: 0.08, blue: 0.2)],
                   preview: .megaverse, shortcut: "u"),
        LyricStyle(id: "fever", windowID: "fever", name: "Fever City", windowTitle: "Fever City",
                   tagline: "Lyrics on billboards, blimps and skywriting over a toy-box city gone wild.",
                   symbol: "building.2.crop.circle.fill",
                   colors: [Color(red: 1, green: 0.5, blue: 0.62), Color(red: 0.2, green: 0.1, blue: 0.4)],
                   preview: .fever, shortcut: "c"),
    ]

    static func named(_ id: String) -> LyricStyle? { all.first { $0.id == id } }
}

enum LaunchPrefs {
    /// Style id to open straight away at launch, or "" for the dashboard.
    static let styleKey = "launchStyle"
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(LaunchPrefs.styleKey) private var launchStyle = ""

    /// Only skip the dashboard once per run, so it can still be reopened from the menu.
    private static var didAutoLaunch = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 24, alignment: .top)],
                          alignment: .leading, spacing: 28) {
                    ForEach(LyricStyle.all) { style in
                        StyleCard(style: style) { open(style) }
                    }
                }
                footer
            }
            .padding(.horizontal, 36)
            .padding(.top, 44)     // clears the traffic lights
            .padding(.bottom, 24)
        }
        .scrollIndicators(.automatic)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(edges: .top)
        .frame(minWidth: 620, minHeight: 480)
        .onAppear {
            guard !Self.didAutoLaunch else { return }
            Self.didAutoLaunch = true
            if let style = LyricStyle.named(launchStyle) {
                open(style)
            }
        }
    }

    private func open(_ style: LyricStyle) {
        openWindow(id: style.windowID)
        dismissWindow(id: "dashboard")
    }

    // MARK: Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                titleBlock
                Spacer(minLength: 0)
                NowPlayingPill(model: model)
            }
            VStack(alignment: .leading, spacing: 16) {
                titleBlock
                NowPlayingPill(model: model)
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("LyricBubbles")
                .font(.system(size: 28, weight: .bold))
            Text("Choose a style to watch the song.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Not affiliated with Spotify or LRCLIB. Lyrics belong to their owners.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            SettingsLink {
                Label("Settings", systemImage: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }
}

// MARK: - Pieces

/// What's playing, with play/pause and skip, in the dashboard's top-right corner.
struct NowPlayingPill: View {
    @ObservedObject var model: PlayerModel

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: model.snapshot?.artworkURL) { $0.resizable().scaledToFill() } placeholder: {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 170, alignment: .leading)

            if model.snapshot != nil {
                HStack(spacing: 0) {
                    transport("backward.fill", 11, "Previous track") { model.control(.previous) }
                    transport(model.snapshot?.state == .playing ? "pause.fill" : "play.fill", 15,
                              model.snapshot?.state == .playing ? "Pause" : "Play") { model.control(.playPause) }
                    transport("forward.fill", 11, "Next track") { model.control(.next) }
                }
            }
        }
        .padding(8)
        .padding(.trailing, model.snapshot == nil ? 8 : 2)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
        .help(model.playbackError ?? "")
    }

    private func transport(_ symbol: String, _ size: CGFloat, _ help: String, action: @escaping () -> Void) -> some View {
        TransportButton(symbol: symbol, size: size, help: help, action: action)
    }

    private var title: String {
        switch model.status {
        case .active(let s): s.title
        case .notRunning: "Spotify isn't open"
        case .stopped: "Nothing playing"
        case .error: "Can't reach Spotify"
        }
    }

    private var subtitle: String {
        switch model.status {
        case .active(let s): s.artist
        case .error(let msg): msg
        default: "Play a song in Spotify to begin"
        }
    }
}

private struct TransportButton: View {
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
                .foregroundStyle(hover ? .primary : .secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.primary.opacity(hover ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// One style: a live preview with its name and a line about it underneath.
struct StyleCard: View {
    let style: LyricStyle
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    switch style.preview {
                    case .messages: MessagesPreview()
                    case .glass: GlassPreview()
                    case .neon: NeonPreview()
                    case .gotham: GothamPreview()
                    case .fever: FeverPreview()
                    case .postcards: PostcardPreview()
                    case .sky: NightSkyPreview()
                    case .kinetic: KineticPreview()
                    case .megaverse: MegaversePreview()
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(hover ? 0.22 : 0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(hover ? 0.28 : 0.12), radius: hover ? 16 : 6, y: hover ? 8 : 3)
                .scaleEffect(hover ? 1.015 : 1)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(style.name).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                        Text("⇧⌘\(String(style.shortcut.character).uppercased())")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .opacity(hover ? 1 : 0)
                    }
                    Text(style.tagline)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(CardPressStyle())
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hover = h } }
        .help("Open \(style.name)")
        .accessibilityLabel("\(style.name). \(style.tagline)")
    }
}

private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// Looping mini thread: placeholder bubbles (no text) pop in on alternating sides.
struct MessagesPreview: View {
    private let widths: [CGFloat] = [92, 120, 70, 134, 104, 80]

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            let step = 0.9
            let n = Int(t / step)
            let phase = t - Double(n) * step
            VStack(spacing: 6) {
                ForEach(0..<4) { slot in
                    let k = n - 3 + slot
                    let outgoing = k % 2 != 0
                    let newest = slot == 3
                    let (p, _) = newest ? Spring.step(phase) : (1, 0)
                    HStack {
                        if outgoing { Spacer() }
                        Capsule()
                            .fill(outgoing ? Color.white : Color.white.opacity(0.28))
                            .frame(width: widths[((k % widths.count) + widths.count) % widths.count], height: 20)
                            .overlay(alignment: outgoing ? .trailing : .leading) {
                                if k % 3 == 0 && !newest {
                                    Circle().fill(.white).frame(width: 14, height: 14)
                                        .overlay(Image(systemName: "heart.fill").font(.system(size: 7)).foregroundStyle(.pink))
                                        .offset(x: outgoing ? -6 : 6, y: -12)
                                }
                            }
                            .scaleEffect(0.5 + 0.5 * p, anchor: outgoing ? .bottomTrailing : .bottomLeading)
                            .opacity(min(1, p * 2))
                        if !outgoing { Spacer() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .offset(y: 13 * (1 - Spring.step(phase, response: 0.5, damping: 0.9).0))
        }
    }
}
