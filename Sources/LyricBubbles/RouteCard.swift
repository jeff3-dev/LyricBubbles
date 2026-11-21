import SwiftUI

// MARK: - Geometry

enum Turn: Equatable {
    case left, right, straight, arrive

    var symbol: String {
        switch self {
        case .left: "arrow.turn.up.left"
        case .right: "arrow.turn.up.right"
        case .straight: "arrow.up"
        case .arrive: "mappin.and.ellipse"
        }
    }
}

/// A staircase route on a city grid. points[0] is the start; points[k + 1] is stop k.
/// Headings only go north or east, so the route never crosses itself.
struct RouteGeometry {
    static let block: CGFloat = 70
    static let milesPerBlock = 0.12

    let points: [CGPoint]
    let blocks: [Int]       // length of each segment, in blocks
    let turns: [Turn]       // maneuver at each stop

    init(_ info: RouteInfo) {
        var rng = SeededRNG(String(info.seed))
        let north = CGVector(dx: 0, dy: -1), east = CGVector(dx: 1, dy: 0)
        var heading = rng.chance(0.5) ? north : east
        var p = CGPoint.zero
        var points = [p]
        var blocks: [Int] = []
        var headings: [CGVector] = []
        for k in 0..<info.stops.count {
            if k > 0 && !rng.chance(0.25) { heading = heading == north ? east : north }
            let len = k == 0 ? Int.random(in: 1...2, using: &rng) : Int.random(in: 2...4, using: &rng)
            p = CGPoint(x: p.x + heading.dx * Self.block * CGFloat(len), y: p.y + heading.dy * Self.block * CGFloat(len))
            points.append(p)
            blocks.append(len)
            headings.append(heading)
        }
        var turns: [Turn] = []
        for k in headings.indices {
            if k == headings.count - 1 { turns.append(.arrive); break }
            let a = headings[k], b = headings[k + 1]
            turns.append(a == b ? .straight : (a == east ? .left : .right))   // east->north is a left turn
        }
        self.points = points
        self.blocks = blocks
        self.turns = turns
    }

    var bounds: CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}

/// Where the trip is at a given song time.
struct RouteState {
    let reached: Int            // last stop reached, -1 before the first
    let dot: CGPoint
    let heading: CGVector
    let segmentLeft: Double     // fraction of the current segment still ahead
    let totalLeft: Double       // fraction of the whole trip still ahead
    let overview: Double        // 0 = following the dot, 1 = zoomed out after arrival
    let arrived: Bool

    init(_ info: RouteInfo, _ g: RouteGeometry, pos: Double) {
        let n = info.stops.count
        reached = info.stops.lastIndex { $0.time <= pos } ?? -1
        arrived = reached == n - 1

        let seg: Int
        let t0: Double, t1: Double
        if reached < 0 { seg = 0; t0 = info.start; t1 = info.stops[0].time }
        else if !arrived { seg = reached + 1; t0 = info.stops[reached].time; t1 = info.stops[reached + 1].time }
        else { seg = n - 1; t0 = 0; t1 = 0 }

        let raw = arrived ? 1 : min(1, max(0, (pos - t0) / max(t1 - t0, 0.01)))
        let f = arrived ? 1 : 0.5 - 0.5 * cos(.pi * raw)
        let a = g.points[seg], b = g.points[seg + 1]
        dot = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
        let len = max(hypot(b.x - a.x, b.y - a.y), 1)
        heading = CGVector(dx: (b.x - a.x) / len, dy: (b.y - a.y) / len)
        segmentLeft = 1 - f

        let total = Double(g.blocks.reduce(0, +))
        let done = Double(g.blocks.prefix(seg).reduce(0, +)) + Double(g.blocks[seg]) * f
        totalLeft = max(0, 1 - done / total)

        overview = arrived ? min(1, max(0, (pos - info.stops[n - 1].time - 1.5) / 1.2)) : 0
    }
}

// MARK: - Card

/// Turn-by-turn navigation card. The verse's lines are the stops; the dot reaches
/// each stop as its line is sung, and the line pops up there and in the header.
struct RouteCard: View {
    let info: RouteInfo
    let outgoing: Bool
    let pos: Double
    var blur: Double = 1
    @Environment(\.colorScheme) private var scheme

    private let width: CGFloat = 284
    private static let navGreen = Color(red: 0.06, green: 0.45, blue: 0.26)
    private static let navGreenDark = Color(red: 0.04, green: 0.36, blue: 0.2)
    private static let etaGreen = Color(red: 0.09, green: 0.5, blue: 0.22)

    var body: some View {
        let g = RouteGeometry(info)
        let s = RouteState(info, g, pos: pos)

        HStack {
            if outgoing { Spacer(minLength: 30) }
            VStack(spacing: 0) {
                header(g, s)
                RouteMap(info: info, geometry: g, state: s, pos: pos, dark: scheme == .dark)
                    .frame(width: width, height: 230)
                footer(g, s)
            }
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.black.opacity(0.08)))
            if !outgoing { Spacer(minLength: 30) }
        }
        .padding(.horizontal, 14)
    }

    // MARK: Header

    /// (icon, instruction, distance to next stop) for the green header.
    private func instruction(_ g: RouteGeometry, _ s: RouteState) -> (String, String, String) {
        if s.reached < 0 {
            let north = s.heading.dy < 0
            return (north ? "arrow.up" : "arrow.right", north ? "Head north" : "Head east",
                    Self.distance(Double(g.blocks[0]) * s.segmentLeft))
        }
        if s.arrived { return ("flag.checkered", "You've arrived", "") }
        return (g.turns[s.reached].symbol, info.stops[s.reached].text,
                Self.distance(Double(g.blocks[s.reached + 1]) * s.segmentLeft))
    }

    @ViewBuilder private func header(_ g: RouteGeometry, _ s: RouteState) -> some View {
        let (icon, title, distance) = instruction(g, s)
        let since = s.reached >= 0 ? pos - info.stops[s.reached].time : pos - info.start
        let pop = Ease.outCubic(since / 0.35)

        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 2) {
                    Image(systemName: icon).font(.system(size: 26, weight: .bold))
                    if !distance.isEmpty {
                        Text(distance).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    }
                }
                .frame(width: 52)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(y: 8 * (1 - pop))
                    .blur(radius: 5 * (1 - pop) * blur)
                    .opacity(pop)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Self.navGreen)

            if !s.arrived && s.reached + 1 < g.turns.count {
                // Only the direction of the next turn: the next line stays a surprise.
                HStack(spacing: 6) {
                    Text("Then").font(.system(size: 12, weight: .medium))
                    Image(systemName: g.turns[s.reached + 1].symbol).font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("Stop \(s.reached + 2) of \(info.stops.count)").font(.system(size: 11)).opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Self.navGreenDark)
            }
        }
    }

    // MARK: Footer

    @ViewBuilder private func footer(_ g: RouteGeometry, _ s: RouteState) -> some View {
        let totalMiles = Double(g.blocks.reduce(0, +)) * RouteGeometry.milesPerBlock
        let minutesLeft = max(1, Int((Double(info.minutes) * s.totalLeft).rounded(.up)))
        let arrival = Date().addingTimeInterval(Double(minutesLeft) * 60).formatted(date: .omitted, time: .shortened)

        HStack(spacing: 8) {
            if s.arrived {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Self.etaGreen)
                Text("Arrived · \(info.place)").font(.system(size: 13, weight: .semibold)).lineLimit(1)
            } else {
                Text("\(minutesLeft) min")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Self.etaGreen)
                    .contentTransition(.numericText())
                Text("\(String(format: "%.1f", totalMiles * s.totalLeft)) mi · \(arrival)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !s.arrived {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                        .opacity(0.5 + 0.5 * sin(pos * 4))
                    Text("LIVE").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Palette.gray(scheme))
    }

    static func distance(_ blocks: Double) -> String {
        let mi = blocks * RouteGeometry.milesPerBlock
        if mi < 0.1 { return "\(max(50, Int(mi * 5280 / 50) * 50)) ft" }
        return String(format: "%.1f mi", mi)
    }
}

// MARK: - Map

/// Street-map drawing that follows the dot, then zooms out to the whole route on arrival.
struct RouteMap: View {
    let info: RouteInfo
    let geometry: RouteGeometry
    let state: RouteState
    let pos: Double
    let dark: Bool

    private struct Colors {
        let land, block, park, water, road, roadEdge, highway, highwayEdge, label, routeCasing, route, traveled: Color
    }

    private var c: Colors {
        dark
        ? Colors(land: Color(red: 0.14, green: 0.18, blue: 0.24), block: Color(red: 0.16, green: 0.2, blue: 0.27),
                 park: Color(red: 0.15, green: 0.24, blue: 0.25), water: Color(red: 0.09, green: 0.15, blue: 0.24),
                 road: Color(red: 0.22, green: 0.26, blue: 0.31), roadEdge: Color(red: 0.12, green: 0.15, blue: 0.2),
                 highway: Color(red: 0.45, green: 0.41, blue: 0.33), highwayEdge: Color(red: 0.12, green: 0.15, blue: 0.2),
                 label: Color(red: 0.61, green: 0.65, blue: 0.7), routeCasing: Color(red: 0.1, green: 0.35, blue: 0.75),
                 route: Color(red: 0.4, green: 0.62, blue: 1), traveled: Color(white: 0.45))
        : Colors(land: Color(red: 0.95, green: 0.95, blue: 0.94), block: Color(red: 0.91, green: 0.91, blue: 0.9),
                 park: Color(red: 0.78, green: 0.9, blue: 0.77), water: Color(red: 0.67, green: 0.85, blue: 1),
                 road: .white, roadEdge: Color(red: 0.85, green: 0.85, blue: 0.85),
                 highway: Color(red: 0.99, green: 0.89, blue: 0.58), highwayEdge: Color(red: 0.95, green: 0.75, blue: 0.35),
                 label: Color(red: 0.42, green: 0.44, blue: 0.47), routeCasing: Color(red: 0.1, green: 0.4, blue: 0.82),
                 route: Color(red: 0.26, green: 0.52, blue: 0.96), traveled: Color(white: 0.7))
    }

    private static let streets = ["Oak", "Pine", "Maple", "Cedar", "Elm", "Main", "Park", "Lake", "Hill", "Sunset",
                                  "Willow", "River", "Market", "Church", "Mill", "Spring", "Union", "Grand"]

    private func hash(_ i: Int, _ j: Int) -> Double {
        var x = info.seed ^ (UInt64(bitPattern: Int64(i)) &* 0x9E37_79B9_7F4A_7C15) ^ (UInt64(bitPattern: Int64(j)) &* 0xC2B2_AE3D_27D4_EB4F)
        x = (x ^ (x >> 31)) &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 29
        return Double(x >> 11) / Double(1 << 53)
    }

    var body: some View {
        Canvas(rendersAsynchronously: true) { ctx, size in
            let c = self.c
            let g = geometry
            let block = RouteGeometry.block
            let ov = Ease.outCubic(state.overview)

            // Camera: follow the dot (a bit below center so you see ahead), then frame the whole route.
            let b = g.bounds.insetBy(dx: -50, dy: -60)
            let fit = min(1, min(size.width / max(b.width, 1), size.height / max(b.height, 1)))
            let scale = 1 + (fit - 1) * ov
            var follow = CGPoint.zero
            let samples = 8
            for k in 0..<samples {
                let d = RouteState(info, g, pos: pos - Double(k) * 0.05).dot
                follow.x += d.x / CGFloat(samples)
                follow.y += d.y / CGFloat(samples)
            }
            let center = CGPoint(x: follow.x + (b.midX - follow.x) * ov,
                                 y: follow.y + (b.midY - follow.y) * ov)
            let anchorY = size.height * (0.62 - 0.12 * ov)
            func s(_ p: CGPoint) -> CGPoint {
                CGPoint(x: (p.x - center.x) * scale + size.width / 2, y: (p.y - center.y) * scale + anchorY)
            }
            let minX = center.x - size.width / 2 / scale, maxX = center.x + size.width / 2 / scale
            let minY = center.y - anchorY / scale, maxY = center.y + (size.height - anchorY) / scale

            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(c.land))

            // City blocks, parks and the odd pond.
            let i0 = Int(floor(minX / block)) - 1, i1 = Int(ceil(maxX / block)) + 1
            let j0 = Int(floor(minY / block)) - 1, j1 = Int(ceil(maxY / block)) + 1
            for i in i0...i1 {
                for j in j0...j1 {
                    let h = hash(i, j)
                    let inset: CGFloat = 7
                    let r = CGRect(x: CGFloat(i) * block + inset, y: CGFloat(j) * block + inset,
                                   width: block - 2 * inset, height: block - 2 * inset)
                    let o = s(r.origin)
                    let sr = CGRect(x: o.x, y: o.y, width: r.width * scale, height: r.height * scale)
                    let color = h < 0.08 ? c.park : (h < 0.11 ? c.water : c.block)
                    ctx.fill(Path(roundedRect: sr, cornerRadius: 3 * scale), with: .color(color))
                }
            }

            // Roads: edges first, then fill. Every 5th line is a highway.
            for pass in 0..<2 {
                for i in i0...i1 {
                    let hw = i % 5 == 0
                    let w = (hw ? 9 : 6) * scale + (pass == 0 ? 2 : 0)
                    let x = CGFloat(i) * block
                    let p = Path { $0.move(to: s(CGPoint(x: x, y: minY - block))); $0.addLine(to: s(CGPoint(x: x, y: maxY + block))) }
                    ctx.stroke(p, with: .color(pass == 0 ? (hw ? c.highwayEdge : c.roadEdge) : (hw ? c.highway : c.road)), lineWidth: w)
                }
                for j in j0...j1 {
                    let hw = j % 5 == 0
                    let w = (hw ? 9 : 6) * scale + (pass == 0 ? 2 : 0)
                    let y = CGFloat(j) * block
                    let p = Path { $0.move(to: s(CGPoint(x: minX - block, y: y))); $0.addLine(to: s(CGPoint(x: maxX + block, y: y))) }
                    ctx.stroke(p, with: .color(pass == 0 ? (hw ? c.highwayEdge : c.roadEdge) : (hw ? c.highway : c.road)), lineWidth: w)
                }
            }

            // Street names (only when zoomed in).
            if scale > 0.75 {
                for j in j0...j1 where j % 2 == 0 {
                    let name = Self.streets[abs(j) % Self.streets.count] + " St"
                    let p = s(CGPoint(x: (floor(center.x / block) + 0.5) * block, y: CGFloat(j) * block))
                    ctx.draw(Text(name).font(.system(size: 8, weight: .medium)).foregroundColor(c.label),
                             at: CGPoint(x: p.x, y: p.y - 9))
                }
                for i in i0...i1 where i % 3 == 0 {
                    let n = abs(i) + 1
                    let suffix = n % 10 == 1 && n != 11 ? "st" : n % 10 == 2 && n != 12 ? "nd" : n % 10 == 3 && n != 13 ? "rd" : "th"
                    var lc = ctx
                    let p = s(CGPoint(x: CGFloat(i) * block, y: (floor(center.y / block) + 0.5) * block))
                    lc.translateBy(x: p.x + 9, y: p.y)
                    lc.rotate(by: .degrees(-90))
                    lc.draw(Text("\(n)\(suffix) Ave").font(.system(size: 8, weight: .medium)).foregroundColor(c.label), at: .zero)
                }
            }

            // Route: casing, then the part still ahead in blue, the part behind in gray.
            let reachedSeg = state.reached + 1
            var ahead = Path()
            ahead.move(to: s(state.dot))
            for p in g.points[(reachedSeg + 1)...] { ahead.addLine(to: s(p)) }
            var behind = Path()
            behind.move(to: s(g.points[0]))
            for p in g.points[1..<(reachedSeg + 1)] { behind.addLine(to: s(p)) }   // empty before the first stop
            behind.addLine(to: s(state.dot))
            let rw = max(5, 7 * scale)
            let round = StrokeStyle(lineWidth: rw, lineCap: .round, lineJoin: .round)
            ctx.stroke(behind, with: .color(c.traveled), style: round)
            ctx.stroke(ahead, with: .color(c.routeCasing), style: StrokeStyle(lineWidth: rw + 3, lineCap: .round, lineJoin: .round))
            ctx.stroke(ahead, with: .color(c.route), style: round)

            // Start marker and stops.
            let sp = s(g.points[0])
            ctx.fill(Path(ellipseIn: CGRect(x: sp.x - 6, y: sp.y - 6, width: 12, height: 12)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: sp.x - 6, y: sp.y - 6, width: 12, height: 12)), with: .color(c.traveled), lineWidth: 3)
            for k in info.stops.indices {
                let p = s(g.points[k + 1])
                if k == info.stops.count - 1 {
                    drawPin(&ctx, at: p)
                } else {
                    let r = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                    ctx.fill(Path(ellipseIn: r), with: .color(.white))
                    ctx.stroke(Path(ellipseIn: r), with: .color(k <= state.reached ? c.traveled : c.routeCasing), lineWidth: 2.5)
                }
            }

            // Lyric callouts: newest is big, the two before it shrink and fade. Hidden in overview.
            if state.reached >= 0 && ov < 1 {
                let first = max(0, state.reached - 2)
                for k in first...state.reached {
                    let newest = k == state.reached
                    let age = pos - info.stops[k].time
                    let p = s(g.points[k + 1])
                    callout(&ctx, text: info.stops[k].text, at: p, newest: newest, age: age,
                            fade: (newest ? 1 : (k == state.reached - 1 ? 0.65 : 0.4)) * (1 - ov), canvasWidth: size.width)
                }
            }

            // You: heading cone, pulsing halo, white ring, blue dot.
            let d = s(state.dot)
            let angle = atan2(state.heading.dy, state.heading.dx)
            var cone = Path()
            cone.move(to: d)
            cone.addArc(center: d, radius: 30, startAngle: .radians(angle - 0.5), endAngle: .radians(angle + 0.5), clockwise: false)
            cone.closeSubpath()
            ctx.fill(cone, with: .radialGradient(Gradient(colors: [c.route.opacity(0.45), c.route.opacity(0)]),
                                                 center: d, startRadius: 0, endRadius: 30))
            let pulse = (pos * 0.9).truncatingRemainder(dividingBy: 1)
            let hr = 9 + 16 * pulse
            ctx.fill(Path(ellipseIn: CGRect(x: d.x - hr, y: d.y - hr, width: hr * 2, height: hr * 2)),
                     with: .color(c.route.opacity(0.3 * (1 - pulse))))
            ctx.fill(Path(ellipseIn: CGRect(x: d.x - 9, y: d.y - 9, width: 18, height: 18)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: d.x - 6.5, y: d.y - 6.5, width: 13, height: 13)), with: .color(c.route))
        }
    }

    private func drawPin(_ ctx: inout GraphicsContext, at p: CGPoint) {
        var pin = Path()
        pin.move(to: p)
        pin.addCurve(to: CGPoint(x: p.x - 10, y: p.y - 22), control1: CGPoint(x: p.x - 3, y: p.y - 8), control2: CGPoint(x: p.x - 10, y: p.y - 14))
        pin.addArc(center: CGPoint(x: p.x, y: p.y - 22), radius: 10, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        pin.addCurve(to: p, control1: CGPoint(x: p.x + 10, y: p.y - 14), control2: CGPoint(x: p.x + 3, y: p.y - 8))
        ctx.fill(pin, with: .color(Color(red: 0.92, green: 0.26, blue: 0.21)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 25.5, width: 7, height: 7)), with: .color(Color(red: 0.6, green: 0.1, blue: 0.08)))
    }

    private func callout(_ ctx: inout GraphicsContext, text: String, at p: CGPoint, newest: Bool, age: Double, fade: Double, canvasWidth: CGFloat) {
        let font: Font = .system(size: newest ? 12 : 10, weight: newest ? .semibold : .medium)
        let resolved = ctx.resolve(Text(text).font(font).foregroundColor(dark ? .white : .black))
        let maxW: CGFloat = newest ? 170 : 110
        let measured = resolved.measure(in: CGSize(width: maxW, height: newest ? 60 : 16))
        let w = min(maxW, measured.width), h = min(newest ? 60 : 16, measured.height)
        let pad: CGFloat = newest ? 8 : 5
        // Keep the bubble inside the map; the tip still points at the stop.
        let boxW = w + pad * 2
        let x = min(max(p.x - boxW / 2, 6), canvasWidth - boxW - 6)
        let box = CGRect(x: x, y: p.y - h - pad * 2 - 12, width: boxW, height: h + pad * 2)

        var layer = ctx
        layer.opacity = fade
        let pop = newest ? Ease.outBack(age / 0.35) : 1
        layer.translateBy(x: p.x, y: p.y - 8)
        layer.scaleBy(x: pop, y: pop)
        layer.translateBy(x: -p.x, y: -(p.y - 8))

        var bubble = Path(roundedRect: box, cornerRadius: 8)
        var tip = Path()
        tip.move(to: CGPoint(x: p.x - 6, y: box.maxY))
        tip.addLine(to: CGPoint(x: p.x, y: box.maxY + 7))
        tip.addLine(to: CGPoint(x: p.x + 6, y: box.maxY))
        tip.closeSubpath()
        bubble = bubble.union(tip)

        layer.drawLayer { l in
            l.addFilter(.shadow(color: .black.opacity(0.25), radius: 4, y: 2))
            l.fill(bubble, with: .color(dark ? Color(white: 0.2) : .white))
        }
        layer.draw(resolved, in: CGRect(x: box.minX + pad, y: box.minY + pad, width: w, height: h))
    }
}
