import Foundation

/// Decides what each fan should do on every tick. Pure value logic: no hardware, no clock.
public struct FanController {
    public struct Config: Equatable {
        /// RPM per second the target may rise.
        public var rampUp: Double = 1800
        /// RPM per second the target may fall (slower than rise, so fans don't hunt).
        public var rampDown: Double = 400
        /// Ignore target changes smaller than this (avoids pointless SMC writes and audible wobble).
        public var deadband: Double = 40
        /// Exponential smoothing factor for the control temperature (1 = no smoothing).
        public var tempSmoothing: Double = 0.35
        public var criticalTemp: Double = 95
        /// The safety latch releases this many degrees below `criticalTemp`.
        public var criticalHysteresis: Double = 7
        public init() {}
    }

    public var config: Config
    public private(set) var criticalLatched = false
    private var lastTarget: [Int: Double] = [:]
    private var smoothedTemp: [Int: Double] = [:]

    public init(config: Config = Config()) {
        self.config = config
    }

    public mutating func updateSafety(siliconTemp: Double?) {
        guard let t = siliconTemp else { return }
        if t >= config.criticalTemp {
            criticalLatched = true
        } else if t <= config.criticalTemp - config.criticalHysteresis {
            criticalLatched = false
        }
    }

    public mutating func reset() {
        lastTarget.removeAll()
        smoothedTemp.removeAll()
    }

    public mutating func decide(fan: Int, setting: FanSetting, limits: FanLimits, temps: TemperatureSnapshot,
                                actualRPM: Double?, dt: TimeInterval) -> FanDecision {
        let desired: Double
        switch setting.mode {
        case .auto:
            lastTarget[fan] = nil
            smoothedTemp[fan] = nil
            return .automatic
        case .max:
            desired = limits.max
        case .manual:
            desired = limits.rpm(forPercent: setting.manualPercent)
        case .curve:
            if let raw = temps.value(for: setting.sensor) ?? temps.hottest {
                let prev = smoothedTemp[fan] ?? raw
                let smoothed = prev + config.tempSmoothing * (raw - prev)
                smoothedTemp[fan] = smoothed
                desired = limits.rpm(forPercent: setting.curve.percent(at: smoothed))
            } else {
                desired = limits.max   // no temperature data: fail safe, not fail quiet
            }
        }

        var target = desired
        var immediate = false
        if criticalLatched {
            target = limits.max
            immediate = true
        }

        let start = lastTarget[fan] ?? actualRPM ?? target
        var next = start
        if immediate {
            next = target
        } else {
            let delta = target - start
            let atEndpoint = target <= limits.min || target >= limits.max
            if abs(delta) < config.deadband && !atEndpoint {
                next = start
            } else {
                let step = (delta > 0 ? config.rampUp : config.rampDown) * max(dt, 0)
                next = start + min(max(delta, -step), step)
            }
        }

        next = min(max(next, limits.min), limits.max)
        lastTarget[fan] = next
        return .target(rpm: next.rounded())
    }
}
