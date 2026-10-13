import Foundation
import SwiftUI
import Observation
import FanCore

@Observable
final class AppState {
    struct FanState: Identifiable, Equatable {
        let id: Int
        let limits: FanLimits
        var rpm: Double
        var targetRPM: Double?
        var mode: FanControlMode
        var name: String { "Fan \(id + 1)" }
    }

    struct SensorState: Identifiable, Equatable {
        var id: String { descriptor.key }
        let descriptor: SensorDescriptor
        var value: Double
    }

    // MARK: Published state
    var fans: [FanState] = []
    var sensors: [SensorState] = []
    var temps = TemperatureSnapshot()
    var history: [String: [Double]] = [:]
    var config: AppConfig
    var helperReady = false
    var criticalActive = false
    var lastError: String?
    var isDemo: Bool { source.isSimulated }
    var hasFans: Bool { !fans.isEmpty }

    // MARK: Internals
    @ObservationIgnored private var source: HardwareSource
    @ObservationIgnored private var actuator: FanActuator
    @ObservationIgnored private let helper = HelperClient()
    @ObservationIgnored private var controller = FanController()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var manualFans = Set<Int>()
    @ObservationIgnored private var categoryMap: [String: SensorCategory] = [:]
    @ObservationIgnored private var visibleSurfaces = 0
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    /// Called after every sample so the menu bar can redraw. Not observed by SwiftUI.
    @ObservationIgnored var onUpdate: (() -> Void)?

    private static let historyLength = 120

    init(forceDemo: Bool = false) {
        config = ConfigStore.load()
        if !forceDemo, let real = SMCSource() {
            source = real
            actuator = helper
        } else {
            let sim = SimulatedSource()
            source = sim
            actuator = sim
        }
        categoryMap = Dictionary(uniqueKeysWithValues: source.sensors.map { ($0.key, $0.category) })
        fans = source.fans.map {
            FanState(id: $0.index, limits: FanLimits(min: $0.minRPM, max: $0.maxRPM), rpm: $0.minRPM, targetRPM: nil, mode: .auto)
        }
        // Never resume a saved profile that holds fans at a fixed speed without the user's say-so.
        // Curves and Auto are safe to restore; manual/max start from Auto.
        if config.working.fallback.mode == .manual || config.working.fallback.mode == .max {
            apply(profile: .auto)
        }
    }

    // MARK: Lifecycle

    func start() {
        refreshHelper()
        tick()
        reschedule()
    }

    func shutdown() {
        timer?.invalidate()
        actuator.releaseAllBlocking()
        ConfigStore.save(config)
    }

    /// Windows and the popover register while visible so we can sample faster only when someone is looking.
    func surfaceVisibilityChanged(visible: Bool) {
        visibleSurfaces = max(0, visibleSurfaces + (visible ? 1 : -1))
        reschedule()
        if visible { tick() }
    }

    private func reschedule() {
        timer?.invalidate()
        let seconds = visibleSurfaces > 0 ? config.settings.foregroundInterval : config.settings.backgroundInterval
        let t = Timer(timeInterval: max(seconds, 0.5), repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = seconds * 0.2   // lets macOS coalesce wakeups
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Sampling + control

    func tick() {
        let now = Date()
        let dt = min(lastTick.map { now.timeIntervalSince($0) } ?? config.settings.backgroundInterval, 10)
        lastTick = now

        let sample = source.sample()
        temps = TemperatureSnapshot(values: sample.temps, categories: categoryMap)
        sensors = source.sensors.compactMap { d in sample.temps[d.key].map { SensorState(descriptor: d, value: $0) } }

        controller.config.criticalTemp = config.settings.criticalTemp
        controller.updateSafety(siliconTemp: temps.silicon)
        criticalActive = controller.criticalLatched

        for i in fans.indices {
            let index = fans[i].id
            if let rpm = sample.rpm[index] { fans[i].rpm = rpm }
            let setting = config.working.setting(forFan: index)
            let decision = controller.decide(fan: index, setting: setting, limits: fans[i].limits, temps: temps,
                                             actualRPM: fans[i].rpm, dt: dt)
            switch decision {
            case .automatic:
                if manualFans.remove(index) != nil { actuator.release(fan: index) }
                fans[i].targetRPM = nil
                fans[i].mode = .auto
            case .target(let rpm):
                manualFans.insert(index)
                actuator.setTarget(fan: index, rpm: rpm) { [weak self] error, unreachable in
                    guard let self else { return }
                    if unreachable {
                        self.helperReady = false
                        self.lastError = "Fan control helper isn't running."
                    } else if let error {
                        self.helperReady = true
                        self.lastError = error
                    } else {
                        self.helperReady = true
                        self.lastError = nil
                    }
                }
                fans[i].targetRPM = rpm
                fans[i].mode = setting.mode
            }
            record("fan\(index)", fans[i].rpm)
        }
        if let v = temps.average(.cpu) { record("cpu", v) }
        if let v = temps.average(.gpu) { record("gpu", v) }
        if let v = temps.value(for: config.settings.menuBarSensor) { record("menubar", v) }
        onUpdate?()
    }

    private func record(_ key: String, _ value: Double) {
        var series = history[key] ?? []
        series.append(value)
        if series.count > Self.historyLength { series.removeFirst(series.count - Self.historyLength) }
        history[key] = series
    }

    // MARK: Derived

    var menuBarTemperature: Double? { temps.value(for: config.settings.menuBarSensor) ?? temps.hottest }

    var averageRPM: Double? {
        fans.isEmpty ? nil : fans.map(\.rpm).reduce(0, +) / Double(fans.count)
    }

    var allProfiles: [Profile] { Profile.builtIns + config.customProfiles }

    var activeProfile: Profile? { allProfiles.first { $0.id == config.activeProfileID } }

    var isModified: Bool {
        guard let p = activeProfile else { return true }
        return p.fallback != config.working.fallback || p.overrides != config.working.overrides
    }

    var workingName: String {
        guard let p = activeProfile else { return "Custom" }
        return isModified ? "\(p.name) (modified)" : p.name
    }

    func format(_ celsius: Double?, decimals: Int = 0) -> String {
        guard let c = celsius else { return "–" }
        return String(format: "%.\(decimals)f°", config.settings.unit.convert(c))
    }

    // MARK: Profiles & settings

    func apply(profile: Profile) {
        config.working = profile
        config.activeProfileID = profile.id
        controller.reset()
        persist()
        tick()
    }

    func setting(forFan index: Int) -> FanSetting { config.working.setting(forFan: index) }

    func update(_ setting: FanSetting, forFan index: Int) {
        config.working.set(setting, forFan: index)
        persist()
    }

    func saveWorkingAsProfile(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let profile = Profile(name: trimmed, symbol: "person.crop.circle", isBuiltIn: false,
                              fallback: config.working.fallback, overrides: config.working.overrides)
        config.customProfiles.append(profile)
        config.working.id = profile.id
        config.working.name = profile.name
        config.activeProfileID = profile.id
        persist()
    }

    func deleteProfile(_ profile: Profile) {
        guard !profile.isBuiltIn else { return }
        config.customProfiles.removeAll { $0.id == profile.id }
        if config.activeProfileID == profile.id { apply(profile: .auto) } else { persist() }
    }

    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.config.settings[keyPath: keyPath] },
                set: { self.config.settings[keyPath: keyPath] = $0; self.settingsChanged() })
    }

    func settingsChanged() {
        reschedule()
        persist()
        onUpdate?()
    }

    private func persist() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [config] in ConfigStore.save(config) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: Helper

    func refreshHelper() {
        guard !isDemo else { helperReady = true; return }
        helper.ping { [weak self] ok in self?.helperReady = ok }
    }
}
