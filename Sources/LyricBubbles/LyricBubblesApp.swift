import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Lets the app take focus even when launched as a bare binary (swift run).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        #if DEBUG
        DebugSnapshot.start()   // developer aid, left out of release builds
        #endif
        WindowChrome.installEscape()
        DemoReel.installShortcut()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct LyricBubblesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = PlayerModel()
    @Environment(\.openWindow) private var openWindow
    @AppStorage("bubbleSide") private var sideRaw = BubbleSide.alternate.rawValue
    @AppStorage("floatOnTop") private var floatOnTop = true
    @AppStorage("leadTime") private var leadTime = 0.25

    private static var didCheckNotice = false

    private static func title(_ id: String) -> String { LyricStyle.named(id)?.windowTitle ?? id }

    var body: some Scene {
        // Home: pick a style. Opens first at launch.
        Window("LyricBubbles", id: "dashboard") {
            DashboardView(model: model)
                .onAppear(perform: bootstrap)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 640)
        .commands { commands }

        // Style: Messages (lyrics as a text thread).
        Window(Self.title("messages"), id: "messages") {
            ChatView(model: model)
                .frame(minWidth: 300, idealWidth: 360, minHeight: 420, idealHeight: 620)
                .styleChrome("messages", model: model, scalesInFullScreen: true)
                .overlay { GlowBorder(model: model) }
                .onAppear {
                    bootstrap()
                    applyFloat()
                }
                .onChange(of: floatOnTop) { applyFloat() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 360, height: 620)
        .windowManagerRole(.principal)   // full screen, like a main window

        // Style: Fogged Glass (lyrics written into a steamy window).
        Window(Self.title("glass"), id: "glass") {
            FogGlassView(model: model)
                .frame(minWidth: 320, idealWidth: 440, minHeight: 400, idealHeight: 600)
                .styleChrome("glass", model: model)
                .onAppear {
                    bootstrap()
                    applyFloat()
                }
                .onChange(of: floatOnTop) { applyFloat() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 440, height: 600)
        .windowManagerRole(.principal)   // full screen, like a main window

        // Style: Neon Sign (each part of the song is a neon sign on a wall at night).
        Window(Self.title("neon"), id: "neon") {
            NeonSignView(model: model)
                .frame(minWidth: 380, idealWidth: 640, minHeight: 300, idealHeight: 440)
                .styleChrome("neon", model: model)
                .onAppear {
                    bootstrap()
                    applyFloat()
                }
                .onChange(of: floatOnTop) { applyFloat() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 640, height: 440)
        .windowManagerRole(.principal)   // full screen, like a main window

        // Style: Gotham Night (lyrics thrown onto the clouds above a dark, rainy city).
        Window(Self.title("gotham"), id: "gotham") {
            GothamView(model: model)
                .frame(minWidth: 420, idealWidth: 760, minHeight: 300, idealHeight: 460)
                .styleChrome("gotham", model: model)
                .onAppear {
                    bootstrap()
                    applyFloat()
                }
                .onChange(of: floatOnTop) { applyFloat() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 460)
        .windowManagerRole(.principal)   // full screen, like a main window

        // Style: Fever City (a toy-box city on crack; lyrics on billboards, blimps and skywriting).
        Window(Self.title("fever"), id: "fever") {
            FeverView(model: model)
                .frame(minWidth: 420, idealWidth: 760, minHeight: 300, idealHeight: 460)
                .styleChrome("fever", model: model)
                .onAppear {
                    bootstrap()
                    applyFloat()
                }
                .onChange(of: floatOnTop) { applyFloat() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 460)
        .windowManagerRole(.principal)   // full screen, like a main window

        // Style: Postcards (each part of the song is a living retro travel poster).
        Window(Self.title("postcards"), id: "postcards") {
            PostcardView(model: model)
                .frame(minWidth: 380, idealWidth: 760, minHeight: 300, idealHeight: 520)
                .styleChrome("postcards", model: model)
                .onAppear {
                    bootstrap()
                    applyFloat()
                }
                .onChange(of: floatOnTop) { applyFloat() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 520)
        .windowManagerRole(.principal)   // full screen, like a main window

        // Style: Night Sky (constellations of stars, reached by flying through the night).
        Window(Self.title("sky"), id: "sky") {
            NightSkyView(model: model)
                .frame(minWidth: 400, idealWidth: 760, minHeight: 300, idealHeight: 480)
                .styleChrome("sky", model: model)
                .onAppear {
                    bootstrap()
                    applyFloat()
                }
                .onChange(of: floatOnTop) { applyFloat() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 480)
        .windowManagerRole(.principal)   // full screen, like a main window

        // Style: Kinetic (big words fly at the camera over blurred album art or a scene).
        Window(Self.title("kinetic"), id: "kinetic") {
            KineticView(model: model)
                .frame(minWidth: 380, idealWidth: 760, minHeight: 300, idealHeight: 480)
                .styleChrome("kinetic", model: model)
                .onAppear {
                    bootstrap()
                    applyFloat()
                }
                .onChange(of: floatOnTop) { applyFloat() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 480)
        .windowManagerRole(.principal)   // full screen, like a main window

        // Style: Megaverse (deco, noir, comic and neon scenes that cut on each section).
        Window(Self.title("megaverse"), id: "megaverse") {
            MegaverseView(model: model)
                .frame(minWidth: 380, idealWidth: 760, minHeight: 300, idealHeight: 480)
                .styleChrome("megaverse", model: model)
                .onAppear {
                    bootstrap()
                    applyFloat()
                }
                .onChange(of: floatOnTop) { applyFloat() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 480)
        .windowManagerRole(.principal)   // full screen, like a main window

        Settings {
            SettingsView(model: model)
        }

        // Welcome notice: opens on the first launch of each version, and from Help.
        Window("Welcome to LyricBubbles", id: "welcome") {
            WelcomeNoticeView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
    }

    @CommandsBuilder private var commands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About LyricBubbles") { Notice.showAbout() }
        }
        CommandGroup(replacing: .help) {
            Button("Welcome to LyricBubbles…") { openWindow(id: "welcome") }
        }
        CommandMenu("Styles") {
            Button("Back to Dashboard") {
                let w = NSApp.keyWindow
                if WindowChrome.isStyleWindow(w) {
                    WindowChrome.backToDashboard(from: w, open: openWindow)
                } else {
                    openWindow(id: "dashboard")
                }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Toggle Full Screen") {
                let w = NSApp.keyWindow
                if WindowChrome.isStyleWindow(w) { WindowChrome.toggleFullScreen(w) }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            Toggle("Float on Top", isOn: $floatOnTop)
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            ForEach(LyricStyle.all) { style in
                Button(style.name) { openWindow(id: style.windowID) }
                    .keyboardShortcut(style.shortcut, modifiers: [.command, .shift])
            }
        }
        CommandMenu("Messages") {
            Picker("Bubble Style", selection: $sideRaw) {
                ForEach(BubbleSide.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Divider()
            SettingsLink { Text("Strength Sliders…") }
            Button("Extras: Off") { Strength.set(.off) }
            Button("Extras: Calm") { Strength.set(.calm) }
            Button("Extras: Lively") { Strength.set(.lively) }
        }
        CommandMenu("Playback") {
            Button("Play/Pause") { model.control(.playPause) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Next Track") { model.control(.next) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Previous Track") { model.control(.previous) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Divider()
            Button("Lyrics Earlier") { leadTime += 0.1 }
                .keyboardShortcut("[", modifiers: .command)
            Button("Lyrics Later") { leadTime -= 0.1 }
                .keyboardShortcut("]", modifiers: .command)
            Button("Reset Timing") { leadTime = 0.25 }
            Divider()
            Button("This Song Earlier") { model.nudgeSong(by: 0.1) }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(model.snapshot == nil)
            Button("This Song Later") { model.nudgeSong(by: -0.1) }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(model.snapshot == nil)
            Button("Reset This Song's Timing") { model.resetSongNudge() }
                .disabled(model.songNudge == 0)
        }
    }

    /// Shared startup, safe to call from any window: Spotify polling and the audio source.
    private func bootstrap() {
        // Duet style was removed; move anyone still on it to the conversation style.
        if BubbleSide(rawValue: sideRaw) == nil { sideRaw = BubbleSide.alternate.rawValue }
        if !Self.didCheckNotice {
            Self.didCheckNotice = true
            if Notice.due { openWindow(id: "welcome") }
        }
        DemoReel.model = model
        model.start()
        let stored = UserDefaults.standard.string(forKey: AudioReactor.sourceKey) ?? "off"
        model.audio.setSource(AudioReactor.Source(rawValue: stored) ?? .off)
    }

    /// Float on Top applies to the lyric style windows (not the dashboard, not while full screen).
    private func applyFloat() {
        DispatchQueue.main.async { WindowChrome.applyFloat() }
    }
}
