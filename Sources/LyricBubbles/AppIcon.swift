import SwiftUI

/// The app icon, drawn in SwiftUI. Rendered to Resources/AppIcon.icns by
/// `ICONSET=… swift test --filter renderIcon` (see build.sh).
struct AppIconArt: View {
    var body: some View {
        GeometryReader { g in
            let s = g.size.width
            ZStack {
                // macOS icon grid: content squircle inset ~10% with a soft drop shadow.
                RoundedRectangle(cornerRadius: s * 0.185, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.55, blue: 1), Color(red: 0.42, green: 0.25, blue: 0.95),
                                                  Color(red: 0.72, green: 0.2, blue: 0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        // Rainbow rim, a nod to the glow border.
                        RoundedRectangle(cornerRadius: s * 0.185, style: .continuous)
                            .strokeBorder(AngularGradient(colors: [.cyan, .blue, .purple, .pink, .orange, .cyan], center: .center),
                                          lineWidth: s * 0.022)
                            .blur(radius: s * 0.006)
                            .opacity(0.9)
                    )
                    .overlay(
                        RadialGradient(colors: [.white.opacity(0.28), .clear], center: .topLeading,
                                       startRadius: 0, endRadius: s * 0.8)
                            .clipShape(RoundedRectangle(cornerRadius: s * 0.185, style: .continuous))
                    )
                    .padding(s * 0.1)
                    .shadow(color: .black.opacity(0.3), radius: s * 0.025, y: s * 0.015)

                // Received bubble (back) and sent bubble (front) with a music note.
                bubble(width: s * 0.44, height: s * 0.24, tailLeft: true)
                    .fill(.white.opacity(0.35))
                    .frame(width: s * 0.44, height: s * 0.24)
                    .offset(x: -s * 0.1, y: -s * 0.12)
                bubble(width: s * 0.48, height: s * 0.27, tailLeft: false)
                    .fill(.white)
                    .frame(width: s * 0.48, height: s * 0.27)
                    .shadow(color: .black.opacity(0.18), radius: s * 0.012, y: s * 0.008)
                    .offset(x: s * 0.08, y: s * 0.1)
                Image(systemName: "music.note")
                    .font(.system(size: s * 0.15, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(red: 0.05, green: 0.55, blue: 1), Color(red: 0.6, green: 0.25, blue: 0.9)],
                                                    startPoint: .top, endPoint: .bottom))
                    .offset(x: s * 0.08, y: s * 0.1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func bubble(width: CGFloat, height: CGFloat, tailLeft: Bool) -> some Shape {
        BubbleShape(outgoing: !tailLeft, showTail: true)
    }
}
