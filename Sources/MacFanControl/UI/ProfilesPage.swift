import SwiftUI
import FanCore

struct ProfilesPage: View {
    @Environment(AppState.self) private var state
    @State private var newName = ""

    var body: some View {
        PageScroll {
            PageHeader(title: "Profiles", subtitle: "One-click fan behaviour for every fan") { EmptyView() }

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Save current setup")
                HStack(spacing: 10) {
                    TextField("Profile name", text: $newName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(Color.black.opacity(0.3)))
                        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
                        .onSubmit(save)
                    Button("Save", action: save)
                        .buttonStyle(PillButtonStyle(filled: true))
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(state.isModified
                     ? "You have unsaved changes to “\(state.activeProfile?.name ?? "Custom")”."
                     : "Saves the current curves and manual speeds for each fan.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
            .padding(20)
            .glass()

            ForEach(state.allProfiles) { profile in row(profile) }
        }
    }

    private func save() {
        state.saveWorkingAsProfile(named: newName)
        newName = ""
    }

    private func row(_ profile: Profile) -> some View {
        let active = profile.id == state.config.activeProfileID
        return HStack(spacing: 14) {
            Image(systemName: profile.symbol).font(.system(size: 16))
                .foregroundStyle(active ? Theme.accent : Theme.textSecondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(summary(profile)).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if active && !state.isModified {
                StatusPill(text: "Active", tint: Theme.teal)
            } else {
                Button(active ? "Revert" : "Apply") { state.apply(profile: profile) }.buttonStyle(PillButtonStyle())
            }
            if !profile.isBuiltIn {
                Button { state.deleteProfile(profile) } label: { Image(systemName: "trash") }
                    .buttonStyle(PillButtonStyle(tint: Theme.red)).help("Delete profile")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .glass(radius: 16)
    }

    private func summary(_ p: Profile) -> String {
        let all = [p.fallback] + p.overrides.values
        let modes = Set(all.map(\.mode))
        if modes.count == 1, let m = modes.first {
            switch m {
            case .auto: return "Fans managed by macOS"
            case .max: return "All fans at maximum"
            case .manual: return "Fixed speed"
            case .curve: return "Temperature curve · \(p.fallback.sensor.title)"
            }
        }
        return "Mixed per-fan settings"
    }
}
