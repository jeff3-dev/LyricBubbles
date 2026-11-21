import SwiftUI
import Testing
@testable import LyricBubbles

// POSTCARD_PNG=/path/out.png [POSTCARD_KIND=0…5] [POSTCARD_SEED=7] [POSTCARD_TEXT='city lights'] [POSTCARD_T=3]
//   [POSTCARD_SET='{"frame":0}'] [POSTCARD_SIZE=760x480] [POSTCARD_TIME=1] swift test --filter postcardPreview
// Renders one Postcards frame. KIND: 0 coast, 1 beach, 2 desert, 3 city, 4 harbour, 5 lake, 6 forest, 7 mountains.
// POSTCARD_TIME=1 also renders 30 frames and prints the average time per frame.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["POSTCARD_PNG"] != nil))
func postcardPreview() throws {
    let env = ProcessInfo.processInfo.environment
    let t = Double(env["POSTCARD_T"] ?? "") ?? 3
    let seed = UInt64(env["POSTCARD_SEED"] ?? "") ?? 7
    let kind = Int(env["POSTCARD_KIND"] ?? "").flatMap { PCKind(rawValue: $0) }
    let text = env["POSTCARD_TEXT"] ?? "City lights are calling"
    let dims = (env["POSTCARD_SIZE"] ?? "760x480").split(separator: "x").compactMap { Double($0) }
    let size = CGSize(width: dims.count == 2 ? dims[0] : 760, height: dims.count == 2 ? dims[1] : 480)
    var s = PostcardSettings()
    if let raw = env["POSTCARD_SET"], let extra = PostcardSettings(rawValue: raw) {
        for (k, v) in extra.values { s.values[k] = v }
    }
    let grain = PostcardGrain.make()
    func frame(_ t: Double) -> PostcardFrame {
        PostcardFrame.still(seed: seed, kind: kind, text: text, lineAge: t, age: t + 10, t: t, size: size, s: s, grain: grain)
    }
    let renderer = ImageRenderer(content: PostcardCanvas(frame: frame(t)).frame(width: size.width, height: size.height))
    renderer.scale = 2
    let cg = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: env["POSTCARD_PNG"]!))

    if env["POSTCARD_TIME"] != nil {
        let t0 = Date()
        for i in 0..<30 {
            let r = ImageRenderer(content: PostcardCanvas(frame: frame(t + Double(i) / 60)).frame(width: size.width, height: size.height))
            r.scale = 2
            _ = r.cgImage
        }
        print(String(format: "avg frame (offscreen CPU render): %.1f ms", Date().timeIntervalSince(t0) / 30 * 1000))
    }
}

@Test func postcardPagesFollowTheSections() {
    let pages = PostcardScript.make(lines: NeonFixture.lines, title: "Song")
    // Intro title, then the two sections, each its own page of lyrics, all on one poster.
    #expect(pages.map { $0.lines.map(\.text) } == [["Song"], ["City lights are calling", "out my name tonight", "and I can't stay home"],
                                                   ["Turn it up", "one more time"]])
    #expect(Set(pages.map(\.seed)).count == 1)
    let i = PostcardScript.index(pages, pos: 13)
    #expect(i == 1)
    let shot = PostcardFrame.shot(pages[i], pos: 13, album: nil)
    #expect(shot.lyrics.last?.text == "out my name tonight")
    #expect(PostcardScript.instrumental("Song").count == 1)

    // The poster never crossfades between pages, and the camera keeps the song's clock.
    let f = PostcardFrame.make(pages: pages, pos: pages[2].start + 0.2, t: 0, size: CGSize(width: 480, height: 330),
                               s: PostcardSettings(), kind: .forest, art: [], title: "Song", caption: "",
                               level: 0, beat: 0, grain: nil)
    #expect(f.prev == nil)
    #expect(f.shot.scene.kind == .forest)
    #expect(f.shot.age > 1)
}

@Test func postcardVibeDecoding() {
    func kind(_ title: String, _ lyrics: [String], art: [NeonRGB] = []) -> PCKind {
        PCVibeDecoder.decode(title: title, lyrics: lyrics, art: art, seed: 9)
    }
    #expect(kind("Downtown", ["neon on the avenue"]) == .city)
    #expect(kind("Into the Woods", ["leaves fall from the trees"]) == .forest)
    #expect(kind("Ain't No Mountain High Enough", ["no valley low enough"]) == .mountains)
    #expect(kind("Hello", ["sailing out of the harbour", "on a boat"]) == .harbor)
    #expect(kind("Hello", ["dusty highway", "miles of desert"]) == .desert)
    // No place words: the album art's colour decides.
    let green = [NeonRGB(0.1, 0.6, 0.2), NeonRGB(0.2, 0.5, 0.1)]
    #expect([.forest, .mountains].contains(kind("Hello", ["I love you"], art: green)))
    // Every vibe maps to its scene kind.
    #expect(PostcardVibe.allCases.compactMap(\.kind) == PCKind.allCases)
}

@Test func postcardScenesAreStable() {
    for kind in PCKind.allCases {
        let a = PCScene.make(seed: 42, kind: kind), b = PCScene.make(seed: 42, kind: kind)
        #expect(a.items.count == b.items.count)
        #expect(a.place == b.place)
        #expect(a.items.contains { if case .lyric = $0 { true } else { false } })
        let box = a.surface.box
        #expect(box.minX >= -100 && box.maxX <= pcW + 100 && box.minY >= 0 && box.maxY <= pcH)
    }
    #expect(PostcardGrain.make() != nil)
}
