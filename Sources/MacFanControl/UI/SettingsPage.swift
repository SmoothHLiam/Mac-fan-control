import SwiftUI
import FanCore

struct SettingsPage: View {
    @Environment(AppState.self) private var state
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var helperMessage: String?

    var body: some View {
        PageScroll {
            PageHeader(title: "Settings", subtitle: "Menu bar, behaviour and the fan helper") { EmptyView() }

            card("Menu bar") {
                row("Fan item", "Shows fan speed") {
                    HStack(spacing: 12) {
                        widgetPicker(state.binding(\.fanWidget))
                        Toggle("", isOn: state.binding(\.showFanItem)).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                    }
                }
                divider
                row("Temperature item", "Shows the selected sensor") {
                    HStack(spacing: 12) {
                        widgetPicker(state.binding(\.tempWidget))
                        Toggle("", isOn: state.binding(\.showTempItem)).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                    }
                }
                divider
                row("Sensor", "Used by the temperature item") {
                    SensorPicker(selection: state.binding(\.menuBarSensor))
                }
                divider
                row("Colour-coded", "Tint widgets by temperature") {
                    Toggle("", isOn: state.binding(\.colorCodedMenuBar)).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                }
            }

            card("General") {
                row("Units", nil) {
                    Picker("", selection: state.binding(\.unit)) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 190)
                }
                divider
                row("Launch at login", "Keeps your fan profile active after restart") {
                    Toggle("", isOn: Binding(get: { launchAtLogin }, set: { launchAtLogin = $0; LoginItem.set($0) }))
                        .labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                }
                divider
                row("Refresh rate", "While open / menu bar only") {
                    HStack(spacing: 8) {
                        stepper(state.binding(\.foregroundInterval), range: 0.5...5, step: 0.5)
                        Text("/").foregroundStyle(Theme.textTertiary)
                        stepper(state.binding(\.backgroundInterval), range: 1...15, step: 1)
                    }
                }
            }

            card("Safety") {
                row("Thermal safeguard", "Forces maximum fan speed at this silicon temperature") {
                    stepper(state.binding(\.criticalTemp), range: 80...105, step: 1, suffix: "°C")
                }
                divider
                Text("Fans return to automatic whenever the app quits, crashes or the helper loses contact for 6 seconds.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 20).padding(.vertical, 12)
            }

            card("Fan helper") { helperSection }
        }
        .onAppear { state.refreshHelper() }
    }

    // MARK: Helper

    @ViewBuilder
    private var helperSection: some View {
        if state.isDemo {
            Text("Demo mode: no SMC found, so there is nothing to install.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary).padding(20)
        } else {
            row(state.helperReady ? "Connected" : "Not running",
                state.helperReady
                ? "Fan changes are applied by the privileged helper."
                : "Writing fan speeds requires a small root helper. macOS will ask you to allow it in Login Items.") {
                HStack(spacing: 8) {
                    if !state.helperReady {
                        Button("Install") { install() }.buttonStyle(PillButtonStyle(filled: true))
                    }
                    Button("Re-check") { state.refreshHelper() }.buttonStyle(PillButtonStyle())
                    if HelperInstaller.state != .notFound && HelperInstaller.state != .notRegistered {
                        Button("Uninstall") { uninstall() }.buttonStyle(PillButtonStyle(tint: Theme.red))
                    }
                }
            }
            if let helperMessage {
                Text(helperMessage).font(.system(size: 11)).foregroundStyle(Theme.amber)
                    .padding(.horizontal, 20).padding(.bottom, 14)
            }
        }
    }

    private func install() {
        do {
            try HelperInstaller.register()
            helperMessage = HelperInstaller.state == .requiresApproval
                ? "Approve “Mac Fan Control” in System Settings → General → Login Items, then press Re-check."
                : nil
        } catch {
            helperMessage = "Install failed: \(error.localizedDescription). Running from a build without the bundled helper? Use scripts/install_helper.sh."
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { state.refreshHelper() }
    }

    private func uninstall() {
        do { try HelperInstaller.unregister(); helperMessage = nil } catch { helperMessage = error.localizedDescription }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { state.refreshHelper() }
    }

    // MARK: Building blocks

    private var divider: some View { Rectangle().fill(Theme.stroke).frame(height: 0.5) }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(title).padding(.leading, 4)
            VStack(spacing: 0) { content() }.glass(radius: 18)
        }
    }

    private func row<Control: View>(_ title: String, _ subtitle: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 20).padding(.vertical, 13)
    }

    private func widgetPicker(_ binding: Binding<WidgetStyle>) -> some View {
        Picker("", selection: binding) {
            ForEach(WidgetStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }.labelsHidden().pickerStyle(.menu).fixedSize()
    }

    private func stepper(_ binding: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String = "s") -> some View {
        HStack(spacing: 6) {
            Text("\(binding.wrappedValue.formatted(.number.precision(.fractionLength(0...1))))\(suffix)")
                .font(.metric(12, weight: .medium)).foregroundStyle(Theme.textPrimary).frame(minWidth: 40, alignment: .trailing)
            Stepper("", value: binding, in: range, step: step).labelsHidden()
        }
    }
}
