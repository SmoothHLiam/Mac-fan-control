import SwiftUI
import FanCore

/// Drag points to shape the temperature -> fan speed curve. Double-click empty space to add a point,
/// right-click a point to remove it. A live marker shows where the fan is operating right now.
struct CurveEditor: View {
    @Binding var curve: FanCurve
    var currentTemp: Double?
    var limits: FanLimits
    var unit: TemperatureUnit

    private let tempLo = 30.0
    private let tempHi = 100.0
    private let inset: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(x: inset, y: inset, width: geo.size.width - inset * 2, height: geo.size.height - inset * 2 - 14)
            ZStack(alignment: .topLeading) {
                grid(plot)
                area(plot)
                line(plot)
                if let t = currentTemp { liveMarker(plot, temp: t) }
                ForEach(Array(curve.points.enumerated()), id: \.offset) { index, _ in
                    handle(index: index, plot: plot)
                }
                axisLabels(plot)
            }
            .coordinateSpace(name: "curve")
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { tap in addPoint(at: tap.location, plot: plot) })
        }
    }

    // MARK: Geometry

    private func x(_ temp: Double, _ plot: CGRect) -> CGFloat {
        plot.minX + CGFloat((temp - tempLo) / (tempHi - tempLo)) * plot.width
    }
    private func y(_ percent: Double, _ plot: CGRect) -> CGFloat {
        plot.maxY - CGFloat(percent / 100) * plot.height
    }
    private func temp(atX px: CGFloat, _ plot: CGRect) -> Double {
        tempLo + Double((px - plot.minX) / plot.width) * (tempHi - tempLo)
    }
    private func percent(atY py: CGFloat, _ plot: CGRect) -> Double {
        Double((plot.maxY - py) / plot.height) * 100
    }

    // MARK: Layers

    private func grid(_ plot: CGRect) -> some View {
        Canvas { ctx, _ in
            var p = Path()
            for pct in stride(from: 0.0, through: 100, by: 25) {
                p.move(to: CGPoint(x: plot.minX, y: y(pct, plot)))
                p.addLine(to: CGPoint(x: plot.maxX, y: y(pct, plot)))
            }
            for t in stride(from: 40.0, through: 100, by: 10) {
                p.move(to: CGPoint(x: x(t, plot), y: plot.minY))
                p.addLine(to: CGPoint(x: x(t, plot), y: plot.maxY))
            }
            ctx.stroke(p, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
        }
    }

    private func curvePath(_ plot: CGRect, closed: Bool) -> Path {
        var p = Path()
        guard let first = curve.points.first, let last = curve.points.last else { return p }
        p.move(to: CGPoint(x: plot.minX, y: y(first.percent, plot)))
        for pt in curve.points { p.addLine(to: CGPoint(x: x(pt.temp, plot), y: y(pt.percent, plot))) }
        p.addLine(to: CGPoint(x: plot.maxX, y: y(last.percent, plot)))
        if closed {
            p.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            p.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            p.closeSubpath()
        }
        return p
    }

    private func area(_ plot: CGRect) -> some View {
        curvePath(plot, closed: true)
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.28), Theme.accent.opacity(0.0)], startPoint: .top, endPoint: .bottom))
    }

    private func line(_ plot: CGRect) -> some View {
        curvePath(plot, closed: false)
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .shadow(color: Theme.accent.opacity(0.5), radius: 5)
    }

    private func liveMarker(_ plot: CGRect, temp t: Double) -> some View {
        let clamped = min(max(t, tempLo), tempHi)
        let pct = curve.percent(at: t)
        return ZStack {
            Path { p in
                p.move(to: CGPoint(x: x(clamped, plot), y: plot.minY))
                p.addLine(to: CGPoint(x: x(clamped, plot), y: plot.maxY))
            }
            .stroke(Theme.heat(t).opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            Circle().fill(Theme.heat(t)).frame(width: 9, height: 9)
                .shadow(color: Theme.heat(t), radius: 5)
                .position(x: x(clamped, plot), y: y(pct, plot))
        }
        .allowsHitTesting(false)
    }

    private func handle(index: Int, plot: CGRect) -> some View {
        let pt = curve.points[index]
        return Circle()
            .fill(Color.white)
            .frame(width: 13, height: 13)
            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 3))
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .position(x: x(pt.temp, plot), y: y(pt.percent, plot))
            .help("\(Int(unit.convert(pt.temp).rounded()))\(unit.suffix) → \(Int(limits.rpm(forPercent: pt.percent).rounded())) RPM")
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("curve")).onChanged { g in
                move(index: index, to: g.location, plot: plot)
            })
            .contextMenu {
                Button("Remove Point", role: .destructive) { remove(index) }
                    .disabled(curve.points.count <= FanCurve.minPoints)
            }
    }

    private func axisLabels(_ plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([40.0, 60.0, 80.0, 100.0], id: \.self) { t in
                Text("\(Int(unit.convert(t).rounded()))°")
                    .font(.system(size: 9, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .position(x: x(t, plot), y: plot.maxY + 11)
            }
            Text("\(Int(limits.max)) RPM")
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .position(x: plot.minX + 28, y: plot.minY + 7)
        }
        .allowsHitTesting(false)
    }

    // MARK: Editing

    private func move(index: Int, to location: CGPoint, plot: CGRect) {
        guard curve.points.indices.contains(index) else { return }
        var t = min(max(temp(atX: location.x, plot), tempLo), tempHi)
        let p = min(max(percent(atY: location.y, plot), 0), 100)
        // Keep neighbours' order so the point can't hop over them mid-drag.
        if index > 0 { t = max(t, curve.points[index - 1].temp + 1) }
        if index < curve.points.count - 1 { t = min(t, curve.points[index + 1].temp - 1) }
        curve.points[index] = CurvePoint(temp: t.rounded(), percent: p.rounded())
        curve.normalize()
    }

    private func addPoint(at location: CGPoint, plot: CGRect) {
        guard curve.points.count < FanCurve.maxPoints, plot.contains(location) else { return }
        curve.points.append(CurvePoint(temp: temp(atX: location.x, plot).rounded(), percent: percent(atY: location.y, plot).rounded()))
        curve.normalize()
    }

    private func remove(_ index: Int) {
        guard curve.points.count > FanCurve.minPoints, curve.points.indices.contains(index) else { return }
        curve.points.remove(at: index)
    }
}
