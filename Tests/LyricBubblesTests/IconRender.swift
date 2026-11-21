import AppKit
import SwiftUI
import Testing
@testable import LyricBubbles

// ICONSET=/path/AppIcon.iconset swift test --filter renderIcon
@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["ICONSET"] != nil))
func renderIcon() throws {
    let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ICONSET"]!)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = base * scale
            let renderer = ImageRenderer(content: AppIconArt().frame(width: CGFloat(px), height: CGFloat(px)))
            renderer.scale = 1
            let cg = try #require(renderer.cgImage)
            let png = try #require(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]))
            let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
            try png.write(to: dir.appendingPathComponent(name))
        }
    }
}
