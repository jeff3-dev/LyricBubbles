import AppKit
import SwiftUI
import Testing
@testable import LyricBubbles

// FEVER_PNG=/path/out.png [FEVER_POS=11] [FEVER_T=3] [FEVER_SET='{"palette":2}'] [FEVER_SIZE=760x460]
//   [FEVER_EVENT=kaiju:0.4,ufo:0.5] [FEVER_TIME=1]
//   swift test --filter feverPreview
// Renders one Fever City frame. FEVER_EVENT pins events at a progress (0...1).
@Test(.enabled(if: ProcessInfo.processInfo.environment["FEVER_PNG"] != nil))
@MainActor
func feverPreview() throws {
    let env = ProcessInfo.processInfo.environment
    let pos = Double(env["FEVER_POS"] ?? "") ?? 11
    let t = Double(env["FEVER_T"] ?? "") ?? 3
    let dims = (env["FEVER_SIZE"] ?? "760x460").split(separator: "x").compactMap { Double($0) }
    let size = CGSize(width: dims.first ?? 760, height: dims.last ?? 460)
    var s = FeverSettings()
    if let raw = env["FEVER_SET"], let extra = FeverSettings(rawValue: raw) {
        for (k, v) in extra.values { s.values[k] = v }
    }
    var force: [FeverEvent: Double] = [:]
    for item in (env["FEVER_EVENT"] ?? "").split(separator: ",") {
        let parts = item.split(separator: ":")
        if parts.count == 2, let e = FeverEvent(rawValue: String(parts[0])), let p = Double(parts[1]) { force[e] = p }
    }
    if !force.isEmpty { s[.chaos] = 0; for k in FeverSettings.Key.events where k != .balloons && k != .moon { s[k] = 0 } }
    let script = GothamScript.make(lines: NeonFixture.lines, title: "Song")
    let tex = GothamTextures.make()
    let city = FeverCityMap()
    func frame(_ t: Double, at p: Double) -> FeverFrame {
        var f = FeverFrame.still(script: script, pos: p, t: t, size: size, s: s, tex: tex, city: city)
        f.force = force
        return f
    }
    let renderer = ImageRenderer(content: FeverCanvas(frame: frame(t, at: pos)).frame(width: size.width, height: size.height))
    renderer.scale = 2
    let cg = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: env["FEVER_PNG"]!))

    if env["FEVER_TIME"] != nil {
        let t0 = Date()
        for i in 0..<30 {
            let r = ImageRenderer(content: FeverCanvas(frame: frame(t + Double(i) / 60, at: pos + Double(i) / 60))
                .frame(width: size.width, height: size.height))
            r.scale = 2
            _ = r.cgImage
        }
        print(String(format: "avg frame (offscreen CPU render): %.1f ms", Date().timeIntervalSince(t0) / 30 * 1000))
    }
}

@Test func feverEventsComeFromTheClock() {
    var s = FeverSettings()
    s.apply(.overdose)
    let city = FeverCityMap()
    // Same moment, same events; and over a few minutes every event shows up at least once.
    var seen = Set<FeverEvent>()
    for i in 0..<2400 {
        let t = Double(i) * 0.25
        let f = FeverFrame.still(script: [], pos: 0, t: t, size: CGSize(width: 400, height: 300), s: s, tex: nil, city: city)
        let a = FeverEvents.active(f)
        #expect(Set(a.keys) == Set(FeverEvents.active(f).keys))
        for (k, e) in a { #expect(e.p >= 0 && e.p < 1); seen.insert(k) }
    }
    #expect(seen == Set(FeverEvent.allCases))
    // Everything off: nothing happens.
    for k in FeverSettings.Key.events { s[k] = 0 }
    let quiet = FeverFrame.still(script: [], pos: 0, t: 100, size: CGSize(width: 400, height: 300), s: s, tex: nil, city: city)
    #expect(FeverEvents.active(quiet).isEmpty)
}

@Test func feverLyricsKeepOneCarrierPerSection() {
    let script = GothamScript.make(lines: NeonFixture.lines, title: "Song")
    var carrierOf: [Int: String] = [:]          // line id -> carrier it was drawn on
    var lastLeave: [Int: Double] = [:]
    for i in 0..<1200 {
        let pos = Double(i) * 0.03
        let m = GothamScript.moment(script, pos: pos)
        let stages = FeverLyrics.stages(script, moment: m, pos: pos, place: .everywhere)
        #expect(stages.count <= 2)                // at most the leaving carrier and the arriving one
        for st in stages {
            #expect(st.leave >= 0 && st.leave <= 1)
            if let l = lastLeave[st.index] { #expect(st.leave >= l) }   // leaving never reverses
            lastLeave[st.index] = st.leave
            for (line, _) in st.lines {
                let c = "\(st.carrier)"
                if let prev = carrierOf[line.id] { #expect(prev == c) }  // a line never jumps carriers
                carrierOf[line.id] = c
            }
        }
    }
    // Lines in one section share a carrier; the mix still uses more than one over the song.
    for (a, b) in zip(script, script.dropFirst()) where !b.newSection {
        if let ca = carrierOf[a.id], let cb = carrierOf[b.id] { #expect(ca == cb) }
    }
    #expect(Set(carrierOf.values).count > 1)
    #expect(FeverLyrics.carrier(section: 3, seed: 5, .billboards) == .billboard)
}
