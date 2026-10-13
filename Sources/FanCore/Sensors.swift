import Foundation

public enum SensorCategory: String, Codable, CaseIterable {
    case cpu, gpu, memory, storage, battery, ambient, other

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .storage: return "Storage"
        case .battery: return "Battery"
        case .ambient: return "Ambient"
        case .other: return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery: return "battery.100"
        case .ambient: return "wind"
        case .other: return "thermometer.medium"
        }
    }
}

/// SMC temperature key naming differs between Apple Silicon generations, so classification is by
/// prefix and deliberately conservative: unknown keys land in "Other" rather than being mislabelled.
public enum SensorCatalog {
    public static func classify(key: String) -> (category: SensorCategory, name: String) {
        let prefix = String(key.prefix(2))
        switch prefix {
        case "Tp": return (.cpu, "CPU Performance · \(key)")
        case "Te": return (.cpu, "CPU Efficiency · \(key)")
        case "Tf": return (.cpu, "CPU Cluster · \(key)")
        case "Tg": return (.gpu, "GPU · \(key)")
        case "Tm": return (.memory, "Memory · \(key)")
        case "TH", "Tn", "TN": return (.storage, "Storage · \(key)")
        case "TB": return (.battery, "Battery · \(key)")
        case "Ta": return (.ambient, "Ambient · \(key)")
        default: return (.other, "Sensor · \(key)")
        }
    }

    /// A plausible live temperature. Filters out disconnected / placeholder sensors (0, negatives, 255...).
    public static func isPlausible(_ celsius: Double) -> Bool {
        celsius > 5 && celsius < 130
    }
}

public struct TemperatureSnapshot: Equatable {
    public var values: [String: Double]
    public var categories: [String: SensorCategory]

    public init(values: [String: Double] = [:], categories: [String: SensorCategory] = [:]) {
        self.values = values
        self.categories = categories
    }

    private func readings(in category: SensorCategory) -> [Double] {
        values.compactMap { categories[$0.key] == category ? $0.value : nil }
    }

    public func peak(_ category: SensorCategory) -> Double? { readings(in: category).max() }

    public func average(_ category: SensorCategory) -> Double? {
        let r = readings(in: category)
        return r.isEmpty ? nil : r.reduce(0, +) / Double(r.count)
    }

    public var hottest: Double? { values.values.max() }

    /// The temperature the safety latch watches: CPU and GPU only, so a warm charger sensor can't pin the fans.
    public var silicon: Double? {
        [peak(.cpu), peak(.gpu)].compactMap { $0 }.max() ?? hottest
    }

    public func value(for selection: SensorSelection) -> Double? {
        switch selection {
        case .cpu: return peak(.cpu)
        case .gpu: return peak(.gpu)
        case .hottest: return hottest
        case .key(let k): return values[k]
        }
    }
}
