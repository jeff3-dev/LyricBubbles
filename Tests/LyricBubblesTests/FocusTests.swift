import Testing
@testable import LyricBubbles

// Placeholder text only; no real lyrics.
private func song() -> [LyricLine] {
    var rows: [(Double, String)] = []
    var t = 10.0
    for block in 0..<6 {
        for n in 0..<5 {
            rows.append((t, block % 2 == 1 ? "hook \(n) drive tonight" : "verse \(block) road \(n)"))
            t += 3
        }
        t += 9
    }
    var lines = rows.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    SingerDetector.markSections(&lines)
    return lines
}

private let loud = Intensity(emoji: 1, reactions: 1, bubble: 1, screen: 1, attachments: 1, banners: 1)

private func plans() -> [ChatThread] {
    (0..<12).map { n in
        ThreadPlanner.plan(lines: song(), trackID: "focus-\(n)", title: "T", artist: "A", duration: 240,
                           style: .alternate, cast: Cast(names: ["A"], source: .single), intensity: loud)
    }
}

@Test func everyRouteGetsAFocusWindow() {
    for p in plans() {
        let routeIDs = p.items.compactMap { if case .route = $0.kind { $0.id } else { nil } }
        #expect(!routeIDs.isEmpty)
        for id in routeIDs { #expect(p.focus.contains { $0.id == id }) }
    }
}

@Test func zoomEndsBeforeTheNextEvent() {
    for p in plans() {
        let events = p.items.map(\.time) + p.cues.map(\.at) + p.banners.map(\.at)
        for w in p.focus {
            let card = p.items.first { $0.id == w.id }!
            #expect(w.start > card.time)
            #expect(w.end - w.start >= 1.2)
            // Nothing else happens while focused, and the zoom is fully out before the next event.
            let inside = events.filter { $0 > card.time + 0.001 && $0 <= w.end }
            #expect(inside.isEmpty)
            #expect(w.amount(at: w.end) == 0)
            #expect(w.amount(at: w.end - FocusWindow.zoomOut) == 1 || w.end - w.start < FocusWindow.zoomIn + FocusWindow.zoomOut)
        }
    }
}

@Test func noEffectsOrBannersDuringARoute() {
    for p in plans() {
        for item in p.items {
            guard case .route(let r) = item.kind else { continue }
            let window = r.start...(r.stops.last!.time + 3)
            #expect(!p.cues.contains { window.contains($0.at) })
            #expect(!p.banners.contains { window.contains($0.at) || window.contains($0.at + Banner.duration) })
        }
    }
}

@Test func focusEasesSmoothly() {
    let w = FocusWindow(id: 1, start: 10, end: 20)
    #expect(w.amount(at: 9) == 0 && w.amount(at: 10) == 0)
    #expect(w.amount(at: 15) == 1)
    #expect(w.amount(at: 20) == 0 && w.amount(at: 21) == 0)
    // Monotonic in, monotonic out, no jumps bigger than a frame's worth.
    var prev = 0.0
    for i in 0...800 {
        let a = w.amount(at: 10 + Double(i) / 800)
        #expect(a >= prev - 1e-9 && a - prev < 0.01)
        prev = a
    }
}

@Test func motionBlurScale() {
    #expect(MotionPrefs.multiplier(0) == 0)
    #expect(MotionPrefs.multiplier(0.5) == 1)
    #expect(MotionPrefs.multiplier(1) == 4)
    #expect(MotionPrefs.label(0) == "Off" && MotionPrefs.label(1) == "Extreme")
}
