import AppKit
import SwiftUI

// MARK: - Style window chrome
//
// Shared by every lyric style window: real full screen (its own Space, menu bar and Dock
// hidden), Esc to leave it, the pointer hiding when the mouse rests, Float on Top kept out of
// the way while full screen, and a small hover bar to go back to the dashboard.

enum WindowChrome {
    static var styleTitles: Set<String> { Set(LyricStyle.all.map(\.windowTitle)) }

    static func isStyleWindow(_ w: NSWindow?) -> Bool {
        guard let w else { return false }
        return styleTitles.contains(w.title)
    }

    /// SwiftUI marks every window but the first scene's as auxiliary with `fullScreenNone`,
    /// which greys out full screen, and it can put that back after we change it. So this is
    /// applied again before every toggle and whenever the window becomes key.
    static func allowFullScreen(_ w: NSWindow) {
        w.collectionBehavior.remove([.fullScreenNone, .fullScreenAuxiliary])
        w.collectionBehavior.insert(.fullScreenPrimary)
    }

    /// Float on Top for the style windows (never the dashboard, never while full screen:
    /// a floating window can't go full screen properly).
    static func applyFloat() {
        let float = UserDefaults.standard.object(forKey: "floatOnTop") as? Bool ?? true
        for w in NSApp.windows where isStyleWindow(w) {
            allowFullScreen(w)
            w.isMovableByWindowBackground = true
            guard !w.styleMask.contains(.fullScreen) else { continue }
            w.level = float ? .floating : .normal
        }
    }

    static func toggleFullScreen(_ w: NSWindow?) {
        guard let w else { return }
        guard !w.styleMask.contains(.fullScreen) else { w.toggleFullScreen(nil); return }
        // SwiftUI turns full screen off (fullScreenNone) for floating windows and only turns it
        // back on once the window is at the normal level, so drop the level first and go full
        // screen on the next turn of the run loop.
        w.level = .normal
        DispatchQueue.main.async {
            allowFullScreen(w)
            w.toggleFullScreen(nil)
        }
    }

    /// Opens the dashboard and closes the style window (works from full screen too).
    static func backToDashboard(from w: NSWindow?, open: OpenWindowAction) {
        open(id: "dashboard")
        // Close after the dashboard exists, so the app doesn't quit on its last window closing.
        DispatchQueue.main.async { w?.close() }
    }

    private static var escMonitor: Any?

    /// Esc leaves full screen in a style window. (Popovers are their own key window, so Esc
    /// still closes them as usual.)
    static func installEscape() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53, let w = NSApp.keyWindow, isStyleWindow(w), w.styleMask.contains(.fullScreen) {
                w.toggleFullScreen(nil)
                return nil
            }
            return e
        }
    }
}

/// Tracks one style window's full-screen state and idle pointer.
@MainActor
final class StyleWindowState: ObservableObject {
    @Published private(set) var isFullScreen = false
    @Published private(set) var idle = false
    private(set) weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var lastMove = Date()

    func attach(_ w: NSWindow) {
        guard w !== window else { return }
        window = w
        observers.forEach(NotificationCenter.default.removeObserver)
        WindowChrome.allowFullScreen(w)
        let nc = NotificationCenter.default
        observers = [
            // Keeps the green button and View > Enter Full Screen working.
            nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated { WindowChrome.allowFullScreen(w) }
            },
            // Covers the green button and View > Enter Full Screen as well as our own button.
            nc.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    w.level = .normal
                    self?.isFullScreen = true
                }
            },
            nc.addObserver(forName: NSWindow.didExitFullScreenNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isFullScreen = false
                    self?.idle = false
                    WindowChrome.applyFloat()
                }
            },
        ]
        isFullScreen = w.styleMask.contains(.fullScreen)
    }

    func mouseMoved() {
        lastMove = Date()
        if idle { idle = false }
    }

    /// While full screen, hides the pointer (and the hover bar) after 2 s without movement.
    func watchIdle() async {
        while isFullScreen, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(400))
            if !idle, Date().timeIntervalSince(lastMove) > 2 {
                idle = true
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

/// Wraps a style window's content with the hover bar, the playback controls and full-screen
/// handling.
struct StyleChrome: ViewModifier {
    let styleID: String
    @ObservedObject var model: PlayerModel
    /// Messages is a layout of real views (not a canvas that fills any size), so in full screen
    /// it's laid out at a comfortable reading size and scaled up to fill the whole display.
    var scalesInFullScreen = false
    @StateObject private var state = StyleWindowState()
    @State private var hovering = false
    @Environment(\.openWindow) private var openWindow
    @AppStorage private var playbackMode: Int

    init(styleID: String, model: PlayerModel, scalesInFullScreen: Bool) {
        self.styleID = styleID
        self.model = model
        self.scalesInFullScreen = scalesInFullScreen
        _playbackMode = AppStorage(wrappedValue: PlaybackPrefs.defaultMode.rawValue, PlaybackPrefs.key(styleID))
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .topLeading) {
            if scalesInFullScreen {
                GeometryReader { geo in
                    let k = state.isFullScreen ? Self.fullScreenScale(geo.size) : 1
                    content
                        .frame(width: geo.size.width / k, height: geo.size.height / k)
                        .scaleEffect(k, anchor: .topLeading)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
                .ignoresSafeArea()
            } else {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            PlaybackBar(model: model, mode: PlaybackPrefs.Mode(rawValue: playbackMode) ?? .hover,
                        visible: hovering && !state.idle)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            bar
                .opacity(hovering && !state.idle ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: hovering && !state.idle)
        }
        .background(WindowReader { state.attach($0) })
        .onHover { hovering = $0 }
        .onContinuousHover { _ in state.mouseMoved() }
        .task(id: state.isFullScreen) { await state.watchIdle() }
    }

    /// Lays Messages out as if the screen were about 820 pt tall, so the text grows with the
    /// display and the thread uses the full width of any aspect ratio.
    static func fullScreenScale(_ size: CGSize) -> CGFloat {
        max(1, min(2, size.height / 820))
    }

    private var bar: some View {
        HStack(spacing: 6) {
            chip("house.fill", "Dashboard", help: "Back to the dashboard (⇧⌘D)") {
                WindowChrome.backToDashboard(from: state.window, open: openWindow)
            }
            chip(state.isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                 nil, help: state.isFullScreen ? "Exit full screen (Esc)" : "Full screen (⇧⌘F)") {
                WindowChrome.toggleFullScreen(state.window)
            }
        }
        // Clears the traffic lights, which are hidden in full screen.
        .padding(.leading, state.isFullScreen ? 12 : 76)
        .padding(.top, state.isFullScreen ? 12 : 5)
        .ignoresSafeArea()
    }

    private func chip(_ symbol: String, _ title: String?, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                if let title { Text(title).font(.system(size: 11, weight: .semibold)) }
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, title == nil ? 7 : 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension View {
    /// The shared chrome for a style window. `id` is the style's `LyricStyle.id`; it keys the
    /// style's own playback-controls setting.
    func styleChrome(_ id: String, model: PlayerModel, scalesInFullScreen: Bool = false) -> some View {
        modifier(StyleChrome(styleID: id, model: model, scalesInFullScreen: scalesInFullScreen))
    }
}

/// Hands back the NSWindow a view lives in.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { ReaderView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        let onWindow: (NSWindow) -> Void
        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { DispatchQueue.main.async { self.onWindow(window) } }
        }
    }
}
