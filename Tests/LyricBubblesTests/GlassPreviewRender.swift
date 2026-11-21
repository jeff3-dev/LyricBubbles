import SwiftUI
import Testing
@testable import LyricBubbles

// GLASS_PNG=/path/out.png [GLASS_POS=17.4] [GLASS_MOTION=1] [GLASS_TIME=1] swift test --filter glassPreview
// Renders one fogged-glass frame: droplets simulated for 40 s, camera settled on its target.
// GLASS_TIME=1 also renders 30 frames and prints the average time per frame.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["GLASS_PNG"] != nil))
func glassPreview() throws {
    let env = ProcessInfo.processInfo.environment
    let lines = [
        LyricLine(id: 0, time: 10, text: "I left my name on the window", section: 0),
        LyricLine(id: 1, time: 13, text: "so you'd know I was here", section: 0),
        LyricLine(id: 2, time: 16, text: "and the rain came down", section: 0),
        LyricLine(id: 3, time: 30, text: "next part", section: 1),
    ]
    let pos = Double(env["GLASS_POS"] ?? "") ?? 17.4
    let size = CGSize(width: 440, height: 600)
    let over = CGSize(width: size.width * GlassComposite.overscan, height: size.height * GlassComposite.overscan)
    let s = GlassSettings()
    let scene = GlassScene.make(lines: lines, title: "Song", pos: pos)
    let sim = DropletSim()
    let start = Date()
    for i in 0..<(40 * 30) {
        sim.step(at: start.addingTimeInterval(Double(i) / 30), size: size, amount: s[.droplets], boost: 0, wipe: nil)
    }
    let cam = GlassCameraPlanner.target(scene: scene, pos: pos, size: size, s: s, t: 3, beat: 0)
    let blur = env["GLASS_MOTION"] != nil
        ? MotionTaps(velocity: CGVector(dx: -600, dy: 80), zoomVelocity: 0.4, zoom: cam.zoom, amount: 0.7)
        : MotionTaps(velocity: .zero, zoomVelocity: 0, zoom: cam.zoom, amount: 0.5)
    let tex = GlassTextures.make()
    func frame(_ t: Double) -> some View {
        GlassComposite(scene: scene, pos: pos + 6, size: size, t: t, beat: 0, cam: cam, blur: blur, s: s, art: nil,
                       lights: BokehField.lights(t: t, beat: 0, size: over, amount: s[.lights], palette: []),
                       drops: sim.drops, trail: sim.trail, simTime: sim.time, tex: tex)
            .frame(width: size.width, height: size.height)
    }
    let renderer = ImageRenderer(content: frame(3))
    renderer.scale = 2
    let cg = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: env["GLASS_PNG"]!))
    print("drops:", sim.drops.count, "sliding:", sim.drops.filter(\.sliding).count, "trail dots:", sim.trail.count)

    if env["GLASS_TIME"] != nil {
        let t0 = Date()
        for i in 0..<30 {
            let r = ImageRenderer(content: frame(3 + Double(i) / 60))
            r.scale = 2
            _ = r.cgImage
        }
        print(String(format: "avg frame (offscreen CPU render): %.1f ms", Date().timeIntervalSince(t0) / 30 * 1000))
    }
}
