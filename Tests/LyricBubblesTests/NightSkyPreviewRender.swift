import SwiftUI
import Testing
@testable import LyricBubbles

// SKY_PNG=/path/out.png [SKY_POS=14.2] [SKY_SET='{"font":2}'] [SKY_SIZE=640x400] [SKY_TIME=1]
//   swift test --filter skyPreview
// Renders one Night Sky frame. SKY_TIME=1 also renders 30 frames and prints the average time per frame.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["SKY_PNG"] != nil))
func skyPreview() throws {
    let env = ProcessInfo.processInfo.environment
    let pos = Double(env["SKY_POS"] ?? "") ?? 14.2
    let dims = (env["SKY_SIZE"] ?? "640x400").split(separator: "x").compactMap { Double($0) }
    let size = CGSize(width: dims.count == 2 ? dims[0] : 640, height: dims.count == 2 ? dims[1] : 400)
    var s = SkySettings()
    if let raw = env["SKY_SET"], let extra = SkySettings(rawValue: raw) {
        for (k, v) in extra.values { s.values[k] = v }
    }
    let flight = SkyProgramCache().flight(lines: SkyFixture.lines, title: "Song", s: s)
    let tex = SkyTextures.make()
    func frame(_ t: Double, at p: Double) -> SkyFrame {
        SkyStage.frame(flight: flight, pos: p, t: t, beat: 0, level: Double(env["SKY_LEVEL"] ?? "") ?? 0, size: size, s: s, art: [], tex: tex)
    }
    let renderer = ImageRenderer(content: SkyCanvas(frame: frame(3, at: pos)).frame(width: size.width, height: size.height))
    renderer.scale = 2
    let cg = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: env["SKY_PNG"]!))

    if env["SKY_TIME"] != nil {
        let t0 = Date()
        for i in 0..<30 {
            let r = ImageRenderer(content: SkyCanvas(frame: frame(3 + Double(i) / 60, at: pos + Double(i) / 60))
                .frame(width: size.width, height: size.height))
            r.scale = 2
            _ = r.cgImage
        }
        print(String(format: "avg frame (offscreen CPU render): %.1f ms", Date().timeIntervalSince(t0) / 30 * 1000))
    }
}

enum SkyFixture {
    static let lines = [
        LyricLine(id: 0, time: 10, text: "Stars are calling", section: 0),
        LyricLine(id: 1, time: 12.5, text: "out my name tonight", singer: 1, section: 0),
        LyricLine(id: 2, time: 20, text: "Shine on", section: 1),
        LyricLine(id: 3, time: 22, text: "light up the sky", singer: Cast.everyone, section: 1),
        LyricLine(id: 4, time: 30, text: "Every night I wonder", section: 2),
        LyricLine(id: 5, time: 40, text: "Shine on", section: 3),
        LyricLine(id: 6, time: 42, text: "light up the sky", singer: Cast.everyone, section: 3),
    ]
}

@Test func skyChorusIsReachedAtWarp() {
    let pages = SkyProgram.make(lines: SkyFixture.lines, title: "Song", maxRows: 2)
    // Intro title, three parts, then the repeated chorus.
    #expect(pages.count == 5)
    #expect(pages.map(\.chorus) == [false, false, false, false, true])
    let flight = SkyFlight(pages: pages, speed: 0.5, warp: 0.7, curve: 0.6)
    let chorus = flight.pages[4].plan.start
    // The warp swells before the chorus, then eases off; it's quiet elsewhere.
    #expect(flight.at(chorus - 0.4).warp > 0.95)
    #expect(flight.at(chorus - 2.5).warp > 0.05)
    #expect(flight.at(chorus + 2.5).warp == 0)
    #expect(flight.at(25).warp == 0)
}

@Test func skyEveryPartComesToTheCamera() {
    let flight = SkyFlight(pages: SkyProgram.make(lines: SkyFixture.lines, title: "Song", maxRows: 2),
                           speed: 0.5, warp: 0.7, curve: 0.6)
    var lastZ = -Double.infinity
    for p in flight.pages {
        #expect(p.z > lastZ)
        lastZ = p.z
        // Ahead in the sky as it starts, still ahead (and readable) as its words are sung.
        let atStart = flight.depth(p, cam: flight.at(p.plan.start))
        #expect(atStart > 700 && atStart < 4500, "page \(p.plan.index) starts at depth \(atStart)")
        let lastWord = p.plan.lines.map { $0.start + $0.duration }.max()!
        #expect(flight.depth(p, cam: flight.at(lastWord)) > 450)
    }
}

@Test func skyLettersBecomeStars() {
    let con = SkyStars.constellation(["hello"], font: .clean, box: CGSize(width: 1000, height: 400), density: 0.5)
    #expect(con.stars.count > 15)
    #expect(con.links.count >= con.stars.count / 2)
    #expect(Set(con.stars.map(\.letter)).count == 5)
}

@Test func skyCameraNeverParks() {
    let flight = SkyFlight(pages: SkyProgram.make(lines: SkyFixture.lines, title: "Song", maxRows: 2),
                           speed: 0.5, warp: 1, curve: 0.6)
    var last = flight.at(5)
    var lastV = 0.0, lastDV = 0.0
    var p = 5.02
    while p < 70 {
        let c = flight.at(p)
        let v = (c.z - last.z) / 0.02
        #expect(v > 5, "camera parked at \(p)")
        // No jolts: acceleration changes smoothly from one frame to the next.
        let dv = v - lastV
        if p > 5.07 { #expect(abs(dv - lastDV) < 90, "speed jolted at \(p)") }
        last = c; lastV = v; lastDV = dv
        p += 0.02
    }
}
