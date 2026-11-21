import SwiftUI

/// UserDefaults keys for the strength sliders (0 = off, 1 = max).
enum Strength {
    static let emoji = "sEmoji"
    static let reactions = "sReactions"
    static let bubble = "sBubble"
    static let screen = "sScreen"
    static let attachments = "sAttach"
    static let banners = "sBanners"

    static func set(_ i: Intensity) {
        let d = UserDefaults.standard
        d.set(i.emoji, forKey: emoji)
        d.set(i.reactions, forKey: reactions)
        d.set(i.bubble, forKey: bubble)
        d.set(i.screen, forKey: screen)
        d.set(i.attachments, forKey: attachments)
        d.set(i.banners, forKey: banners)
    }
}

/// Style picker plus one strength slider per extra. Used in the popover and in Settings (⌘,).
struct ExtrasPanel: View {
    @AppStorage("bubbleSide") private var sideRaw = BubbleSide.alternate.rawValue
    @AppStorage(MotionPrefs.blurKey) private var motionBlurAmount = 0.5
    @AppStorage(MotionPrefs.zoomKey) private var focusZoom = true
    @AppStorage(GlowPrefs.on) private var glowOn = true
    @AppStorage(GlowPrefs.palette) private var glowPalette = GlowPalette.intelligence.rawValue
    @AppStorage(GlowPrefs.width) private var glowWidth = 0.45
    @AppStorage(GlowPrefs.speed) private var glowSpeed = 0.35
    @AppStorage(Strength.emoji) private var emoji = Intensity.calm.emoji
    @AppStorage(Strength.reactions) private var reactions = Intensity.calm.reactions
    @AppStorage(Strength.bubble) private var bubble = Intensity.calm.bubble
    @AppStorage(Strength.screen) private var screen = Intensity.calm.screen
    @AppStorage(Strength.attachments) private var attachments = Intensity.calm.attachments
    @AppStorage(Strength.banners) private var banners = Intensity.calm.banners

    var body: some View {
        ScrollView {
            content
        }
        .playbackSettings("messages")
        .frame(width: 320)
        .frame(maxHeight: 640)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingSection("Conversation")
            Picker("Bubbles", selection: $sideRaw) {
                ForEach(BubbleSide.allCases) { Text($0.label).tag($0.rawValue) }
            }

            Divider()

            SettingSection("Strength")
            slider("Emojis", "face.smiling", $emoji, hint: "Emoji on lines, big emoji replies")
            slider("Reactions", "heart.circle", $reactions, hint: "Tapbacks and stickers")
            slider("Bubble effects", "bubble.left.and.exclamationmark.bubble.right", $bubble, hint: "Slam, Loud, Gentle")
            slider("Screen effects", "sparkles", $screen, hint: "Confetti, balloons, hearts, fireworks")
            slider("Attachments", "paperclip", $attachments, hint: "Maps, weather, voice, photos, invites")
            slider("Notifications", "bell.badge", $banners, hint: "Banners sliding in from the top")

            Divider()

            HStack {
                Button("Off") { Strength.set(.off) }
                Button("Calm") { Strength.set(.calm) }
                Button("Lively") { Strength.set(.lively) }
                Spacer()
            }
            .controlSize(.small)

            Divider()

            SettingSection("Motion")
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    SettingLabel(title: "Motion blur", symbol: "wind")
                    Spacer()
                    Text(MotionPrefs.label(motionBlurAmount)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Slider(value: $motionBlurAmount, in: 0...1).controlSize(.small)
                SettingHint("Blurs bubbles, stickers, banners and confetti while they move fast.")
            }
            SettingToggle(title: "Zoom into maps", symbol: "plus.magnifyingglass", isOn: $focusZoom,
                          hint: "While a map is live, the chat zooms onto it, then eases back before the next message.")

            Divider()

            HStack {
                SettingSection("Glow border")
                Spacer()
                Toggle("", isOn: $glowOn.animation(.easeInOut(duration: 0.4))).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            }
            Group {
                Picker("Colors", selection: $glowPalette) {
                    ForEach(GlowPalette.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .font(.system(size: 12))
                plainSlider("Thickness", "rectangle.dashed", $glowWidth)
                plainSlider("Speed", "arrow.triangle.2.circlepath", $glowSpeed)
            }
            .disabled(!glowOn)
            .opacity(glowOn ? 1 : 0.45)

            SettingHint("To make the glow move with the music, turn on React to Music in Settings ▸ General.")
        }
        .padding(16)
    }

    private func plainSlider(_ title: String, _ symbol: String, _ value: Binding<Double>) -> some View {
        SettingSlider(title: title, symbol: symbol, value: value, offAtZero: false)
    }

    private func slider(_ title: String, _ symbol: String, _ value: Binding<Double>, hint: String) -> some View {
        SettingSlider(title: title, symbol: symbol, value: value, hint: hint)
    }
}
