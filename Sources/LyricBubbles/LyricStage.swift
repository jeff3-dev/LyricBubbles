import SwiftUI

// MARK: - Shared stage pieces
//
// Building blocks every camera-driven lyric style uses: the camera and its spring, layer
// placement with parallax, motion blur taps, splitting a song into pages, and small helpers.

// MARK: Camera

struct StageCamera {
    var center: CGPoint     // point on the pane the camera looks at
    var zoom: Double
    var angle: Double       // roll, degrees
}

/// Places a layer as seen through the camera. `depth` < 1 for things further away (parallax).
/// `tap` shifts a copy along the motion for motion blur.
struct CamTransform: ViewModifier {
    let cam: StageCamera
    let size: CGSize
    var depth: Double = 1
    var tap: MotionTaps.Tap = .identity

    func body(content: Content) -> some View {
        let z = (1 + (cam.zoom - 1) * depth) * tap.scale
        let cx = size.width / 2 + (cam.center.x - size.width / 2) * depth
        let cy = size.height / 2 + (cam.center.y - size.height / 2) * depth
        content
            .scaleEffect(z)
            .offset(x: (size.width / 2 - cx) * z + tap.offset.width,
                    y: (size.height / 2 - cy) * z + tap.offset.height)
            .rotationEffect(.degrees(cam.angle * (0.4 + 0.6 * depth)))
    }
}

/// Critically damped spring that chases the planner's target, frame by frame.
/// Its velocity drives the motion blur.
final class CameraRig {
    private var cam = StageCamera(center: .zero, zoom: 1, angle: 0)
    private var vx = 0.0, vy = 0.0, vz = 0.0, va = 0.0
    private var last: Date?
    private var lastSize = CGSize.zero
    private(set) var screenVelocity = CGVector.zero
    private(set) var zoomVelocity = 0.0

    func step(to target: StageCamera, at date: Date, response: Double) -> StageCamera {
        guard let l = last else {
            cam = target
            last = date
            return cam
        }
        let dt = min(1.0 / 20, date.timeIntervalSince(l))
        guard dt > 0 else { return cam }
        last = date

        let w = 2 * Double.pi / max(0.15, response)
        func spring(_ x: inout Double, _ v: inout Double, _ goal: Double) {
            let a = w * w * (goal - x) - 2 * w * v
            v += a * dt
            x += v * dt
        }
        var x = Double(cam.center.x), y = Double(cam.center.y), z = cam.zoom, a = cam.angle
        spring(&x, &vx, Double(target.center.x))
        spring(&y, &vy, Double(target.center.y))
        spring(&z, &vz, target.zoom)
        spring(&a, &va, target.angle)
        cam = StageCamera(center: CGPoint(x: x, y: y), zoom: z, angle: a)
        screenVelocity = CGVector(dx: -vx * z, dy: -vy * z)
        zoomVelocity = vz
        return cam
    }
}

/// Copies of the writing spread along the camera's motion (and zoom) during one "shutter".
struct MotionTaps {
    struct Tap: Identifiable {
        let id: Int
        let offset: CGSize
        let scale: CGFloat
        let opacity: Double
        static let identity = Tap(id: 0, offset: .zero, scale: 1, opacity: 1)
    }

    let taps: [Tap]
    let backdropBlur: CGFloat

    init(velocity: CGVector, zoomVelocity: Double, zoom: Double, amount: Double) {
        let shutter = amount * 2 / 40      // up to 1/20 s
        var span = CGSize(width: velocity.dx * shutter, height: velocity.dy * shutter)
        var len = (span.width * span.width + span.height * span.height).squareRoot()
        if len > 36 {   // cap the smear on very fast whips
            span = CGSize(width: span.width * 36 / len, height: span.height * 36 / len)
            len = 36
        }
        let zoomSpan = zoomVelocity * shutter / max(0.5, zoom)
        backdropBlur = min(12, len * 0.22 + CGFloat(abs(zoomSpan)) * 160)
        guard amount > 0, len > 1.2 || abs(zoomSpan) > 0.004 else {
            taps = [.identity]
            return
        }
        let n = min(5, max(3, Int(len / 4) + 3))
        taps = (0..<n).map { i in
            let f = CGFloat(i) / CGFloat(n - 1) - 0.5
            return Tap(id: i, offset: CGSize(width: span.width * f, height: span.height * f),
                       scale: 1 + CGFloat(zoomSpan) * f, opacity: 1.7 / Double(n) + 0.1)
        }
    }
}

// MARK: Pages

/// One page of a song: a verse/chorus block (or a slice of a long one). Empty pages mark
/// breaks (blank or ♪ lines) where nothing is shown.
struct LyricPage {
    var start: Double
    var lines: [(line: LyricLine, next: Double)]
}

enum LyricPages {
    /// Splits the song into pages: blocks broken on empty lines and section changes, long
    /// blocks cut into evenly sized pages of at most `maxRows` lines. When `intro` is given
    /// and the first lyric comes late, it becomes a page of its own during the intro.
    static func make(lines: [LyricLine], intro: String?, maxRows: Int) -> [LyricPage] {
        let firstTime = lines.first?.time ?? 0
        var segments: [LyricPage] = []
        if let intro, firstTime > 2.5 {
            let l = LyricLine(id: -1, time: min(0.4, firstTime / 4), text: intro)
            segments.append(LyricPage(start: l.time, lines: [(l, firstTime)]))
        }

        var blocks: [LyricPage] = []
        var lastSection = Int.min
        for (i, l) in lines.enumerated() {
            let next = i + 1 < lines.count ? lines[i + 1].time : l.time + 5
            let text = l.text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty || text == "♪" {
                blocks.append(LyricPage(start: l.time, lines: []))
                lastSection = Int.min
                continue
            }
            if l.section != lastSection || blocks.isEmpty {
                blocks.append(LyricPage(start: l.time, lines: []))
                lastSection = l.section
            }
            blocks[blocks.count - 1].lines.append((l, next))
        }
        let cap = max(1, maxRows)
        for b in blocks {
            guard b.lines.count > cap else { segments.append(b); continue }
            let pages = Int((Double(b.lines.count) / Double(cap)).rounded(.up))
            let per = Int((Double(b.lines.count) / Double(pages)).rounded(.up))
            for p in stride(from: 0, to: b.lines.count, by: per) {
                let chunk = Array(b.lines[p..<min(b.lines.count, p + per)])
                segments.append(LyricPage(start: chunk[0].line.time, lines: chunk))
            }
        }
        return segments
    }

    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }
}

// MARK: Helpers

func smoothstep(_ x: Double) -> Double {
    let t = min(1, max(0, x))
    return t * t * (3 - 2 * t)
}

/// Deterministic 0...1 values from a seed, so strokes keep their tilt and drips frame to frame.
struct Seeded {
    var state: UInt64
    init(_ seed: UInt64) { state = seed | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 10_000) / 10_000
    }
}

/// Simple wrapping layout that centers each row.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((i, s))
            x += s.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let rs = rows(subviews, maxWidth: maxW)
        var w: CGFloat = 0, h: CGFloat = 0
        for (k, row) in rs.enumerated() {
            let rw = row.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            w = max(w, rw)
            h += (row.map(\.1.height).max() ?? 0) + (k > 0 ? lineSpacing : 0)
        }
        return CGSize(width: min(w, maxW), height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, maxWidth: bounds.width) {
            let rw = row.map(\.1.width).reduce(0, +) + spacing * CGFloat(max(0, row.count - 1))
            let rh = row.map(\.1.height).max() ?? 0
            var x = bounds.midX - rw / 2
            for (i, s) in row {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += rh + lineSpacing
        }
    }
}

extension View {
    /// Shows this view everywhere except where `mask` draws.
    func reverseMask<M: View>(@ViewBuilder _ mask: () -> M) -> some View {
        self.mask {
            Rectangle()
                .overlay { mask().blendMode(.destinationOut) }
                .compositingGroup()
        }
    }
}

