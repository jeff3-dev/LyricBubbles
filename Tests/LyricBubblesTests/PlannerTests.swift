import Testing
@testable import LyricBubbles

// Placeholder text only; no real lyrics.
private func song() -> [LyricLine] {
    var rows: [(Double, String)] = []
    var t = 10.0
    for block in 0..<6 {
        let chorus = block % 2 == 1
        for n in 0..<4 {
            rows.append((t, chorus ? "hook \(n) love tonight" : "verse \(block) line \(n)"))
            t += 3
        }
        t += 9   // pause between blocks
    }
    var lines = rows.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    SingerDetector.markSections(&lines)
    return lines
}

private func plan(_ style: BubbleSide = .alternate, id: String = "track-1", _ k: Intensity = .lively) -> ChatThread {
    ThreadPlanner.plan(lines: song(), trackID: id, title: "T", artist: "A", duration: 200,
                       style: style, cast: Cast(names: ["A"], source: .single), intensity: k)
}

/// Lively, but with no attachments, so every lyric stays a bubble.
private let noRoutes = Intensity(emoji: 0.5, reactions: 0.5, bubble: 0.5, screen: 0.5, attachments: 0, banners: 0.5)

@Test func sameSongSamePlan() {
    #expect(plan() == plan())
    #expect(plan(id: "track-1") != plan(id: "track-2"))
}

@Test func everyLyricBecomesOneMessage() {
    let lyrics = plan(.alternate, id: "track-1", noRoutes).items.filter(\.isLyric)
    #expect(lyrics.count == song().count)
    #expect(plan().items.first?.kind == .link)
}

@Test func alternatingRunsAreShortAndFlipAtBlocks() {
    let lines = song()
    let items = plan(.alternate, id: "track-1", noRoutes).items.filter(\.isLyric)
    var run = 1
    for i in 1..<items.count {
        if items[i].outgoing == items[i - 1].outgoing && lines[i].section == lines[i - 1].section {
            run += 1
        } else {
            run = 1
        }
        #expect(run <= 3)
        if lines[i].section != lines[i - 1].section { #expect(items[i].outgoing != items[i - 1].outgoing) }
    }
    #expect(Set(items.map(\.outgoing)).count == 2)
}

@Test func singleSideStyles() {
    #expect(plan(.incoming).items.filter { if case .lyric = $0.kind { true } else { false } }.allSatisfy { !$0.outgoing })
    #expect(plan(.outgoing).items.allSatisfy { $0.outgoing })
}

@Test func itemsAreTimeOrdered() {
    let times = plan().items.map(\.time)
    #expect(times == times.sorted())
}

@Test func jumboEmojiOnlyInGaps() {
    let items = plan().items
    for (i, item) in items.enumerated() {
        guard case .jumbo = item.kind else { continue }
        #expect(i > 0 && i + 1 < items.count)
        #expect(items[i + 1].time - items[i - 1].time >= 6.5)
    }
}

@Test func reactionsComeAfterTheirMessage() {
    for item in plan().items {
        if let r = item.reaction {
            #expect(r.at > item.time && r.at < item.time + 3)
            #expect(r.byMe == !item.outgoing)
        }
    }
}

@Test func effectsAreSpacedOut() {
    let p = plan()
    let cueTimes = p.cues.map(\.at)
    for (a, b) in zip(cueTimes, cueTimes.dropFirst()) { #expect(b - a > 22) }
    #expect(!p.cues.isEmpty)   // first chorus always fires one
    let fx = p.items.filter { $0.bubbleEffect != nil }.map(\.time)
    for (a, b) in zip(fx, fx.dropFirst()) { #expect(b - a > 10) }
}

@Test func bannersAreSpacedAndInsideSong() {
    let b = plan().banners
    #expect(!b.isEmpty)
    for (x, y) in zip(b, b.dropFirst()) { #expect(y.at - x.at >= 10) }
    #expect(b.allSatisfy { $0.at >= 18 && $0.at <= 200 - 12 })
    #expect(b.contains { $0.title == "Now Playing" })
}

@Test func emojiKeywordsMatchWholeWords() {
    #expect(EmojiMap.candidates(EmojiMap.tokens("fire in the sky")).contains("🔥"))
    #expect(EmojiMap.candidates(EmojiMap.tokens("firefly")).isEmpty)
}

// MARK: - Strength and attachments (placeholder text only)

private func travelSong() -> [LyricLine] {
    let rows: [(Double, String)] = [
        (5, "driving down to Nashville"), (12, "rain on the window"), (19, "see you tonight"),
        (26, "sing it on the radio"), (33, "take a picture"), (40, "back home again"),
        (47, "out in Texas"), (54, "storm rolling in"), (61, "friday night"), (68, "call me"),
    ]
    var lines = rows.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    SingerDetector.markSections(&lines)
    return lines
}

private func travelPlan(_ k: Intensity) -> ChatThread {
    ThreadPlanner.plan(lines: travelSong(), trackID: "trip", title: "T", artist: "A", duration: 120,
                       style: .alternate, cast: Cast(names: ["A"], source: .single), intensity: k)
}

@Test func zeroStrengthMeansPlainThread() {
    let p = plan(.alternate)   // default lively, for contrast
    #expect(p.items.contains { $0.emoji != nil || $0.reaction != nil })
    let off = ThreadPlanner.plan(lines: song(), trackID: "track-1", title: "T", artist: "A", duration: 200,
                                 style: .alternate, cast: Cast(names: ["A"], source: .single), intensity: .off)
    #expect(off.cues.isEmpty && off.banners.isEmpty)
    #expect(off.items.allSatisfy { $0.emoji == nil && $0.reaction == nil && $0.sticker == nil
        && $0.bubbleEffect == nil && $0.screenEffect == nil })
    #expect(off.items.allSatisfy { $0.isLyric || $0.kind == .link })
}

@Test func strengthScalesAmount() {
    func extras(_ k: Intensity) -> Int {
        let p = travelPlan(k)
        return p.items.filter { !$0.isLyric }.count + p.items.filter { $0.emoji != nil || $0.reaction != nil }.count
    }
    #expect(extras(.calm) <= extras(.lively))
    let max = Intensity(emoji: 1, reactions: 1, bubble: 1, screen: 1, attachments: 1, banners: 1)
    #expect(extras(.lively) <= extras(max))
}

@Test func attachmentsFollowKeywordsAndFitGaps() {
    let max = Intensity(emoji: 0, reactions: 0, bubble: 0, screen: 0, attachments: 1, banners: 0)
    let items = travelPlan(max).items
    let attachments = items.enumerated().filter { if case .attachment = $0.element.kind { true } else { false } }
    #expect(!attachments.isEmpty)
    for (i, a) in attachments {
        #expect(i > 0)
        #expect(items[i - 1].time < a.time)
        if i + 1 < items.count { #expect(a.time < items[i + 1].time) }
    }
    // A named place produces a map card for that place.
    let places: [String] = items.compactMap {
        switch $0.kind {
        case .attachment(.liveLocation(let p)), .attachment(.trip(let p, _)): p
        case .route(let r): r.place
        default: nil
        }
    }
    #expect(places.contains("Nashville") || places.contains("Texas"))
}

@Test func placeMatchingIsWholeWord() {
    #expect(Places.find(in: "heading to new york city") == "New York")
    #expect(Places.find(in: "york") == nil)
    #expect(Places.find(in: "texasville") == nil)
}

// MARK: - Lyric route (placeholder text only)

private func routes(_ p: ChatThread) -> [(ChatItem, RouteInfo)] {
    p.items.compactMap { if case .route(let r) = $0.kind { ($0, r) } else { nil } }
}

@Test func calmSongGetsOneRoute() {
    let p = ThreadPlanner.plan(lines: song(), trackID: "track-1", title: "T", artist: "A", duration: 200,
                               style: .alternate, cast: Cast(names: ["A"], source: .single), intensity: .calm)
    #expect(routes(p).count == 1)
}

@Test func routeCarriesItsLinesInsteadOfBubbles() {
    let p = plan()
    let (card, r) = routes(p)[0]
    #expect(r.stops.count >= 3 && r.stops.count <= 7)
    #expect(card.time == r.start && r.start < r.stops[0].time)
    // Stop lines are not also shown as bubbles, and every song line appears exactly once.
    let bubbleTexts = p.items.compactMap { if case .lyric(let t) = $0.kind { t } else { nil } }
    let bubbleTimes = Set(p.items.filter(\.isLyric).map(\.time))
    #expect(r.stops.allSatisfy { !bubbleTimes.contains($0.time) })
    #expect(bubbleTexts.count + routes(p).map(\.1.stops.count).reduce(0, +) == song().count)
    // Stops are consecutive lines of one block, in order.
    #expect(r.stops.map(\.time) == r.stops.map(\.time).sorted())
}

@Test func nothingElseLandsInsideARoute() {
    let max = Intensity(emoji: 1, reactions: 1, bubble: 1, screen: 1, attachments: 1, banners: 1)
    let p = ThreadPlanner.plan(lines: song(), trackID: "track-1", title: "T", artist: "A", duration: 200,
                               style: .alternate, cast: Cast(names: ["A"], source: .single), intensity: max)
    for (_, r) in routes(p) {
        let window = r.start...(r.stops.last!.time + 3)
        let intruders = p.items.filter { item in
            if case .route = item.kind { return false }
            if case .lyric = item.kind { return false }   // other blocks' lyrics may follow right after
            return window.contains(item.time)
        }
        #expect(intruders.isEmpty)
    }
}

@Test func noRouteWhenAttachmentsOff() {
    let k = Intensity(emoji: 0.5, reactions: 0.5, bubble: 0.5, screen: 0.5, attachments: 0, banners: 0.5)
    let p = ThreadPlanner.plan(lines: song(), trackID: "track-1", title: "T", artist: "A", duration: 200,
                               style: .alternate, cast: Cast(names: ["A"], source: .single), intensity: k)
    #expect(routes(p).isEmpty)
}

@Test func routeGeometryHasATurnPerStop() {
    let info = RouteInfo(stops: (0..<5).map { .init(time: Double($0) * 3 + 10, text: "stop \($0)") },
                         start: 8, place: "Austin", minutes: 12, seed: 42)
    let g = RouteGeometry(info)
    #expect(g.points.count == 6 && g.turns.count == 5 && g.turns.last == .arrive)
    // Dot sits on the start before departure, on each stop at its time, and at the end afterwards.
    #expect(RouteState(info, g, pos: 0).dot == g.points[0])
    #expect(RouteState(info, g, pos: 13).dot == g.points[2])
    let end = RouteState(info, g, pos: 99)
    #expect(end.arrived && end.dot == g.points[5] && end.totalLeft == 0 && end.overview == 1)
}
