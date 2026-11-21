import SwiftUI

enum BubbleSide: String, CaseIterable, Identifiable {
    case alternate, incoming, outgoing, group
    var id: String { rawValue }
    var label: String {
        switch self {
        case .alternate: "Conversation (alternating)"
        case .incoming: "Received (gray)"
        case .outgoing: "Sent (blue)"
        case .group: "Group chat by singer"
        }
    }
}

// MARK: - Palette

enum Palette {
    static let blue = Color(red: 0.04, green: 0.52, blue: 1.0)
    static func gray(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.16) : Color(red: 0.91, green: 0.91, blue: 0.92)
    }
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }
}

// MARK: - Bubble shape with tail

struct BubbleShape: Shape {
    var outgoing: Bool
    var showTail: Bool

    func path(in rect: CGRect) -> Path {
        let p = Path(roundedRect: rect, cornerRadius: 18, style: .continuous)
        guard showTail else { return p }

        // Tail curls out from the bottom corner, like a speech bubble.
        var tail = Path()
        let y = rect.maxY
        let x = outgoing ? rect.maxX : rect.minX
        let d: CGFloat = outgoing ? 1 : -1
        tail.move(to: CGPoint(x: x - 14 * d, y: y - 12))
        tail.addQuadCurve(to: CGPoint(x: x + 5 * d, y: y), control: CGPoint(x: x - 2 * d, y: y - 1))
        tail.addQuadCurve(to: CGPoint(x: x - 18 * d, y: y - 4), control: CGPoint(x: x - 8 * d, y: y + 2))
        tail.closeSubpath()
        // Union, not addPath: the mirrored (incoming) tail winds opposite to the
        // rounded rect, and non-zero fill would punch holes where they overlap.
        return p.union(tail)
    }
}

// MARK: - Avatars

struct Monogram: View {
    let name: String
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.66), Color(white: 0.52)],
                                         startPoint: .top, endPoint: .bottom))
            if name == "Everyone" {
                Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

// MARK: - Message row

struct MessageRow: View {
    let text: String
    let outgoing: Bool
    let showTail: Bool
    var senderName: String? = nil     // group chat: label above first bubble of a run
    var avatarColumn = false          // group chat: reserve space for avatars on incoming rows
    var showAvatar = false
    var avatarName = ""
    var reaction: Reaction? = nil
    var reactionAge: Double = 0
    var blur: Double = 1
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 2) {
            if let senderName {
                Text(senderName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, (avatarColumn ? 34 : 0) + 12)
            }
            HStack(alignment: .bottom, spacing: 6) {
                if outgoing { Spacer(minLength: 48) }
                if avatarColumn && !outgoing {
                    if showAvatar { Monogram(name: avatarName) } else { Color.clear.frame(width: 26, height: 1) }
                }
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(outgoing ? .white : .primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(BubbleShape(outgoing: outgoing, showTail: showTail)
                        .fill(outgoing ? Palette.blue : Palette.gray(scheme)))
                    .overlay(alignment: outgoing ? .topLeading : .topTrailing) {
                        if let reaction {
                            let (p, v) = Spring.step(reactionAge, response: 0.38, damping: 0.55)
                            TapbackBadge(reaction: reaction, onOutgoing: outgoing)
                                .scaleEffect(p)
                                .rotationEffect(.degrees((1 - p) * (outgoing ? -30 : 30)))
                                .blur(radius: min(4, abs(v) * 0.25) * blur)
                                .offset(x: outgoing ? -16 : 16, y: -18)
                        }
                    }
                    .textSelection(.enabled)
                    // Keeps long lines readable when the thread is wide (full screen).
                    .frame(maxWidth: 520, alignment: outgoing ? .trailing : .leading)
                if !outgoing { Spacer(minLength: 48) }
            }
        }
        .padding(.top, reaction == nil ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
        .padding(.horizontal, 14)
    }
}

// MARK: - Typing indicator

struct TypingIndicator: View {
    let outgoing: Bool
    var avatarColumn = false
    var avatarName = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if outgoing { Spacer() }
            if avatarColumn && !outgoing { Monogram(name: avatarName) }
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        let phase = (sin(t * 6 - Double(i) * 0.9) + 1) / 2
                        Circle()
                            .fill(outgoing ? Color.white.opacity(0.5 + 0.5 * phase)
                                           : Color.secondary.opacity(0.4 + 0.5 * phase))
                            .frame(width: 8, height: 8)
                            .offset(y: -2 * phase)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(BubbleShape(outgoing: outgoing, showTail: true)
                    .fill(outgoing ? Palette.blue : Palette.gray(scheme)))
            }
            if !outgoing { Spacer() }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Header

struct ContactHeader: View {
    let snapshot: SpotifySnapshot?
    let cast: Cast
    let style: BubbleSide

    private var showCast: Bool { style == .group && cast.isMulti }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: snapshot?.artworkURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        LinearGradient(colors: [.gray.opacity(0.6), .gray.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        Image(systemName: "music.note")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())

                if showCast {
                    HStack(spacing: -8) {
                        ForEach(cast.names.prefix(3), id: \.self) { Monogram(name: $0, size: 20) }
                    }
                    .offset(x: 14, y: 4)
                }
            }

            HStack(spacing: 2) {
                Text(showCast ? castTitle : (snapshot?.artist ?? "Not Playing"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            if showCast {
                Text(cast.edited ? "\(cast.names.count) people · edited by you"
                                 : "\(cast.names.count) people · right-click to fix singers")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 30)   // clears the traffic lights
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var castTitle: String {
        let n = cast.names
        if n.count == 2 { return "\(n[0]) & \(n[1])" }
        return n.dropLast().joined(separator: ", ") + " & " + (n.last ?? "")
    }
}

// MARK: - Main view

struct ChatView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("bubbleSide") private var sideRaw = BubbleSide.alternate.rawValue
    @AppStorage("leadTime") private var leadTime = 0.25
    @AppStorage(Strength.emoji) private var sEmoji = Intensity.calm.emoji
    @AppStorage(Strength.reactions) private var sReactions = Intensity.calm.reactions
    @AppStorage(Strength.bubble) private var sBubble = Intensity.calm.bubble
    @AppStorage(Strength.screen) private var sScreen = Intensity.calm.screen
    @AppStorage(Strength.attachments) private var sAttach = Intensity.calm.attachments
    @AppStorage(Strength.banners) private var sBanners = Intensity.calm.banners
    @AppStorage(MotionPrefs.blurKey) private var motionBlurAmount = 0.5
    @AppStorage(MotionPrefs.zoomKey) private var focusZoom = true
    @AppStorage(PlaybackPrefs.key("messages")) private var playbackMode = PlaybackPrefs.defaultMode.rawValue
    @State private var showExtras = false
    @State private var focusFrame: CGRect?
    static let threadSpace = "thread"
    @Environment(\.colorScheme) private var scheme

    private var side: BubbleSide { BubbleSide(rawValue: sideRaw) ?? .alternate }

    private var intensity: Intensity {
        Intensity(emoji: sEmoji, reactions: sReactions, bubble: sBubble,
                  screen: sScreen, attachments: sAttach, banners: sBanners)
    }

    var body: some View {
        VStack(spacing: 0) {
            ContactHeader(snapshot: model.snapshot, cast: model.cast, style: side)
                .overlay(alignment: .topTrailing) { styleButton }
            content
        }
        .background(Palette.background(scheme))
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder private var content: some View {
        switch model.status {
        case .notRunning:
            placeholder("Spotify isn't running", "Open Spotify and play a song.")
        case .stopped:
            placeholder("Nothing playing", "Press play in Spotify.")
        case .error(let msg):
            placeholder("Can't reach Spotify", msg)
        case .active(let s):
            if model.loadingLyrics {
                threadView(s, ChatThread(items: [], cues: [], banners: []), loading: true)
            } else {
                switch model.lyrics {
                case .synced:
                    if let thread = model.thread(style: side, intensity: intensity) {
                        threadView(s, thread, loading: false)
                    }
                case .instrumental:
                    placeholder("Instrumental", "No words in this one. Just vibes.")
                case .plainOnly:
                    placeholder("No timed lyrics", "Only unsynced lyrics exist for this track.")
                case .notFound, .none:
                    placeholder("No lyrics found", "\(s.title) isn't in the LRCLIB database.")
                }
            }
        }
    }

    private func threadView(_ s: SpotifySnapshot, _ thread: ChatThread, loading: Bool) -> some View {
        let items = thread.items
        let cast = model.cast
        let avatarColumn = side == .group && cast.isMulti
        let track = TrackInfo(s)
        let blur = MotionPrefs.multiplier(motionBlurAmount)

        // Display-rate clock: every frame of a 120 Hz screen gets a fresh song time.
        return TimelineView(.animation) { ctx in
            let pos = model.position(at: ctx.date) + leadTime
            let shownCount = items.lastIndex(where: { $0.time <= pos }).map { $0 + 1 } ?? 0
            let shown = Array(items.prefix(shownCount))
            let next = shownCount < items.count ? items[shownCount] : nil
            let typing = loading || showsTyping(prev: shown.last, next: next, pos: pos)
            let slamAge = shown.last(where: { $0.bubbleEffect == .slam }).map { pos - $0.time } ?? 99
            let cue = thread.cues.last(where: { pos >= $0.at && pos < $0.at + EffectCue.duration })
            let banner = thread.banners.last(where: { pos >= $0.at && pos < $0.at + Banner.duration })
            let focusWindow = focusZoom ? thread.focus.first(where: { pos > $0.start && pos < $0.end }) : nil
            let zoom = focusWindow?.amount(at: pos) ?? 0

            GeometryReader { geo in
            let lens = focusTransform(frame: focusFrame, size: geo.size, amount: zoom)
            ZStack(alignment: .top) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            Text("Today \(Date().addingTimeInterval(-pos).formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.top, 14)
                                .padding(.bottom, 8)

                            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, item in
                                ChatRow(input: rowInput(item, idx: idx, shown: shown, typing: typing, next: next,
                                                        pos: pos, avatarColumn: avatarColumn, cast: cast, blur: blur),
                                        track: track,
                                        reportsFrame: item.id == focusWindow?.id)
                                    .equatable()
                                    .contextMenu {
                                        if side == .group, item.isLyric {
                                            singerMenu(section: lyricSection(item.id), singer: item.sender)
                                        }
                                    }
                                    .transition(.identity)
                            }

                            if typing {
                                TypingIndicator(outgoing: next?.outgoing ?? false,
                                                avatarColumn: avatarColumn,
                                                avatarName: cast.name(next?.sender ?? 1))
                                    .padding(.top, 4)
                                    .transition(.scale(scale: 0.5, anchor: (next?.outgoing ?? false) ? .bottomTrailing : .bottomLeading)
                                        .combined(with: .opacity))
                            }

                            if side != .incoming, let last = shown.last, last.outgoing, !typing {
                                HStack {
                                    Spacer()
                                    Text(pos - last.time > 2 ? "Read" : "Delivered")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .contentTransition(.opacity)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 2)
                            }

                            // Room under the newest message for the playback controls when they're always shown.
                            Color.clear.frame(height: playbackMode == PlaybackPrefs.Mode.always.rawValue ? 84 : 12).id("bottom")
                        }
                        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: shownCount)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: typing)
                        .offset(x: BubbleMotion.shake(age: slamAge))
                    }
                    .scrollIndicators(.never)
                    .onChange(of: shownCount) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: typing) {
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                    .coordinateSpace(name: Self.threadSpace)
                    .onPreferenceChange(FocusFrameKey.self) { focusFrame = $0 }
                }
                // Zoom the whole thread onto the live map card.
                .scaleEffect(lens.scale, anchor: .topLeading)
                .offset(lens.offset)

                if zoom > 0 {
                    // Soft vignette pulls the eye to the card.
                    RadialGradient(colors: [.clear, .black.opacity(scheme == .dark ? 0.6 : 0.28)],
                                   center: .center,
                                   startRadius: min(geo.size.width, geo.size.height) * 0.38,
                                   endRadius: max(geo.size.width, geo.size.height) * 0.8)
                        .opacity(zoom)
                        .allowsHitTesting(false)
                }

                if let cue {
                    ScreenEffectCanvas(cue: cue, t: pos - cue.at, blur: blur)
                }

                if let banner {
                    NotificationBanner(banner: banner, artworkURL: s.artworkURL, age: pos - banner.at, blur: blur)
                        .padding(.top, 6)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            }
        }
    }

    /// Scale and offset (anchor top-left) that move `frame` to the center and enlarge it,
    /// blended by `amount` (0 = untouched, 1 = fully focused).
    private func focusTransform(frame: CGRect?, size: CGSize, amount: Double) -> (scale: CGFloat, offset: CGSize) {
        guard let f = frame, amount > 0, f.width > 1, f.height > 1 else { return (1, .zero) }
        let fit = min((size.width - 28) / f.width, (size.height - 28) / f.height)
        let k = max(1, min(1.3, fit))
        let s = 1 + (k - 1) * amount
        let target = CGPoint(x: size.width / 2, y: size.height / 2)
        let c = CGPoint(x: f.midX + (target.x - f.midX) * amount, y: f.midY + (target.y - f.midY) * amount)
        return (s, CGSize(width: c.x - f.midX * s, height: c.y - f.midY * s))
    }

    private func rowInput(_ item: ChatItem, idx: Int, shown: [ChatItem], typing: Bool, next: ChatItem?,
                          pos: Double, avatarColumn: Bool, cast: Cast, blur: Double) -> RowInput {
        let same = { (a: ChatItem, b: ChatItem) in a.outgoing == b.outgoing && a.sender == b.sender }
        let prevSame = idx > 0 && same(shown[idx - 1], item)
        let following = idx + 1 < shown.count ? shown[idx + 1] : nil
        let nextIsBubbleSameSide: Bool = {
            guard let f = following, same(f, item) else { return false }
            if case .lyric = f.kind { return true }
            if case .attachment(.voice) = f.kind { return true }
            return false
        }()
        let typingContinues = typing && idx == shown.count - 1 && next.map { same($0, item) } == true
        return RowInput(
            item: item,
            clock: min(pos, RowInput.settleTime(item)),
            prevSame: prevSame,
            endOfRun: !nextIsBubbleSameSide && !typingContinues,
            isFirst: idx == 0,
            avatarColumn: avatarColumn,
            senderName: avatarColumn && !item.outgoing && !prevSame ? cast.name(item.sender) : nil,
            avatarName: cast.name(item.sender),
            caption: effectCaption(item),
            blur: blur)
    }

    /// "Sent with Slam", "Sent with Confetti": shown under your own (blue) messages, as iMessage does.
    private func effectCaption(_ item: ChatItem) -> String? {
        guard item.outgoing else { return nil }
        if let s = item.screenEffect { return "Sent with \(s.label)" }
        if let b = item.bubbleEffect { return "Sent with \(b.label)" }
        return nil
    }

    private func lyricSection(_ id: Int) -> Int {
        if case .synced(let lines) = model.lyrics, let l = lines.first(where: { $0.id == id }) { return l.section }
        return 0
    }

    /// Show "…" before a message that follows a pause.
    private func showsTyping(prev: ChatItem?, next: ChatItem?, pos: Double) -> Bool {
        guard let next else { return false }
        let untilNext = next.time - pos
        return next.time - (prev?.time ?? 0) >= 2.2 && untilNext > 0 && untilNext <= 1.5
    }

    // MARK: Menus

    private var styleButton: some View {
        Button {
            showExtras.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15))
                .foregroundStyle(Palette.blue)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showExtras, arrowEdge: .bottom) { ExtrasPanel() }
        .help("Style and strength")
        .padding(.top, 8)
        .padding(.trailing, 12)
    }

    /// Group chat only: right-click a bubble to say who sings that part.
    @ViewBuilder private func singerMenu(section: Int, singer: Int) -> some View {
        let cast = model.cast
        Section("This part is sung by") {
            ForEach(Array(cast.names.enumerated()), id: \.offset) { i, name in
                Button {
                    model.setSinger(i, forSection: section)
                } label: {
                    if singer == i { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
            Button("Another singer (Singer \(cast.names.count + 1))") {
                model.setSinger(cast.names.count, forSection: section)
            }
            if cast.isMulti {
                Button("Everyone") { model.setSinger(Cast.everyone, forSection: section) }
            }
        }
        if cast.edited {
            Divider()
            Button("Reset Singers for This Song") { model.resetSingers() }
        }
    }

    private func placeholder(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
