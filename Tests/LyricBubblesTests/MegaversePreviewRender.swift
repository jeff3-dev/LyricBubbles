import AppKit
import SwiftUI
import Testing
@testable import LyricBubbles

// MEGA_PNG=/path/out.png [MEGA_LOOK=0,1,2,3] [MEGA_LOC=0,1] [MEGA_POS=12] [MEGA_SIZE=480x330]
//   [MEGA_SET='{"placement":2}'] [MEGA_BEAT=0.8] [MEGA_HIT=0.15] [MEGA_CUT=0.5] [MEGA_CARD=1] [MEGA_TIME=1]
//   swift test --filter megaPreview
// Renders one Megaverse frame for every look × location (looks across, locations down), with
// stand-in album art and a sung line. Looks: 0 Deco, 1 Noir, 2 Comic, 3 Neon. Locations:
// 0 Lounge, 1 Jazz Stage, 2 Street, 3 Rooftop, 4 Billiards, 5 Marquee, 6 Record Shop. MEGA_HIT shows an accent hit that age (s),
// MEGA_CUT a transition from the previous location at that progress, MEGA_CARD the title card.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["MEGA_PNG"] != nil))
func megaPreview() throws {
    let env = ProcessInfo.processInfo.environment
    func ints(_ k: String, _ d: String) -> [Int] { (env[k] ?? d).split(separator: ",").compactMap { Int($0) } }
    let looks = ints("MEGA_LOOK", "0,1,2,3")
    let locs = ints("MEGA_LOC", "0")
    let pos = Double(env["MEGA_POS"] ?? "12") ?? 12
    let dims = (env["MEGA_SIZE"] ?? "480x330").split(separator: "x").compactMap { Double($0) }
    let size = CGSize(width: dims.count == 2 ? dims[0] : 480, height: dims.count == 2 ? dims[1] : 330)
    let beat = Double(env["MEGA_BEAT"] ?? "0") ?? 0
    let fixture = MegaFixture.art()

    func frame(look: Int, loc: Int, at p: Double) -> MegaFrame {
        var s = MegaSettings()
        if let raw = env["MEGA_SET"], let extra = MegaSettings(rawValue: raw) {
            for (k, v) in extra.values { s.values[k] = v }
        }
        s[.look] = Double(look)
        let location = MegaLocation(rawValue: loc) ?? .lounge
        let shot = MegaShot(index: 1, scene: MegaScenes.scene(location, variant: 0), start: p - 3, zoom: 1, pan: .zero)
        var prev: MegaShot?
        var cut = 1.0
        if let c = env["MEGA_CUT"].flatMap(Double.init) {
            cut = c
            let other = MegaLocation(rawValue: (loc + 1) % 4) ?? .stage
            prev = MegaShot(index: 0, scene: MegaScenes.scene(other, variant: 0), start: p - 20, zoom: 1, pan: .zero)
        }
        let art = MegaArtTreatment.apply(fixture, look: s.look, strength: s[.artStrength])
        var f = MegaFrame(size: size, pos: p, t: 40 + p, beat: beat, level: 0.55, s: s, palette: s.palette([]), shot: shot, prev: prev,
                          cut: cut, lyric: MegaLyric(text: env["MEGA_LYRIC"] ?? "Look in my eyes, tell me your secrets", start: p - 1.2,
                                                     end: p + 3, singer: 0, next: s.flag(.showNext) ? "in the smoke tonight" : nil),
                          header: ("CHORUS", 1), card: nil, hit: nil, art: art,
                          title: "Midnight Stroll", artist: "The Fixtures", singers: 2)
        if let h = env["MEGA_HIT"].flatMap(Double.init) { f.hit = (h, 3); f.lastHit = (h, 3) }
        if let b = env["MEGA_BEATS"].flatMap(Int.init) { f.beats = b }
        if env["MEGA_CARD"] != nil { f.card = MegaCard(title: "Midnight Stroll", sub: "The Fixtures", alpha: 1); f.lyric = nil }
        return f
    }

    if env["MEGA_PICKER"] != nil {
        // The Quick row's scene picker at the popover's width.
        let r = ImageRenderer(content: MegaScenePicker().padding(16).frame(width: 360).background(Color(white: 0.2)).environment(\.colorScheme, .dark))
        r.scale = 2
        let img = try #require(r.cgImage)
        try #require(NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: env["MEGA_PNG"]!))
        return
    }
    if env["MEGA_THUMBS"] != nil {
        // The scene picker's tiles: every built location in each look.
        let tiles = VStack(spacing: 6) {
            ForEach(looks, id: \.self) { look in
                HStack(spacing: 6) {
                    ForEach(MegaLocation.builtCases) { l in
                        var s = MegaSettings()
                        let _ = s[.look] = Double(look)
                        MegaThumb(location: l, settings: s, size: CGSize(width: 97, height: 60))
                    }
                }
            }
        }
        .padding(6)
        .background(Color.gray)
        let r = ImageRenderer(content: tiles)
        r.scale = 2
        let img = try #require(r.cgImage)
        try #require(NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: env["MEGA_PNG"]!))
        return
    }

    let grid = VStack(spacing: 4) {
        ForEach(locs, id: \.self) { loc in
            HStack(spacing: 4) {
                ForEach(looks, id: \.self) { look in
                    MegaCanvas(frame: frame(look: look, loc: loc, at: pos)).frame(width: size.width, height: size.height)
                }
            }
        }
    }
    .background(Color.gray)
    let renderer = ImageRenderer(content: grid)
    renderer.scale = 1
    let cg = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: env["MEGA_PNG"]!))

    if env["MEGA_TIME"] != nil {
        let t0 = Date()
        for i in 0..<30 {
            let r = ImageRenderer(content: MegaCanvas(frame: frame(look: looks[0], loc: locs[0], at: pos + Double(i) / 60))
                .frame(width: size.width, height: size.height))
            r.scale = 2
            _ = r.cgImage
        }
        print(String(format: "avg frame (offscreen CPU render): %.1f ms", Date().timeIntervalSince(t0) / 30 * 1000))
    }
}

enum MegaFixture {
    /// Stand-in album art: a red sun over purple hills.
    static func art() -> CGImage {
        let ctx = CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.98, green: 0.62, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.15, blue: 0.25, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 90, y: 120, width: 120, height: 120))
        ctx.setFillColor(CGColor(srgbRed: 0.3, green: 0.12, blue: 0.4, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: -60, y: -120, width: 260, height: 240))
        ctx.fillEllipse(in: CGRect(x: 120, y: -150, width: 300, height: 260))
        return ctx.makeImage()!
    }
}

@Test func megaShotsAreSeededAndVary() {
    var s = MegaSettings()
    let a = (0..<16).map { MegaDirector.shot($0, start: 0, seed: 42, s: s).scene.location }
    let b = (0..<16).map { MegaDirector.shot($0, start: 0, seed: 42, s: s).scene.location }
    #expect(a == b)
    // Shuffle visits every built location in each block, never twice in a row.
    let n = MegaLocation.builtCases.count
    #expect(Set(a.prefix(n)) == Set(MegaLocation.builtCases))
    #expect(Set(a.dropFirst(n).prefix(n)) == Set(MegaLocation.builtCases))
    #expect(zip(a, a.dropFirst()).allSatisfy { $0 != $1 })
    // Unbuilt locations are never visited; switching all off falls back to the Lounge.
    for l in MegaLocation.allCases { s[l.key] = 0 }
    #expect(MegaDirector.shot(3, start: 0, seed: 1, s: s).scene.location == .lounge)
    s[MegaLocation.office.key] = 1
    #expect(s.locations == [.lounge])
    // Pinning a scene stays there whatever the visit order; unbuilt pins are ignored.
    s = MegaSettings()
    s[.pin] = Double(MegaLocation.rooftop.rawValue)
    #expect((0..<6).allSatisfy { MegaDirector.shot($0, start: 0, seed: 9, s: s).scene.location == .rooftop })
    s[.pin] = Double(MegaLocation.office.rawValue)
    #expect(s.pinned == nil && s.locations.count == MegaLocation.builtCases.count)
}

@Test func megaDirectorCutsOnSections() {
    let lines = [
        LyricLine(id: 0, time: 10, text: "first verse line", section: 0),
        LyricLine(id: 1, time: 13, text: "second", section: 0),
        LyricLine(id: 2, time: 20, text: "the hook", section: 1),
        LyricLine(id: 3, time: 30, text: "verse again", section: 2),
        LyricLine(id: 4, time: 40, text: "the hook", section: 3),
    ]
    let d = MegaDirector()
    var input = MegaInput(songKey: "song", title: "T", artist: "A", singers: 1)
    input.lines = lines
    func at(_ p: Double) -> MegaFrame {
        d.frame(size: CGSize(width: 100, height: 100), pos: p, t: p, audio: (0, 0), s: MegaSettings(), input: input,
                palette: MegaMood.smoky.palette, art: nil)
    }
    #expect(at(11).shot.index == 0)
    #expect(at(21).shot.index == 1)
    #expect(at(41).shot.index == 3)
    #expect(at(20.1).cut < 1)
    #expect(at(21).header?.text == "CHORUS")
    #expect(at(31).header?.text == "VERSE 2")
    #expect(at(14).lyric?.text == "second")
    #expect(at(5).card?.title == "T")
}
