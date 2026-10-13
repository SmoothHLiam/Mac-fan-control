import SwiftUI

// MARK: - Typography helpers

extension Font {
    static func metric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }
}

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.textTertiary)
    }
}

// MARK: - Gauge

/// 270° ring gauge. `value` is 0...1.
struct RingGauge: View {
    let value: Double
    var tint: Color = Theme.accent
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * min(max(value, 0.001), 1))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.35), tint], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(0.45), radius: 6)
                .animation(.easeOut(duration: 0.5), value: value)
        }
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    var tint: Color = Theme.accent
    var fill = true
    var lineWidth: CGFloat = 1.5
    /// Fixed y-range; nil auto-scales to the data (with a minimum span so flat lines stay flat).
    var range: ClosedRange<Double>? = nil

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let lo = range?.lowerBound ?? (values.min() ?? 0)
            var hi = range?.upperBound ?? (values.max() ?? 1)
            if hi - lo < 1 { hi = lo + 1 }
            let step = size.width / CGFloat(values.count - 1)
            func point(_ i: Int) -> CGPoint {
                let n = (values[i] - lo) / (hi - lo)
                return CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(min(max(n, 0), 1)) * (size.height - 2) - 1)
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<values.count { line.addLine(to: point(i)) }
            if fill {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.28), tint.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Controls

struct ChipPicker<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let title: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selected {
                                Capsule().fill(Color.white.opacity(0.12))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "chip", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.28)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
    }
}

struct PillButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(filled ? Color.black.opacity(0.85) : Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(filled ? tint : Color.white.opacity(configuration.isPressed ? 0.14 : 0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(filled ? 0 : 0.12), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SliderTrack: View {
    @Binding var value: Double      // 0...1
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(height: 6)
                Capsule().fill(LinearGradient(colors: [tint.opacity(0.5), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, w * value), height: 6)
                Circle().fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .offset(x: min(max(w * value - 9, 0), w - 18))
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = min(max(g.location.x / w, 0), 1)
            })
        }
        .frame(height: 22)
    }
}

struct StatusPill: View {
    let text: String
    var tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6).shadow(color: tint.opacity(0.8), radius: 3)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

struct Banner: View {
    let symbol: String
    let text: String
    var tint: Color = Theme.amber
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action {
                Button(action.title, action: action.run).buttonStyle(PillButtonStyle(tint: tint))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
    }
}

func formatRPM(_ rpm: Double) -> String {
    NumberFormatter.localizedString(from: NSNumber(value: Int(rpm.rounded())), number: .decimal)
}
