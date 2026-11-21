import SwiftUI
import Testing
@testable import LyricBubbles

// NEON_PNG=/path/out.png [NEON_POS=14.2] [NEON_SET='{"wall":1}'] [NEON_SIZE=640x440] [NEON_MOTION=1] [NEON_TIME=1]
//   swift test --filter neonPreview
// Renders one Neon Sign frame with the camera settled on its target.
// NEON_TIME=1 also renders 30 frames and prints the average time per frame.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["NEON_PNG"] != nil))
func neonPreview() throws {
    let env = ProcessInfo.processInfo.environment
    let pos = Double(env["NEON_POS"] ?? "") ?? 14.2
    let dims = (env["NEON_SIZE"] ?? "640x440").split(separator: "x").compactMap { Double($0) }
    let size = CGSize(width: dims.count == 2 ? dims[0] : 640, height: dims.count == 2 ? dims[1] : 440)
    var s = NeonSettings()
    if let raw = env["NEON_SET"], let extra = NeonSettings(rawValue: raw) {
        for (k, v) in extra.values { s.values[k] = v }
    }
    let plans = NeonProgram.make(lines: NeonFixture.lines, title: "Song", maxRows: s.lines)
    let tex = NeonTextures.make()
    func frame(_ t: Double, at p: Double) -> NeonFrame {
        var f = NeonStage.frame(plans: plans, pos: p, t: t, beat: 0, level: 0.5, size: size, s: s, palette: [],
                                rig: nil, date: Date(), tex: tex)
        if env["NEON_MOTION"] != nil {
            f.taps = MotionTaps(velocity: CGVector(dx: -600, dy: 60), zoomVelocity: 0.3, zoom: f.cam.zoom, amount: 0.7).taps
        }
        return f
    }
    let renderer = ImageRenderer(content: NeonCanvas(frame: frame(3, at: pos)).frame(width: size.width, height: size.height))
    renderer.scale = 2
    let cg = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: env["NEON_PNG"]!))

    if env["NEON_TIME"] != nil {
        let t0 = Date()
        for i in 0..<30 {
            let r = ImageRenderer(content: NeonCanvas(frame: frame(3 + Double(i) / 60, at: pos + Double(i) / 60))
                .frame(width: size.width, height: size.height))
            r.scale = 2
            _ = r.cgImage
        }
        print(String(format: "avg frame (offscreen CPU render): %.1f ms", Date().timeIntervalSince(t0) / 30 * 1000))
    }
}

enum NeonFixture {
    static let lines = [
        LyricLine(id: 0, time: 10, text: "City lights are calling", section: 0),
        LyricLine(id: 1, time: 12.5, text: "out my name tonight", section: 0),
        LyricLine(id: 2, time: 15, text: "and I can't stay home", singer: Cast.everyone, section: 0),
        LyricLine(id: 3, time: 20, text: "Turn it up", section: 1),
        LyricLine(id: 4, time: 22, text: "one more time", section: 1),
    ]
}

@Test func neonSignsFollowThePages() {
    let plans = NeonProgram.make(lines: NeonFixture.lines, title: "Song", maxRows: 3)
    // Intro title, then the two sections.
    #expect(plans.map(\.texts) == [["Song"], ["City lights are calling", "out my name tonight", "and I can't stay home"],
                                   ["Turn it up", "one more time"]])
    #expect(plans.map(\.index) == [0, 1, 2])
    // Each sign powers down before (or as) the next one starts, and never before its last line is lit.
    for (a, b) in zip(plans, plans.dropFirst()) {
        #expect(a.offStart <= b.start)
        let last = a.lines.last!
        #expect(a.offStart >= min(b.start, last.start + last.duration))
    }
    #expect(plans.last!.offStart == .infinity)
}

@Test func neonWordsLightInOrder() {
    let plans = NeonProgram.make(lines: NeonFixture.lines, title: "Song", maxRows: 3)
    let geo = NeonGlyphs.sign(plans[1].texts, font: .script, fontSize: 40, box: CGSize(width: 500, height: 300))
    #expect(geo.words.count == 13)
    #expect(!geo.letters.isEmpty)
    let times = NeonLight.wordTimes(plans[1], geo)
    #expect(times.map(\.start) == times.map(\.start).sorted())
    #expect(times.first!.start == 10)
    // Halfway through the first line some letters are lit and later lines are still dark.
    let s = NeonSettings()
    let mid = NeonLight.letters(plans[1], geo, pos: 11, t: 0, s: s)
    let firstLine = geo.lineWords[0].flatMap { geo.words[$0].letters }
    let thirdLine = geo.lineWords[2].flatMap { geo.words[$0].letters }
    #expect(firstLine.contains { mid.bright[$0] > 0.5 })
    #expect(thirdLine.allSatisfy { mid.bright[$0] == 0 })
    // After powering down everything is dark.
    let off = NeonLight.letters(plans[1], geo, pos: plans[1].offStart + 1.5, t: 0, s: s)
    #expect(off.bright.allSatisfy { $0 == 0 })
}

@Test func neonIgnitionSettlesAtFull() {
    #expect(NeonLight.ignite(-0.1, seed: 1, speed: 0.5) == 0)
    #expect(abs(NeonLight.ignite(3, seed: 1, speed: 0.5) - 1) < 0.001)
    #expect(NeonLight.ignite(0.2, seed: 1, speed: 0.5) > 1)   // overshoot just after ignition
}

@Test func neonHumStartsAndStops() {
    // Volume 0 keeps it silent; this only checks the audio engine comes up and goes away.
    #expect(NeonHum.shared.update(enabled: true, volume: 0))
    #expect(!NeonHum.shared.update(enabled: false, volume: 0))
}
