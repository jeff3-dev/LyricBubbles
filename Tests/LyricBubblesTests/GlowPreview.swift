import SwiftUI
import Testing
@testable import LyricBubbles

// GLOW_PNG=/path/out.png swift test --filter glowPreview  -> renders the border over a dark window.
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["GLOW_PNG"] != nil))
func glowPreview() throws {
    let view = ZStack {
        Color.black
        Text("glow preview").foregroundStyle(.white)
    }
    .frame(width: 360, height: 460)
    .overlay { GlowBorder(model: PlayerModel()) }
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let cg = try #require(renderer.cgImage)
    let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
    try png.write(to: URL(fileURLWithPath: ProcessInfo.processInfo.environment["GLOW_PNG"]!))
}
