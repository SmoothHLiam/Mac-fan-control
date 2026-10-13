import SwiftUI
import FanCore

struct SensorsPage: View {
    @Environment(AppState.self) private var state

    var body: some View {
        PageScroll {
            PageHeader(title: "Sensors", subtitle: "\(state.sensors.count) temperature sensors · updated live") { EmptyView() }
            if state.sensors.isEmpty {
                Banner(symbol: "questionmark.circle", text: "No temperature sensors were readable on this Mac.", tint: Theme.textSecondary)
            }
            ForEach(SensorCategory.allCases, id: \.self) { category in
                let rows = state.sensors.filter { $0.descriptor.category == category }
                if !rows.isEmpty { SensorGroup(category: category, rows: rows) }
            }
        }
    }
}

private struct SensorGroup: View {
    @Environment(AppState.self) private var state
    let category: SensorCategory
    let rows: [AppState.SensorState]

    var body: some View {
        let values = rows.map(\.value)
        let avg = values.reduce(0, +) / Double(values.count)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: category.symbol).foregroundStyle(Theme.heat(avg))
                Text(category.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("avg \(state.format(avg))  ·  peak \(state.format(values.max()))")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            ForEach(rows) { row in
                Rectangle().fill(Theme.stroke).frame(height: 0.5)
                HStack(spacing: 14) {
                    Text(row.descriptor.name).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    GeometryReader { geo in
                        let f = min(max((row.value - 20) / 80, 0), 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule().fill(Theme.heat(row.value)).frame(width: max(4, geo.size.width * f))
                        }
                    }
                    .frame(width: 120, height: 4)
                    Text(state.format(row.value, decimals: 1))
                        .font(.metric(13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        .frame(width: 58, alignment: .trailing)
                }
                .padding(.horizontal, 20).padding(.vertical, 9)
            }
        }
        .glass(radius: 18)
    }
}
