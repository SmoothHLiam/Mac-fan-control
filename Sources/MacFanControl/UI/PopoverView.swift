import SwiftUI
import FanCore

/// Menu bar dropdown: glanceable status + one-tap profiles.
struct PopoverView: View {
    @Environment(AppState.self) private var state
    var openControlCenter: () -> Void
    var openSettings: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            header
            ProfileStrip()
            if let message = bannerMessage {
                Banner(symbol: "exclamationmark.triangle.fill", text: message.text, tint: message.tint)
            }
            if state.hasFans {
                VStack(spacing: 8) {
                    ForEach(state.fans) { fan in FanRow(fan: fan) }
                }
            }
            TemperatureGrid()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(AmbientBackground())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fan Control").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(state.workingName).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            statusPill
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if state.criticalActive {
            StatusPill(text: "Thermal safeguard", tint: Theme.red)
        } else if state.isDemo {
            StatusPill(text: "Demo data", tint: Theme.amber)
        } else if !state.hasFans {
            StatusPill(text: "No fans", tint: Theme.textTertiary)
        } else if state.config.working.fallback.mode == .auto && !state.isModified {
            StatusPill(text: "Managed by macOS", tint: Theme.teal)
        } else {
            StatusPill(text: state.helperReady ? "Controlling" : "Helper offline",
                       tint: state.helperReady ? Theme.accent : Theme.amber)
        }
    }

    private var bannerMessage: (text: String, tint: Color)? {
        if state.criticalActive {
            return ("Silicon is above \(Int(state.config.settings.criticalTemp))°C. Fans are forced to maximum.", Theme.red)
        }
        if state.hasFans, !state.helperReady, !state.isDemo, state.activeProfile?.id != Profile.auto.id || state.isModified {
            return ("Helper isn't running, so fan changes can't be applied. Open Settings to install it.", Theme.amber)
        }
        return nil
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Control Center", action: openControlCenter).buttonStyle(PillButtonStyle(filled: true))
            Spacer()
            Button { openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(PillButtonStyle()).help("Settings")
            Button { quit() } label: { Image(systemName: "power") }
                .buttonStyle(PillButtonStyle()).help("Quit (fans return to automatic)")
        }
    }
}

// MARK: - Pieces

struct ProfileStrip: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Profile.builtIns) { profile in
                let selected = state.config.activeProfileID == profile.id && !state.isModified
                Button { state.apply(profile: profile) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: profile.symbol).font(.system(size: 14, weight: .medium))
                        Text(profile.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.12) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.white.opacity(0.16) : .clear, lineWidth: 0.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !state.config.customProfiles.isEmpty {
                Menu {
                    ForEach(state.config.customProfiles) { p in
                        Button(p.name) { state.apply(profile: p) }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28).foregroundStyle(Theme.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(4)
        .glass(radius: 14)
    }
}

struct FanRow: View {
    @Environment(AppState.self) private var state
    let fan: AppState.FanState

    var body: some View {
        let fraction = fan.limits.percent(forRPM: fan.rpm) / 100
        HStack(spacing: 12) {
            ZStack {
                RingGauge(value: fraction, tint: Theme.accent, lineWidth: 4)
                Image(systemName: "fan").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(fan.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            Sparkline(values: state.history["fan\(fan.id)"] ?? [], tint: Theme.accent, fill: false,
                      range: fan.limits.min...fan.limits.max)
                .frame(width: 52, height: 22)
            VStack(alignment: .trailing, spacing: 0) {
                Text(formatRPM(fan.rpm)).font(.metric(15)).foregroundStyle(Theme.textPrimary)
                Text("RPM").font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.textTertiary)
            }
            .frame(minWidth: 46, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glass(radius: 14)
    }

    private var subtitle: String {
        let s = state.setting(forFan: fan.id)
        switch s.mode {
        case .auto: return "Auto · macOS"
        case .manual: return "Manual · \(Int(s.manualPercent))%"
        case .max: return "Maximum"
        case .curve:
            let t = state.temps.value(for: s.sensor)
            return "Curve · \(s.sensor.title) \(state.format(t))"
        }
    }
}

struct TemperatureGrid: View {
    @Environment(AppState.self) private var state

    private var tiles: [(SensorCategory, Double)] {
        [SensorCategory.cpu, .gpu, .storage, .battery, .memory, .ambient].compactMap { c in
            state.temps.average(c).map { (c, $0) }
        }
        .prefix(4).map { $0 }
    }

    var body: some View {
        if !tiles.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(tiles, id: \.0) { category, value in
                    HStack(spacing: 10) {
                        Image(systemName: category.symbol).font(.system(size: 12))
                            .foregroundStyle(Theme.heat(value)).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textTertiary)
                            Text(state.format(value)).font(.metric(15)).foregroundStyle(Theme.textPrimary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .glass(radius: 12)
                }
            }
        }
    }
}
