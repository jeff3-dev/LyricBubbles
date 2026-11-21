import AppKit
import SwiftUI
import Testing
@testable import LyricBubbles

// KINETIC_PNG=/path/out.png [KINETIC_POS=10.4,11.2,12.9] [KINETIC_SET='{"background":1}'] [KINETIC_SIZE=480x300] [KINETIC_TIME=1]
//   swift test --filter kineticPreview
// Renders one Kinetic frame per position, side by side in a grid (3 per row), with stand-in
// album art. KINETIC_TIME=1 also renders 30 frames and prints the average time per frame.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["KINETIC_PNG"] != nil))
func kineticPreview() throws {
    let env = ProcessInfo.processInfo.environment
    let positions = (env["KINETIC_POS"] ?? "10.3,11.0,12.2").split(separator: ",").compactMap { Double($0) }
    let dims = (env["KINETIC_SIZE"] ?? "480x300").split(separator: "x").compactMap { Double($0) }
    let size = CGSize(width: dims.count == 2 ? dims[0] : 480, height: dims.count == 2 ? dims[1] : 300)
    var s = KineticSettings()
    if let raw = env["KINETIC_SET"], let extra = KineticSettings(rawValue: raw) {
        for (k, v) in extra.values { s.values[k] = v }
    }
    let lines = KineticScript.make(lines: KineticFixture.lines, bigChance: s[.bigWords], emoji: s.flag(.emoji))
    let tex = KineticTextures.make()
    let art = KineticArtStore.smear(KineticFixture.art())
    func frame(_ p: Double) -> KineticFrame {
        KineticFrame(size: size, pos: p, t: 40 + p, beat: 0, level: 0.4, lines: KineticScript.visible(lines, at: p, s: s),
                     s: s, palette: s.palette([]), art: art, tex: tex)
    }
    let cols = min(3, positions.count)
    let rows = (positions.count + cols - 1) / cols
    let grid = VStack(spacing: 4) {
        ForEach(0..<rows, id: \.self) { r in
            HStack(spacing: 4) {
                ForEach(0..<cols, id: \.self) { c in
                    let i = r * cols + c
                    if i < positions.count {
                        KineticCanvas(frame: frame(positions[i])).frame(width: size.width, height: size.height)
                    }
                }
            }
        }
    }
    .background(Color.gray)
    let renderer = ImageRenderer(content: grid)
    renderer.scale = 1
    let cg = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: env["KINETIC_PNG"]!))

    if env["KINETIC_TIME"] != nil {
        let p0 = positions[0]
        let t0 = Date()
        for i in 0..<30 {
            let r = ImageRenderer(content: KineticCanvas(frame: frame(p0 + Double(i) / 60)).frame(width: size.width, height: size.height))
            r.scale = 2
            _ = r.cgImage
        }
        print(String(format: "avg frame (offscreen CPU render): %.1f ms", Date().timeIntervalSince(t0) / 30 * 1000))
    }
}

enum KineticFixture {
    static let lines = [
        LyricLine(id: 0, time: 10, text: "Look in my eyes, tell me your", section: 0),
        LyricLine(id: 1, time: 13, text: "secrets in the smoke", section: 0),
        LyricLine(id: 2, time: 15.5, text: "you", section: 0),
        LyricLine(id: 3, time: 17, text: "Turn it up one more time", section: 1),
    ]

    /// Stand-in album art: blue sky with a peach cloud band.
    static func art() -> CGImage {
        let ctx = CGContext(data: nil, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.22, green: 0.4, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.8, blue: 0.68, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 40, y: 140, width: 220, height: 40))
        ctx.setFillColor(CGColor(srgbRed: 0.15, green: 0.15, blue: 0.25, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 90, y: 150, width: 120, height: 14))
        return ctx.makeImage()!
    }
}

@Test func kineticPicksAStrongWord() {
    let lines = KineticScript.make(lines: KineticFixture.lines, bigChance: 1, emoji: true)
    #expect(lines.count == 4)
    // "eyes" (emoji bonus) beats the filler words.
    #expect(lines[0].big.map { lines[0].words[$0].text.hasPrefix("eyes") } == true)
    #expect(lines[2].big == 0)
    // Words reveal in order, all before the line ends.
    for l in lines {
        #expect(zip(l.words, l.words.dropFirst()).allSatisfy { $0.time <= $1.time })
        #expect(l.words.last!.time < l.end)
    }
    let none = KineticScript.make(lines: KineticFixture.lines, bigChance: 0, emoji: false)
    #expect(none.allSatisfy { $0.big == nil })
}
