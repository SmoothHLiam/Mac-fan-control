import Foundation
import FanCore

struct SensorDescriptor: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let category: SensorCategory
    let name: String
}

struct HardwareSample {
    var rpm: [Int: Double] = [:]
    var temps: [String: Double] = [:]
}

protocol HardwareSource: AnyObject {
    var isSimulated: Bool { get }
    var fans: [FanHardwareInfo] { get }
    var sensors: [SensorDescriptor] { get }
    func sample() -> HardwareSample
}

/// Writes fan targets. The real implementation talks to the root helper over XPC.
protocol FanActuator: AnyObject {
    func setTarget(fan: Int, rpm: Double, completion: @escaping (_ error: String?, _ unreachable: Bool) -> Void)
    func release(fan: Int)
    /// Used on quit: blocks briefly so fans are handed back before the process exits.
    func releaseAllBlocking()
}

// MARK: - Real hardware

final class SMCSource: HardwareSource {
    let isSimulated = false
    let fans: [FanHardwareInfo]
    let sensors: [SensorDescriptor]
    private let smc: SMCClient

    init?() {
        guard let smc = SMCClient() else { return nil }
        let fans = smc.fanHardware()
        let sensors = smc.discoverTemperatureKeys().map { key -> SensorDescriptor in
            let c = SensorCatalog.classify(key: key)
            return SensorDescriptor(key: key, category: c.category, name: c.name)
        }
        // A Mac with neither fans nor readable temperatures isn't something we can do anything with.
        guard !fans.isEmpty || !sensors.isEmpty else { return nil }
        self.smc = smc
        self.fans = fans
        self.sensors = sensors
    }

    func sample() -> HardwareSample {
        var s = HardwareSample()
        for f in fans {
            if let v = smc.actualRPM(fan: f.index) { s.rpm[f.index] = max(v, 0) }
        }
        for d in sensors {
            if let v = smc.readValue(d.key), SensorCatalog.isPlausible(v) { s.temps[d.key] = v }
        }
        return s
    }
}

// MARK: - Demo data (no SMC, e.g. VMs / Intel / CI)

final class SimulatedSource: HardwareSource, FanActuator {
    let isSimulated = true
    let fans = [FanHardwareInfo(index: 0, minRPM: 1200, maxRPM: 5800),
                FanHardwareInfo(index: 1, minRPM: 1200, maxRPM: 6200)]
    let sensors: [SensorDescriptor] = ["Tp01", "Tp05", "Tp09", "Te04", "Tg05", "Tg0D", "Tm02", "TH0x", "TB1T", "Ta0P"]
        .map { key in
            let c = SensorCatalog.classify(key: key)
            return SensorDescriptor(key: key, category: c.category, name: c.name)
        }

    private var phase = 0.0
    private var rpm: [Double] = [1250, 1250]
    private var targets: [Int: Double] = [:]
    private var cpu = 42.0

    func sample() -> HardwareSample {
        phase += 0.07
        let load = min(max(0.45 + 0.4 * sin(phase) + 0.12 * sin(phase * 3.3), 0), 1)
        let cooling = (rpm[0] - 1200) / 4600
        cpu += (35 + 62 * load - 38 * cooling - cpu) * 0.12
        var s = HardwareSample()
        for f in fans {
            let desired = targets[f.index] ?? (f.minRPM + min(max((cpu - 48) / 38, 0), 1) * (f.maxRPM - f.minRPM))
            rpm[f.index] += min(max(desired - rpm[f.index], -350), 700)
            s.rpm[f.index] = rpm[f.index]
        }
        let offsets: [String: Double] = ["Tp01": 0, "Tp05": -3, "Tp09": 2, "Te04": -9, "Tg05": -5, "Tg0D": -2,
                                         "Tm02": -14, "TH0x": -18, "TB1T": -24, "Ta0P": -26]
        for d in sensors { s.temps[d.key] = cpu + (offsets[d.key] ?? 0) + 0.4 * sin(phase * 5 + Double(d.key.hashValue % 7)) }
        return s
    }

    func setTarget(fan: Int, rpm: Double, completion: @escaping (String?, Bool) -> Void) {
        targets[fan] = rpm
        completion(nil, false)
    }
    func release(fan: Int) { targets[fan] = nil }
    func releaseAllBlocking() { targets.removeAll() }
}
