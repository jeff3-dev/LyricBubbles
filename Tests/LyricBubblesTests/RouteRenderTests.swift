import SwiftUI
import Testing
@testable import LyricBubbles

/// Regression: the map crashed (invalid range) in the second before the first stop.
/// Draw every phase of many routes: before departure, between stops, arrival, overview.
@MainActor
@Test func routeMapDrawsAtEveryMoment() {
    for seed in UInt64(1)...20 {
        let count = Int(seed % 5) + 3
        let info = RouteInfo(stops: (0..<count).map { .init(time: 10 + Double($0) * 2.5, text: "stop \($0)") },
                             start: 8.6, place: "Austin", minutes: 12, seed: seed)
        let g = RouteGeometry(info)
        var pos = 0.0
        while pos < 10 + Double(count) * 2.5 + 5 {
            for dark in [false, true] {
                let view = VStack(spacing: 0) {
                    RouteCard(info: info, outgoing: seed % 2 == 0, pos: pos)
                    RouteMap(info: info, geometry: g, state: RouteState(info, g, pos: pos), pos: pos, dark: dark)
                        .frame(width: 284, height: 230)
                }
                let renderer = ImageRenderer(content: view)
                #expect(renderer.cgImage != nil)
            }
            pos += 0.37
        }
    }
}
