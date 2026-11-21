import AppKit
import SwiftUI

// MARK: - Demo reel (hidden)
//
// A full-screen tour of every style for recording promo videos. It opens from ⌃⌥⌘D (while the
// app is in front). Night Sky
// opens as the hook and Messages comes last, then stays put. → / ← skip, Space pauses, Esc
// leaves. The pointer is hidden the whole time.

@MainActor
final class DemoReel: ObservableObject {
    /// Set by the app at launch; the reel shows what this model is playing.
    static weak var model: PlayerModel?

    /// Hook first, Messages last.
    static let order = ["sky", "neon", "gotham", "postcards", "glass", "messages"]
    /// Seconds on each style before moving on (the last one stays).
    static let dwell: Double = 8

    @Published private(set) var index = 0
    /// Which way the last switch went, so ← swipes back the other way.
    @Published private(set) var forward = true

    /// The next style, started early underneath the current one so its first (slowest)
    /// frames are drawn before anyone sees it. The switch then just swipes the current one away.
    @Published private(set) var preroll: Int?
    /// How long the next style runs hidden before the swipe.
    static let prerollTime: Double = 1.5

    /// The styles on screen: the current one and, while it warms up, the next.
    var mounted: [Int] { preroll.map { [$0, index] } ?? [index] }

    /// The automatic timer: dwell, warm up the next style, swipe.
    func runTimer() async {
        guard ready, !paused, index < Self.order.count - 1 else { return }
        try? await Task.sleep(for: .seconds(Self.dwell - Self.prerollTime))
        guard !Task.isCancelled else { return }
        preroll = index + 1
        forward = true
        try? await Task.sleep(for: .seconds(Self.prerollTime))
        guard !Task.isCancelled else { preroll = nil; return }
        swipe()
    }

    /// → / ←: a short warm-up (forward) or a quick fade (back), then switch.
    func step(_ delta: Int) {
        let i = index + delta
        guard (0..<Self.order.count).contains(i) else { return }
        forward = delta > 0
        preroll = forward ? i : nil
        Task {
            try? await Task.sleep(for: .milliseconds(forward ? 400 : 30))
            if forward { swipe() } else { withAnimation(.easeInOut(duration: 0.45)) { index = i } }
        }
    }

    private func swipe() {
        guard let next = preroll else { return }
        withAnimation(.easeInOut(duration: 0.55)) {
            index = next
            preroll = nil
        }
    }
    @Published var paused = false
    /// False while the styles are being built ahead of time (the screen stays black).
    @Published var ready = false

    // Built once before the reel starts and handed to every style, so a switch never has to
    // lay out lyrics, generate a city or process album art in the middle of a crossfade.
    let sky = SkyProgramCache()
    let neon = NeonProgramCache()
    let gothamFX = GothamFX()
    let gothamScript = GothamScriptCache()
    let postcards = PostcardScriptCache()
    var glassArt: ArtLayers?

    /// Loads every style's textures and renders each style once offscreen, filling the caches.
    func prepare(model: PlayerModel, size: CGSize) async {
        async let a = NeonTextures.shared.value
        async let b = SkyTextures.shared.value
        async let c = GothamTextures.shared.value
        async let d = GlassTextures.shared.value
        async let e = PostcardGrain.shared.value
        _ = await (a, b, c, d, e)
        // Give a just-changed song a moment to fetch its lyrics.
        for _ in 0..<50 where model.loadingLyrics { try? await Task.sleep(for: .milliseconds(100)) }
        if let url = model.snapshot?.artworkURL, let (data, _) = try? await URLSession.shared.data(from: url) {
            glassArt = await ArtLayers.make(from: data)
        }
        // Lay out the lyrics directly (reading the settings but never changing them).
        if case .active(let snap) = model.status, case .synced(let lines) = model.lyrics {
            let d = UserDefaults.standard
            let skyS = d.string(forKey: SkySettings.storageKey).flatMap(SkySettings.init(rawValue:)) ?? SkySettings()
            let neonS = d.string(forKey: NeonSettings.storageKey).flatMap(NeonSettings.init(rawValue:)) ?? NeonSettings()
            _ = sky.flight(lines: lines, title: snap.title, s: skyS)
            _ = neon.plans(lines: lines, title: snap.title, maxRows: neonS.lines)
            _ = gothamScript.lines(lines, title: snap.title)
            _ = postcards.pages(lines, title: snap.title)
        }
        for id in Self.order {
            let r = ImageRenderer(content: DemoReelView.style(id, reel: self, model: model)
                .frame(width: size.width, height: size.height))
            _ = r.cgImage
            await Task.yield()
        }
        ready = true
    }

    private static var current: (reel: DemoReel, window: NSWindow)?
    private static var keyMonitor: Any?
    private static var closeObserver: NSObjectProtocol?

    static var isRunning: Bool { current != nil }

    static func toggle() { isRunning ? stop() : start() }

    static func start() {
        guard current == nil, let model else { return }
        let reel = DemoReel()
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = NSWindow(contentRect: screen.insetBy(dx: screen.width * 0.1, dy: screen.height * 0.1),
                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "LyricBubbles Demo"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.backgroundColor = .black
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.fullScreenPrimary]
        w.contentView = NSHostingView(rootView: DemoReelView(reel: reel, model: model))
        current = (reel, w)
        let size = w.screen?.frame.size ?? screen.size
        Task { await reel.prepare(model: model, size: size) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { cleanUp() }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        NSCursor.hide()
        DispatchQueue.main.async { w.toggleFullScreen(nil) }
    }

    static func stop() {
        guard let w = current?.window else { return }
        if w.styleMask.contains(.fullScreen) {
            final class Box: @unchecked Sendable { var token: NSObjectProtocol? }
            let box = Box()
            box.token = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: w, queue: .main) { _ in
                if let token = box.token { NotificationCenter.default.removeObserver(token) }
                MainActor.assumeIsolated { w.close() }
            }
            w.toggleFullScreen(nil)
        } else {
            w.close()
        }
    }

    private static func cleanUp() {
        guard current != nil else { return }
        current = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        NSCursor.unhide()
    }

    /// ⌃⌥⌘D anywhere in the app; Esc, arrows and Space inside the reel.
    static func installShortcut() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chord = mods == [.control, .option, .command] && e.charactersIgnoringModifiers?.lowercased() == "d"
            let code = e.keyCode
            let used = MainActor.assumeIsolated { () -> Bool in
                if chord { toggle(); return true }
                guard let (reel, w) = current, NSApp.keyWindow === w else { return false }
                switch code {
                case 53: stop()                                                   // Esc
                case 124: reel.step(1)                                            // →
                case 123: reel.step(-1)                                           // ←
                case 49: reel.paused.toggle()                                     // Space
                default: return false
                }
                return true
            }
            return used ? nil : e
        }
    }
}

struct DemoReelView: View {
    @ObservedObject var reel: DemoReel
    @ObservedObject var model: PlayerModel

    var body: some View {
        ZStack {
            Color.black
            if reel.ready {
                ForEach(reel.mounted, id: \.self) { i in
                    let id = DemoReel.order[i]
                    let current = i == reel.index
                    Self.style(id, reel: reel, model: model)
                        // The title starts when its style comes on, not while it warms up.
                        .overlay { if current { DemoTitle(styleID: id) } }
                        .zIndex(current ? 1 : 0)
                        // Forward: the current style swipes away, uncovering the next one,
                        // which is already running underneath. Back: a quick fade.
                        .transition(reel.forward
                                    ? .asymmetric(insertion: .identity, removal: .move(edge: .leading))
                                    : .opacity)
                }
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1), value: reel.ready)
        .task(id: "\(reel.index)-\(reel.paused)-\(reel.ready)") { await reel.runTimer() }
    }

    @MainActor @ViewBuilder
    static func style(_ id: String, reel: DemoReel, model: PlayerModel) -> some View {
        switch id {
        case "sky": NightSkyView(model: model, programs: reel.sky)
        case "neon": NeonSignView(model: model, programs: reel.neon)
        case "gotham": GothamView(model: model, fx: reel.gothamFX, script: reel.gothamScript)
        case "postcards": PostcardView(model: model, script: reel.postcards)
        case "glass": FogGlassView(model: model, art: reel.glassArt)
        default:
            // Same as the Messages window in full screen: a centred thread, not 5K wide.
            ZStack {
                Color(nsColor: .underPageBackgroundColor)
                ChatView(model: model)
                    .overlay { GlowBorder(model: model) }
                    .frame(maxWidth: 620)
            }
        }
    }
}

// MARK: - Style titles (demo only)

/// The style's name, drawn in that style's own look: a starry serif for Night Sky, a lit neon
/// script, a Gotham searchlight caption, a "Greetings from" postcard banner, a word wiped
/// into the fog, and a Messages conversation header.
struct DemoTitle: View {
    let styleID: String
    @State private var shown = false
    var still = false

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.height, geo.size.width * 0.6) / 1000   // 1 at about 1000 pt tall
            title(u)
                .frame(maxWidth: .infinity)
                .padding(.top, styleID == "messages" ? 0 : geo.size.height * 0.07)
                .opacity(shown || still ? 1 : 0)
                .offset(y: shown || still ? 0 : -12 * u)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.35)) { shown = true }
        }
    }

    @ViewBuilder private func title(_ u: CGFloat) -> some View {
        switch styleID {
        case "sky":
            HStack(spacing: 18 * u) {
                Image(systemName: "sparkle").font(.system(size: 18 * u, weight: .light))
                Text("NIGHT SKY")
                    .font(.custom("AvenirNext-UltraLight", size: 54 * u))
                    .tracking(22 * u)
                Image(systemName: "sparkle").font(.system(size: 18 * u, weight: .light))
            }
            .foregroundStyle(.white)
            .shadow(color: Color(red: 0.6, green: 0.75, blue: 1).opacity(0.9), radius: 6 * u)
            .shadow(color: Color(red: 0.4, green: 0.5, blue: 1).opacity(0.6), radius: 24 * u)

        case "neon":
            NeonTitle(u: u)

        case "gotham":
            VStack(spacing: 6 * u) {
                Text("GOTHAM NIGHT")
                    .font(.custom("AvenirNextCondensed-Bold", size: 64 * u))
                    .tracking(10 * u)
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.7),
                                                             Color(red: 0.85, green: 0.68, blue: 0.35)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.9), radius: 3 * u, y: 3 * u)
                    .shadow(color: Color(red: 1, green: 0.85, blue: 0.5).opacity(0.35), radius: 30 * u)
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Color(red: 1, green: 0.88, blue: 0.55), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 420 * u, height: 2 * u)
            }

        case "postcards":
            VStack(spacing: 2 * u) {
                Text("GREETINGS FROM")
                    .font(.custom("Futura-CondensedExtraBold", size: 20 * u))
                    .tracking(8 * u)
                    .foregroundStyle(Color(red: 0.98, green: 0.93, blue: 0.82))
                ZStack {
                    Text("Postcards")
                        .font(.custom("SnellRoundhand-Black", size: 84 * u))
                        .foregroundStyle(Color(red: 0.78, green: 0.3, blue: 0.18))
                        .offset(x: 4 * u, y: 4 * u)
                    Text("Postcards")
                        .font(.custom("SnellRoundhand-Black", size: 84 * u))
                        .foregroundStyle(Color(red: 0.99, green: 0.94, blue: 0.84))
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 8 * u, y: 3 * u)

        case "glass":
            FogTitle(u: u)

        default:
            MessagesHeader(u: u)
        }
    }
}

/// A neon script that buzzes on: a couple of flickers, then a steady glow.
private struct NeonTitle: View {
    let u: CGFloat
    @State private var lit = false

    var body: some View {
        let pink = Color(red: 1, green: 0.25, blue: 0.65)
        Text("Neon Sign")
            .font(.custom("SnellRoundhand-Black", size: 78 * u))
            .foregroundStyle(Color(red: 1, green: 0.88, blue: 0.95))
            .shadow(color: pink, radius: 2 * u)
            .shadow(color: pink, radius: 10 * u)
            .shadow(color: pink.opacity(0.8), radius: 28 * u)
            .keyframeAnimator(initialValue: 0.15, trigger: lit) { view, glow in
                view.opacity(glow)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0.15, duration: 0.4)
                    CubicKeyframe(1, duration: 0.06)
                    CubicKeyframe(0.2, duration: 0.08)
                    CubicKeyframe(0.9, duration: 0.07)
                    CubicKeyframe(0.35, duration: 0.12)
                    CubicKeyframe(1, duration: 0.1)
                }
            }
            .onAppear { lit = true }
    }
}

/// Handwriting wiped into the fog, left to right, like a fingertip.
private struct FogTitle: View {
    let u: CGFloat
    @State private var wiped = false

    var body: some View {
        Text("Fogged Glass")
            .font(.custom("BradleyHandITCTT-Bold", size: 72 * u))
            .foregroundStyle(.white.opacity(0.82))
            .shadow(color: .white.opacity(0.5), radius: 6 * u)
            .shadow(color: .black.opacity(0.25), radius: 2 * u, y: 1 * u)
            .mask(alignment: .leading) {
                GeometryReader { g in
                    LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: wiped ? g.size.width * 1.2 : 0)
                }
            }
            .onAppear { withAnimation(.easeInOut(duration: 1.3).delay(0.45)) { wiped = true } }
    }
}

/// The top of a Messages conversation, with "LyricBubbles" as the contact.
private struct MessagesHeader: View {
    let u: CGFloat

    var body: some View {
        let s = max(u, 0.8)
        VStack(spacing: 5 * s) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 0.04, green: 0.52, blue: 1),
                                                      Color(red: 0.55, green: 0.3, blue: 1)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22 * s))
                    .foregroundStyle(.white)
            }
            .frame(width: 54 * s, height: 54 * s)
            HStack(spacing: 3 * s) {
                Text("Messages").font(.system(size: 14 * s, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 10 * s, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 14 * s)
        .padding(.bottom, 10 * s)
        .frame(maxWidth: 620)
        .background(.bar)
    }
}

