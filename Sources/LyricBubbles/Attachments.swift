import SwiftUI
import MapKit
import CoreLocation

// MARK: - Map snapshots

/// Geocodes a place name and renders a static map image once; the motion is drawn on top in SwiftUI.
actor MapSnapshotCache {
    static let shared = MapSnapshotCache()
    private var images: [String: NSImage] = [:]
    private var coords: [String: CLLocationCoordinate2D] = [:]
    private var failed = Set<String>()

    func image(place: String, dark: Bool, size: CGSize, meters: Double) async -> NSImage? {
        let key = "\(place)|\(dark)|\(Int(size.width))x\(Int(size.height))|\(Int(meters))"
        if let hit = images[key] { return hit }
        if failed.contains(key) { return nil }
        guard let c = await coordinate(place) else { failed.insert(key); return nil }

        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(center: c, latitudinalMeters: meters, longitudinalMeters: meters)
        opts.size = size
        opts.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        guard let snap = try? await MKMapSnapshotter(options: opts).start() else { failed.insert(key); return nil }
        images[key] = snap.image
        return snap.image
    }

    private func coordinate(_ place: String) async -> CLLocationCoordinate2D? {
        if let c = coords[place] { return c }
        let marks = try? await CLGeocoder().geocodeAddressString(place)
        let c = marks?.first?.location?.coordinate
        if let c { coords[place] = c }
        return c
    }
}

/// Map image for a place, with a drawn street grid as a fallback while loading or offline.
struct MapTile: View {
    let place: String
    let size: CGSize
    let meters: Double
    @State private var image: NSImage?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            FakeStreets(seed: place, dark: scheme == .dark)
            if let image {
                Image(nsImage: image).resizable().transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .task(id: "\(place)\(scheme == .dark)") {
            let img = await MapSnapshotCache.shared.image(place: place, dark: scheme == .dark, size: size, meters: meters)
            withAnimation(.easeOut(duration: 0.4)) { image = img }
        }
    }
}

/// Procedural map: land, a park, water and a road grid.
struct FakeStreets: View {
    let seed: String
    let dark: Bool

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(seed)
            let land = dark ? Color(white: 0.17) : Color(red: 0.96, green: 0.95, blue: 0.92)
            let road = dark ? Color(white: 0.32) : .white
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(land))
            ctx.fill(Path(ellipseIn: CGRect(x: rng.range(0...size.width * 0.6), y: rng.range(0...size.height * 0.6),
                                            width: 70, height: 50)),
                     with: .color(dark ? Color(red: 0.15, green: 0.27, blue: 0.18) : Color(red: 0.75, green: 0.89, blue: 0.7)))
            var water = Path()
            water.move(to: CGPoint(x: 0, y: size.height * 0.8))
            water.addCurve(to: CGPoint(x: size.width, y: size.height * 0.9),
                           control1: CGPoint(x: size.width * 0.3, y: size.height * 0.65),
                           control2: CGPoint(x: size.width * 0.7, y: size.height * 1.05))
            water.addLine(to: CGPoint(x: size.width, y: size.height))
            water.addLine(to: CGPoint(x: 0, y: size.height))
            ctx.fill(water, with: .color(dark ? Color(red: 0.13, green: 0.2, blue: 0.3) : Color(red: 0.67, green: 0.83, blue: 0.96)))
            for i in 0..<6 {
                let x = Double(i) * size.width / 5 + rng.range(-10...10)
                let y = Double(i) * size.height / 5 + rng.range(-10...10)
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x + 20, y: size.height)) },
                           with: .color(road), lineWidth: i % 2 == 0 ? 5 : 3)
                ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y - 15)) },
                           with: .color(road), lineWidth: i % 3 == 0 ? 6 : 3)
            }
        }
    }
}

// MARK: - Card chrome

/// Rounded card with a content area on top and a gray caption strip below.
struct AttachmentCard<Top: View, Caption: View>: View {
    let outgoing: Bool
    var width: CGFloat = 230
    @ViewBuilder let top: () -> Top
    @ViewBuilder let caption: () -> Caption
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            if outgoing { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 0) {
                top()
                caption()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(width: width, alignment: .leading)
                    .background(Palette.gray(scheme))
            }
            .frame(width: width)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !outgoing { Spacer(minLength: 50) }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Location

struct LiveLocationCard: View {
    let place: String
    let outgoing: Bool
    let age: Double

    var body: some View {
        let size = CGSize(width: 230, height: 140)
        AttachmentCard(outgoing: outgoing) {
            ZStack {
                MapTile(place: place, size: size, meters: 2200)
                // Pulsing blue dot that wanders a little, like someone walking.
                let drift = CGSize(width: sin(age * 0.35) * 26, height: cos(age * 0.27) * 16)
                let pulse = (age * 0.8).truncatingRemainder(dividingBy: 1)
                ZStack {
                    Circle().fill(Palette.blue.opacity(0.25 * (1 - pulse)))
                        .frame(width: 18 + 50 * pulse, height: 18 + 50 * pulse)
                    Circle().fill(.white).frame(width: 18, height: 18).shadow(radius: 2)
                    Circle().fill(Palette.blue).frame(width: 13, height: 13)
                }
                .offset(drift)
            }
        } caption: {
            HStack(spacing: 6) {
                Image(systemName: "location.fill").foregroundStyle(Palette.blue).font(.system(size: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Live Location").font(.system(size: 13, weight: .semibold))
                    Text("\(place) · updated just now").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

struct TripCard: View {
    let place: String
    let minutes: Int
    let outgoing: Bool
    let age: Double

    var body: some View {
        let size = CGSize(width: 230, height: 140)
        // The dot crawls along the route; each 8 s of song knocks a minute off the ETA.
        let progress = min(1, 0.08 + age / 45)
        let eta = max(1, minutes - Int(age / 8))

        AttachmentCard(outgoing: outgoing) {
            ZStack {
                MapTile(place: place, size: size, meters: 6000)
                Canvas { ctx, sz in
                    let p0 = CGPoint(x: sz.width * 0.12, y: sz.height * 0.85)
                    let c1 = CGPoint(x: sz.width * 0.25, y: sz.height * 0.2)
                    let c2 = CGPoint(x: sz.width * 0.6, y: sz.height * 0.95)
                    let p1 = CGPoint(x: sz.width * 0.82, y: sz.height * 0.28)
                    var route = Path()
                    route.move(to: p0)
                    route.addCurve(to: p1, control1: c1, control2: c2)
                    ctx.stroke(route, with: .color(.white), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    ctx.stroke(route, with: .color(Palette.blue), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    ctx.stroke(route.trimmedPath(from: 0, to: progress), with: .color(Color(red: 0.0, green: 0.36, blue: 0.85)),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round))

                    let t = progress, u = 1 - t
                    let x = u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p1.x
                    let y = u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p1.y
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 8, y: y - 8, width: 16, height: 16)), with: .color(.white))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11)), with: .color(Palette.blue))
                }
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white, .red)
                    .position(x: size.width * 0.82, y: size.height * 0.28 - 12)
            }
            .frame(width: size.width, height: size.height)
        } caption: {
            HStack(spacing: 6) {
                Image(systemName: "car.fill").foregroundStyle(Palette.blue).font(.system(size: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("On my way").font(.system(size: 13, weight: .semibold))
                    Text("Arriving in \(eta) min · \(place)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}

// MARK: - Weather

struct WeatherCard: View {
    let place: String
    let kind: Weather
    let temp: Int
    let outgoing: Bool
    let age: Double

    private var colors: [Color] {
        switch kind {
        case .sunny: [Color(red: 0.25, green: 0.6, blue: 0.98), Color(red: 0.5, green: 0.78, blue: 1)]
        case .rain, .cloudy, .windy: [Color(red: 0.36, green: 0.44, blue: 0.55), Color(red: 0.55, green: 0.62, blue: 0.7)]
        case .storm: [Color(red: 0.18, green: 0.2, blue: 0.3), Color(red: 0.34, green: 0.36, blue: 0.48)]
        case .snow: [Color(red: 0.55, green: 0.68, blue: 0.82), Color(red: 0.8, green: 0.86, blue: 0.93)]
        case .night: [Color(red: 0.05, green: 0.08, blue: 0.22), Color(red: 0.18, green: 0.2, blue: 0.42)]
        }
    }

    var body: some View {
        HStack {
            if outgoing { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(place).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text("\(temp)°").font(.system(size: 40, weight: .thin))
                    }
                    Spacer()
                    animatedSymbol.frame(width: 54, height: 54)
                }
                Text("\(kind.label)  H:\(temp + 5)° L:\(temp - 8)°").font(.system(size: 11, weight: .medium))
                Divider().overlay(.white.opacity(0.4))
                HStack {
                    ForEach(0..<4) { h in
                        VStack(spacing: 3) {
                            Text(h == 0 ? "Now" : "\(h)h").font(.system(size: 10, weight: .medium))
                            Image(systemName: kind.symbol).symbolRenderingMode(.multicolor).font(.system(size: 13))
                            Text("\(temp + [0, -1, -3, -4][h])°").font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .frame(width: 230)
            .background(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !outgoing { Spacer(minLength: 50) }
        }
        .padding(.horizontal, 14)
    }

    @ViewBuilder private var animatedSymbol: some View {
        let icon = Image(systemName: kind.symbol).symbolRenderingMode(.multicolor).font(.system(size: 36))
        switch kind {
        case .sunny:
            icon.rotationEffect(.degrees(age * 18))
        case .rain, .storm:
            ZStack {
                Canvas { ctx, size in
                    for i in 0..<10 {
                        let x = Double(i) / 10 * size.width + 4
                        let y = ((age * 60 + Double(i * 37)).truncatingRemainder(dividingBy: size.height))
                        ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: y)); $0.addLine(to: CGPoint(x: x - 2, y: y + 6)) },
                                   with: .color(.white.opacity(0.7)), lineWidth: 1.5)
                    }
                }
                icon.opacity(kind == .storm && sin(age * 5) > 0.93 ? 0.4 : 1)
            }
        case .snow:
            icon.offset(y: sin(age * 1.5) * 3)
        case .night:
            icon.opacity(0.75 + 0.25 * sin(age * 2))
        case .windy, .cloudy:
            icon.offset(x: sin(age * 0.8) * 5)
        }
    }
}

// MARK: - Voice message

struct VoiceMessage: View {
    let seconds: Int
    let seed: UInt64
    let outgoing: Bool
    let showTail: Bool
    let age: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Auto-plays once when it arrives.
        let progress = min(1, max(0, (age - 0.6) / Double(seconds)))
        let playing = progress > 0 && progress < 1
        let remaining = Int((1 - progress) * Double(seconds) + 0.99)
        let fg: Color = outgoing ? .white : .primary
        var rng = SeededRNG(String(seed))
        let bars = (0..<28).map { _ in rng.range(0.2...1) }

        HStack {
            if outgoing { Spacer(minLength: 60) }
            HStack(spacing: 8) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(fg)
                    .frame(width: 14)
                HStack(alignment: .center, spacing: 2) {
                    ForEach(bars.indices, id: \.self) { i in
                        let played = Double(i) / Double(bars.count) < progress
                        Capsule()
                            .fill(fg.opacity(played ? 1 : 0.4))
                            .frame(width: 2.5, height: 4 + 18 * bars[i] * (playing && played ? 0.85 + 0.15 * sin(age * 12 + Double(i)) : 1))
                    }
                }
                .frame(height: 24)
                Text(String(format: "0:%02d", playing ? remaining : seconds))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(fg.opacity(0.85))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(BubbleShape(outgoing: outgoing, showTail: showTail)
                .fill(outgoing ? Palette.blue : Palette.gray(scheme)))
            if !outgoing { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Photo

struct PhotoMessage: View {
    let artworkURL: URL?
    let outgoing: Bool
    let age: Double

    var body: some View {
        HStack {
            if outgoing { Spacer(minLength: 60) }
            AsyncImage(url: artworkURL) { img in
                img.resizable().scaledToFill()
                    .scaleEffect(1 + 0.08 * min(age / 10, 1))   // slow Ken Burns zoom
                    .offset(x: -6 * min(age / 10, 1))
            } placeholder: {
                LinearGradient(colors: [.orange.opacity(0.6), .pink.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .frame(width: 190, height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    Image(systemName: "livephoto").font(.system(size: 10, weight: .semibold))
                    Text("LIVE").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.black.opacity(0.35), in: Capsule())
                .padding(8)
                .opacity(age < 3 ? 1 : max(0, 1 - (age - 3)))
            }
            if !outgoing { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 14)
    }
}

// MARK: - Event invite

struct EventCard: View {
    let title: String
    let when: String
    let place: String
    let outgoing: Bool
    let age: Double

    var body: some View {
        let day = String(when.prefix(3)).uppercased()
        AttachmentCard(outgoing: outgoing) {
            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    Text(day == "TON" ? "TODAY" : day)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(Color.red)
                    Text("\(Calendar.current.component(.day, from: Date()))")
                        .font(.system(size: 20, weight: .medium))
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 42, height: 44)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(when).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(place).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 230)
            .background(.background.secondary)
        } caption: {
            // The invite gets answered a beat after it arrives.
            if age < 2.5 {
                HStack {
                    Text("Decline").foregroundStyle(.red)
                    Spacer()
                    Text("Accept").foregroundStyle(Palette.blue).fontWeight(.semibold)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 20)
            } else {
                Label("Accepted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: age >= 2.5)
    }
}

// MARK: - Sticker

struct StickerView: View {
    let sticker: Sticker
    let age: Double   // seconds since it was stuck on
    var blur: Double = 1

    var body: some View {
        // Slapped on from above: big and spinning, then springs flat onto the bubble.
        let (p, v) = Spring.step(age, response: 0.36, damping: 0.6)
        Text(sticker.emoji)
            .font(.system(size: 30))
            .shadow(color: .black.opacity(0.25 * p), radius: 2 + 6 * (1 - p), y: 1 + 5 * (1 - p))
            .rotationEffect(.degrees(sticker.angle + (1 - p) * 40))
            .scaleEffect(1.9 - 0.9 * p)
            .blur(radius: min(4, abs(v) * 0.3) * blur)
            .opacity(min(1, age / 0.1))
    }
}
