import Testing
@testable import LyricBubbles

// Placeholder text only; no real lyrics.
private func lrc(_ rows: [(Double, String)]) -> [LyricLine] {
    rows.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
}

@Test func splitsCreditedArtists() {
    #expect(SingerDetector.artists(artist: "Alpha, Beta & Gamma", title: "Song") == ["Alpha", "Beta", "Gamma"])
    #expect(SingerDetector.artists(artist: "Alpha", title: "Song (feat. Beta)") == ["Alpha", "Beta"])
    #expect(SingerDetector.artists(artist: "Alpha", title: "Song (with Beta & Gamma)") == ["Alpha", "Beta", "Gamma"])
    #expect(SingerDetector.artists(artist: "Solo Act", title: "Song - Remastered") == ["Solo Act"])
}

@Test func usesNamePrefixTags() {
    let (lines, cast) = SingerDetector.detect(lrc([
        (1, "Alpha: line one"), (3, "line two"),
        (5, "Beta: line three"), (7, "line four"),
        (9, "Both: line five"),
    ]), artist: "Alpha", title: "Song (feat. Beta)")
    #expect(cast.source == .tagged)
    #expect(lines.map(\.singer) == [0, 0, 1, 1, Cast.everyone])
    #expect(lines[0].text == "line one")   // tag stripped
}

@Test func usesSectionHeaders() {
    let (lines, cast) = SingerDetector.detect(lrc([
        (1, "[Verse 1: Beta]"), (2, "aaa"), (4, "bbb"),
        (6, "[Chorus: Alpha & Beta]"), (7, "ccc"),
    ]), artist: "Alpha & Beta", title: "Song")
    #expect(cast.source == .tagged)
    #expect(lines.filter { !$0.text.isEmpty }.map(\.singer) == [1, 1, Cast.everyone])
}

@Test func voiceMarkersAddSingers() {
    let (lines, cast) = SingerDetector.detect(lrc([
        (1, "v1: aaa"), (3, "v2: bbb"), (5, "v1: ccc"),
    ]), artist: "Solo", title: "Song")
    #expect(cast.names.count == 2)
    #expect(lines.map(\.singer) == [0, 1, 0])
}

@Test func unknownRepeatedPrefixBecomesSinger() {
    let (lines, cast) = SingerDetector.detect(lrc([
        (1, "Delta: aaa"), (3, "Alpha: bbb"), (5, "Delta: ccc"),
    ]), artist: "Alpha", title: "Song")
    #expect(cast.names == ["Alpha", "Delta"])
    #expect(lines.map(\.singer) == [1, 0, 1])
}

@Test func guessesVersesAndChorus() {
    // verse A | chorus | verse B | chorus. Sections split by 8s pauses.
    let (lines, cast) = SingerDetector.detect(lrc([
        (0, "verse one a"), (2, "verse one b"),
        (10, "hook x"), (12, "hook y"),
        (20, "verse two a"), (22, "verse two b"),
        (30, "hook x"), (32, "hook y"),
    ]), artist: "Alpha", title: "Song (feat. Beta)")
    #expect(cast.source == .guessed)
    #expect(lines.map(\.singer) == [0, 0, Cast.everyone, Cast.everyone, 1, 1, Cast.everyone, Cast.everyone])
}

@Test func blankLrcLineSplitsSections() {
    var lines = lrc([(0, "a"), (2, "b"), (3, ""), (4, "c")])
    SingerDetector.markSections(&lines)
    #expect(lines.map(\.section) == [0, 0, 0, 1])
}

@Test func singleArtistStaysSingle() {
    let (lines, cast) = SingerDetector.detect(lrc([(0, "a"), (10, "b")]), artist: "Solo", title: "Song")
    #expect(cast.source == .single)
    #expect(lines.allSatisfy { $0.singer == 0 })
}

@Test func plainColonLyricIsNotATag() {
    // A single "Word: text" line that is not a credited artist must stay as text.
    let (lines, _) = SingerDetector.detect(lrc([(0, "Listen: something"), (2, "more")]), artist: "Solo", title: "Song")
    #expect(lines[0].text == "Listen: something")
}

@Test func overridesApplyPerSection() {
    var lines = lrc([(0, "a"), (2, "b"), (4, "c"), (12, "d")])
    SingerDetector.markSections(&lines)
    var cast = Cast(names: ["Alpha"], source: .single)
    SingerOverrides.apply([1: 1], to: &lines, cast: &cast)
    #expect(lines.map(\.singer) == [0, 0, 0, 1])
    #expect(cast.names.count == 2 && cast.edited)
}
