import Foundation

public enum FanControlMode: String, Codable, CaseIterable, Equatable {
    case auto, manual, curve, max

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .manual: return "Manual"
        case .curve: return "Curve"
        case .max: return "Max"
        }
    }
}

public enum SensorSelection: Codable, Equatable, Hashable {
    case cpu        // hottest CPU sensor
    case gpu        // hottest GPU sensor
    case hottest    // hottest sensor of any kind
    case key(String)

    public var title: String {
        switch self {
        case .cpu: return "CPU (peak)"
        case .gpu: return "GPU (peak)"
        case .hottest: return "Hottest sensor"
        case .key(let k): return k
        }
    }
}

public struct FanSetting: Codable, Equatable {
    public var mode: FanControlMode
    /// Manual target as percent (0...100) of the fan's min...max range, so profiles travel across machines.
    public var manualPercent: Double
    public var curve: FanCurve
    public var sensor: SensorSelection

    public init(mode: FanControlMode = .auto, manualPercent: Double = 50,
                curve: FanCurve = .balanced, sensor: SensorSelection = .cpu) {
        self.mode = mode
        self.manualPercent = manualPercent
        self.curve = curve
        self.sensor = sensor
    }

    public static let auto = FanSetting(mode: .auto)
}

public struct FanLimits: Equatable {
    public var min: Double
    public var max: Double
    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }
    public var range: Double { Swift.max(max - min, 1) }

    public func rpm(forPercent p: Double) -> Double {
        min + Swift.min(Swift.max(p, 0), 100) / 100 * range
    }
    public func percent(forRPM r: Double) -> Double {
        Swift.min(Swift.max((r - min) / range * 100, 0), 100)
    }
}

public enum FanDecision: Equatable {
    case automatic
    case target(rpm: Double)
}

// MARK: - Profiles

public struct Profile: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var isBuiltIn: Bool
    public var fallback: FanSetting
    /// Per-fan overrides keyed by fan index ("0", "1"...). String keys keep the JSON an object.
    public var overrides: [String: FanSetting]

    public init(id: UUID = UUID(), name: String, symbol: String = "slider.horizontal.3", isBuiltIn: Bool = false,
                fallback: FanSetting, overrides: [String: FanSetting] = [:]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.isBuiltIn = isBuiltIn
        self.fallback = fallback
        self.overrides = overrides
    }

    public func setting(forFan index: Int) -> FanSetting {
        overrides[String(index)] ?? fallback
    }

    public mutating func set(_ setting: FanSetting, forFan index: Int) {
        overrides[String(index)] = setting
    }

    public static let auto = Profile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!, name: "Auto",
                                     symbol: "wand.and.stars", isBuiltIn: true, fallback: .auto)
    public static let quiet = Profile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!, name: "Quiet",
                                      symbol: "moon.stars", isBuiltIn: true,
                                      fallback: FanSetting(mode: .curve, curve: .quiet, sensor: .cpu))
    public static let balanced = Profile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!, name: "Balanced",
                                         symbol: "scale.3d", isBuiltIn: true,
                                         fallback: FanSetting(mode: .curve, curve: .balanced, sensor: .cpu))
    public static let performance = Profile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!, name: "Performance",
                                            symbol: "bolt", isBuiltIn: true,
                                            fallback: FanSetting(mode: .curve, curve: .performance, sensor: .hottest))
    public static let max = Profile(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!, name: "Max",
                                    symbol: "wind", isBuiltIn: true, fallback: FanSetting(mode: .max))

    public static let builtIns: [Profile] = [.auto, .quiet, .balanced, .performance, .max]
}

// MARK: - App settings

public enum TemperatureUnit: String, Codable, CaseIterable {
    case celsius, fahrenheit
    public var title: String { self == .celsius ? "Celsius" : "Fahrenheit" }
    public func convert(_ celsius: Double) -> Double { self == .celsius ? celsius : celsius * 9 / 5 + 32 }
    public var suffix: String { self == .celsius ? "°C" : "°F" }
}

public enum WidgetStyle: String, Codable, CaseIterable {
    case iconText, sparkline, bar, textOnly
    public var title: String {
        switch self {
        case .iconText: return "Icon + value"
        case .sparkline: return "Sparkline"
        case .bar: return "Bar"
        case .textOnly: return "Value only"
        }
    }
}

public struct AppSettings: Codable, Equatable {
    public var unit: TemperatureUnit = .celsius
    public var showFanItem: Bool = true
    public var fanWidget: WidgetStyle = .sparkline
    public var showTempItem: Bool = true
    public var tempWidget: WidgetStyle = .iconText
    public var menuBarSensor: SensorSelection = .cpu
    public var colorCodedMenuBar: Bool = true
    /// Seconds between samples while a window/popover is visible.
    public var foregroundInterval: Double = 1
    /// Seconds between samples while only the menu bar is showing.
    public var backgroundInterval: Double = 3
    /// At or above this the app forces fans to maximum (and stays there until 7° below).
    public var criticalTemp: Double = 95

    public init() {}
}

public struct AppConfig: Codable, Equatable {
    public var customProfiles: [Profile] = []
    public var activeProfileID: UUID = Profile.auto.id
    public var working: Profile = .auto
    public var settings = AppSettings()
    public init() {}
}
