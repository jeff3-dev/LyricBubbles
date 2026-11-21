import SwiftUI

/// Everything one thread row needs, in one Equatable value.
/// `clock` is the song time, frozen once the row's animations have finished,
/// so settled rows compare equal frame to frame and SwiftUI skips them.
struct RowInput: Equatable {
    let item: ChatItem
    let clock: Double
    let prevSame: Bool
    let endOfRun: Bool
    let isFirst: Bool
    let avatarColumn: Bool
    let senderName: String?
    let avatarName: String
    let caption: String?
    let blur: Double

    /// Song time after which nothing in this row moves any more.
    static func settleTime(_ item: ChatItem) -> Double {
        switch item.kind {
        case .lyric:
            var t = item.time + (item.bubbleEffect == nil ? 1.3 : 1.7)
            if let r = item.reaction { t = max(t, r.at + 0.9) }
            if let s = item.sticker { t = max(t, s.at + 0.9) }
            return t
        case .jumbo, .link:
            return item.time + 1.3
        case .route(let r):
            return (r.stops.last?.time ?? item.time) + 4
        case .attachment(.voice(let seconds, _)):
            return item.time + Double(seconds) + 1.5
        case .attachment(.event):
            return item.time + 3.5
        case .attachment:
            return item.time + 45   // maps, weather and photos keep gently moving for a while
        }
    }
}

/// Snapshot fields that never change during a song (position excluded), for stable equality.
struct TrackInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?

    init(_ s: SpotifySnapshot) {
        title = s.title; artist = s.artist; album = s.album; artworkURL = s.artworkURL
    }

    var snapshot: SpotifySnapshot {
        SpotifySnapshot(trackID: "", title: title, artist: artist, album: album, durationSeconds: 0,
                        positionSeconds: 0, state: .paused, artworkURL: artworkURL)
    }
}

/// Frame of the focused map card, in the thread's coordinate space.
struct FocusFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

struct ChatRow: View, Equatable {
    let input: RowInput
    let track: TrackInfo
    var reportsFrame = false

    static func == (a: ChatRow, b: ChatRow) -> Bool {
        a.input == b.input && a.track == b.track && a.reportsFrame == b.reportsFrame
    }

    var body: some View {
        let item = input.item
        let age = input.clock - item.time
        let anchor: UnitPoint = item.outgoing ? .bottomTrailing : .bottomLeading

        Group {
            switch item.kind {
            case .lyric(let text):
                lyric(text, age: age)
            case .jumbo(let e):
                JumboEmoji(text: e, outgoing: item.outgoing)
                    .springEntrance(age: age, anchor: anchor, blur: input.blur, from: 0.25, distance: 10)
            case .link:
                LinkCard(snapshot: track.snapshot, outgoing: item.outgoing)
                    .springEntrance(age: age, anchor: anchor, blur: input.blur, from: 0.8, distance: 30)
            case .route(let info):
                RouteCard(info: info, outgoing: item.outgoing, pos: input.clock, blur: input.blur)
                    .springEntrance(age: age, anchor: anchor, blur: input.blur, from: 0.8, distance: 30)
            case .attachment(let a):
                attachment(a, age: age)
                    .springEntrance(age: age, anchor: anchor, blur: input.blur, from: 0.8, distance: 30)
            }
        }
        .background {
            if reportsFrame {
                GeometryReader { g in
                    Color.clear.preference(key: FocusFrameKey.self, value: g.frame(in: .named(ChatView.threadSpace)))
                }
            }
        }
        .padding(.top, !input.isFirst && !input.prevSame ? 8 : 0)
    }

    @ViewBuilder private func lyric(_ text: String, age: Double) -> some View {
        let item = input.item
        let clock = input.clock
        let reaction = item.reaction.flatMap { clock >= $0.at ? $0 : nil }
        let sticker = item.sticker.flatMap { clock >= $0.at ? $0 : nil }
        let anchor: UnitPoint = item.outgoing ? .bottomTrailing : .bottomLeading

        VStack(alignment: item.outgoing ? .trailing : .leading, spacing: 2) {
            MessageRow(
                text: text + (item.emoji.map { " \($0)" } ?? ""),
                outgoing: item.outgoing,
                showTail: input.endOfRun,
                senderName: input.senderName,
                avatarColumn: input.avatarColumn,
                showAvatar: input.endOfRun,
                avatarName: input.avatarName,
                reaction: reaction,
                reactionAge: reaction.map { clock - $0.at } ?? 0,
                blur: input.blur)
            .overlay {
                if let sticker {
                    GeometryReader { geo in
                        StickerView(sticker: sticker, age: clock - sticker.at, blur: input.blur)
                            .position(x: geo.size.width * sticker.x, y: 6)
                    }
                    .allowsHitTesting(false)
                }
            }
            .modifier(BubbleArrival(effect: item.bubbleEffect, age: age, anchor: anchor, blur: input.blur))
            .zIndex(item.bubbleEffect == .slam && age < 0.5 ? 1 : 0)

            if let caption = input.caption {
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 22)
                    .opacity(min(1, max(0, (age - 0.4) / 0.4)))
            }
        }
    }

    @ViewBuilder private func attachment(_ a: Attachment, age: Double) -> some View {
        let item = input.item
        switch a {
        case .liveLocation(let place):
            LiveLocationCard(place: place, outgoing: item.outgoing, age: age)
        case .trip(let place, let minutes):
            TripCard(place: place, minutes: minutes, outgoing: item.outgoing, age: age)
        case .weather(let place, let kind, let temp):
            WeatherCard(place: place, kind: kind, temp: temp, outgoing: item.outgoing, age: age)
        case .voice(let seconds, let seed):
            VoiceMessage(seconds: seconds, seed: seed, outgoing: item.outgoing, showTail: input.endOfRun, age: age)
        case .photo:
            PhotoMessage(artworkURL: track.artworkURL, outgoing: item.outgoing, age: age)
        case .event(let title, let when, let place):
            EventCard(title: title, when: when, place: place, outgoing: item.outgoing, age: age)
        }
    }
}

/// Normal bubbles spring in; Slam / Loud / Gentle play their own motion, all with motion blur.
struct BubbleArrival: ViewModifier {
    let effect: BubbleEffect?
    let age: Double
    let anchor: UnitPoint
    let blur: Double

    func body(content: Content) -> some View {
        switch effect {
        case nil:
            content.springEntrance(age: age, anchor: anchor, blur: blur)
        case .some(let fx):
            content
                .scaleEffect(BubbleMotion.scale(fx, age: age), anchor: anchor == .bottomTrailing ? .trailing : .leading)
                .opacity(BubbleMotion.opacity(fx, age: age))
                .blur(radius: BubbleMotion.blur(fx, age: age) * blur)
        }
    }
}
