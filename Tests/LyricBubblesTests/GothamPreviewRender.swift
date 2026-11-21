import SwiftUI
import Testing
@testable import LyricBubbles

// GOTHAM_PNG=/path/out.png [GOTHAM_POS=11] [GOTHAM_T=3] [GOTHAM_SET='{"rain":0.8}'] [GOTHAM_SIZE=760x460] [GOTHAM_TIME=1] [GOTHAM_FLASH=1]
//   swift test --filter gothamPreview
// Renders one Gotham Night frame. GOTHAM_T picks the moment for the extras (fliers, cars,
// lightning). GOTHAM_TIME=1 also renders 30 frames and prints the average time per frame.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["GOTHAM_PNG"] != nil))
func gothamPreview() throws {
    let env = ProcessInfo.processInfo.environment
    let pos = Double(env["GOTHAM_POS"] ?? "") ?? 11
    let t = Double(env["GOTHAM_T"] ?? "") ?? 3
    let dims = (env["GOTHAM_SIZE"] ?? "760x460").split(separator: "x").compactMap { Double($0) }
    let size = CGSize(width: dims.count == 2 ? dims[0] : 760, height: dims.count == 2 ? dims[1] : 460)
    var s = GothamSettings()
    if let raw = env["GOTHAM_SET"], let extra = GothamSettings(rawValue: raw) {
        for (k, v) in extra.values { s.values[k] = v }
    }
    let script = GothamScript.make(lines: NeonFixture.lines, title: "Song")
    let tex = GothamTextures.make()
    let city = GothamCity()
    func frame(_ t: Double, at p: Double) -> GothamFrame {
        var f = GothamFrame.still(script: script, pos: p, t: t, size: size, s: s, tex: tex, city: city)
        if env["GOTHAM_FLASH"] != nil { f.flashAt = t - 0.05; f.flashSeed = 12345 }
        return f
    }
    let renderer = ImageRenderer(content: GothamCanvas(frame: frame(t, at: pos)).frame(width: size.width, height: size.height))
    renderer.scale = 2
    let cg = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: env["GOTHAM_PNG"]!))

    if env["GOTHAM_TIME"] != nil {
        let t0 = Date()
        for i in 0..<30 {
            let r = ImageRenderer(content: GothamCanvas(frame: frame(t + Double(i) / 60, at: pos + Double(i) / 60))
                .frame(width: size.width, height: size.height))
            r.scale = 2
            _ = r.cgImage
        }
        print(String(format: "avg frame (offscreen CPU render): %.1f ms", Date().timeIntervalSince(t0) / 30 * 1000))
    }
}

@Test func gothamLinesTakeTurnsOnTheClouds() {
    let lines = GothamScript.make(lines: NeonFixture.lines, title: "Song")
    #expect(lines.map(\.text) == ["Song", "City lights are calling", "out my name tonight", "and I can't stay home",
                                  "Turn it up", "one more time"])
    // Each line hands over no later than the next one starts, and a new section is flagged.
    for (a, b) in zip(lines, lines.dropFirst()) { #expect(a.end <= b.start) }
    #expect(lines.map(\.newSection) == [true, true, false, false, true, false])
    // Mid-line: that line is fully up, the next is queued, and the signal stays in its corner.
    let mid = GothamScript.moment(lines, pos: 13)
    #expect(mid.shown.last?.line.text == "out my name tonight")
    #expect(mid.shown.last?.out == 0)
    #expect(mid.next?.text == "and I can't stay home")
    #expect(mid.hero < 0.01)
    // A long gap after "and I can't stay home" hands the sky to the bat-signal.
    let sparse = GothamScript.make(lines: [LyricLine(id: 0, time: 10, text: "hold on"),
                                           LyricLine(id: 1, time: 25, text: "let go")], title: "")
    #expect(GothamScript.moment(sparse, pos: 11).hero < 0.01)
    #expect(GothamScript.moment(sparse, pos: 20).hero > 0.99)
    // After the song, everything has drifted off.
    let after = GothamScript.moment(lines, pos: 40)
    #expect(after.shown.isEmpty)
    #expect(after.hero > 0.99)
}

@Test func gothamCityIsStable() {
    // The same slot always builds the same building, so the skyline never reshuffles.
    let a = GothamCity.make(1, 42), b = GothamCity.make(1, 42)
    #expect(a.body.boundingRect == b.body.boundingRect)
    #expect(!a.body.isEmpty)
    #expect(GothamTextures.make() != nil)
}
