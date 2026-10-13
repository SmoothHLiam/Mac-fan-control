import SwiftUI

enum Theme {
    static let background = Color(red: 0.027, green: 0.035, blue: 0.055)
    static let surface = Color.white.opacity(0.045)
    static let surfaceStrong = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.09)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.34)

    static let accent = Color(red: 0.42, green: 0.65, blue: 1.0)
    static let teal = Color(red: 0.36, green: 0.86, blue: 0.78)
    static let amber = Color(red: 1.0, green: 0.78, blue: 0.30)
    static let red = Color(red: 1.0, green: 0.36, blue: 0.38)

    /// Cool -> warm ramp for temperatures (°C).
    static func heat(_ celsius: Double) -> Color {
        let stops: [(Double, (Double, Double, Double))] = [
            (40, (0.36, 0.86, 0.78)), (62, (0.42, 0.65, 1.0)), (76, (1.0, 0.78, 0.30)), (92, (1.0, 0.36, 0.38)),
        ]
        if celsius <= stops[0].0 { return color(stops[0].1) }
        for i in 1..<stops.count where celsius <= stops[i].0 {
            let (t0, c0) = stops[i - 1], (t1, c1) = stops[i]
            let f = (celsius - t0) / (t1 - t0)
            return color((c0.0 + (c1.0 - c0.0) * f, c0.1 + (c1.1 - c0.1) * f, c0.2 + (c1.2 - c0.2) * f))
        }
        return color(stops[stops.count - 1].1)
    }

    private static func color(_ c: (Double, Double, Double)) -> Color {
        Color(red: c.0, green: c.1, blue: c.2)
    }

    static func nsHeat(_ celsius: Double) -> NSColor { NSColor(heat(celsius)) }
}

// MARK: - Glass

/// Liquid Glass on macOS 26+, a dark frosted material before that.
struct GlassSurface: ViewModifier {
    var radius: CGFloat = 18
    var prominent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            fallback(content, shape)
        }
        #else
        fallback(content, shape)
        #endif
    }

    private func fallback(_ content: Content, _ shape: RoundedRectangle) -> some View {
        content
            .background(shape.fill(prominent ? Theme.surfaceStrong : Theme.surface))
            .background(shape.fill(.ultraThinMaterial).opacity(0.5))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.04)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75))
    }
}

extension View {
    func glass(radius: CGFloat = 18, prominent: Bool = false) -> some View {
        modifier(GlassSurface(radius: radius, prominent: prominent))
    }
}

/// Window / popover backdrop: deep blue-black with a faint cool bloom, so glass has something to refract.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.background.opacity(0.88)
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.teal.opacity(0.07), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

/// Native behind-window blur for the control center and popover chrome.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}
