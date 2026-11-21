import Foundation
import Testing
@testable import LyricBubbles

// Opt-in network check: LIVE_CHECK=1 swift test --filter liveDuets
// Prints only counts, never lyric text.
@Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_CHECK"] == "1"))
func liveDuets() async {
    let songs = [("Under Pressure", "Queen, David Bowie", 248.0), ("Shallow", "Lady Gaga, Bradley Cooper", 216.0),
                 ("Islands in the Stream", "Kenny Rogers, Dolly Parton", 249.0), ("Die With A Smile", "Lady Gaga, Bruno Mars", 252.0)]
    let svc = LyricsService()
    for (t, a, d) in songs {
        let snap = SpotifySnapshot(trackID: t, title: t, artist: a, album: "", durationSeconds: d,
                                   positionSeconds: 0, state: .paused, artworkURL: nil)
        guard case .synced(let raw) = await svc.lyrics(for: snap) else { print("LIVE \(t): no synced"); continue }
        let (lines, cast) = SingerDetector.detect(raw, artist: a, title: t)
        let w = lines.filter { !$0.text.isEmpty }
        let dist = Dictionary(grouping: w, by: \.singer).mapValues(\.count).sorted { $0.key < $1.key }
        print("LIVE \(t): source=\(cast.source) singers=\(cast.names.count) sections=\(Set(w.map(\.section)).count) lines_by_singer=\(dist)")
    }
}

// LIVE_CHECK=1 swift test --filter livePlan   (counts only, never lyric text)
@Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_CHECK"] == "1"))
func livePlan() async {
    let env = ProcessInfo.processInfo.environment
    let snap = SpotifySnapshot(trackID: "live", title: env["TITLE"] ?? "I Remember Everything", artist: env["ARTIST"] ?? "Zach Bryan", album: "",
                               durationSeconds: Double(env["DUR"] ?? "227") ?? 227, positionSeconds: 0, state: .paused, artworkURL: nil)
    guard case .synced(let raw) = await LyricsService().lyrics(for: snap) else { print("PLAN no synced"); return }
    let (lines, cast) = SingerDetector.detect(raw, artist: snap.artist, title: snap.title)
    let p = ThreadPlanner.plan(lines: lines, trackID: "live", title: snap.title, artist: snap.artist,
                               duration: snap.durationSeconds, style: .alternate, cast: cast, intensity: .calm)
    let ws = lines.filter { !$0.text.isEmpty }
    let gaps = zip(ws, ws.dropFirst()).map { $1.time - $0.time }
    print("GAPS >=3.2s:", gaps.filter { $0 >= 3.2 }.count, ">=6.5s:", gaps.filter { $0 >= 6.5 }.count, "sections:", Set(ws.map(\.section)).count)
    let lyric = p.items.filter { if case .lyric = $0.kind { true } else { false } }
    print("PLAN lyrics=\(lyric.count) sent=\(lyric.filter(\.outgoing).count) emojis=\(lyric.filter { $0.emoji != nil }.count)",
          "reactions=\(lyric.filter { $0.reaction != nil }.count) bubbleFX=\(lyric.filter { $0.bubbleEffect != nil }.count)",
          "stickers=\(lyric.filter { $0.sticker != nil }.count) other=\(p.items.filter { !$0.isLyric }.map(kindName)) screenFX=\(p.cues.map(\.effect.rawValue)) banners=\(p.banners.count)")
}

private func kindName(_ i: ChatItem) -> String {
    switch i.kind {
    case .lyric: "lyric"
    case .jumbo: "jumbo"
    case .link: "link"
    case .route(let r): "route(\(r.stops.count) stops, \(Int(r.start))s-\(Int(r.stops.last!.time))s)"
    case .attachment(let a):
        switch a {
        case .liveLocation: "map"
        case .trip: "trip"
        case .weather: "weather"
        case .voice: "voice"
        case .photo: "photo"
        case .event: "event"
        }
    }
}
