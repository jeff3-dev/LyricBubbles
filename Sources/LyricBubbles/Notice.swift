import SwiftUI
import AppKit

/// The one-time welcome notice and the About panel. They say what LyricBubbles is (an
/// independent project), where the lyrics come from and who owns them.
enum Notice {
    static let seenKey = "welcomeNoticeSeenVersion"

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    static let points: [(symbol: String, text: String)] = [
        ("music.note", "LyricBubbles shows the lyrics of whatever the Spotify app for Mac is playing, in time with the song."),
        ("person.2.slash", "It's an independent project. It isn't made, endorsed or supported by Spotify or LRCLIB."),
        ("text.quote", "Lyrics come from LRCLIB and belong to their songwriters and publishers. They're shown for personal use."),
        ("lock", "The app only reads what Spotify is playing. If you turn on React to Music, audio is analysed live and never recorded or saved."),
    ]

    /// Shown once per version, the first time that version launches.
    static var due: Bool { UserDefaults.standard.string(forKey: seenKey) != version }

    static func showAbout() {
        let body = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: para,
        ]
        body.append(NSAttributedString(string: "Lyrics for whatever Spotify is playing, in nine visual styles.\n\n"
            + "Not affiliated with or endorsed by Spotify or LRCLIB. Lyrics are provided by LRCLIB and "
            + "belong to their owners.", attributes: attrs))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: body])
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Welcome notice

struct WelcomeNoticeView: View {
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to LyricBubbles").font(.system(size: 20, weight: .semibold))
                    Text("Version \(Notice.version)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Notice.points, id: \.text) { point in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: point.symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(.tint)
                            .frame(width: 22)
                        Text(point.text)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Get Started") {
                    UserDefaults.standard.set(Notice.version, forKey: Notice.seenKey)
                    dismissWindow(id: "welcome")
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 460)
    }
}
