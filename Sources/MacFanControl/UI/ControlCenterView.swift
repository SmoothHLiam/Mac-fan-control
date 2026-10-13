import SwiftUI
import FanCore

enum ControlCenterPage: String, CaseIterable, Identifiable {
    case fans, sensors, profiles, settings
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .fans: return "fan"
        case .sensors: return "thermometer.medium"
        case .profiles: return "square.stack.3d.up"
        case .settings: return "slider.horizontal.3"
        }
    }
}

@Observable
final class Navigation {
    var page: ControlCenterPage = .fans
}

struct ControlCenterView: View {
    @Environment(AppState.self) private var state
    @Environment(Navigation.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        HStack(spacing: 0) {
            sidebar(selection: $nav.page)
            Rectangle().fill(Theme.stroke).frame(width: 0.5)
            Group {
                switch nav.page {
                case .fans: FansPage()
                case .sensors: SensorsPage()
                case .profiles: ProfilesPage()
                case .settings: SettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(AmbientBackground())
        .preferredColorScheme(.dark)
    }

    private func sidebar(selection: Binding<ControlCenterPage>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "fan.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .glass(radius: 9)
                Text("Fan Control").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            }
            .padding(.top, 34)
            .padding(.bottom, 22)
            .padding(.horizontal, 10)

            ForEach(ControlCenterPage.allCases) { page in
                let selected = selection.wrappedValue == page
                Button { selection.wrappedValue = page } label: {
                    HStack(spacing: 10) {
                        Image(systemName: page.symbol).frame(width: 18)
                        Text(page.title)
                        Spacer()
                    }
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.1) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                if state.isDemo { StatusPill(text: "Demo data", tint: Theme.amber) }
                else if state.hasFans { StatusPill(text: state.helperReady ? "Helper connected" : "Helper offline",
                                                  tint: state.helperReady ? Theme.teal : Theme.amber) }
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .frame(width: 200)
        .background(Color.black.opacity(0.18))
    }
}

// MARK: - Page scaffold

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let trailing: Trailing

    init(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            trailing
        }
    }
}

struct PageScroll<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(.horizontal, 32)
                .padding(.top, 40)
                .padding(.bottom, 32)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Fans

struct FansPage: View {
    @Environment(AppState.self) private var state
    @Environment(Navigation.self) private var nav

    var body: some View {
        PageScroll {
            PageHeader(title: "Fans", subtitle: state.hasFans
                       ? "Profile: \(state.workingName)"
                       : "This Mac has no fans to control") {
                ProfileMenu()
            }
            if state.criticalActive {
                Banner(symbol: "flame.fill",
                       text: "Silicon reached \(Int(state.config.settings.criticalTemp))°C. Fans are held at maximum until it cools down.",
                       tint: Theme.red)
            }
            if state.isDemo {
                Banner(symbol: "info.circle.fill",
                       text: "No SMC was found, so this is simulated data. Run on an Apple Silicon Mac to control real fans.")
            } else if state.hasFans, !state.helperReady {
                Banner(symbol: "lock.fill",
                       text: "Reading works, but changing fan speed needs the privileged helper.",
                       action: ("Set Up", { nav.page = .settings }))
            }
            if let error = state.lastError, state.helperReady {
                Banner(symbol: "exclamationmark.triangle.fill", text: error)
            }
            ForEach(state.fans) { fan in FanPanel(fan: fan) }
            if !state.hasFans { SensorOnlyHint() }
        }
    }
}

struct ProfileMenu: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Menu {
            ForEach(state.allProfiles) { p in
                Button { state.apply(profile: p) } label: {
                    Label(p.name, systemImage: p.id == state.config.activeProfileID ? "checkmark" : p.symbol)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: state.activeProfile?.symbol ?? "slider.horizontal.3")
                Text(state.workingName)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct SensorOnlyHint: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wind").font(.system(size: 20)).foregroundStyle(Theme.textSecondary)
            Text("Fanless Macs (MacBook Air) cool passively. Temperatures are still monitored under Sensors and in the menu bar.")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }
}

struct FanPanel: View {
    @Environment(AppState.self) private var state
    let fan: AppState.FanState

    private var setting: Binding<FanSetting> {
        Binding(get: { state.setting(forFan: fan.id) }, set: { state.update($0, forFan: fan.id) })
    }

    var body: some View {
        let fraction = fan.limits.percent(forRPM: fan.rpm) / 100
        HStack(alignment: .top, spacing: 28) {
            VStack(spacing: 10) {
                ZStack {
                    RingGauge(value: fraction, tint: Theme.accent, lineWidth: 10)
                    VStack(spacing: 0) {
                        Text(formatRPM(fan.rpm)).font(.metric(30)).foregroundStyle(Theme.textPrimary)
                        Text("RPM").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 164, height: 164)
                Text(fan.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("\(formatRPM(fan.limits.min)) – \(formatRPM(fan.limits.max)) RPM")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 170)

            VStack(alignment: .leading, spacing: 16) {
                ChipPicker(options: FanControlMode.allCases,
                           selection: Binding(get: { setting.wrappedValue.mode },
                                              set: { var s = setting.wrappedValue; s.mode = $0; setting.wrappedValue = s }),
                           title: { $0.title })
                controls
                Sparkline(values: state.history["fan\(fan.id)"] ?? [], tint: Theme.accent,
                          range: fan.limits.min...fan.limits.max)
                    .frame(height: 44)
                    .overlay(alignment: .topLeading) { Eyebrow("Last \(state.history["fan\(fan.id)"]?.count ?? 0) samples") }
            }
        }
        .padding(24)
        .glass(radius: 22)
    }

    @ViewBuilder
    private var controls: some View {
        switch setting.wrappedValue.mode {
        case .auto:
            description("macOS manages this fan. This is the default and the safest choice.")
        case .max:
            description("Runs at \(formatRPM(fan.limits.max)) RPM until you change mode.")
        case .manual:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow("Target")
                    Spacer()
                    Text("\(formatRPM(fan.limits.rpm(forPercent: setting.wrappedValue.manualPercent))) RPM")
                        .font(.metric(14)).foregroundStyle(Theme.textPrimary)
                }
                SliderTrack(value: Binding(get: { setting.wrappedValue.manualPercent / 100 },
                                           set: { var s = setting.wrappedValue; s.manualPercent = ($0 * 100).rounded(); setting.wrappedValue = s }))
            }
        case .curve:
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow("Driven by")
                    SensorPicker(selection: Binding(get: { setting.wrappedValue.sensor },
                                                    set: { var s = setting.wrappedValue; s.sensor = $0; setting.wrappedValue = s }))
                    Spacer()
                    if let t = state.temps.value(for: setting.wrappedValue.sensor) {
                        Text(state.format(t)).font(.metric(14)).foregroundStyle(Theme.heat(t))
                    }
                    Menu("Presets") {
                        Button("Quiet") { apply(.quiet) }
                        Button("Balanced") { apply(.balanced) }
                        Button("Performance") { apply(.performance) }
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                CurveEditor(curve: Binding(get: { setting.wrappedValue.curve },
                                           set: { var s = setting.wrappedValue; s.curve = $0; setting.wrappedValue = s }),
                            currentTemp: state.temps.value(for: setting.wrappedValue.sensor),
                            limits: fan.limits, unit: state.config.settings.unit)
                    .frame(height: 190)
                Text("Drag points · double-click to add · right-click to remove")
                    .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func apply(_ curve: FanCurve) {
        var s = setting.wrappedValue
        s.curve = curve
        setting.wrappedValue = s
    }

    private func description(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

struct SensorPicker: View {
    @Environment(AppState.self) private var state
    @Binding var selection: SensorSelection

    var body: some View {
        Picker("", selection: $selection) {
            Text("CPU (peak)").tag(SensorSelection.cpu)
            Text("GPU (peak)").tag(SensorSelection.gpu)
            Text("Hottest sensor").tag(SensorSelection.hottest)
            Divider()
            ForEach(state.sensors) { s in
                Text(s.descriptor.name).tag(SensorSelection.key(s.descriptor.key))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}
